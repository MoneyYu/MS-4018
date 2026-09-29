<#
.SYNOPSIS
    Seed Outlook email threads via Microsoft Graph (Application Permissions).
.DESCRIPTION
    Reads emails.json and sends emails as different users using application permissions.
    Creates real email threads using Send + Reply chain with robust message tracking.

    Idempotency (see engine/Seed-Idempotency.ps1):
      * A thread is keyed by the exact subject of its first message, matched manually against
        the adminUpn INBOX collection (admin is CC on every seeded message). Deleted Items and
        Sent Items are out of scope: a deleted thread must count as absent, and only an Inbox
        message is usable demo data. The Inbox is paged through @odata.nextLink and the CJK
        subject is compared in memory instead of through an OData `$filter`.
      * 0 messages            -> create the whole thread
      * exactly the expected  -> skip the whole thread
      * anything else         -> throw (partial or ambiguous state, never resume/duplicate)

    Fail-fast: if the first sent message cannot be found for conversation tracking, or a
    reply target cannot be found, the script throws instead of warning and continuing.
.PARAMETER ConfigPath
    Path to the scenario config.json.
.PARAMETER EmailsPath
    Path to the emails.json data file.
#>
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$EmailsPath
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\Seed-Idempotency.ps1"
. "$PSScriptRoot\Seed-GraphRead.ps1"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$emailData = Get-Content $EmailsPath -Raw -Encoding UTF8 | ConvertFrom-Json

$adminUpn = $config.adminUpn
if (-not $adminUpn) { throw "config.json is missing 'adminUpn' - email thread idempotency is keyed on the admin mailbox." }

# Build role -> UPN lookup
$roleMap = @{}
foreach ($prop in $config.roles.PSObject.Properties) {
    $roleMap[$prop.Name] = $prop.Value.upn
}

function Get-Upn([string]$role) {
    if (-not $roleMap.ContainsKey($role)) { throw "Unknown role: $role" }
    return $roleMap[$role]
}

function Invoke-Graph {
    param([string]$Method, [string]$Uri, [object]$Body)
    $headers = @{ Authorization = "Bearer $($global:AccessToken)"; "Content-Type" = "application/json" }
    $bodyJson = if ($Body) { $Body | ConvertTo-Json -Depth 20 -Compress } else { $null }
    $params = @{ Method = $Method; Uri = $Uri; Headers = $headers }
    if ($bodyJson) { $params.Body = [System.Text.Encoding]::UTF8.GetBytes($bodyJson) }
    return Invoke-RestMethod @params
}

function Get-SeedMailReadRetryDelay {
    param([Parameter(Mandatory)]$ErrorRecord, [int]$DefaultSeconds)
    $exception = $ErrorRecord.Exception
    $response = $exception.Response
    $status = if ($response) { [int]$response.StatusCode } else { 0 }
    if (-not $status -and $exception.Message -match '^Response status code does not indicate success: (429|503|504) \(') {
        $status = [int]$Matches[1]
    }
    $isTimeout = $exception -is [System.TimeoutException] -or
        ($exception -is [System.Net.WebException] -and $exception.Status -eq [System.Net.WebExceptionStatus]::Timeout)
    if ($status -notin @(429, 503, 504) -and -not $isTimeout) { throw $ErrorRecord }

    $delay = $DefaultSeconds
    if ($response -and $response.Headers -and $response.Headers.RetryAfter) {
        $retryAfter = $response.Headers.RetryAfter
        if ($retryAfter.Delta) {
            $delay = [int][Math]::Ceiling($retryAfter.Delta.TotalSeconds)
        } elseif ($retryAfter.Date) {
            $delay = [int][Math]::Max(0, [Math]::Ceiling(($retryAfter.Date - [DateTimeOffset]::UtcNow).TotalSeconds))
        }
    }
    Write-Warning "Transient mailbox GET failure ($status); retrying within the polling budget after $delay seconds."
    return $delay
}

# Bounded polling for mailbox propagation, Inbox only. Returns $null when the budget is
# exhausted - every caller turns that into a terminating error.
function Wait-SeedForMailboxMessage {
    param(
        [Parameter(Mandatory)][string]$Upn,
        [string]$ConversationId,
        [string]$InternetMessageId,
        [string[]]$ExcludeInternetMessageIds = @(),
        [string]$Subject,
        [int]$MaxRetries = 12,
        [int]$DelaySec = 5
    )
    $budget = $MaxRetries * $DelaySec
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $nextDelay = $DelaySec
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        if ($nextDelay -gt ($budget - $timer.Elapsed.TotalSeconds)) { break }
        Start-Sleep -Seconds $nextDelay
        try {
            $msgs = Get-SeedRecentInboxMessages -Upn $Upn -Top 50
        } catch {
            $nextDelay = Get-SeedMailReadRetryDelay -ErrorRecord $_ -DefaultSeconds $DelaySec
            continue
        }
        $nextDelay = $DelaySec
        $matches = @($msgs | Where-Object {
            if ($InternetMessageId) { $_.internetMessageId -eq $InternetMessageId }
            elseif ($ConversationId) {
                $_.conversationId -eq $ConversationId -and
                    $_.internetMessageId -and
                    $_.internetMessageId -notin $ExcludeInternetMessageIds
            } else { $_.subject -eq $Subject }
        })
        if ($matches.Count -gt 1) { throw "Ambiguous Inbox messages for thread '$Subject' in $Upn; refusing to reply." }
        if ($matches.Count -eq 1) {
            if (-not $matches[0].id -or -not $matches[0].internetMessageId) {
                throw "Inbox message in $Upn has no message ID or internetMessageId; refusing to reply."
            }
            return $matches[0]
        }
        if ($i -ge 2) { Write-Host "      (polling $($i+1)/$MaxRetries...)" -ForegroundColor DarkGray }
    }
    return $null
}

# Count the messages the admin INBOX already holds for a thread, keyed by the exact subject of
# the thread's first message (matched in memory - see Select-SeedThreadMessages). Duplicated
# threads are surfaced as an excess count so Get-SeedEmailThreadAction can refuse to continue.

Write-Host "`n===== Seeding Outlook Emails =====" -ForegroundColor Cyan
Write-Host "  Thread key mailbox: $adminUpn (Inbox)" -ForegroundColor Gray

$global:SeedEmailResults = @()

foreach ($thread in $emailData.emailThreads) {
    Write-Host "`n--- Thread: $($thread.threadName) ---" -ForegroundColor Yellow

    $ordered = @($thread.emails | Sort-Object { $_.order })
    if ($ordered.Count -eq 0) { throw "Email thread '$($thread.threadName)' declares no messages." }

    $firstSubject = $ordered[0].subject
    $expectedCount = $ordered.Count

    $state = Get-SeedInboxThreadState -Upn $adminUpn -FirstSubject $firstSubject
    $action = Get-SeedEmailThreadAction -ExistingMessageCount $state.MessageCount `
                                        -ExpectedMessageCount $expectedCount `
                                        -ThreadKey $firstSubject

    if ($action -eq 'Skip') {
        Write-Host "  SKIP: thread already complete ($($state.MessageCount)/$expectedCount messages, conversationId $($state.ConversationIds -join ', '))" -ForegroundColor Yellow
        $global:SeedEmailResults += [pscustomobject]@{
            ThreadName     = $thread.threadName
            Subject        = $firstSubject
            Action         = 'Skip'
            ConversationId = ($state.ConversationIds -join ', ')
        }
        continue
    }

    Write-Host "  CREATE: seeding $expectedCount messages" -ForegroundColor White
    $conversationId = $null
    $anchorMessageId = $null
    $seenMessageIds = @()

    foreach ($email in $ordered) {
        $fromUpn = Get-Upn $email.fromRole
        $toRecipients = @($email.toRoles | ForEach-Object {
            @{ emailAddress = @{ address = (Get-Upn $_) } }
        })
        $ccRecipients = @($email.ccRoles | ForEach-Object {
            @{ emailAddress = @{ address = (Get-Upn $_) } }
        })

        if ($email.order -eq $ordered[0].order) {
            # -- First email: send new --
            Write-Host "  [1] Sending: [$($email.fromRole)] -> [$($email.toRoles -join ', ')] | $($email.subject)" -ForegroundColor White
            $mailBody = @{
                message = @{
                    subject      = $email.subject
                    body         = @{ contentType = "HTML"; content = $email.bodyHtml }
                    toRecipients = $toRecipients
                }
                saveToSentItems = $true
            }
            if ($ccRecipients.Count -gt 0) { $mailBody.message.ccRecipients = $ccRecipients }

            Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$fromUpn/sendMail" -Body $mailBody | Out-Null

            $sent = Wait-SeedForMailboxMessage -Upn $adminUpn -Subject $email.subject -MaxRetries 12 -DelaySec 5
            if (-not $sent) {
                throw ("Could not locate the first message of thread '$firstSubject' in the $adminUpn mailbox after sending. " +
                       "Conversation tracking failed, so the remaining replies cannot be threaded. " +
                       "Preserve the existing messages and report the partial state. Seed a new dated scenario with fresh thread subjects instead.")
            }

            $conversationId = $sent.conversationId
            if (-not $conversationId) {
                throw "The first message of thread '$firstSubject' was found but carries no conversationId; cannot thread the replies."
            }
            $anchorMessageId = $sent.internetMessageId
            $seenMessageIds += $anchorMessageId
            Write-Host "    -> ConversationId: $conversationId" -ForegroundColor Gray
        }
        else {
            # -- Reply: find message in replier's mailbox, then reply --
            Write-Host "  [$($email.order)] Replying: [$($email.fromRole)] | $($email.subject)" -ForegroundColor White

            $msgInMailbox = Wait-SeedForMailboxMessage -Upn $fromUpn -InternetMessageId $anchorMessageId -MaxRetries 12 -DelaySec 5
            if (-not $msgInMailbox) {
                throw ("Could not find message '$anchorMessageId' in the $fromUpn mailbox to reply to " +
                       "(thread '$firstSubject', message order $($email.order)). Preserve the existing messages " +
                       "and report the partial state. Seed a new dated scenario with fresh thread subjects instead.")
            }

            Write-Host "    -> Found message to reply to: $($msgInMailbox.id)" -ForegroundColor Gray

            $replyBody = @{
                message = @{
                    toRecipients = $toRecipients
                }
                comment = $email.bodyHtml
            }
            if ($ccRecipients.Count -gt 0) { $replyBody.message.ccRecipients = $ccRecipients }

            Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$fromUpn/messages/$($msgInMailbox.id)/reply" -Body $replyBody | Out-Null
            Write-Host "    -> Replied successfully" -ForegroundColor Green

            $received = Wait-SeedForMailboxMessage -Upn $adminUpn -ConversationId $conversationId `
                -ExcludeInternetMessageIds $seenMessageIds -Subject $firstSubject -MaxRetries 12 -DelaySec 5
            if (-not $received) {
                throw ("Could not verify the next reply in $adminUpn Inbox for thread '$firstSubject'. " +
                       "Preserve the partial state; never resend the reply.")
            }
            $anchorMessageId = $received.internetMessageId
            $seenMessageIds += $anchorMessageId
        }
    }

    $global:SeedEmailResults += [pscustomobject]@{
        ThreadName     = $thread.threadName
        Subject        = $firstSubject
        Action         = 'Create'
        ConversationId = $conversationId
    }
    Write-Host "  Thread '$($thread.threadName)' completed." -ForegroundColor Green
}

Write-Host "`n===== Email Seeding Complete =====" -ForegroundColor Cyan
foreach ($r in $global:SeedEmailResults) {
    Write-Host ("  [{0}] {1} - conversationId: {2}" -f $r.Action, $r.Subject, $r.ConversationId) -ForegroundColor Green
}
