<#
.SYNOPSIS
    Shared read-only Microsoft Graph collection readers for the PL-7008 M365 seed engine.
.DESCRIPTION
    GET requests only. Nothing here creates, modifies or deletes a tenant resource, and no
    resource is ever matched by wildcard.

    Dot-source this file from a script that already defines its own

        Invoke-Graph -Method GET -Uri <uri>

    wrapper (that is where the bearer token lives). Every collection read pages through
    `@odata.nextLink`: a partial first page would otherwise make a complete team or a
    complete mail thread look incomplete and abort a healthy re-run.

    Preflight (engine/Invoke-SeedPreflight.ps1) and the Teams phase
    (engine/Invoke-SeedTeamsChannel.ps1) both consume these readers so that the state they
    verify is produced by exactly one implementation.
#>

. "$PSScriptRoot\Seed-Idempotency.ps1"

# Follow @odata.nextLink until the collection is exhausted.
function Get-SeedGraphCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [int]$MaxPages = 100
    )

    $items = @()
    $next = $Uri
    $page = 0

    while ($next) {
        $page++
        if ($page -gt $MaxPages) {
            throw "Graph collection '$Uri' returned more than $MaxPages pages; refusing to keep paging."
        }

        $response = Invoke-Graph -Method GET -Uri $next
        if ($null -eq $response) { break }

        $props = @($response.PSObject.Properties.Name)
        if ($props -contains 'value') { $items += @($response.value) }

        $following = $null
        if ($props -contains '@odata.nextLink') { $following = $response.'@odata.nextLink' }
        if ($following -and $following -eq $next) {
            throw "Graph collection '$Uri' returned a self-referencing @odata.nextLink; refusing to loop."
        }
        $next = $following
    }

    return , @($items)
}

# ───────────────────────────────────────────────────────
# Drive folders (OneDrive and SharePoint document libraries)
# ───────────────────────────────────────────────────────

# The names of the items directly under one drive folder, following @odata.nextLink so a
# truncated first page can never make a stored file look absent.
#
# A folder that does not exist yet answers 404 itemNotFound; that is reported as an empty
# snapshot, because the caller creates the folder and uploads everything. Any other failure is
# rethrown: an empty snapshot produced by a throttled or forbidden read would re-upload every
# declared file and add a version to each of them.
function Get-SeedDriveChildNames {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ChildrenUri)

    $items = @()
    try {
        $items = Get-SeedGraphCollection -Uri $ChildrenUri
    } catch {
        if (-not (Test-SeedNotFoundError -ErrorRecord $_)) { throw }
        return , @()
    }

    $names = @()
    foreach ($item in @($items)) {
        if ($null -eq $item) { continue }
        $props = @($item.PSObject.Properties.Name)
        if (($props -contains 'name') -and $item.name) { $names += "$($item.name)" }
    }
    return , @($names)
}

# ───────────────────────────────────────────────────────
# Mailbox (Inbox only)
# ───────────────────────────────────────────────────────

# Every seeded message reaches the admin mailbox as an Inbox item (admin is CC on all of
# them). The unscoped /users/{upn}/messages collection also returns Deleted Items and Sent
# Items, so a thread deleted by the operator would still be counted: a partial thread would
# not clear, and a "complete" thread could be skipped although no usable Inbox mail exists.
function Get-SeedInboxMessages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Upn,
        [int]$PageSize = 100
    )

    $uri = "https://graph.microsoft.com/v1.0/users/$Upn/mailFolders/inbox/messages?" +
           "`$select=id,subject,conversationId,receivedDateTime&`$top=$PageSize"
    $messages = Get-SeedGraphCollection -Uri $uri
    return , @($messages)
}

# Most recent Inbox page only - used while polling for a message that was just sent.
function Get-SeedRecentInboxMessages {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Upn,
        [int]$Top = 50
    )

    $uri = "https://graph.microsoft.com/v1.0/users/$Upn/mailFolders/inbox/messages?" +
           "`$select=id,subject,conversationId,internetMessageId,receivedDateTime&`$top=$Top&`$orderby=receivedDateTime%20desc"
    $response = Invoke-Graph -Method GET -Uri $uri
    if ($null -eq $response) { return , @() }
    return , @($response.value)
}

# Thread state for one declared thread, matched manually against the Inbox collection.
# Pass -Messages to reuse a mailbox snapshot across several threads.
function Get-SeedInboxThreadState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Upn,
        [Parameter(Mandatory)][string]$FirstSubject,
        [Parameter()][AllowNull()]$Messages
    )

    $pool = $Messages
    if ($null -eq $pool) { $pool = Get-SeedInboxMessages -Upn $Upn }
    return Select-SeedThreadMessages -Messages $pool -FirstSubject $FirstSubject
}

# ───────────────────────────────────────────────────────
# Group ownership and Teams membership (identity proofs)
# ───────────────────────────────────────────────────────

# UPNs of the owners of a Microsoft 365 group, paged. Used to prove that the demo operator
# admin already owns a reused site group or the group behind a reused team.
# GET /groups/{id}/owners is served by the documented Group.ReadWrite.All application role:
# https://learn.microsoft.com/graph/api/group-list-owners
function Get-SeedGroupOwnerUpns {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$GroupId)

    try {
        $owners = Get-SeedGraphCollection -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId/owners?`$select=id,userPrincipalName"
    } catch {
        # Fail closed, but say what is missing: an unreadable owner collection is indistinguishable
        # from "nobody owns it", and treating it as the latter would let a write land in a resource
        # whose ownership was never proven.
        throw ("Cannot read the owners of group $GroupId, so the demo operator's ownership cannot be proven: " +
               "$(Get-SeedGraphErrorText -ErrorObject $_). GET /groups/{id}/owners is served by the " +
               "Group.ReadWrite.All application permission (GroupMember.Read.All is the least-privileged " +
               "alternative); grant and consent it, then re-run. Nothing was written.")
    }
    # Assigned first on purpose: `@(Get-SeedUpnList ...)` would wrap the array the helper emits
    # as ONE pipeline object into a second array, and the nested value compares as
    # "System.Object[]" against every UPN.
    $upns = Get-SeedUpnList -Items $owners
    return , @($upns)
}

function Get-SeedGroupMemberUpns {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$GroupId)

    try {
        $members = Get-SeedGraphCollection -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId/members"
    } catch {
        throw ("Cannot read members of group ${GroupId}: $(Get-SeedGraphErrorText -ErrorObject $_). " +
               "Verify group membership read permission before seeding; no access is granted automatically.")
    }
    $users = @($members | Where-Object { $_ -and $_.'@odata.type' -eq '#microsoft.graph.user' })
    $upns = Get-SeedUpnList -Items $users
    return , @($upns)
}

function Assert-SeedSiteGroupRoles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][string]$Alias,
        [string[]]$OwnerRoles = @(),
        [string[]]$MemberRoles = @(),
        [Parameter(Mandatory)][hashtable]$RoleMap,
        [string[]]$OwnerUpns = @()
    )

    $memberUpns = if (@($MemberRoles).Count -gt 0) { Get-SeedGroupMemberUpns -GroupId $GroupId } else { @() }
    foreach ($entry in @(
        @{ Kind = 'owner'; Roles = @($OwnerRoles); Upns = @($OwnerUpns) }
        @{ Kind = 'member'; Roles = @($MemberRoles); Upns = @($memberUpns) }
    )) {
        foreach ($role in $entry.Roles) {
            if (-not $RoleMap.ContainsKey($role) -or -not $RoleMap[$role].upn) {
                throw "Site '$Alias' declares undefined $($entry.Kind) role '$role'. No writes were made."
            }
            $upn = "$($RoleMap[$role].upn)"
            if (-not (Test-SeedUpnInList -Upns $entry.Upns -Upn $upn)) {
                throw "Site '$Alias' group $GroupId is missing declared $($entry.Kind) role '$role' ($upn). No access was granted; aborting before writes."
            }
        }
    }
}

# The team membership collection is the only place the Teams 'owner' ROLE exists — the group
# owner collection does not carry it. GET /teams/{id}/members is served by the
# TeamMember.ReadWrite.All application role that Phase 4's owner-membership POST already requires
# (documented in config.json.example):
# https://learn.microsoft.com/graph/api/team-list-members
function Get-SeedTeamMembers {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TeamId)

    try {
        $members = Get-SeedGraphCollection -Uri "https://graph.microsoft.com/v1.0/teams/$TeamId/members"
    } catch {
        throw ("Cannot read the membership of team $TeamId, so the demo operator's Teams owner role cannot be " +
               "proven: $(Get-SeedGraphErrorText -ErrorObject $_). GET /teams/{id}/members requires the " +
               "TeamMember.ReadWrite.All application permission (see the permission list in config.json.example; " +
               "the same role is what lets Phase 4 add the admin with the 'owner' role); grant and consent it, " +
               "then re-run. The seeder fails closed rather than writing into a team whose ownership is " +
               "unverified.")
    }
    return , @($members)
}

# ───────────────────────────────────────────────────────
# Teams
# ───────────────────────────────────────────────────────

function Get-SeedTeamChannels {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TeamId)

    $channels = Get-SeedGraphCollection -Uri "https://graph.microsoft.com/v1.0/teams/$TeamId/channels"
    return , @($channels)
}

# Channel message reads are the one collection the seeder cannot always reach on v1.0: that
# endpoint requires ChannelMessage.Read.All / ChannelMessage.Read.Group, which the documented
# application permission set does not include, while the identical beta collection is served
# under Group.ReadWrite.All. The version is probed once per script and then reused, so a run
# issues exactly one 403 instead of one per request. Both variants are GET-only.
$script:SeedChannelApiVersion = $null

function Get-SeedChannelGraphCollection {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PathAndQuery)

    if ($script:SeedChannelApiVersion) {
        $cached = Get-SeedGraphCollection -Uri "https://graph.microsoft.com/$($script:SeedChannelApiVersion)$PathAndQuery"
        return , @($cached)
    }

    try {
        $items = Get-SeedGraphCollection -Uri "https://graph.microsoft.com/v1.0$PathAndQuery"
        $script:SeedChannelApiVersion = 'v1.0'
        return , @($items)
    } catch {
        if (-not (Test-SeedChannelReadForbidden -ErrorRecord $_)) { throw }
        Write-Host ("      (channel read: v1.0 needs ChannelMessage.Read.*, which this app registration " +
                    "does not hold - falling back to the read-only beta collection)") -ForegroundColor DarkGray
        $items = Get-SeedGraphCollection -Uri "https://graph.microsoft.com/beta$PathAndQuery"
        $script:SeedChannelApiVersion = 'beta'
        return , @($items)
    }
}

# Content fingerprint of one channel: the hashes of every top-level message plus, per parent,
# the hashes of its replies. Replies must be fetched separately for every parent because
# list-channel-messages never returns them.
function Get-SeedChannelMessageState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TeamId,
        [Parameter(Mandatory)][string]$ChannelId
    )

    $topHashes = @()
    $replyMap = @{}

    $messages = Get-SeedChannelGraphCollection -PathAndQuery "/teams/$TeamId/channels/$ChannelId/messages?`$top=50"
    foreach ($m in @($messages)) {
        if ($m.messageType -and $m.messageType -ne 'message') { continue }
        if (-not $m.body -or -not $m.body.content) { continue }

        $hash = Get-SeedContentHash -Content $m.body.content
        $topHashes += $hash

        $replies = Get-SeedChannelGraphCollection -PathAndQuery "/teams/$TeamId/channels/$ChannelId/messages/$($m.id)/replies?`$top=50"
        $replyHashes = @()
        foreach ($r in @($replies)) {
            if ($r.messageType -and $r.messageType -ne 'message') { continue }
            if (-not $r.body -or -not $r.body.content) { continue }
            $replyHashes += (Get-SeedContentHash -Content $r.body.content)
        }

        if ($replyMap.ContainsKey($hash)) {
            $replyMap[$hash] = @($replyMap[$hash]) + $replyHashes
        } else {
            $replyMap[$hash] = $replyHashes
        }
    }

    return [pscustomobject]@{ TopLevelHashes = $topHashes; ReplyHashes = $replyMap }
}
