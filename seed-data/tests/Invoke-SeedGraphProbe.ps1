<#
.SYNOPSIS
    Offline Microsoft Graph stub probe for the PL-7008 seed engine test harness.
.DESCRIPTION
    Runs a real engine script (Invoke-SeedPreflight.ps1 / Invoke-SeedTeamsChannel.ps1) in a
    child process against an in-process fake Graph. `Invoke-RestMethod` is shadowed by a
    function in this script's scope, so every request the engine makes is recorded and
    answered locally. NO NETWORK CALL IS EVER MADE and no tenant is contacted.

    The fake tenant content is derived from the scenario's own teams-messages.json /
    emails.json, so the probe exercises the real hashing, pagination, matching and
    idempotency code paths rather than a hand-written fixture.

    Results are written as UTF-8 JSON to -ResultPath (stdout is only for humans):
      Threw / ErrorMessage / Requests[] / Findings[] / TeamsResult

.PARAMETER Target
    Which engine script to drive: Preflight, Teams, SharePoint or Upload.
.PARAMETER Mode
    Fake tenant state, see Get-StubTenantState below.
.PARAMETER EngineDir
    seed-data/engine directory holding the scripts under test.
.PARAMETER ScenarioDir
    Scenario directory providing teams-messages.json / emails.json / sharepoint-sites.json.
.PARAMETER ConfigPath
    Throwaway config.json (copied from config.json.example by the harness).
.PARAMETER ResultPath
    Where to write the JSON probe result.
#>
param(
    [Parameter(Mandatory)][ValidateSet('Preflight', 'Teams', 'SharePoint', 'Upload', 'Emails')][string]$Target,
    [Parameter(Mandatory)][string]$Mode,
    [Parameter(Mandatory)][string]$EngineDir,
    [Parameter(Mandatory)][string]$ScenarioDir,
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$ResultPath,
    [string]$Surfaces = 'Emails,Teams,SharePoint'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# The engine reads $global:AccessToken for its Authorization header. Nothing authenticates
# here - the stub never inspects the header and never leaves the process.
$global:AccessToken = 'stub-token-no-authentication-happens-here'

$global:SeedProbeRequests = New-Object 'System.Collections.Generic.List[object]'
$global:SeedProbeMailboxes = @{}
$global:SeedProbeMailNumber = 0
$global:SeedProbeInjectedMailReadError = $false

$global:SeedProbeTeamId = 'stub-team-0001'
$global:SeedProbeGeneralId = 'stub-ch-general'
$global:SeedProbeChannelId = 'stub-ch-0001'

$global:SeedProbeConfig = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($role in $global:SeedProbeConfig.roles.PSObject.Properties) {
    $global:SeedProbeMailboxes["$($role.Value.upn)"] = @()
}
if ($Mode -eq 'MismatchedAdminRole') {
    $global:SeedProbeConfig.roles.Admin.upn = 'other-admin@moneyyu.com'
    $global:SeedProbeConfig | ConvertTo-Json -Depth 20 | Set-Content $ConfigPath -Encoding UTF8
}
if ($Mode -eq 'MismatchedDemoUser') {
    $global:SeedProbeConfig.demoUserUpn = 'other-admin@moneyyu.com'
    $global:SeedProbeConfig | ConvertTo-Json -Depth 20 | Set-Content $ConfigPath -Encoding UTF8
}
if ($Mode -eq 'StrictOutsideSource') {
    $global:SeedProbeConfig.filesSourceDir = '..\outside-scenario'
    $global:SeedProbeConfig | ConvertTo-Json -Depth 20 | Set-Content $ConfigPath -Encoding UTF8
}
$stubRoles = @('User.Read.All', 'Mail.ReadWrite', 'Mail.Send', 'Group.ReadWrite.All',
    'Teamwork.Migrate.All', 'TeamMember.ReadWrite.All', 'Files.ReadWrite.All',
    'Sites.Manage.All', 'Sites.ReadWrite.All')
if ($Mode -eq 'MissingMailSendRole') { $stubRoles = @($stubRoles | Where-Object { $_ -ne 'Mail.Send' }) }
$stubClaims = @{
    tid = if ($Mode -eq 'WrongTenantToken') { 'other-tenant' } else { $global:SeedProbeConfig.tenantId }
    aud = 'https://graph.microsoft.com'
    appid = $global:SeedProbeConfig.clientId
    roles = $stubRoles
}
$stubPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($stubClaims | ConvertTo-Json -Compress))) `
    -replace '\+', '-' -replace '/', '_' -replace '=+$', ''
$global:AccessToken = "stub-header.$stubPayload.stub-signature"
$declaredSurfaces = $Surfaces -split ','
$teamsData = Get-Content (Join-Path $ScenarioDir 'teams-messages.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$emailData = Get-Content (Join-Path $ScenarioDir 'emails.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$spData = Get-Content (Join-Path $ScenarioDir 'sharepoint-sites.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$fileData = Get-Content (Join-Path $ScenarioDir 'files-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($Mode -match '^Strict' -or $declaredSurfaces -contains 'Files') {
    $sampleNames = @(Get-ChildItem (Join-Path $ScenarioDir 'DEMO-FILE') -File | Select-Object -First 2 -ExpandProperty Name)
    $fileData = [pscustomobject]@{
        targetFolder = 'Strict-Test-20260929'
        uploadToRole = 'Admin'
        files = @($sampleNames | ForEach-Object { [pscustomobject]@{ localName = $_ } })
    }
    $strictManifestPath = Join-Path (Split-Path $ConfigPath -Parent) 'strict-files-manifest.json'
    $fileData | ConvertTo-Json -Depth 5 | Set-Content $strictManifestPath -Encoding UTF8
    $global:SeedProbeStrictItems = [Collections.Generic.List[object]]::new()
    $global:SeedProbeStrictProof = $null
}
if ($Mode -match '^NamedLibrary') {
    $spData.sites[0] | Add-Member -NotePropertyName documentLibrary -NotePropertyValue 'Products'
}
if ($Mode -eq 'SharePointMissingOwner' -or $Mode -eq 'SiteMissingOwner') {
    $spData.sites[0].owners = @($spData.sites[0].owners) + @('ITLead')
}
$sharePointProbePath = Join-Path (Split-Path $ConfigPath -Parent) 'sharepoint-sites-probe.json'
if ($Mode -match '^NamedLibrary|^(SharePoint|Site)MissingOwner$') {
    $spData | ConvertTo-Json -Depth 30 | Set-Content -Path $sharePointProbePath -Encoding UTF8
} else {
    $sharePointProbePath = Join-Path $ScenarioDir 'sharepoint-sites.json'
}
if ($declaredSurfaces -notcontains 'Teams') {
    $global:SeedProbeConfig.PSObject.Properties.Remove('teamDisplayName')
}

$global:SeedProbeGroupId = 'stub-group-0001'
$global:SeedProbeSiteId = 'stub.sharepoint.com,stub-site-0001,stub-web-0001'

# ───────────────────────────────────────────────────────
# Fake tenant content
# ───────────────────────────────────────────────────────

# Graph re-serializes stored HTML with its own indentation; the probe reproduces that so the
# engine's normalization + hashing is genuinely exercised.
function Add-StubHtmlNoise {
    param([string]$Html)
    return "`r`n  " + ($Html -replace '><', ">`r`n  <") + "  `r`n"
}

function New-StubGraphError {
    param([Parameter(Mandatory)][string]$Json, [string]$Plain = 'Response status code does not indicate success: 400 (Bad Request).')
    $ex = [System.Net.Http.HttpRequestException]::new($Plain)
    $record = [System.Management.Automation.ErrorRecord]::new(
        $ex, 'StubGraphHttpError', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
    # PowerShell 7 puts the Graph JSON payload here, not in Exception.Message.
    $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Json)
    return $record
}

function New-StubChannelMessages {
    param([switch]$DropReply, [switch]$ExtraMessage)

    $channel = @($teamsData.channels)[0]
    $messages = @()
    $index = 0
    foreach ($m in (@($channel.messages) | Sort-Object { $_.order })) {
        $messageId = "stub-msg-$index"
        $replies = @()
        $replyIndex = 0
        foreach ($r in @($m.replies)) {
            $skip = ($DropReply -and $index -eq 1 -and $replyIndex -eq 0)
            if (-not $skip) {
                $replies += [pscustomobject]@{
                    id          = "$messageId-r$replyIndex"
                    messageType = 'message'
                    body        = [pscustomobject]@{ contentType = 'html'; content = (Add-StubHtmlNoise $r.bodyHtml) }
                }
            }
            $replyIndex++
        }
        $messages += [pscustomobject]@{
            id          = $messageId
            messageType = 'message'
            body        = [pscustomobject]@{ contentType = 'html'; content = (Add-StubHtmlNoise $m.bodyHtml) }
            Replies     = $replies
        }
        $index++
    }

    if ($ExtraMessage) {
        $messages += [pscustomobject]@{
            id          = 'stub-msg-extra'
            messageType = 'message'
            body        = [pscustomobject]@{ contentType = 'html'; content = '<p>手動補的訊息，不在 scenario 宣告內</p>' }
            Replies     = @()
        }
    }

    # A system event message must be ignored by the engine.
    $messages += [pscustomobject]@{
        id          = 'stub-msg-system'
        messageType = 'systemEventMessage'
        body        = [pscustomobject]@{ contentType = 'html'; content = '<systemEventMessage/>' }
        Replies     = @()
    }

    return $messages
}

function New-StubInboxThread {
    param([Parameter(Mandatory)][int]$ThreadIndex, [Parameter(Mandatory)][int]$Count)

    $thread = @($emailData.emailThreads)[$ThreadIndex]
    $ordered = @($thread.emails | Sort-Object { $_.order })
    $firstSubject = $ordered[0].subject
    $messages = @()
    for ($i = 0; $i -lt $Count -and $i -lt $ordered.Count; $i++) {
        $subject = if ($i -eq 0) { $firstSubject } else { "RE: $firstSubject" }
        $messages += [pscustomobject]@{
            id               = "stub-mail-$ThreadIndex-$i"
            subject          = $subject
            conversationId   = "stub-conv-$ThreadIndex"
            receivedDateTime = ('2026-08-{0:d2}T09:0{1}:00Z' -f (10 + $ThreadIndex), $i)
        }
    }
    return $messages
}

function New-StubInboxFiller {
    param([int]$Count = 3)
    $messages = @()
    for ($i = 0; $i -lt $Count; $i++) {
        $messages += [pscustomobject]@{
            id               = "stub-mail-filler-$i"
            subject          = "【公告】無關的信件 $i"
            conversationId   = "stub-conv-filler-$i"
            receivedDateTime = ('2026-08-01T0{0}:00:00Z' -f $i)
        }
    }
    return $messages
}

# ───────────────────────────────────────────────────────
# Fake SharePoint content, derived from the real scenario declaration
# ───────────────────────────────────────────────────────

# Deterministic stub list id per declared list displayName.
function Get-StubListId {
    param([Parameter(Mandatory)][string]$DisplayName)
    $slug = ($DisplayName -replace '[^a-zA-Z0-9]', '-').ToLowerInvariant()
    return "stub-list-$slug"
}

function Get-StubSiteLists {
    $lists = @()
    foreach ($site in @($spData.sites)) {
        foreach ($l in @($site.lists)) {
            $lists += [pscustomobject]@{ id = (Get-StubListId -DisplayName $l.displayName); displayName = $l.displayName }
        }
    }
    return , @($lists)
}

# listId -> the complete declared Title set, i.e. the state a previous successful run leaves.
function Get-StubSeededListItems {
    $map = @{}
    foreach ($site in @($spData.sites)) {
        foreach ($l in @($site.lists)) {
            $map[(Get-StubListId -DisplayName $l.displayName)] = @(@($l.items) | ForEach-Object { "$($_.Title)" })
        }
    }
    return $map
}

# ───────────────────────────────────────────────────────
# Fake drive content (OneDrive folder + SharePoint document library)
# ───────────────────────────────────────────────────────

# A real Graph DriveItem answer to an upload PUT carries @microsoft.graph.downloadUrl, a
# short-lived PRE-AUTHENTICATED URL whose `tempauth=` query parameter is a bearer capability
# token: anyone holding the string can download the file without signing in. Live evidence
# (SDD Task 4) showed those URLs in the ignored run logs because the upload PUT left its
# response on the pipeline, so the stub reproduces the exact shape and the harness asserts the
# engine never prints it.
$global:SeedProbeDownloadUrl = 'https://stubtenant-my.sharepoint.com/personal/stub/_layouts/15/download.aspx?UniqueId=stub-unique-id&Translate=false&tempauth=STUBTEMPAUTHTOKEN.eyJzdHViIjoibm90LWEtcmVhbC10b2tlbiJ9.stub-signature&ApiVersion=2.0'

function New-StubDriveItem {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [int]$Size = 40017
    )
    return [pscustomobject]@{
        '@microsoft.graph.downloadUrl' = $global:SeedProbeDownloadUrl
        id                             = $Id
        name                           = $Name
        size                           = $Size
        webUrl                         = "https://stubtenant.sharepoint.com/Documents/$Name"
        lastModifiedDateTime           = '2026-08-31T00:00:00Z'
        file                           = [pscustomobject]@{ mimeType = 'application/octet-stream' }
    }
}

# File names declared by files-manifest.json, i.e. what a completed OneDrive upload leaves behind.
function Get-StubDeclaredOneDriveNames {
    $names = @()
    foreach ($f in @($fileData.files)) {
        $rel = ($f.localName -replace '\\', '/').Trim('/')
        $names += ($rel -split '/')[-1]
    }
    return , @($names)
}

# File names declared by sharepoint-sites.json, i.e. what a completed document upload leaves.
function Get-StubDeclaredSiteDocumentNames {
    $names = @()
    foreach ($site in @($spData.sites)) {
        foreach ($d in @($site.documents)) { $names += "$($d.sourceFilename)" }
    }
    return , @($names)
}

# Mode -> fake tenant state.
function Get-StubTenantState {
    param([Parameter(Mandatory)][string]$Mode)

    $adminUpn = "$($global:SeedProbeConfig.adminUpn)"
    $roleUpns = @()
    foreach ($p in @($global:SeedProbeConfig.roles.PSObject.Properties)) {
        if ("$($p.Value.upn)" -ne $adminUpn) { $roleUpns += "$($p.Value.upn)" }
    }

    $state = [pscustomobject]@{
        TeamExists               = $true
        AllowCreation            = $false
        MigrationAlreadyComplete = $true
        MembersAlreadyExist      = $true
        MigrationFinalizedWording = $false
        ChannelReadRequiresBeta  = $false
        SiteGroupExists          = $false
        GroupOwnersReadForbidden = $false
        TeamMembersReadForbidden = $false
        SiteGroupDisplayName     = "$(@($spData.sites)[0].displayName)"
        SiteGroupAlias           = "$(@($spData.sites)[0].alias)"
        SiteGroupTypes           = @('Unified')
        SiteGroupOwners          = @($adminUpn)
        SiteGroupMembers         = @(@($spData.sites[0].members) | ForEach-Object { "$($global:SeedProbeConfig.roles.PSObject.Properties[$_].Value.upn)" })
        MemberSpoofUpn           = ''
        GroupMembersReadForbidden = $false
        MissingUser              = ''
        DisabledUser             = ''
        NamedLibraryExists       = $false
        TeamGroupTypes           = @('Unified')
        TeamGroupOwners          = @($adminUpn)
        TeamMembers              = @(
            @([pscustomobject]@{ id = 'stub-member-admin'; email = $adminUpn; displayName = 'Tenant Admin'; roles = @('owner') }) +
            @($roleUpns | ForEach-Object { [pscustomobject]@{ id = "stub-member-$($_ -replace '[^a-zA-Z0-9]', '-')"; email = $_; displayName = $_; roles = @() } })
        )
        SiteListsExist           = $false
        SiteListItems            = @{}
        SiteItemPageSize         = 200
        SiteDriveFiles           = @()
        DriveFolderFiles         = @()
        DriveFolderExists        = $false
        DriveFolderMissing       = $false
        DriveChildPageSize       = 200
        Channels                 = @(
            [pscustomobject]@{ id = $global:SeedProbeGeneralId; displayName = 'General' }
            [pscustomobject]@{ id = $global:SeedProbeChannelId; displayName = @($teamsData.channels)[0].channelName }
        )
        Messages                 = (New-StubChannelMessages)
        Inbox                    = @()
        InboxPageSize            = 1000
    }

    switch ($Mode) {
        'MismatchedAdminRole' {
            $state.TeamExists = $false
        }
        'MismatchedDemoUser' {
            $state.TeamExists = $false
        }
        'MissingMailSendRole' {
            $state.TeamExists = $false
        }
        'WrongTenantToken' {
            $state.TeamExists = $false
        }
        'ForeignOneDriveFolder' {
            $state.TeamExists = $false
            $state.DriveFolderExists = $true
        }
        'NewOneDriveFolder' {
            $state.TeamExists = $false
        }
        'StrictForeignFolder' {
            $state.DriveFolderExists = $true
        }
        'StrictRerun' {
            $state.DriveFolderExists = $false
        }
        'StrictOutsideSource' {
            $state.DriveFolderExists = $false
        }
        'StrictProofBytes' {
            $state.DriveFolderExists = $false
        }
        'MissingRole' {
            $state.MissingUser = "$($global:SeedProbeConfig.roles.ITLead.upn)"
            $state.TeamExists = $false
        }
        'DisabledRole' {
            $state.DisabledUser = "$($global:SeedProbeConfig.roles.ITLead.upn)"
            $state.TeamExists = $false
        }
        'MissingAdmin' {
            $state.MissingUser = $adminUpn
            $state.TeamExists = $false
        }
        'DisabledAdmin' {
            $state.DisabledUser = $adminUpn
            $state.TeamExists = $false
        }
        'SiteMissingMember' {
            $state.SiteGroupExists = $true
            $state.TeamExists = $false
            $state.SiteGroupMembers = @()
        }
        'SiteMissingOwner' {
            $state.SiteGroupExists = $true
            $state.TeamExists = $false
        }
        'SharePointMissingMember' {
            $state.SiteGroupExists = $true
            $state.TeamExists = $false
            $state.SiteGroupMembers = @()
        }
        'SharePointMissingOwner' {
            $state.SiteGroupExists = $true
            $state.TeamExists = $false
        }
        'SharePointMembersForbidden' {
            $state.SiteGroupExists = $true
            $state.TeamExists = $false
            $state.GroupMembersReadForbidden = $true
        }
        'GroupMemberSpoof' {
            $state.SiteGroupExists = $true
            $state.TeamExists = $false
            $state.MemberSpoofUpn = "$($global:SeedProbeConfig.roles.PSObject.Properties[$spData.sites[0].members[0]].Value.upn)"
            $state.SiteGroupMembers = @($state.SiteGroupMembers | Where-Object { $_ -ne $state.MemberSpoofUpn })
        }
        'NamedLibraryFresh' {
            $state.SiteGroupExists = $true
            $state.TeamExists = $false
            $state.SiteListsExist = $true
            $state.SiteListItems = (Get-StubSeededListItems)
        }
        'NamedLibrarySeeded' {
            $state.SiteGroupExists = $true
            $state.TeamExists = $false
            $state.NamedLibraryExists = $true
            $state.SiteDriveFiles = (Get-StubDeclaredSiteDocumentNames)
            $state.SiteListsExist = $true
            $state.SiteListItems = (Get-StubSeededListItems)
        }
        'TeamCompleteMailComplete' {
            # Everything this scenario declares already exists and is correct: the reused team is
            # complete and admin-owned, and the dated alias resolves to the scenario's own site.
            $state.SiteGroupExists = $true
            $state.Inbox = @(New-StubInboxThread -ThreadIndex 0 -Count 4) + @(New-StubInboxThread -ThreadIndex 1 -Count 3)
        }
        'TeamMissingReply' {
            $state.Messages = (New-StubChannelMessages -DropReply)
            $state.Inbox = @(New-StubInboxThread -ThreadIndex 0 -Count 4) + @(New-StubInboxThread -ThreadIndex 1 -Count 3)
        }
        'TeamExtraMessage' {
            $state.Messages = (New-StubChannelMessages -ExtraMessage)
            $state.Inbox = @(New-StubInboxThread -ThreadIndex 0 -Count 4) + @(New-StubInboxThread -ThreadIndex 1 -Count 3)
        }
        'TeamMissingChannel' {
            $state.Channels = @([pscustomobject]@{ id = $global:SeedProbeGeneralId; displayName = 'General' })
            $state.Inbox = @(New-StubInboxThread -ThreadIndex 0 -Count 4) + @(New-StubInboxThread -ThreadIndex 1 -Count 3)
        }
        'TeamDuplicateChannel' {
            $state.Channels = @(
                [pscustomobject]@{ id = $global:SeedProbeGeneralId; displayName = 'General' }
                [pscustomobject]@{ id = $global:SeedProbeChannelId; displayName = @($teamsData.channels)[0].channelName }
                [pscustomobject]@{ id = 'stub-ch-dupe'; displayName = @($teamsData.channels)[0].channelName }
            )
            $state.Inbox = @(New-StubInboxThread -ThreadIndex 0 -Count 4) + @(New-StubInboxThread -ThreadIndex 1 -Count 3)
        }
        'MailDeletedOnly' {
            # Both threads exist ONLY in Deleted Items (served by the unscoped /messages
            # collection). A correct Inbox-scoped lookup must report 0 -> Create.
            $state.TeamExists = $false
            $state.Inbox = @()
        }
        'MailPartial' {
            $state.TeamExists = $false
            $state.Inbox = @(New-StubInboxThread -ThreadIndex 0 -Count 2) + @(New-StubInboxThread -ThreadIndex 1 -Count 3)
        }
        'MailPaged' {
            $state.TeamExists = $false
            $state.Inbox = @(New-StubInboxFiller -Count 3) +
                           @(New-StubInboxThread -ThreadIndex 0 -Count 4) +
                           @(New-StubInboxThread -ThreadIndex 1 -Count 3)
            $state.InboxPageSize = 4
        }
        'ReusedCompleteTeam' {
            $state.Inbox = @()
        }
        'ChannelReadNeedsBeta' {
            # The moneyyu app registration holds Group.ReadWrite.All + Teamwork.Migrate.All but
            # no ChannelMessage.Read.* role, so v1.0 list-channel-messages answers 403 while the
            # identical beta read succeeds. The engine must fall back instead of aborting.
            $state.ChannelReadRequiresBeta = $true
            $state.Inbox = @(New-StubInboxThread -ThreadIndex 0 -Count 4) + @(New-StubInboxThread -ThreadIndex 1 -Count 3)
        }
        'MigrationFinalizedWording' {
            # Live wording observed on a re-run: Graph answers a repeated completeMigration with
            # "Channel has already been finalized." instead of "already been completed".
            $state.MigrationFinalizedWording = $true
            $state.Inbox = @()
        }
        'SharePointFresh' {
            # Nothing exists: the group, the site, the documents, the lists and every declared
            # item are written for the first time.
            $state.TeamExists = $false
            $state.AllowCreation = $true
            $state.SiteGroupExists = $false
            $state.SiteListsExist = $false
            $state.SiteDriveFiles = @()
            $state.Inbox = @()
        }
        'SharePointSeeded' {
            # A previous run already wrote everything. The second run must add nothing: the
            # list-item snapshot has to survive its return trip intact, otherwise every declared
            # item is posted again and the lists silently double. The document library already
            # holds all declared files, so re-uploading them would only add versions.
            $state.TeamExists = $false
            $state.AllowCreation = $true
            $state.SiteGroupExists = $true
            $state.SiteListsExist = $true
            $state.SiteListItems = (Get-StubSeededListItems)
            $state.SiteDriveFiles = (Get-StubDeclaredSiteDocumentNames)
            $state.Inbox = @()
        }
        'SharePointDocsPartial' {
            # Two declared documents survive in the library, three are gone. The missing three
            # must still be uploaded; the two present ones must not be touched.
            $declaredDocs = Get-StubDeclaredSiteDocumentNames
            $state.TeamExists = $false
            $state.AllowCreation = $true
            $state.SiteGroupExists = $true
            $state.SiteListsExist = $true
            $state.SiteListItems = (Get-StubSeededListItems)
            $state.SiteDriveFiles = @($declaredDocs | Select-Object -First 2)
            $state.Inbox = @()
        }
        'SharePointSeededPaged' {
            # Same as SharePointSeeded, but the item snapshot is served one item per page so a
            # reader that stops at the first page would look "almost empty" and duplicate items.
            $state.TeamExists = $false
            $state.AllowCreation = $true
            $state.SiteGroupExists = $true
            $state.SiteListsExist = $true
            $state.SiteListItems = (Get-StubSeededListItems)
            $state.SiteItemPageSize = 1
            $state.SiteDriveFiles = (Get-StubDeclaredSiteDocumentNames)
            $state.DriveChildPageSize = 1
            $state.Inbox = @()
        }
        'OneDriveFresh' {
            # The target folder does not exist yet: it is created and all 5 declared files are
            # uploaded for the first time.
            $state.TeamExists = $false
            $state.AllowCreation = $true
            $state.DriveFolderExists = $false
            $state.DriveFolderFiles = @()
            $state.Inbox = @()
        }
        'OneDriveSeeded' {
            # A previous run already uploaded every declared file. Re-uploading identical bytes
            # is not free: SharePoint/OneDrive keeps a new version and re-serialises Office
            # containers, so the stored size drifts on every run. The second run must upload
            # nothing.
            $state.TeamExists = $false
            $state.AllowCreation = $true
            $state.DriveFolderExists = $true
            $state.DriveFolderFiles = (Get-StubDeclaredOneDriveNames)
            $state.Inbox = @()
        }
        'OneDriveSeededPaged' {
            # Same as OneDriveSeeded, but the folder snapshot is served one child per page: a
            # reader that stops at the first page would re-upload 4 of the 5 files.
            $state.TeamExists = $false
            $state.AllowCreation = $true
            $state.DriveFolderExists = $true
            $state.DriveFolderFiles = (Get-StubDeclaredOneDriveNames)
            $state.DriveChildPageSize = 1
            $state.Inbox = @()
        }
        'OneDrivePartial' {
            # Two declared files survive in the folder, three were removed by hand. Only the
            # three missing files may be uploaded.
            $declaredFiles = Get-StubDeclaredOneDriveNames
            $state.TeamExists = $false
            $state.AllowCreation = $true
            $state.DriveFolderExists = $true
            $state.DriveFolderFiles = @($declaredFiles | Select-Object -First 2)
            $state.Inbox = @()
        }
        'OneDriveFolderUnreadable' {
            # The folder children read answers 404 itemNotFound (the folder was just created and
            # is not queryable yet). "Nothing is there" must mean upload everything, never abort.
            $state.TeamExists = $false
            $state.AllowCreation = $true
            $state.DriveFolderExists = $false
            $state.DriveFolderMissing = $true
            $state.Inbox = @()
        }
        'ReusedIncompleteTeam' {
            $state.Messages = (New-StubChannelMessages -DropReply)
            $state.Inbox = @()
        }
        'TeamAdminNotOwner' {
            # A previous operator left admin as a plain member of the reused team. Promoting a
            # role on a shared tenant is a write the seeder must never make on its own, so the
            # run has to stop while it is still read-only.
            $state.TeamMembers = @($state.TeamMembers | ForEach-Object {
                if ("$($_.email)" -eq "$($global:SeedProbeConfig.adminUpn)") {
                    [pscustomobject]@{ id = $_.id; email = $_.email; displayName = $_.displayName; roles = @() }
                } else { $_ }
            })
            $state.Inbox = @(New-StubInboxThread -ThreadIndex 0 -Count 4) + @(New-StubInboxThread -ThreadIndex 1 -Count 3)
        }
        'TeamExtraChannel' {
            # An undeclared channel is content the scenario cannot verify and must never delete.
            $state.Channels = @($state.Channels) + @([pscustomobject]@{ id = 'stub-ch-extra'; displayName = '臨時討論' })
            $state.Inbox = @(New-StubInboxThread -ThreadIndex 0 -Count 4) + @(New-StubInboxThread -ThreadIndex 1 -Count 3)
        }
        'TeamMembersForbidden' {
            # An app registration consented against the OLD documented permission set holds no
            # membership role at all, so the reused-team owner proof cannot be read. That must fail
            # closed with a message naming the required role, not with a bare 403.
            $state.TeamMembersReadForbidden = $true
            $state.Inbox = @(New-StubInboxThread -ThreadIndex 0 -Count 4) + @(New-StubInboxThread -ThreadIndex 1 -Count 3)
        }
        'TeamGroupOwnersForbidden' {
            $state.GroupOwnersReadForbidden = $true
            $state.Inbox = @(New-StubInboxThread -ThreadIndex 0 -Count 4) + @(New-StubInboxThread -ThreadIndex 1 -Count 3)
        }
        'SiteAliasDisplayNameMismatch' {
            # The dated alias resolves to an unrelated group: same mailNickname, different site.
            $state.TeamExists = $false
            $state.SiteGroupExists = $true
            $state.SiteGroupDisplayName = '行銷部共用資料區'
            $state.Inbox = @()
        }
        'SiteAliasNotUnified' {
            # A security group carrying the alias provisions no SharePoint site at all.
            $state.TeamExists = $false
            $state.SiteGroupExists = $true
            $state.SiteGroupTypes = @()
            $state.Inbox = @()
        }
        'SiteAliasNoAdminOwner' {
            $state.TeamExists = $false
            $state.SiteGroupExists = $true
            $state.SiteGroupOwners = @('ChristieC@moneyyu.com')
            $state.Inbox = @()
        }
        'SharePointAliasDisplayNameMismatch' {
            $state.TeamExists = $false
            $state.AllowCreation = $true
            $state.SiteGroupExists = $true
            $state.SiteGroupDisplayName = '行銷部共用資料區'
            $state.SiteListsExist = $true
            $state.SiteListItems = (Get-StubSeededListItems)
            $state.SiteDriveFiles = (Get-StubDeclaredSiteDocumentNames)
            $state.Inbox = @()
        }
        'SharePointAliasNoAdminOwner' {
            $state.TeamExists = $false
            $state.AllowCreation = $true
            $state.SiteGroupExists = $true
            $state.SiteGroupOwners = @('ChristieC@moneyyu.com')
            $state.SiteListsExist = $true
            $state.SiteListItems = (Get-StubSeededListItems)
            $state.SiteDriveFiles = (Get-StubDeclaredSiteDocumentNames)
            $state.Inbox = @()
        }
        'NewTeam' {
            # Nothing exists yet: the create path posts the whole declared set and completes
            # migration for real.
            $state.TeamExists = $false
            $state.AllowCreation = $true
            $state.MigrationAlreadyComplete = $false
            $state.MembersAlreadyExist = $false
            $state.Messages = @()
            $state.Inbox = @()
        }
        { $_ -in @('MailCrossMailbox', 'MailRead503', 'MailRead403') } {
            $state.Inbox = @()
        }
        default { throw "Unknown probe mode '$Mode'." }
    }
    return $state
}

$global:SeedProbeTenant = Get-StubTenantState -Mode $Mode
$global:SeedProbeMessageCount = 0
$global:SeedProbeReplyCount = 0
$global:SeedProbeListPosts = 0
$global:SeedProbeListItemPosts = 0

# Deleted Items content: always the COMPLETE set of both threads. Any engine that counts the
# unscoped /users/{upn}/messages collection therefore sees a complete thread and skips - which
# is exactly the defect the Inbox-scoped lookup must avoid.
$global:SeedProbeDeleted = @(New-StubInboxThread -ThreadIndex 0 -Count 4) + @(New-StubInboxThread -ThreadIndex 1 -Count 3)

# ───────────────────────────────────────────────────────
# Fake Graph
# ───────────────────────────────────────────────────────
function Get-StubPage {
    param([object[]]$Items, [string]$Uri, [int]$PageSize)

    $skip = 0
    if ($Uri -match '(?i)(?:\$|%24)skiptoken=(\d+)') { $skip = [int]$Matches[1] }
    $all = @($Items)
    $page = @($all | Select-Object -Skip $skip -First $PageSize)
    $nextSkip = $skip + $page.Count

    $response = [ordered]@{ value = $page }
    if ($nextSkip -lt $all.Count) {
        $separator = if ($Uri -match '\?') { '&' } else { '?' }
        $base = $Uri -replace '(?i)[&?](?:\$|%24)skiptoken=\d+', ''
        $response['@odata.nextLink'] = "$base$separator`$skiptoken=$nextSkip"
    }
    return [pscustomobject]$response
}

function Add-StubMailCopies {
    param([string]$Sender, $Message, [int]$ThreadIndex)
    $global:SeedProbeMailNumber++
    $thread = @($emailData.emailThreads)[$ThreadIndex]
    $firstSubject = $thread.emails[0].subject
    $recipients = @($Message.toRecipients) + @($Message.ccRecipients)
    foreach ($recipient in $recipients) {
        $mailbox = "$($recipient.emailAddress.address)"
        if (-not $global:SeedProbeMailboxes.ContainsKey($mailbox) -or $mailbox -eq $Sender) { continue }
        $global:SeedProbeMailboxes[$mailbox] += [pscustomobject]@{
            id = "mail-$global:SeedProbeMailNumber-$mailbox"
            internetMessageId = "<seed-$global:SeedProbeMailNumber@example.invalid>"
            conversationId = "local-$ThreadIndex-$mailbox"
            subject = $Message.subject
            firstSubject = $firstSubject
            threadIndex = $ThreadIndex
            receivedDateTime = ('2026-09-29T12:{0:d2}:00Z' -f $global:SeedProbeMailNumber)
        }
    }
}

function Get-StubResponse {
    param([string]$Method, [string]$Uri)

    if ($Target -eq 'Emails' -and $Method -eq 'POST' -and $Uri -match '/users/([^/]+)/sendMail$') {
        $sender = $Matches[1]
        $message = ($global:SeedProbeRequestBody | ConvertFrom-Json).message
        $index = -1
        for ($i = 0; $i -lt @($emailData.emailThreads).Count; $i++) {
            if (@($emailData.emailThreads)[$i].emails[0].subject -eq $message.subject) { $index = $i; break }
        }
        if ($index -lt 0) { throw "STUB: unknown first email subject" }
        Add-StubMailCopies -Sender $sender -Message $message -ThreadIndex $index
        return $null
    }
    if ($Target -eq 'Emails' -and $Method -eq 'POST' -and $Uri -match '/users/([^/]+)/messages/([^/]+)/reply$') {
        $sender = $Matches[1]
        $targetId = $Matches[2]
        $parent = @($global:SeedProbeMailboxes[$sender] | Where-Object { $_.id -eq $targetId })
        if ($parent.Count -ne 1) { throw "STUB: reply target is not in the sender's Inbox" }
        $reply = $global:SeedProbeRequestBody | ConvertFrom-Json
        $message = [pscustomobject]@{
            subject = "RE: $($parent[0].firstSubject)"
            toRecipients = $reply.message.toRecipients
            ccRecipients = $reply.message.ccRecipients
        }
        Add-StubMailCopies -Sender $sender -Message $message -ThreadIndex $parent[0].threadIndex
        return $null
    }
    if ($Mode -match '^Strict' -and $Method -eq 'POST' -and $Uri -match '/createUploadSession$') {
        $name = [Uri]::UnescapeDataString(($Uri -split '/')[-2].Split(':')[0])
        if ($global:SeedProbeRequestBody -notmatch '"@microsoft.graph.conflictBehavior"\s*:\s*"fail"') {
            throw "STUB: upload session did not specify fail-on-conflict for '$name'."
        }
        return [pscustomobject]@{ uploadUrl = "https://stub-upload.invalid/$([Uri]::EscapeDataString($name))" }
    }
    if ($Mode -match '^Strict' -and $Method -eq 'PUT' -and $Uri -match '^https://stub-upload\.invalid/(.+)$') {
        $name = [Uri]::UnescapeDataString($Matches[1])
        if (@($global:SeedProbeStrictItems | Where-Object name -eq $name).Count) {
            throw "STUB: strict upload would overwrite '$name'."
        }
        $global:SeedProbeStrictItems.Add([pscustomobject]@{
            id = "strict-$($global:SeedProbeStrictItems.Count)"
            name = $name
            eTag = "etag-$($global:SeedProbeStrictItems.Count)"
            size = $global:SeedProbeRequestBytes
            file = [pscustomobject]@{}
        })
        if ($name -eq '.ms4018-seed-proof.json') {
            $global:SeedProbeStrictProof = $global:SeedProbeRequestBody | ConvertFrom-Json
        }
        return [pscustomobject]@{ id = "strict-$($global:SeedProbeStrictItems.Count)" }
    }
    # ── SharePoint writes ──
    if ($Method -eq 'PUT' -and $Uri -match '/sites/[^/]+/drive/root:/(.+):/content$') {
        $docName = [System.Uri]::UnescapeDataString((($Matches[1] -split '/')[-1]))
        return (New-StubDriveItem -Id "stub-driveitem-$($global:SeedProbeRequests.Count)" -Name $docName)
    }
    if ($Method -eq 'PUT' -and $Uri -match '/drives/[^/]+/root:/(.+):/content$') {
        $docName = [System.Uri]::UnescapeDataString((($Matches[1] -split '/')[-1]))
        return (New-StubDriveItem -Id "stub-driveitem-$($global:SeedProbeRequests.Count)" -Name $docName)
    }
    # ── OneDrive writes ──
    if ($Method -eq 'PUT' -and $Uri -match '/users/[^/]+/drive/root:/(.+):/content$') {
        $fileName = [System.Uri]::UnescapeDataString((($Matches[1] -split '/')[-1]))
        return (New-StubDriveItem -Id "stub-onedrive-put-$($global:SeedProbeRequests.Count)" -Name $fileName)
    }
    if ($Method -eq 'PATCH' -and $Uri -match '/sites/[^/]+/lists/[^/]+/columns/Title$') {
        return [pscustomobject]@{ name = 'Title' }
    }
    if ($Method -eq 'POST' -and $Uri -match '/sites/([^/]+)/lists/([^/?]+)/items$') {
        $global:SeedProbeListItemPosts++
        return [pscustomobject]@{ id = "stub-item-$($global:SeedProbeListItemPosts)" }
    }
    if ($Method -eq 'POST' -and $Uri -match '/sites/[^/]+/lists$') {
        if ($global:SeedProbeRequestBody -match '"template"\s*:\s*"documentLibrary"') {
            $global:SeedProbeTenant.NamedLibraryExists = $true
            return [pscustomobject]@{ id = 'stub-library-list'; displayName = 'Products' }
        }
        $global:SeedProbeListPosts++
        return [pscustomobject]@{ id = "stub-list-created-$($global:SeedProbeListPosts)"; displayName = 'stub-created-list' }
    }
    if ($Method -eq 'POST' -and $Uri -match '/v1\.0/groups$') {
        return [pscustomobject]@{ id = $global:SeedProbeGroupId; displayName = @($spData.sites)[0].displayName; mailNickname = @($spData.sites)[0].alias }
    }

    if ($Method -eq 'POST') {
        # OneDrive folder creation: an existing folder answers nameAlreadyExists, which the
        # engine must treat as idempotent.
        if ($Uri -match '/users/[^/]+/drive/root(:/[^:]*:)?/children$') {
            if ($global:SeedProbeTenant.DriveFolderExists) {
                throw (New-StubGraphError -Json '{"error":{"code":"nameAlreadyExists","message":"An item with the same name already exists under the parent."}}')
            }
            if ($Mode -match '^Strict') {
                if ($global:SeedProbeRequestBody -notmatch '"@microsoft.graph.conflictBehavior"\s*:\s*"fail"') {
                    throw 'STUB: strict folder creation must fail on conflict.'
                }
                $global:SeedProbeTenant.DriveFolderExists = $true
            }
            return [pscustomobject]@{ id = 'stub-folder-0001'; name = if ($Mode -match '^Strict') { $fileData.targetFolder } else { 'stub-folder' }; folder = [pscustomobject]@{ childCount = 0 } }
        }
        if ($Uri -match '/teams/[^/]+/channels/[^/]+/completeMigration$') {
            if ($global:SeedProbeTenant.MigrationFinalizedWording) {
                throw (New-StubGraphError -Json '{"error":{"code":"BadRequest","message":"Channel has already been finalized."}}')
            }
            if ($global:SeedProbeTenant.MigrationAlreadyComplete) {
                throw (New-StubGraphError -Json '{"error":{"code":"Request_BadRequest","message":"Migration has already been completed for this channel."}}')
            }
            return $null
        }
        if ($Uri -match '/teams/[^/]+/completeMigration$') {
            if ($global:SeedProbeTenant.MigrationFinalizedWording) {
                throw (New-StubGraphError -Json '{"error":{"code":"BadRequest","message":"Team has already been finalized."}}')
            }
            if ($global:SeedProbeTenant.MigrationAlreadyComplete) {
                throw (New-StubGraphError -Json '{"error":{"code":"Request_BadRequest","message":"The team is not in migration mode."}}')
            }
            return $null
        }
        if ($Uri -match '/teams/[^/]+/members$') {
            if ($global:SeedProbeTenant.MembersAlreadyExist) {
                throw (New-StubGraphError -Json '{"error":{"code":"Request_BadRequest","message":"One or more added object references already exist for the following modified properties: ''members''."}}')
            }
            return [pscustomobject]@{ id = 'stub-membership' }
        }
        if ($global:SeedProbeTenant.AllowCreation) {
            if ($Uri -match '/v1\.0/teams$') {
                return [pscustomobject]@{ id = $global:SeedProbeTeamId }
            }
            if ($Uri -match '/teams/[^/]+/channels$') {
                return [pscustomobject]@{ id = $global:SeedProbeChannelId; displayName = @($global:SeedProbeTenant.Channels)[1].displayName }
            }
            if ($Uri -match '/channels/[^/]+/messages/[^/]+/replies$') {
                $global:SeedProbeReplyCount++
                return [pscustomobject]@{ id = "stub-created-reply-$($global:SeedProbeReplyCount)" }
            }
            if ($Uri -match '/channels/[^/]+/messages$') {
                $global:SeedProbeMessageCount++
                return [pscustomobject]@{ id = "stub-created-msg-$($global:SeedProbeMessageCount)" }
            }
        }
        throw "STUB: unexpected write POST $Uri"
    }
    if ($Method -ne 'GET') { throw "STUB: unexpected $Method $Uri" }

    if ($Mode -match '^Strict' -and $Uri -match '/users/[^/]+/drive/items/stub-folder-0001/children') {
        return Get-StubPage -Items @($global:SeedProbeStrictItems) -Uri $Uri -PageSize 200
    }
    if ($Mode -match '^Strict' -and $Uri -match '/users/[^/]+/drive/items/strict-[^/]+/content$') {
        if ($Mode -eq 'StrictProofBytes') {
            return [Text.Encoding]::UTF8.GetBytes(($global:SeedProbeStrictProof | ConvertTo-Json -Compress))
        }
        return $global:SeedProbeStrictProof
    }
    if ($Uri -match '/users/[^/]+/drive/root:/[^:]+\?\$select=id,name,folder') {
        if (-not $global:SeedProbeTenant.DriveFolderExists) {
            throw (New-StubGraphError -Json '{"error":{"code":"itemNotFound","message":"Folder does not exist."}}' `
                -Plain 'Response status code does not indicate success: 404 (Not Found).')
        }
        $id = if ($Mode -eq 'StrictForeignFolder' -or $Mode -eq 'ForeignOneDriveFolder') { 'foreign-folder-0001' } else { 'stub-folder-0001' }
        return [pscustomobject]@{ id = $id; name = $fileData.targetFolder; folder = [pscustomobject]@{} }
    }

    # ── SharePoint reads ──
    if ($Uri -match '/groups/[^/]+/sites/root$') {
        return [pscustomobject]@{ id = $global:SeedProbeSiteId; webUrl = 'https://stub.sharepoint.com/sites/stub' }
    }
    # ── Drive reads (SharePoint document library + OneDrive folder) ──
    if ($Uri -match '(/sites/[^/]+/drive|/drives/[^/]+)/root(:/[^:]*:)?/children') {
        $docItems = @()
        $docIndex = 0
        foreach ($n in @($global:SeedProbeTenant.SiteDriveFiles)) {
            $docItems += (New-StubDriveItem -Id "stub-sitedoc-$docIndex" -Name $n)
            $docIndex++
        }
        return Get-StubPage -Items $docItems -Uri $Uri -PageSize $global:SeedProbeTenant.DriveChildPageSize
    }
    if ($Uri -match '/users/[^/]+/drive/root(:/[^:]*:)?/children') {
        if ($global:SeedProbeTenant.DriveFolderMissing) {
            throw (New-StubGraphError -Json '{"error":{"code":"itemNotFound","message":"The resource could not be found."}}' `
                                      -Plain 'Response status code does not indicate success: 404 (Not Found).')
        }
        $driveItems = @()
        $driveIndex = 0
        foreach ($n in @($global:SeedProbeTenant.DriveFolderFiles)) {
            $driveItems += (New-StubDriveItem -Id "stub-onedrive-$driveIndex" -Name $n)
            $driveIndex++
        }
        return Get-StubPage -Items $driveItems -Uri $Uri -PageSize $global:SeedProbeTenant.DriveChildPageSize
    }
    if ($Uri -match '/sites/[^/]+/lists/([^/?]+)/items') {
        $listId = $Matches[1]
        $titles = @()
        if ($global:SeedProbeTenant.SiteListItems.ContainsKey($listId)) {
            $titles = @($global:SeedProbeTenant.SiteListItems[$listId])
        }
        $items = @()
        $index = 0
        foreach ($t in $titles) {
            $items += [pscustomobject]@{ id = "$listId-item-$index"; fields = [pscustomobject]@{ Title = $t } }
            $index++
        }
        return Get-StubPage -Items $items -Uri $Uri -PageSize $global:SeedProbeTenant.SiteItemPageSize
    }
    if ($Uri -match '/sites/[^/]+/lists(\?|$)') {
        if ($global:SeedProbeTenant.SiteListsExist) {
            $allLists = Get-StubSiteLists
            return [pscustomobject]@{ value = @($allLists) }
        }
        return [pscustomobject]@{ value = @() }
    }

    if ($Uri -match '/groups\?') {
        if ($Uri -match '(?i)displayName%20eq') {
            if (-not $global:SeedProbeTenant.TeamExists) { return [pscustomobject]@{ value = @() } }
            return [pscustomobject]@{
                value = @([pscustomobject]@{
                    id                          = $global:SeedProbeTeamId
                    displayName                 = $global:SeedProbeConfig.teamDisplayName
                    mailNickname                = 'stub-team-alias'
                    groupTypes                  = @($global:SeedProbeTenant.TeamGroupTypes)
                    resourceProvisioningOptions = @('Team')
                })
            }
        }
        # site alias lookup
        if ($global:SeedProbeTenant.SiteGroupExists) {
            return [pscustomobject]@{
                value = @([pscustomobject]@{
                    id           = $global:SeedProbeGroupId
                    displayName  = $global:SeedProbeTenant.SiteGroupDisplayName
                    mailNickname = $global:SeedProbeTenant.SiteGroupAlias
                    groupTypes   = @($global:SeedProbeTenant.SiteGroupTypes)
                })
            }
        }
        return [pscustomobject]@{ value = @() }
    }

    # Owner collection of a group (site group and the group behind a team both use this).
    if ($Uri -match '/groups/([^/]+)/owners') {
        $groupId = $Matches[1]
        if ($global:SeedProbeTenant.GroupOwnersReadForbidden) {
            throw (New-StubGraphError -Json ('{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}') `
                                      -Plain 'Response status code does not indicate success: 403 (Forbidden).')
        }
        $upns = if ($groupId -eq $global:SeedProbeTeamId) {
            @($global:SeedProbeTenant.TeamGroupOwners)
        } else {
            @($global:SeedProbeTenant.SiteGroupOwners)
        }
        $owners = @($upns | ForEach-Object {
            [pscustomobject]@{
                '@odata.type'     = '#microsoft.graph.user'
                id                = "stub-user-$($_ -replace '[^a-zA-Z0-9]', '-')"
                userPrincipalName = $_
            }
        })
        return Get-StubPage -Items $owners -Uri $Uri -PageSize 100
    }
    if ($Uri -match '/groups/([^/]+)/members') {
        if ($global:SeedProbeTenant.GroupMembersReadForbidden) {
            throw (New-StubGraphError -Json '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}' `
                -Plain 'Response status code does not indicate success: 403 (Forbidden).')
        }
        $members = @($global:SeedProbeTenant.SiteGroupMembers | ForEach-Object {
            [pscustomobject]@{
                '@odata.type' = '#microsoft.graph.user'
                id = "stub-user-$($_ -replace '[^a-zA-Z0-9]', '-')"
                userPrincipalName = $_
            }
        })
        if ($global:SeedProbeTenant.MemberSpoofUpn) {
            $members += [pscustomobject]@{
                '@odata.type' = '#microsoft.graph.group'
                id = 'stub-spoofing-group'
                mail = $global:SeedProbeTenant.MemberSpoofUpn
            }
        }
        return Get-StubPage -Items $members -Uri $Uri -PageSize 2
    }
    if ($Uri -match '/sites/[^/]+/drives') {
        $drives = @()
        if ($global:SeedProbeTenant.NamedLibraryExists) {
            $drives += [pscustomobject]@{ id = 'stub-products-drive'; name = 'Products' }
        }
        return [pscustomobject]@{ value = $drives }
    }

    # Team membership carries the owner ROLE, which the group owner collection does not.
    if ($Uri -match '/teams/[^/]+/members') {
        if ($global:SeedProbeTenant.TeamMembersReadForbidden) {
            throw (New-StubGraphError -Json ('{"error":{"code":"Forbidden","message":"Missing role permissions on the request. ' +
                'API requires one of ''TeamMember.Read.Group, TeamMember.Read.All, TeamMember.ReadWrite.All''. Roles on the ' +
                'request ''Teamwork.Migrate.All, Group.ReadWrite.All''."}}') `
                -Plain 'Response status code does not indicate success: 403 (Forbidden).')
        }
        return Get-StubPage -Items @($global:SeedProbeTenant.TeamMembers) -Uri $Uri -PageSize 100
    }

    if ($Uri -match '/teams/[^/]+/channels/([^/?]+)/messages/([^/?]+)/replies') {
        if ($global:SeedProbeTenant.ChannelReadRequiresBeta -and $Uri -match '/v1\.0/') {
            throw (New-StubGraphError -Json ('{"error":{"code":"Forbidden","message":"Missing role permissions on the request. ' +
                'API requires one of ''ChannelMessage.Read.All, ChannelMessage.Read.Group''. Roles on the request ' +
                '''Teamwork.Migrate.All, Group.ReadWrite.All''."}}') -Plain 'Response status code does not indicate success: 403 (Forbidden).')
        }
        $messageId = $Matches[2]
        $parent = @($global:SeedProbeTenant.Messages | Where-Object { $_.id -eq $messageId })
        if ($parent.Count -eq 0) { return [pscustomobject]@{ value = @() } }
        return Get-StubPage -Items @($parent[0].Replies) -Uri $Uri -PageSize 50
    }

    if ($Uri -match '/teams/[^/]+/channels/([^/?]+)/messages') {
        if ($global:SeedProbeTenant.ChannelReadRequiresBeta -and $Uri -match '/v1\.0/') {
            throw (New-StubGraphError -Json ('{"error":{"code":"Forbidden","message":"Missing role permissions on the request. ' +
                'API requires one of ''ChannelMessage.Read.All, ChannelMessage.Read.Group''. Roles on the request ' +
                '''Teamwork.Migrate.All, Group.ReadWrite.All''."}}') -Plain 'Response status code does not indicate success: 403 (Forbidden).')
        }
        # Two pages, so @odata.nextLink handling is exercised for channel messages too.
        return Get-StubPage -Items @($global:SeedProbeTenant.Messages) -Uri $Uri -PageSize 4
    }

    if ($Uri -match '/teams/[^/]+/channels(\?|$)') {
        return [pscustomobject]@{ value = @($global:SeedProbeTenant.Channels) }
    }

    if ($Uri -match '(?i)/mailFolders/[^/?]+/messages') {
        if ($Target -eq 'Emails') {
            if ($Uri -notmatch '/users/([^/]+)/mailFolders') { throw "STUB: missing mailbox" }
            $mailbox = $Matches[1]
            if ($Uri -match '\$orderby=' -and $mailbox -eq $global:SeedProbeConfig.adminUpn -and
                -not $global:SeedProbeInjectedMailReadError -and $Mode -in @('MailRead503', 'MailRead403')) {
                $global:SeedProbeInjectedMailReadError = $true
                $code = if ($Mode -eq 'MailRead503') { 503 } else { 403 }
                $reason = if ($code -eq 503) { 'Service Unavailable' } else { 'Forbidden' }
                throw (New-StubGraphError -Json "{`"error`":{`"code`":`"$reason`",`"message`":`"Injected GET failure`"}}" `
                    -Plain "Response status code does not indicate success: $code ($reason).")
            }
            $items = @($global:SeedProbeMailboxes[$mailbox] | Sort-Object receivedDateTime -Descending)
            return Get-StubPage -Items $items -Uri $Uri -PageSize 100
        }
        return Get-StubPage -Items @($global:SeedProbeTenant.Inbox) -Uri $Uri -PageSize $global:SeedProbeTenant.InboxPageSize
    }

    if ($Uri -match '/users/[^/]+/messages') {
        # Unscoped mailbox collection == Inbox + Deleted Items + Sent Items.
        if ($Uri -match '(?i)conversationId%20eq%20%27([^%]+)%27') {
            $conversationId = $Matches[1]
            return [pscustomobject]@{ value = @($global:SeedProbeDeleted | Where-Object { $_.conversationId -eq $conversationId }) }
        }
        if ($Uri -match '(?i)subject%20eq%20%27(.+?)%27') {
            $subject = [System.Uri]::UnescapeDataString(($Matches[1] -replace '%27%27', '%27'))
            return [pscustomobject]@{ value = @($global:SeedProbeDeleted | Where-Object { $_.subject -eq $subject }) }
        }
        return Get-StubPage -Items @($global:SeedProbeDeleted) -Uri $Uri -PageSize 50
    }

    if ($Uri -match '/users/([^/?]+)(?:\?.*)?$') {
        $upn = [System.Uri]::UnescapeDataString($Matches[1])
        if ($upn -eq $global:SeedProbeTenant.MissingUser) {
            throw (New-StubGraphError -Json '{"error":{"code":"Request_ResourceNotFound","message":"User not found."}}' `
                -Plain 'Response status code does not indicate success: 404 (Not Found).')
        }
        return [pscustomobject]@{
            id = "stub-user-$($upn -replace '[^a-zA-Z0-9]', '-')"
            userPrincipalName = $upn
            accountEnabled = ($upn -ne $global:SeedProbeTenant.DisabledUser)
        }
    }

    throw "STUB: unhandled GET $Uri"
}

# Shadows the real cmdlet for every script invoked from this scope.
function Invoke-RestMethod {
    [CmdletBinding()]
    param(
        [string]$Method,
        [string]$Uri,
        $Headers,
        $Body,
        $ContentType
    )
    # The engine sends UTF-8 encoded JSON bytes; decode them so tests can assert on the exact
    # wire payload (a PowerShell array that collapsed to a scalar is only visible here).
    $bodyText = $null
    if ($null -ne $Body) {
        if ($Body -is [byte[]]) { $bodyText = [System.Text.Encoding]::UTF8.GetString($Body) }
        else { $bodyText = "$Body" }
    }
    $global:SeedProbeRequestBody = $bodyText
    $global:SeedProbeRequestBytes = if ($Body -is [byte[]]) { $Body.Length } else { 0 }
    $global:SeedProbeRequests.Add([pscustomobject]@{ Method = $Method; Uri = $Uri; Body = $bodyText })
    return (Get-StubResponse -Method $Method -Uri $Uri)
}

# Keep probes fast: the engine's throttling pauses are irrelevant to a local stub.
function Start-Sleep {
    [CmdletBinding()]
    param([int]$Seconds, [int]$Milliseconds)
    return
}

# ───────────────────────────────────────────────────────
# Drive the engine script
# ───────────────────────────────────────────────────────
$threw = $false
$errorMessage = ''
$errorStack = ''
try {
    if ($Target -eq 'Preflight') {
        $args = @{ ConfigPath = $ConfigPath }
        if ($declaredSurfaces -contains 'Emails') { $args.EmailsPath = Join-Path $ScenarioDir 'emails.json' }
        if ($declaredSurfaces -contains 'Teams') { $args.TeamsMessagesPath = Join-Path $ScenarioDir 'teams-messages.json' }
        if ($declaredSurfaces -contains 'SharePoint') { $args.SharePointPath = $sharePointProbePath }
        if ($declaredSurfaces -contains 'Files') { $args.FilesManifestPath = $strictManifestPath }
        & (Join-Path $EngineDir 'Invoke-SeedPreflight.ps1') @args
    } elseif ($Target -eq 'SharePoint') {
        & (Join-Path $EngineDir 'Invoke-SeedSharePoint.ps1') `
            -ConfigPath $ConfigPath `
            -SharePointPath $sharePointProbePath
    } elseif ($Target -eq 'Upload') {
        $uploadArgs = @{
            ConfigPath = $ConfigPath
            FilesManifestPath = if ($Mode -match '^Strict') { $strictManifestPath } else { Join-Path $ScenarioDir 'files-manifest.json' }
        }
        if ($Mode -match '^Strict') { $uploadArgs.StrictScenario = $true }
        & (Join-Path $EngineDir 'Invoke-UploadFiles.ps1') @uploadArgs
        if ($Mode -in @('StrictRerun', 'StrictProofBytes')) {
            & (Join-Path $EngineDir 'Invoke-UploadFiles.ps1') @uploadArgs
        }
    } elseif ($Target -eq 'Emails') {
        & (Join-Path $EngineDir 'Invoke-SeedEmails.ps1') -ConfigPath $ConfigPath -EmailsPath (Join-Path $ScenarioDir 'emails.json')
    } else {
        & (Join-Path $EngineDir 'Invoke-SeedTeamsChannel.ps1') `
            -ConfigPath $ConfigPath `
            -TeamsMessagesPath (Join-Path $ScenarioDir 'teams-messages.json')
    }
} catch {
    $threw = $true
    $errorMessage = "$($_.Exception.Message)"
    $errorStack = "$($_.ScriptStackTrace)"
}

$findings = @()
if ($global:SeedPreflightResult) {
    $findings = @($global:SeedPreflightResult | ForEach-Object {
        [ordered]@{ Kind = "$($_.Kind)"; Key = "$($_.Key)"; Action = "$($_.Action)"; Id = "$($_.Id)" }
    })
}

$teamsResult = $null
if ($global:SeedTeamsResult) {
    $teamsResult = [ordered]@{
        TeamId     = "$($global:SeedTeamsResult.TeamId)"
        TeamAction = "$($global:SeedTeamsResult.TeamAction)"
        Channels   = @($global:SeedTeamsResult.Channels | ForEach-Object {
            [ordered]@{ ChannelName = "$($_.ChannelName)"; ChannelId = "$($_.ChannelId)"; MessageAction = "$($_.MessageAction)" }
        })
    }
}

$result = [ordered]@{
    Target       = $Target
    Mode         = $Mode
    Threw        = $threw
    ErrorMessage = $errorMessage
    ErrorStack   = $errorStack
    Requests     = @($global:SeedProbeRequests | ForEach-Object { [ordered]@{ Method = "$($_.Method)"; Uri = "$($_.Uri)"; Body = $(if ($null -eq $_.Body) { $null } else { "$($_.Body)" }) } })
    Findings     = $findings
    TeamsResult  = $teamsResult
    SharePointResult = @($global:SeedSharePointResults | ForEach-Object {
        [ordered]@{ Alias = "$($_.Alias)"; GroupId = "$($_.GroupId)"; SiteId = "$($_.SiteId)" }
    })
}

$json = $result | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($ResultPath, $json, (New-Object System.Text.UTF8Encoding($false)))
exit 0
