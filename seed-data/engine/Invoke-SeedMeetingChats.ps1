<#
.SYNOPSIS
    Seed meeting group chats via Chat Migration API (Application Permissions only).
.DESCRIPTION
    Creates group chats, then uses startMigration (beta) to enter migration mode,
    injects messages with different from.user (real multi-user avatars) and
    historical createdDateTime, then completes migration and adds members.
    Uses Teamwork.Migrate.All — NO delegated login required.
.PARAMETER ConfigPath
    Path to the scenario config.json.
.PARAMETER MeetingChatsPath
    Path to the meeting-chats.json data file.
#>
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$MeetingChatsPath
)

$ErrorActionPreference = "Stop"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$chatData = Get-Content $MeetingChatsPath -Raw -Encoding UTF8 | ConvertFrom-Json

$roleMap = @{}
foreach ($prop in $config.roles.PSObject.Properties) {
    $roleMap[$prop.Name] = $prop.Value
}

$userIdCache = @{}

function Get-Upn([string]$role) {
    if (-not $roleMap.ContainsKey($role)) { throw "Unknown role: $role" }
    return $roleMap[$role].upn
}

function Invoke-Graph {
    param([string]$Method, [string]$Uri, [object]$Body)
    $headers = @{ Authorization = "Bearer $($global:AccessToken)"; "Content-Type" = "application/json" }
    $bodyJson = if ($Body) { $Body | ConvertTo-Json -Depth 20 -Compress } else { $null }
    $params = @{ Method = $Method; Uri = $Uri; Headers = $headers }
    if ($bodyJson) { $params.Body = [System.Text.Encoding]::UTF8.GetBytes($bodyJson) }
    return Invoke-RestMethod @params
}

function Get-UserId([string]$upn) {
    if (-not $userIdCache.ContainsKey($upn)) {
        $user = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$upn"
        $userIdCache[$upn] = $user.id
    }
    return $userIdCache[$upn]
}

Write-Host "`n===== Seeding Meeting Chats (startMigration API) =====" -ForegroundColor Cyan
Write-Host "  Auth: Application Permissions only (no delegated login needed)" -ForegroundColor Gray

$today = (Get-Date).Date

foreach ($chat in $chatData.meetingChats) {
    Write-Host "`n--- Chat: $($chat.topic) ---" -ForegroundColor Yellow

    # Calculate chat date from dayOffset
    $chatDayOffset = if ($null -ne $chat.dayOffset) { $chat.dayOffset } else { -1 }
    $chatDate = $today.AddDays($chatDayOffset)

    # ── Step 1: Create normal group chat with members (App permissions) ──
    Write-Host "  [1/5] Creating group chat..." -ForegroundColor White

    $members = @()
    foreach ($role in $chat.memberRoles) {
        $upn = Get-Upn $role
        $userId = Get-UserId $upn
        $members += @{
            "@odata.type"     = "#microsoft.graph.aadUserConversationMember"
            "roles"           = @("owner")
            "user@odata.bind" = "https://graph.microsoft.com/v1.0/users('$userId')"
        }
    }

    try {
        $chatResult = Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/chats" -Body @{
            chatType = "group"
            topic    = $chat.topic
            members  = $members
        }
        $chatId = $chatResult.id
        Write-Host "  Chat ID: $chatId" -ForegroundColor Gray
    } catch {
        Write-Host "  ERROR creating chat: $($_.Exception.Message)" -ForegroundColor Red
        continue
    }

    Start-Sleep -Seconds 3

    # ── Step 2: Start migration mode (beta API) ──
    Write-Host "  [2/5] Starting migration mode..." -ForegroundColor White

    # conversationCreationDateTime must be earlier than the chat's createdDateTime
    $migrationStartDate = $chatDate.AddDays(-1).ToUniversalTime().ToString("yyyy-MM-ddT00:00:00Z")

    try {
        Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/beta/chats/$chatId/startMigration" -Body @{
            conversationCreationDateTime = $migrationStartDate
        }
        Write-Host "  -> Migration mode started" -ForegroundColor Green
    } catch {
        Write-Host "  ERROR starting migration: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Falling back to normal message sending..." -ForegroundColor DarkYellow

        # Fallback: send messages without migration (all show as app/admin)
        $msgCount = 0
        foreach ($msg in $chat.messages) {
            $senderName = $roleMap[$msg.fromRole].displayName
            $senderTitle = $roleMap[$msg.fromRole].title
            $content = "<p><strong>$senderName ($senderTitle)</strong></p>" + $msg.bodyHtml
            try {
                Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/chats/$chatId/messages" -Body @{
                    body = @{ contentType = "html"; content = $content }
                }
                $msgCount++
            } catch {
                Write-Host "    ERROR [$senderName]: $($_.Exception.Message)" -ForegroundColor Red
            }
            Start-Sleep -Milliseconds 800
        }
        Write-Host "  -> $msgCount/$($chat.messages.Count) messages sent (fallback)" -ForegroundColor Yellow
        continue
    }

    Start-Sleep -Seconds 2

    # ── Step 3: Inject messages with different from.user and historical dates ──
    Write-Host "  [3/5] Injecting messages with multi-user avatars..." -ForegroundColor White

    $startHour = if ($chat.startTime) { [int]($chat.startTime.Split(":")[0]) } else { 10 }
    $startMinute = if ($chat.startTime) { [int]($chat.startTime.Split(":")[1]) } else { 0 }

    $msgCount = 0
    for ($i = 0; $i -lt $chat.messages.Count; $i++) {
        $msg = $chat.messages[$i]
        $fromUpn = Get-Upn $msg.fromRole
        $fromUserId = Get-UserId $fromUpn
        $fromDisplayName = $roleMap[$msg.fromRole].displayName

        # Calculate message timestamp
        $msgMinuteOffset = $startMinute + ($i * 2)
        $msgHour = $startHour + [math]::Floor($msgMinuteOffset / 60)
        $msgMin = $msgMinuteOffset % 60
        $msgDateTime = $chatDate.AddHours($msgHour).AddMinutes($msgMin).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.000Z")

        $msgBody = @{
            createdDateTime = $msgDateTime
            from = @{
                user = @{
                    id               = $fromUserId
                    displayName      = $fromDisplayName
                    userIdentityType = "aadUser"
                }
            }
            body = @{
                contentType = "html"
                content     = $msg.bodyHtml
            }
        }

        # Add mentions if present
        if ($msg.mentions -and $msg.mentions.Count -gt 0) {
            $mentionsList = @()
            for ($mi = 0; $mi -lt $msg.mentions.Count; $mi++) {
                $mentionRole = $msg.mentions[$mi]
                $mentionUpn = Get-Upn $mentionRole
                $mentionUserId = Get-UserId $mentionUpn
                $mentionDisplayName = $roleMap[$mentionRole].displayName
                $mentionsList += @{
                    id = $mi
                    mentionText = $mentionDisplayName
                    mentioned = @{
                        user = @{
                            id = $mentionUserId
                            displayName = $mentionDisplayName
                            userIdentityType = "aadUser"
                        }
                    }
                }
            }
            $msgBody.mentions = $mentionsList
        }

        try {
            Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/chats/$chatId/messages" -Body $msgBody
            $msgCount++
            Write-Host "    [$($msg.fromRole)] $fromDisplayName" -ForegroundColor Gray
        } catch {
            Write-Host "    ERROR [$fromDisplayName]: $($_.Exception.Message)" -ForegroundColor Red
        }

        Start-Sleep -Seconds 1
    }

    Write-Host "  -> $msgCount/$($chat.messages.Count) messages injected" -ForegroundColor Green

    # ── Step 4: Complete migration ──
    Write-Host "  [4/5] Completing migration..." -ForegroundColor White
    try {
        Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/beta/chats/$chatId/completeMigration"
        Write-Host "  -> Migration completed" -ForegroundColor Green
    } catch {
        Write-Host "  -> ERROR completing migration: $($_.Exception.Message)" -ForegroundColor Red
    }

    Start-Sleep -Seconds 3

    # ── Step 5: Update member visibleHistoryStartDateTime ──
    # After migration, re-add members so they can see the imported messages
    Write-Host "  [5/5] Updating member visibility..." -ForegroundColor White

    # Get current members
    try {
        $currentMembers = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/chats/$chatId/members"
    } catch {
        Write-Host "  -> Could not retrieve members: $($_.Exception.Message)" -ForegroundColor DarkYellow
        $currentMembers = $null
    }

    if ($currentMembers -and $currentMembers.value) {
        $historyStart = $chatDate.AddDays(-1).ToUniversalTime().ToString("yyyy-MM-ddT00:00:00Z")
        foreach ($member in $currentMembers.value) {
            try {
                # Remove and re-add with visibleHistoryStartDateTime
                Invoke-Graph -Method DELETE -Uri "https://graph.microsoft.com/v1.0/chats/$chatId/members/$($member.id)"
                Start-Sleep -Milliseconds 500

                $reAddBody = @{
                    "@odata.type"               = "#microsoft.graph.aadUserConversationMember"
                    "roles"                      = @("owner")
                    "user@odata.bind"            = "https://graph.microsoft.com/v1.0/users('$($member.userId)')"
                    "visibleHistoryStartDateTime" = $historyStart
                }
                Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/chats/$chatId/members" -Body $reAddBody | Out-Null
            } catch {
                # Member operations may fail for some users, continue
            }
            Start-Sleep -Milliseconds 300
        }
        Write-Host "  -> Member visibility updated" -ForegroundColor Green
    }

    Start-Sleep -Seconds 2
}

Write-Host "`n===== Meeting Chat Seeding Complete =====" -ForegroundColor Cyan
