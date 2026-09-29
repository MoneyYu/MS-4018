<#
.SYNOPSIS
    Seed Teams channels and messages via Microsoft Graph (Application Permissions).
.DESCRIPTION
    Creates a Team (migration mode), channels, and injects messages with historical dates
    using the Teams Migration API, completes migration, then adds members.

    Idempotency (see engine/Seed-Idempotency.ps1):
      * The team is keyed by the exact dated displayName.
          0 matching team groups -> create
          1 matching team group  -> reuse
          >1                     -> throw, listing resource ids/names only
      * A reused team must first PROVE that the demo operator admin already owns it: the
        Microsoft 365 group owner collection must contain the admin, and the team membership
        must carry the admin with a 'roles' entry of 'owner'. Either one missing -> ABORT
        before any write. The seeder never promotes a role on a team it did not create.
      * Channels are keyed by exact channel displayName (reuse one, throw on duplicates), and
        the channel set must match exactly: one General, one instance of every declared
        channel, no extras.
      * Message identity is a SHA-256 hash of whitespace-normalized HTML content.
        Replies are fetched separately per parent via /messages/{id}/replies because
        list-channel-messages does not return replies.
      * A reused team whose expected top-level/reply set is complete -> skip messages.
      * A reused team missing any expected message or reply -> ABORT.
        Controller ruling (SDD ledger, Task 3): no automatic recovery. Migration may
        already be complete, in which case historical timestamps can no longer be
        written and a "resume" would silently corrupt the demo dataset.
      * Both completeMigration levels run on every path, including a reused complete team:
        a run that wrote all messages but died before completion would otherwise leave the
        team in migration mode forever, and membership cannot be added in that state.
        "Already completed" / "not in migration" is success; anything else throws.
      * This script never deletes anything and never matches resources by wildcard.
.PARAMETER ConfigPath
    Path to the scenario config.json.
.PARAMETER TeamsMessagesPath
    Path to the teams-messages.json data file.
#>
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$TeamsMessagesPath
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\Seed-Idempotency.ps1"
. "$PSScriptRoot\Seed-GraphRead.ps1"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$teamsData = Get-Content $TeamsMessagesPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Build role -> user info lookup
$roleMap = @{}
$userIdCache = @{}
foreach ($prop in $config.roles.PSObject.Properties) {
    $roleMap[$prop.Name] = $prop.Value
}

function Invoke-Graph {
    param(
        [string]$Method,
        [string]$Uri,
        [object]$Body,
        [string]$ApiVersion = "v1.0"
    )
    $headers = @{
        Authorization  = "Bearer $($global:AccessToken)"
        "Content-Type" = "application/json"
    }
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

function Get-UserForMessage([string]$roleName) {
    if (-not $roleMap.ContainsKey($roleName)) { throw "Unknown role in teams-messages.json: $roleName" }
    $role = $roleMap[$roleName]
    $userId = Get-UserId $role.upn
    return @{
        id          = $userId
        upn         = $role.upn
        displayName = $role.displayName
    }
}

# Exact displayName lookup, restricted to groups that are actually Teams.
function Get-SeedTeamGroup {
    param([Parameter(Mandatory)][string]$DisplayName)
    $escaped = $DisplayName -replace "'", "''"
    $filter = [System.Uri]::EscapeDataString("displayName eq '$escaped'")
    $groups = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName,resourceProvisioningOptions"
    return @($groups.value | Where-Object { $_.resourceProvisioningOptions -contains "Team" })
}

# Bounded polling after an async team creation. Returns $null when the budget is spent;
# the caller turns that into a terminating error.
function Wait-SeedForTeamProvisioning {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [int]$MaxRetries = 30,
        [int]$DelaySec = 5
    )
    for ($i = 0; $i -lt $MaxRetries; $i++) {
        Start-Sleep -Seconds $DelaySec
        try {
            $found = Get-SeedTeamGroup -DisplayName $DisplayName
            if ($found.Count -eq 1) { return $found[0] }
            if ($found.Count -gt 1) { return $null }
        } catch {
            # Bounded, deliberate retry while the group is still provisioning.
            # No state is changed here and the caller throws once the budget is spent.
        }
    }
    return $null
}

function New-SeedMessageBody {
    param([Parameter(Mandatory)]$Message)

    $userInfo = Get-UserForMessage $Message.fromRole
    $body = @{
        createdDateTime = $Message.createdDateTime
        from            = @{
            user = @{
                id               = $userInfo.id
                displayName      = $userInfo.displayName
                userIdentityType = "aadUser"
            }
        }
        body            = @{
            contentType = "html"
            content     = $Message.bodyHtml
        }
    }

    if ($Message.mentions -and $Message.mentions.Count -gt 0) {
        $mentionsList = @()
        for ($mi = 0; $mi -lt $Message.mentions.Count; $mi++) {
            $mentionUser = Get-UserForMessage $Message.mentions[$mi]
            $mentionsList += @{
                id          = $mi
                mentionText = $mentionUser.displayName
                mentioned   = @{
                    user = @{
                        id               = $mentionUser.id
                        displayName      = $mentionUser.displayName
                        userIdentityType = "aadUser"
                    }
                }
            }
        }
        $body.mentions = $mentionsList
    }

    return $body
}

# ---------------------------------------------------------------
Write-Host "`n===== Seeding Teams Channels =====" -ForegroundColor Cyan

$teamDisplayName = $config.teamDisplayName
if (-not $teamDisplayName) { throw "config.json is missing 'teamDisplayName' - the team is keyed on the exact dated display name." }
$adminUpn = $config.adminUpn
if (-not $adminUpn) { throw "config.json is missing 'adminUpn' - the demo operator must be provable as team owner." }

$plan = Get-SeedExpectedTeamsPlan -Channels $teamsData.channels
Write-Host "  Declared: $($plan.TopLevelCount) top-level messages / $($plan.ReplyCount) replies in $($plan.Channels.Count) channel(s)" -ForegroundColor Gray

# Team + channel creation dates must precede the earliest declared message.
$allDates = @()
foreach ($ch in @($teamsData.channels)) {
    foreach ($m in @($ch.messages)) {
        $allDates += [datetime]::Parse($m.createdDateTime, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        foreach ($r in @($m.replies)) {
            $allDates += [datetime]::Parse($r.createdDateTime, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        }
    }
}
if ($allDates.Count -eq 0) { throw "teams-messages.json declares no messages." }
$teamCreatedDate = (($allDates | Sort-Object | Select-Object -First 1).ToUniversalTime().AddDays(-1)).ToString("yyyy-MM-ddT00:00:00Z")

# --- Step 1: resolve the team (create or reuse, never guess) ---
Write-Host "`n[Step 1] Resolving team: $teamDisplayName" -ForegroundColor Yellow

$existingTeams = Get-SeedTeamGroup -DisplayName $teamDisplayName
$teamAction = Get-SeedResourceAction -Existing $existingTeams -ResourceKind 'team group' -ResourceKey $teamDisplayName

$ownerUpn = $config.demoUserUpn
$teamId = $null
$isNewTeam = $false

if ($teamAction -eq 'Reuse') {
    $teamId = $existingTeams[0].id
    Write-Host "  REUSE: existing team group $teamId" -ForegroundColor Yellow

    # Same ownership proof the preflight already ran, executed again against live state right
    # before the write window (defense in depth). The demo operator admin must ALREADY be a
    # group owner and carry the Teams 'owner' role; a reused team that left admin as a plain
    # member aborts here, before migration completion and before any membership call. The
    # seeder never promotes a role on a team it did not create.
    $ownership = Get-SeedTeamOwnershipVerdict -GroupOwners (Get-SeedGroupOwnerUpns -GroupId $teamId) `
                                              -TeamMembers (Get-SeedTeamMembers -TeamId $teamId) `
                                              -AdminUpn $adminUpn `
                                              -TeamKey $teamDisplayName
    Write-Host "  OWNERSHIP: '$adminUpn' verified as group owner and team owner [$($ownership.Action)]" -ForegroundColor Yellow
} else {
    Write-Host "  CREATE: new team in migration mode (createdDateTime $teamCreatedDate)" -ForegroundColor White
    $isNewTeam = $true

    $teamBody = @{
        "template@odata.bind"               = "https://graph.microsoft.com/v1.0/teamsTemplates('standard')"
        displayName                         = $teamDisplayName
        description                         = $config.teamDescription
        createdDateTime                     = $teamCreatedDate
        "@microsoft.graph.teamCreationMode" = "migration"
    }

    $teamResult = Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/teams" -Body $teamBody
    if ($teamResult -and $teamResult.id) {
        $teamId = $teamResult.id
    } else {
        Write-Host "  Waiting for team provisioning..." -ForegroundColor Gray
        $provisioned = Wait-SeedForTeamProvisioning -DisplayName $teamDisplayName
        if (-not $provisioned) {
            throw ("Team '$teamDisplayName' did not provision as exactly one team group within the polling budget. " +
                   "Check Teamwork.Migrate.All consent and the tenant state, then re-run.")
        }
        $teamId = $provisioned.id
    }
    Write-Host "  Team created: $teamId" -ForegroundColor Green
}

# --- Step 2: resolve channels + decide message action ---
Write-Host "`n[Step 2] Resolving channels..." -ForegroundColor Yellow

$channelPlans = @()

if (-not $isNewTeam) {
    # Same verification the preflight already ran, executed again against live state right
    # before the write window: channel cardinality plus top-level AND reply content hashes.
    # Complete -> skip messages; partial, extra, missing or ambiguous -> abort.
    $existingChannels = Get-SeedTeamChannels -TeamId $teamId
    $verdict = Get-SeedTeamContentVerdict -PlanChannels $plan.Channels `
                                          -ExistingChannels $existingChannels `
                                          -ChannelStateProvider { param($Channel) Get-SeedChannelMessageState -TeamId $teamId -ChannelId $Channel.id } `
                                          -TeamKey $teamDisplayName

    foreach ($planChannel in $plan.Channels) {
        $cv = @($verdict.Channels | Where-Object { $_.ChannelName -eq $planChannel.ChannelName })[0]
        Write-Host "  REUSE channel '$($cv.ChannelName)': $($cv.ChannelId)" -ForegroundColor Yellow
        Write-Host "    Messages: $($cv.MessageAction) ($($cv.ExistingTopLevel) top-level found)" -ForegroundColor Gray
        $channelPlans += [pscustomobject]@{
            Plan          = $planChannel
            ChannelId     = $cv.ChannelId
            MessageAction = $cv.MessageAction
        }
    }
} else {
    foreach ($planChannel in $plan.Channels) {
        $channelName = $planChannel.ChannelName
        Write-Host "  CREATE channel '$channelName'" -ForegroundColor White
        $channelBody = @{
            "@microsoft.graph.channelCreationMode" = "migration"
            displayName                            = $channelName
            description                            = $planChannel.Source.channelDescription
            membershipType                         = "standard"
            createdDateTime                        = $teamCreatedDate
        }
        $created = Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/teams/$teamId/channels" -Body $channelBody
        $channelId = $created.id
        if (-not $channelId) { throw "Channel creation for '$channelName' returned no channel id." }
        Write-Host "    Channel ID: $channelId" -ForegroundColor Gray
        Start-Sleep -Seconds 2

        $channelPlans += [pscustomobject]@{
            Plan          = $planChannel
            ChannelId     = $channelId
            MessageAction = 'Create'
        }
    }
}

# --- Step 3: inject messages with historical dates ---
Write-Host "`n[Step 3] Injecting messages..." -ForegroundColor Yellow

foreach ($cp in $channelPlans) {
    $channelName = $cp.Plan.ChannelName
    Write-Host "`n  --- Channel: $channelName ---" -ForegroundColor Yellow

    if ($cp.MessageAction -eq 'Skip') {
        Write-Host "    SKIP: all $($cp.Plan.Messages.Count) top-level messages and their replies already present." -ForegroundColor Yellow
        continue
    }

    foreach ($msg in $cp.Plan.Messages) {
        $source = $msg.Source
        Write-Host "    [$($source.fromRole)] $($source.createdDateTime)" -ForegroundColor White

        $msgBody = New-SeedMessageBody -Message $source
        $msgResult = Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/teams/$teamId/channels/$($cp.ChannelId)/messages" -Body $msgBody
        $messageId = $msgResult.id
        if (-not $messageId) { throw "Teams message creation for channel '$channelName' returned no message id." }

        foreach ($reply in @($source.replies)) {
            Write-Host "      -> [$($reply.fromRole)] reply" -ForegroundColor Gray
            $replyBody = New-SeedMessageBody -Message $reply
            Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/teams/$teamId/channels/$($cp.ChannelId)/messages/$messageId/replies" -Body $replyBody | Out-Null
            Start-Sleep -Seconds 1
        }
        Start-Sleep -Seconds 2
    }
}

# --- Step 4: complete migration (channels first, then team) ---
# This runs on EVERY path, not only after a fresh creation. A previous run that wrote all
# messages but died before completing migration leaves the team in migration mode; on the
# re-run its content hashes look complete, message creation is skipped, and membership would
# then fail because a team in migration mode accepts no members. Both levels are idempotent:
# "already completed" / "not in migration" is success, anything else throws.
Write-Host "`n[Step 4] Completing migration (idempotent, channel level then team level)..." -ForegroundColor Yellow

# Every channel, including General, must be completed before the team.
$allChannels = Get-SeedTeamChannels -TeamId $teamId
foreach ($ch in @($allChannels)) {
    Write-Host "  Completing channel: $($ch.displayName)" -ForegroundColor White
    try {
        Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/teams/$teamId/channels/$($ch.id)/completeMigration" | Out-Null
        Start-Sleep -Seconds 2
    } catch {
        if (Test-SeedMigrationAlreadyComplete -ErrorRecord $_) {
            Write-Host "    (already completed)" -ForegroundColor Gray
        } else {
            throw "Failed to complete migration for channel '$($ch.displayName)' ($($ch.id)): $(Get-SeedGraphErrorText -ErrorObject $_)"
        }
    }
}

Write-Host "  Completing team migration..." -ForegroundColor White
try {
    Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/teams/$teamId/completeMigration" | Out-Null
    Start-Sleep -Seconds 5
} catch {
    if (Test-SeedMigrationAlreadyComplete -ErrorRecord $_) {
        Write-Host "    (already completed)" -ForegroundColor Gray
    } else {
        throw "Failed to complete migration for team '$teamDisplayName' ($teamId): $(Get-SeedGraphErrorText -ErrorObject $_)"
    }
}

# --- Step 5: add team members (idempotent) ---
# A duplicate-member error is absorbed here ONLY because the reuse path above already proved
# that the demo operator admin holds the expected owner role on this team (and the create path
# built the team itself). Without that proof, "already exists" could be hiding a member entry
# whose role is not the declared one.
Write-Host "`n[Step 5] Adding team members..." -ForegroundColor Yellow

foreach ($prop in $config.roles.PSObject.Properties) {
    $role = $prop.Value
    $upn = $role.upn

    $userId = Get-UserId $upn
    # `$x = if (...) { @('owner') } else { @() }` assigns the OUTPUT of a statement, which
    # PowerShell unwraps: a one-element array collapses to a scalar and an empty array to
    # $null. ConvertTo-Json then emits "roles":"owner" / "roles":null, and Graph rejects the
    # membership with 400 "Could not cast or convert from System.String to
    # System.Collections.Generic.IEnumerable`1[System.String]". aadUserConversationMember.roles
    # is a String collection, so the array is built by direct typed assignment instead.
    [string[]]$memberRoles = @()
    if ($upn -eq $ownerUpn -or $upn -eq $adminUpn) { [string[]]$memberRoles = @('owner') }
    Write-Host "  Adding: $($role.displayName) ($upn) [$(if ($memberRoles.Count -gt 0) { 'owner' } else { 'member' })]" -ForegroundColor White

    $memberBody = @{
        "@odata.type"     = "#microsoft.graph.aadUserConversationMember"
        "roles"           = $memberRoles
        "user@odata.bind" = "https://graph.microsoft.com/v1.0/users('$userId')"
    }

    try {
        Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/teams/$teamId/members" -Body $memberBody | Out-Null
        Start-Sleep -Seconds 1
    } catch {
        if (Test-SeedMemberAlreadyExists -ErrorRecord $_) {
            Write-Host "    (already a member)" -ForegroundColor Gray
        } else {
            throw "Failed to add '$upn' to team '$teamDisplayName' ($teamId): $(Get-SeedGraphErrorText -ErrorObject $_)"
        }
    }
}

$global:SeedTeamsResult = [pscustomobject]@{
    TeamDisplayName = $teamDisplayName
    TeamId          = $teamId
    TeamAction      = $teamAction
    Channels        = @($channelPlans | ForEach-Object {
        [pscustomobject]@{
            ChannelName   = $_.Plan.ChannelName
            ChannelId     = $_.ChannelId
            MessageAction = $_.MessageAction
        }
    })
}

Write-Host "`n===== Teams Channel Seeding Complete =====" -ForegroundColor Cyan
Write-Host "Team: $teamDisplayName [$teamAction] -> $teamId" -ForegroundColor Green
foreach ($c in $global:SeedTeamsResult.Channels) {
    Write-Host "  Channel '$($c.ChannelName)' [$($c.MessageAction)] -> $($c.ChannelId)" -ForegroundColor Green
}
