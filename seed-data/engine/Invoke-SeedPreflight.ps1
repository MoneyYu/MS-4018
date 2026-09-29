<#
.SYNOPSIS
    Preflight collision report for a PL-7008 seeding run. Read-only.
.DESCRIPTION
    Runs BEFORE any write phase and prints the exact tenant state of every resource the
    scenario is about to touch:

      * the dated Teams team / M365 group displayName
      * the dated SharePoint site alias (group mailNickname)
      * the first-message subject of every declared email thread

    Abort rules (engine/Seed-Idempotency.ps1):
      * more than one matching team group or site group -> throw, listing ids/names only
      * a partially seeded or duplicated email thread    -> throw
      * an existing single exact dated team is inspected here, before any write phase:
        the demo operator admin must already be a Microsoft 365 group owner AND carry the
        Teams 'owner' role; channel cardinality (exactly one General, exactly one instance of
        every declared channel, nothing else) plus BOTH top-level and reply content hashes must
        match the declared set exactly. Complete -> allowed (the Teams phase will skip
        messages); partial, extra, missing, ambiguous or wrongly owned -> throw, so no profile /
        OneDrive / mail write can happen in front of a Teams phase that would abort anyway.
      * an existing site alias must prove its identity before it is accepted: exact
        mailNickname, exact displayName, Unified (Microsoft 365) group characteristics and the
        admin among its owners. A mailNickname is a tenant-wide key an unrelated site can
        already hold, so an alias match alone is never treated as this scenario's site. The
        owning phase then verifies its lists/items/documents item by item.

    Nothing here is renamed, re-owned, promoted or deleted: a collision is reported and the run
    aborts. This script performs GET requests only, and it never matches tenant resources by
    wildcard.
.PARAMETER ConfigPath
    Path to the scenario config.json.
.PARAMETER EmailsPath
    Optional path to emails.json; omitted surfaces are not inspected.
.PARAMETER TeamsMessagesPath
    Optional path to teams-messages.json.
.PARAMETER SharePointPath
    Optional path to sharepoint-sites.json.
.PARAMETER FilesManifestPath
    Optional path to files-manifest.json; verifies a generated OneDrive scenario folder
    before any phase writes. Existing folders require a matching local and remote receipt.
#>
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [string]$EmailsPath,
    [string]$TeamsMessagesPath,
    [string]$SharePointPath,
    [string]$FilesManifestPath
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\Seed-Idempotency.ps1"
. "$PSScriptRoot\Seed-GraphRead.ps1"
. "$PSScriptRoot\Seed-OneDriveOwnership.ps1"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$emailData = if ($EmailsPath) { Get-Content $EmailsPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$teamsData = if ($TeamsMessagesPath) { Get-Content $TeamsMessagesPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$spData = if ($SharePointPath) { Get-Content $SharePointPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

$adminUpn = $config.adminUpn
if (-not $adminUpn) { throw "config.json is missing 'adminUpn'." }
if (-not $config.roles.Admin.upn -or
    -not [string]::Equals("$($config.roles.Admin.upn)", $adminUpn, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "config.json roles.Admin.upn must match adminUpn before any writes."
}
if ($config.demoUserUpn -and
    -not [string]::Equals("$($config.demoUserUpn)", $adminUpn, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "config.json demoUserUpn must match adminUpn before any writes."
}
if ($TeamsMessagesPath -and -not $config.teamDisplayName) { throw "config.json is missing 'teamDisplayName' for Teams." }

function Assert-SeedAppToken {
    $parts = "$global:AccessToken".Split('.')
    if ($parts.Count -ne 3) { throw "Graph app token has no readable claims; no writes were made." }
    try {
        $encoded = $parts[1].Replace('-', '+').Replace('_', '/')
        $encoded = $encoded.PadRight($encoded.Length + ((4 - $encoded.Length % 4) % 4), '=')
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded)) | ConvertFrom-Json
    } catch {
        throw "Graph app token claims cannot be decoded; no writes were made."
    }
    if (-not [string]::Equals("$($claims.tid)", "$($config.tenantId)", [System.StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals("$(if ($claims.appid) { $claims.appid } else { $claims.azp })", "$($config.clientId)", [System.StringComparison]::OrdinalIgnoreCase) -or
        "$($claims.aud)" -notin @('https://graph.microsoft.com', '00000003-0000-0000-c000-000000000000')) {
        throw "Graph app token tenant, client or audience does not match this scenario; no writes were made."
    }
    $roles = @($claims.roles)
    if ('User.Read.All' -notin $roles -and 'User.ReadWrite.All' -notin $roles) {
        throw "Graph app token is missing User.Read.All or User.ReadWrite.All permission; no writes were made."
    }
    $required = @()
    if ($EmailsPath) { $required += 'Mail.Send', 'Mail.ReadWrite' }
    if ($FilesManifestPath) { $required += 'Files.ReadWrite.All' }
    if ($TeamsMessagesPath) { $required += 'Group.ReadWrite.All', 'Teamwork.Migrate.All', 'TeamMember.ReadWrite.All' }
    if ($SharePointPath) { $required += 'Group.ReadWrite.All', 'Sites.Manage.All', 'Sites.ReadWrite.All', 'Files.ReadWrite.All' }
    $missing = @($required | Sort-Object -Unique | Where-Object { $_ -notin $roles })
    if ($missing.Count) { throw "Graph app token is missing required application permissions: $($missing -join ', '); no writes were made." }
}
Assert-SeedAppToken

function Invoke-Graph {
    param([string]$Method, [string]$Uri)
    $headers = @{ Authorization = "Bearer $($global:AccessToken)"; "Content-Type" = "application/json" }
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers
}

function Get-SeedPreflightGroupsByDisplayName {
    param([Parameter(Mandatory)][string]$DisplayName)
    $escaped = $DisplayName -replace "'", "''"
    $filter = [System.Uri]::EscapeDataString("displayName eq '$escaped'")
    $r = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName,mailNickname,resourceProvisioningOptions"
    return @($r.value)
}

function Get-SeedPreflightGroupsByAlias {
    param([Parameter(Mandatory)][string]$Alias)
    $escaped = $Alias -replace "'", "''"
    $filter = [System.Uri]::EscapeDataString("mailNickname eq '$escaped'")
    $r = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName,mailNickname,groupTypes"
    return @($r.value)
}

Write-Host "`n===== Preflight Collision Report (read-only) =====" -ForegroundColor Cyan
Write-Host "  Admin mailbox: $adminUpn" -ForegroundColor Gray

$findings = @()
$roleMap = @{}
$accounts = @([pscustomobject]@{ Role = 'Admin'; Upn = $adminUpn })
foreach ($role in $config.roles.PSObject.Properties) {
    $upn = "$($role.Value.upn)".Trim()
    if (-not $upn) { throw "Preflight: role '$($role.Name)' has no UPN." }
    $roleMap[$role.Name] = $role.Value
    $accounts += [pscustomobject]@{ Role = $role.Name; Upn = $upn }
}
foreach ($account in $accounts) {
    $encodedUpn = [System.Uri]::EscapeDataString($account.Upn)
    try {
        $user = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$encodedUpn`?`$select=id,userPrincipalName,accountEnabled"
    } catch {
        throw "Preflight: role '$($account.Role)' account '$($account.Upn)' is missing or unreadable: $(Get-SeedGraphErrorText -ErrorObject $_). No writes were made."
    }
    if (-not $user.id -or -not [string]::Equals("$($user.userPrincipalName)", $account.Upn, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Preflight: role '$($account.Role)' account '$($account.Upn)' could not be verified. No writes were made."
    }
    if ($user.accountEnabled -ne $true) {
        throw "Preflight: role '$($account.Role)' account '$($account.Upn)' is disabled or accountEnabled is unavailable. No writes were made."
    }
}
if ($FilesManifestPath) {
    $filePlan = Get-SeedStrictOneDrivePlan -ConfigPath $ConfigPath -FilesManifestPath $FilesManifestPath
    $folderState = Get-SeedStrictOneDriveState -Plan $filePlan
    Write-Host "  OneDrive folder '$($filePlan.Folder)': $($folderState.Action) (verified ownership or new target)"
}

# The declared plan is needed by the team inspection below, so it is built up front.
$plan = if ($TeamsMessagesPath) { Get-SeedExpectedTeamsPlan -Channels $teamsData.channels } else { $null }

# --- 1. Dated Teams team / M365 group displayName ---
if ($TeamsMessagesPath) {
$teamDisplayName = $config.teamDisplayName
Write-Host "`n  [1] Team / group displayName: '$teamDisplayName'" -ForegroundColor Yellow

$groupsByName = Get-SeedPreflightGroupsByDisplayName -DisplayName $teamDisplayName
$teamGroups = @($groupsByName | Where-Object { $_.resourceProvisioningOptions -contains "Team" })

foreach ($g in $groupsByName) {
    $kind = if ($g.resourceProvisioningOptions -contains "Team") { "team group" } else { "group (no team)" }
    Write-Host "      FOUND $kind : $($g.id) | $($g.displayName) | alias=$($g.mailNickname)" -ForegroundColor Gray
}
if ($groupsByName.Count -eq 0) { Write-Host "      none - will be created" -ForegroundColor Gray }

$teamAction = Get-SeedResourceAction -Existing $teamGroups -ResourceKind 'team group' -ResourceKey $teamDisplayName
if ($groupsByName.Count -gt $teamGroups.Count -and $teamAction -eq 'Create') {
    throw ("Collision: a non-Team group already uses displayName '$teamDisplayName' " +
           "($(($groupsByName | ForEach-Object { $_.id }) -join '; ')). Resolve it manually, then re-run.")
}

$teamId = $null
if ($teamAction -eq 'Reuse') {
    # An existing dated team is only acceptable when BOTH its ownership and its content can be
    # verified NOW, before Phase 1 writes anything. Ownership is proven first: the demo operator
    # admin must already be a group owner AND carry the Teams 'owner' role. Channel cardinality
    # and both content levels follow; the verdict throws on partial, extra, missing or ambiguous
    # state.
    $teamId = $teamGroups[0].id
    Write-Host "      ACTION: Reuse ($teamId) - verifying admin ownership, declared channels and message/reply content" -ForegroundColor White

    $groupOwnerUpns = Get-SeedGroupOwnerUpns -GroupId $teamId
    Write-Host "      FOUND group owners: $(@($groupOwnerUpns) -join ', ')" -ForegroundColor Gray
    $teamMembers = Get-SeedTeamMembers -TeamId $teamId
    Write-Host "      FOUND team members: $(@($teamMembers).Count)" -ForegroundColor Gray

    $ownership = Get-SeedTeamOwnershipVerdict -GroupOwners $groupOwnerUpns `
                                              -TeamMembers $teamMembers `
                                              -AdminUpn $adminUpn `
                                              -TeamKey $teamDisplayName
    Write-Host "      OWNERSHIP: '$adminUpn' is both a group owner and a team owner -> $($ownership.Action)" -ForegroundColor White
    $findings += [pscustomobject]@{ Kind = 'TeamOwnership'; Key = $teamDisplayName; Action = $ownership.Action; Id = $teamId }

    $existingChannels = Get-SeedTeamChannels -TeamId $teamId
    foreach ($ch in @($existingChannels)) {
        Write-Host "      FOUND channel: $($ch.id) | $($ch.displayName)" -ForegroundColor Gray
    }

    $verdict = Get-SeedTeamContentVerdict -PlanChannels $plan.Channels `
                                          -ExistingChannels $existingChannels `
                                          -ChannelStateProvider { param($Channel) Get-SeedChannelMessageState -TeamId $teamId -ChannelId $Channel.id } `
                                          -TeamKey $teamDisplayName

    foreach ($cv in @($verdict.Channels)) {
        Write-Host "      CONTENT '$($cv.ChannelName)': complete ($($cv.ExistingTopLevel) top-level found) -> messages $($cv.MessageAction)" -ForegroundColor White
        $findings += [pscustomobject]@{ Kind = 'TeamChannel'; Key = $cv.ChannelName; Action = $cv.MessageAction; Id = $cv.ChannelId }
    }
} else {
    Write-Host "      ACTION: $teamAction" -ForegroundColor White
}
$findings += [pscustomobject]@{ Kind = 'TeamGroup'; Key = $teamDisplayName; Action = $teamAction; Id = $teamId }
}

# --- 2. Dated SharePoint site alias ---
if ($SharePointPath) {
Write-Host "`n  [2] SharePoint site aliases" -ForegroundColor Yellow
foreach ($site in @($spData.sites)) {
    $alias = $site.alias
    $siteGroups = Get-SeedPreflightGroupsByAlias -Alias $alias
    foreach ($g in $siteGroups) {
        Write-Host "      FOUND group: $($g.id) | $($g.displayName) | alias=$($g.mailNickname) | groupTypes=$(@($g.groupTypes) -join ',')" -ForegroundColor Gray
    }
    if ($siteGroups.Count -eq 0) { Write-Host "      '$alias' none - will be created" -ForegroundColor Gray }

    # An alias match alone is not identity: a mailNickname is a tenant-wide key an unrelated
    # group can already hold. Exact displayName, Unified group characteristics and admin
    # ownership are all proven here, before Phase 1, so no write can land in a foreign site.
    $siteVerdict = Get-SeedSiteGroupVerdict -ExistingGroups $siteGroups `
                                            -Alias $alias `
                                            -DisplayName $site.displayName `
                                            -AdminUpn $adminUpn `
                                            -OwnerProvider { param($Group) Get-SeedGroupOwnerUpns -GroupId $Group.id }
    $siteAction = $siteVerdict.Action
    if ($siteAction -eq 'Reuse') {
        Assert-SeedSiteGroupRoles -GroupId $siteVerdict.GroupId -Alias $alias `
            -OwnerRoles $site.owners -MemberRoles $site.members `
            -RoleMap $roleMap -OwnerUpns $siteVerdict.OwnerUpns
        Write-Host "      '$alias' IDENTITY: displayName '$($siteVerdict.DisplayName)' | Unified group | owners $(@($siteVerdict.OwnerUpns) -join ', ')" -ForegroundColor Gray
    }
    Write-Host "      '$alias' ACTION: $siteAction$(if ($siteAction -eq 'Reuse') { " ($($siteVerdict.GroupId)) - lists/items/documents are verified item by item" })" -ForegroundColor White
    $findings += [pscustomobject]@{ Kind = 'SiteGroup'; Key = $alias; Action = $siteAction; Id = $siteVerdict.GroupId }
}
}

# --- 3. Email thread first-message subjects ---
if ($EmailsPath) {
Write-Host "`n  [3] Email thread first-message subjects (in $adminUpn Inbox)" -ForegroundColor Yellow

# One paged Inbox snapshot, matched in memory. Deleted Items / Sent Items are deliberately
# out of scope: only an Inbox message is a usable demo mail.
$adminInbox = Get-SeedInboxMessages -Upn $adminUpn
Write-Host "      Inbox messages fetched: $(@($adminInbox).Count)" -ForegroundColor DarkGray

foreach ($thread in @($emailData.emailThreads)) {
    $ordered = @($thread.emails | Sort-Object { $_.order })
    if ($ordered.Count -eq 0) { throw "Email thread '$($thread.threadName)' declares no messages." }
    $firstSubject = $ordered[0].subject
    $expected = $ordered.Count

    $state = Get-SeedInboxThreadState -Upn $adminUpn -FirstSubject $firstSubject -Messages $adminInbox
    Write-Host "      '$firstSubject' : $($state.MessageCount) existing / $expected expected" -ForegroundColor Gray
    foreach ($cid in $state.ConversationIds) { Write-Host "        conversationId: $cid" -ForegroundColor DarkGray }

    $threadAction = Get-SeedEmailThreadAction -ExistingMessageCount $state.MessageCount `
                                              -ExpectedMessageCount $expected `
                                              -ThreadKey $firstSubject
    Write-Host "      ACTION: $threadAction" -ForegroundColor White
    $findings += [pscustomobject]@{
        Kind   = 'EmailThread'
        Key    = $firstSubject
        Action = $threadAction
        Id     = ($state.ConversationIds -join ', ')
    }
}
}

# --- 4. Declared Teams message plan (data-side sanity check) ---
if ($TeamsMessagesPath) {
    Write-Host "`n  [4] Declared Teams content: $($plan.TopLevelCount) top-level messages / $($plan.ReplyCount) replies" -ForegroundColor Yellow
}

$global:SeedPreflightResult = $findings

Write-Host "`n  No blocking collision detected. Nothing was created, modified or deleted." -ForegroundColor Green
Write-Host "===== Preflight Complete =====" -ForegroundColor Cyan
