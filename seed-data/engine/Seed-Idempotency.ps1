<#
.SYNOPSIS
    Shared idempotency / fail-fast helpers for the PL-7008 M365 seed engine.
.DESCRIPTION
    Pure functions only — no Microsoft Graph calls, no side effects, no output.
    Dot-source this file from the seeding scripts:

        . "$PSScriptRoot\Seed-Idempotency.ps1"

    Design rules encoded here:
      * A seed run either creates a resource from scratch, or reuses a resource
        it can prove is complete. Anything in between aborts.
      * Never guess between duplicate tenant resources.
      * Never resume a partially seeded email thread or Teams channel: the
        historical timestamps used by the Teams migration API cannot be
        back-filled once migration is completed, and re-sending mail would
        duplicate the thread.
#>

# ───────────────────────────────────────────────────────
# Content normalization + hashing
# ───────────────────────────────────────────────────────

# Normalize HTML message content so that inconsequential whitespace introduced by
# Microsoft Graph (indentation, CRLF, spacing between tags) does not change the hash.
function ConvertTo-SeedNormalizedContent {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Content
    )

    if ([string]::IsNullOrEmpty($Content)) { return '' }

    $text = $Content -replace "`r`n", "`n"
    $text = $text -replace '\s+', ' '
    $text = $text -replace '>\s+<', '><'
    $text = $text -replace '>\s+', '>'
    $text = $text -replace '\s+<', '<'
    return $text.Trim()
}

# Stable SHA-256 (lowercase hex) of the normalized content.
function Get-SeedContentHash {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Content
    )

    $normalized = ConvertTo-SeedNormalizedContent -Content $Content
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }
    return (-join ($digest | ForEach-Object { $_.ToString('x2') }))
}

# ───────────────────────────────────────────────────────
# OData string literals
# ───────────────────────────────────────────────────────

# Percent-encoded body of an OData string literal: a single quote is escaped by doubling it,
# and the result is URL-encoded so CJK titles, spaces and '&' survive a $filter query.
#
# This is a function rather than an inline expression on purpose.
# `[System.Uri]::EscapeDataString($x -replace "'", "''")` reads as one argument but parses as
# TWO: inside a method argument list the comma is an argument separator and never binds to the
# -replace operator. The script parses cleanly and then throws "Cannot find an overload for
# EscapeDataString and the argument count: 2" the first time the line actually runs.
function ConvertTo-SeedODataLiteral {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) { return '' }
    $doubled = $Value -replace "'", "''"
    return [System.Uri]::EscapeDataString($doubled)
}

# ───────────────────────────────────────────────────────
# SharePoint list item state
# ───────────────────────────────────────────────────────

# Does a declared item already exist in the list? Matched against a snapshot of the list's
# Titles instead of a server-side OData filter on the Title column: Title is not indexed on a
# freshly created Graph list, so Graph answers such a filter with 400 invalidRequest, and the
# documented Prefer header is explicitly allowed to fail on large lists. The comparison is
# ordinal (case sensitive) on the trimmed value — SharePoint may echo a padded Title, and a
# false miss would duplicate the item on every subsequent run.
function Test-SeedListItemExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()][AllowNull()][AllowEmptyCollection()][string[]]$ExistingTitles,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Title
    )

    $key = "$Title".Trim()
    foreach ($existing in @($ExistingTitles)) {
        if ($null -eq $existing) { continue }
        if ([string]::Equals("$existing".Trim(), $key, [System.StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

# ───────────────────────────────────────────────────────
# Drive file state (OneDrive folders and SharePoint document libraries)
# ───────────────────────────────────────────────────────

# Is a declared file already stored in the target folder? Matched against a snapshot of the
# folder's child names (see engine/Seed-GraphRead.ps1 Get-SeedDriveChildNames).
#
# A PUT of identical bytes is NOT a no-op: OneDrive and SharePoint keep a new version of the
# item and re-serialise Office containers on the way in, so an unconditional re-upload changes
# the stored file on every run of the same dated scenario. The comparison is ordinal
# (case sensitive) on the trimmed name — the declared name is the exact key, and a loose match
# would report a differently named file as present and leave the declared one missing.
function Test-SeedDriveFileExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()][AllowNull()][AllowEmptyCollection()][string[]]$ExistingNames,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name
    )

    $key = "$Name".Trim()
    if ([string]::IsNullOrEmpty($key)) { return $false }

    foreach ($existing in @($ExistingNames)) {
        if ($null -eq $existing) { continue }
        if ([string]::Equals("$existing".Trim(), $key, [System.StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

# ───────────────────────────────────────────────────────
# Resource cardinality
# ───────────────────────────────────────────────────────

# 0 matches -> 'Create'; exactly 1 -> 'Reuse'; more than 1 -> throw.
# The error lists resource ids/names only, and never picks one of the duplicates.
function Get-SeedResourceAction {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()][AllowNull()][AllowEmptyCollection()][object[]]$Existing,
        [Parameter(Mandatory)][string]$ResourceKind,
        [Parameter(Mandatory)][string]$ResourceKey
    )

    $items = @($Existing | Where-Object { $null -ne $_ })

    if ($items.Count -eq 0) { return 'Create' }
    if ($items.Count -eq 1) { return 'Reuse' }

    $described = foreach ($item in $items) {
        $props = @($item.PSObject.Properties.Name)
        $id = if ($props -contains 'id') { $item.id } else { '<no-id>' }
        $name = if ($props -contains 'displayName') { $item.displayName }
                elseif ($props -contains 'name') { $item.name }
                else { '<no-name>' }
        "$id ($name)"
    }

    $list = $described -join '; '
    $message = "Ambiguous tenant state: found $($items.Count) '$ResourceKind' resources matching '$ResourceKey': $list. " +
               "The seeder will not pick one of them and will not delete anything. " +
               "Resolve this manually in the tenant, then re-run."
    throw $message
}

# ───────────────────────────────────────────────────────
# Email thread state
# ───────────────────────────────────────────────────────

# 0 existing -> 'Create'; exactly the expected count -> 'Skip'; anything else -> throw.
# The count is taken from the conversation in the adminUpn mailbox (admin is CC on
# every seeded message, so a complete thread has exactly one message per declared email).
function Get-SeedEmailThreadAction {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][int]$ExistingMessageCount,
        [Parameter(Mandatory)][int]$ExpectedMessageCount,
        [Parameter(Mandatory)][string]$ThreadKey
    )

    if ($ExpectedMessageCount -le 0) {
        throw "Invalid scenario data: email thread '$ThreadKey' declares $ExpectedMessageCount expected messages."
    }
    if ($ExistingMessageCount -lt 0) {
        throw "Invalid mailbox state: email thread '$ThreadKey' reported $ExistingMessageCount existing messages."
    }

    if ($ExistingMessageCount -eq 0) { return 'Create' }
    if ($ExistingMessageCount -eq $ExpectedMessageCount) { return 'Skip' }

    if ($ExistingMessageCount -lt $ExpectedMessageCount) {
        throw ("Partial email thread '$ThreadKey': the admin mailbox holds $ExistingMessageCount of " +
               "$ExpectedMessageCount expected messages. The seeder never resumes or duplicates a partial " +
               "thread. Preserve the existing messages, report the partial state, and seed a new " +
               "dated scenario with fresh thread subjects instead. Leave tenant mail untouched.")
    }

    throw ("Ambiguous email thread '$ThreadKey': the admin mailbox holds $ExistingMessageCount messages but " +
           "only $ExpectedMessageCount are expected (excess or duplicated thread). Resolve this manually, then re-run.")
}

# Pick the messages that belong to a declared thread out of an already fetched mailbox
# collection (see engine/Seed-GraphRead.ps1 Get-SeedInboxMessages).
#
# Matching is done here, in memory, instead of with an OData `$filter=subject eq '…'`:
# the scenario subjects are CJK strings containing 【】and full-width punctuation, and a
# server-side filter that silently returns nothing would make an existing thread look absent
# and duplicate it. A first message is an exact (ordinal, whitespace-trimmed) subject match;
# replies carry an "RE:" prefix, so they never match the key but are counted through their
# conversationId. Two conversations sharing the key surface as excess, never as a pick.
function Select-SeedThreadMessages {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][AllowEmptyCollection()]$Messages,
        [Parameter(Mandatory)][string]$FirstSubject
    )

    $all = @(@($Messages) | Where-Object { $null -ne $_ })
    $key = $FirstSubject.Trim()

    $firsts = @($all | Where-Object {
        $props = @($_.PSObject.Properties.Name)
        $subject = if ($props -contains 'subject') { "$($_.subject)".Trim() } else { '' }
        [string]::Equals($subject, $key, [System.StringComparison]::Ordinal)
    })

    if ($firsts.Count -eq 0) {
        return [pscustomobject]@{ ConversationIds = @(); MessageCount = 0; FirstMessageIds = @() }
    }

    $conversationIds = @($firsts | ForEach-Object {
        $props = @($_.PSObject.Properties.Name)
        if ($props -contains 'conversationId') { $_.conversationId } else { $null }
    } | Where-Object { $_ } | Select-Object -Unique)

    $count = $firsts.Count
    if ($conversationIds.Count -gt 0) {
        $count = @($all | Where-Object {
            $props = @($_.PSObject.Properties.Name)
            ($props -contains 'conversationId') -and $_.conversationId -and ($conversationIds -contains $_.conversationId)
        }).Count
    }

    $firstIds = @($firsts | ForEach-Object {
        $props = @($_.PSObject.Properties.Name)
        if ($props -contains 'id') { $_.id } else { $null }
    } | Where-Object { $_ })

    return [pscustomobject]@{
        ConversationIds = $conversationIds
        MessageCount    = $count
        FirstMessageIds = $firstIds
    }
}

# ───────────────────────────────────────────────────────
# Teams expected plan + channel state
# ───────────────────────────────────────────────────────

# Build the declared message plan (content hashes) from teams-messages.json channels.
function Get-SeedExpectedTeamsPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Channels
    )

    $channelList = @()
    $topLevelCount = 0
    $replyCount = 0

    foreach ($channel in @($Channels)) {
        $messages = @()
        foreach ($msg in (@($channel.messages) | Sort-Object { $_.order })) {
            $replyHashes = @()
            if (@($msg.PSObject.Properties.Name) -contains 'replies' -and $msg.replies) {
                foreach ($reply in @($msg.replies)) {
                    $replyHashes += (Get-SeedContentHash -Content $reply.bodyHtml)
                    $replyCount++
                }
            }
            $messages += [pscustomobject]@{
                Order       = $msg.order
                FromRole    = $msg.fromRole
                Hash        = (Get-SeedContentHash -Content $msg.bodyHtml)
                ReplyHashes = $replyHashes
                Source      = $msg
            }
            $topLevelCount++
        }
        $channelList += [pscustomobject]@{
            ChannelName = $channel.channelName
            Messages    = $messages
            Source      = $channel
        }
    }

    return [pscustomobject]@{
        Channels      = $channelList
        TopLevelCount = $topLevelCount
        ReplyCount    = $replyCount
    }
}

# Compare declared hashes against what the tenant actually holds.
# ExpectedReplyHashes / ExistingReplyHashes map a parent content hash to its reply hashes.
# Comparison is a multiset comparison, so a duplicated or unexpected message is reported as
# extra content instead of being silently absorbed by set semantics.
function Get-SeedHashTally {
    [CmdletBinding()]
    param([Parameter()][AllowNull()][AllowEmptyCollection()][string[]]$Hashes)

    $tally = @{}
    foreach ($h in @($Hashes)) {
        if ([string]::IsNullOrEmpty($h)) { continue }
        if ($tally.ContainsKey($h)) { $tally[$h]++ } else { $tally[$h] = 1 }
    }
    return $tally
}

function Compare-SeedTeamsChannelState {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][AllowEmptyCollection()][string[]]$ExpectedTopLevelHashes,
        [Parameter()][AllowNull()]$ExpectedReplyHashes,
        [Parameter()][AllowNull()][AllowEmptyCollection()][string[]]$ExistingTopLevelHashes,
        [Parameter()][AllowNull()]$ExistingReplyHashes
    )

    $expectedTop = @($ExpectedTopLevelHashes)
    $existingTop = @($ExistingTopLevelHashes)
    $expectedReplies = if ($ExpectedReplyHashes) { $ExpectedReplyHashes } else { @{} }
    $existingReplies = if ($ExistingReplyHashes) { $ExistingReplyHashes } else { @{} }

    $expectedTopTally = Get-SeedHashTally -Hashes $expectedTop
    $existingTopTally = Get-SeedHashTally -Hashes $existingTop

    $missingTopLevel = @()
    foreach ($hash in $expectedTopTally.Keys) {
        $have = if ($existingTopTally.ContainsKey($hash)) { $existingTopTally[$hash] } else { 0 }
        for ($i = $have; $i -lt $expectedTopTally[$hash]; $i++) { $missingTopLevel += $hash }
    }

    $extraTopLevel = @()
    foreach ($hash in $existingTopTally.Keys) {
        $want = if ($expectedTopTally.ContainsKey($hash)) { $expectedTopTally[$hash] } else { 0 }
        for ($i = $want; $i -lt $existingTopTally[$hash]; $i++) { $extraTopLevel += $hash }
    }

    $parents = @(@($expectedReplies.Keys) + @($existingReplies.Keys) | Where-Object { $_ } | Select-Object -Unique)
    $missingReplies = @()
    $extraReplies = @()
    foreach ($parentHash in $parents) {
        $expectedForParent = if ($expectedReplies.ContainsKey($parentHash)) { @($expectedReplies[$parentHash]) } else { @() }
        $existingForParent = if ($existingReplies.ContainsKey($parentHash)) { @($existingReplies[$parentHash]) } else { @() }
        $expectedTally = Get-SeedHashTally -Hashes $expectedForParent
        $existingTally = Get-SeedHashTally -Hashes $existingForParent

        foreach ($replyHash in $expectedTally.Keys) {
            $have = if ($existingTally.ContainsKey($replyHash)) { $existingTally[$replyHash] } else { 0 }
            for ($i = $have; $i -lt $expectedTally[$replyHash]; $i++) { $missingReplies += "$parentHash/$replyHash" }
        }
        foreach ($replyHash in $existingTally.Keys) {
            $want = if ($expectedTally.ContainsKey($replyHash)) { $expectedTally[$replyHash] } else { 0 }
            for ($i = $want; $i -lt $existingTally[$replyHash]; $i++) { $extraReplies += "$parentHash/$replyHash" }
        }
    }

    $existingCount = $existingTop.Count
    foreach ($parentHash in $existingReplies.Keys) {
        $existingCount += @($existingReplies[$parentHash]).Count
    }

    $isComplete = (($missingTopLevel.Count -eq 0) -and ($missingReplies.Count -eq 0))
    $hasUnexpected = (($extraTopLevel.Count -gt 0) -or ($extraReplies.Count -gt 0))

    return [pscustomobject]@{
        MissingTopLevel = $missingTopLevel
        MissingReplies  = $missingReplies
        ExtraTopLevel   = $extraTopLevel
        ExtraReplies    = $extraReplies
        ExistingCount   = $existingCount
        IsEmpty         = ($existingCount -eq 0)
        IsComplete      = $isComplete
        HasUnexpected   = $hasUnexpected
        IsExact         = ($isComplete -and -not $hasUnexpected)
    }
}

# Empty channel -> 'Create'; exactly the declared set -> 'Skip'; anything else aborts.
#
# Controller ruling (SDD ledger, Task 3): an existing dated team that is missing any
# expected top-level message or reply must abort. Automatic recovery is unsafe because
# Teams migration mode may already have been completed, in which case historical
# createdDateTime values can no longer be written and a "resume" would silently produce
# a demo dataset with wrong dates or duplicated messages. Unexpected extra content aborts
# for the same reason: the seeder cannot prove the channel matches the declared history.
function Get-SeedTeamsChannelAction {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$ChannelKey
    )

    if ($State.IsEmpty) { return 'Create' }
    if ($State.IsExact) { return 'Skip' }

    $detail = @()
    if ($State.MissingTopLevel.Count -gt 0) { $detail += "missing $($State.MissingTopLevel.Count) top-level message(s)" }
    if ($State.MissingReplies.Count -gt 0) { $detail += "missing $($State.MissingReplies.Count) reply/replies" }
    if ($State.ExtraTopLevel.Count -gt 0) { $detail += "$($State.ExtraTopLevel.Count) unexpected/duplicated top-level message(s)" }
    if ($State.ExtraReplies.Count -gt 0) { $detail += "$($State.ExtraReplies.Count) unexpected/duplicated reply/replies" }

    throw ("Aborting: channel '$ChannelKey' already exists but does not match the declared set — " +
           ($detail -join ' and ') + ". Teams migration may already have been completed for this team, so " +
           "historical timestamps can no longer be written and resuming would corrupt the demo dataset. " +
           "This seeder never resumes a partially migrated team and never deletes tenant resources: " +
           "resolve the team manually, then re-run.")
}

# Verify that an existing single exact dated team really holds the declared content, before
# any write phase runs. Channel cardinality (0 / 1 / >1) and BOTH top-level and reply content
# hashes are checked. Complete -> 'Skip'; partial, extra, missing or ambiguous -> throw.
#
# ChannelStateProvider receives the resolved channel object and must return an object with
# TopLevelHashes / ReplyHashes (engine/Seed-GraphRead.ps1 Get-SeedChannelMessageState does
# exactly that). Keeping the Graph read behind a callback lets the whole verdict be unit
# tested without touching a tenant.
function Get-SeedTeamContentVerdict {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$PlanChannels,
        [Parameter()][AllowNull()][AllowEmptyCollection()]$ExistingChannels,
        [Parameter(Mandatory)][scriptblock]$ChannelStateProvider,
        [Parameter(Mandatory)][string]$TeamKey
    )

    $existing = @(@($ExistingChannels) | Where-Object { $null -ne $_ })
    $results = @()

    # Channel cardinality is settled for the WHOLE team before a single message is read:
    # exactly one General, exactly one instance of every declared channel, and nothing else.
    # An extra channel is undeclared content the seeder can neither verify nor delete, and a
    # demo grounded on it would show material the scenario never described.
    $expectedNames = @('General')
    foreach ($planChannel in @($PlanChannels)) {
        $planName = "$($planChannel.ChannelName)".Trim()
        if (@($expectedNames | Where-Object { [string]::Equals($_, $planName, [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
            $expectedNames += $planName
        }
    }

    $existingNames = @($existing | ForEach-Object { "$($_.displayName)".Trim() })
    $unexpected = @($existingNames | Where-Object {
        $candidate = $_
        @($expectedNames | Where-Object { [string]::Equals($_, $candidate, [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0
    })
    if ($unexpected.Count -gt 0) {
        throw ("Aborting: team '$TeamKey' holds $($unexpected.Count) channel(s) the scenario never declared " +
               "($(@($unexpected | Select-Object -Unique) -join '; ')). The declared set is " +
               "($($expectedNames -join '; ')). Unexpected content cannot be verified and is never deleted by " +
               "this seeder: resolve the team manually, or seed under a new dated team name, then re-run.")
    }

    foreach ($expectedName in $expectedNames) {
        $count = @($existingNames | Where-Object { [string]::Equals($_, $expectedName, [System.StringComparison]::OrdinalIgnoreCase) }).Count
        if ($count -eq 1) { continue }
        if ($count -eq 0) {
            throw ("Aborting: team '$TeamKey' already exists but its '$expectedName' channel is missing. " +
                   "A channel cannot be added in migration mode to a team whose migration is already complete, " +
                   "so the declared history can no longer be written. Resolve the team manually, then re-run.")
        }
        throw ("Aborting: team '$TeamKey' holds $count channels named '$expectedName'. The tenant state is " +
               "ambiguous; the seeder never picks one of them and never deletes anything. Resolve this " +
               "manually, then re-run.")
    }

    foreach ($planChannel in @($PlanChannels)) {
        $channelName = $planChannel.ChannelName
        $matched = @($existing | Where-Object { $_.displayName -eq $channelName })

        # 0 -> missing, 1 -> reuse, >1 -> throws and lists ids/names only.
        $channelAction = Get-SeedResourceAction -Existing $matched -ResourceKind 'channel' -ResourceKey $channelName
        if ($channelAction -eq 'Create') {
            throw ("Aborting: team '$TeamKey' already exists but channel '$channelName' is missing. " +
                   "A channel cannot be added in migration mode to a team whose migration is already complete, " +
                   "so the declared history can no longer be written. Resolve the team manually, then re-run.")
        }

        $channel = $matched[0]

        $expectedTop = @()
        $expectedReplies = @{}
        foreach ($message in @($planChannel.Messages)) {
            $expectedTop += $message.Hash
            if ($expectedReplies.ContainsKey($message.Hash)) {
                $expectedReplies[$message.Hash] = @($expectedReplies[$message.Hash]) + @($message.ReplyHashes)
            } else {
                $expectedReplies[$message.Hash] = @($message.ReplyHashes)
            }
        }

        $existingState = & $ChannelStateProvider $channel
        $state = Compare-SeedTeamsChannelState -ExpectedTopLevelHashes $expectedTop `
                                               -ExpectedReplyHashes $expectedReplies `
                                               -ExistingTopLevelHashes $existingState.TopLevelHashes `
                                               -ExistingReplyHashes $existingState.ReplyHashes

        $messageAction = Get-SeedTeamsChannelAction -State $state -ChannelKey $channelName
        if ($messageAction -eq 'Create') {
            throw ("Aborting: team '$TeamKey' already exists but channel '$channelName' holds no seeded messages. " +
                   "Migration mode is already complete for an existing team, so historical timestamps can no " +
                   "longer be written. Resolve the team manually, then re-run.")
        }

        $results += [pscustomobject]@{
            ChannelName      = $channelName
            ChannelId        = $channel.id
            MessageAction    = $messageAction
            ExistingTopLevel = @($existingState.TopLevelHashes).Count
            State            = $state
        }
    }

    return [pscustomobject]@{
        TeamKey       = $TeamKey
        Channels      = $results
        MessageAction = 'Skip'
    }
}

# ───────────────────────────────────────────────────────
# Identity of a REUSED tenant resource
# ───────────────────────────────────────────────────────

# Normalize an owner / member collection to plain UPN strings. Graph answers
# /groups/{id}/owners with directoryObject entries (userPrincipalName) and
# /teams/{id}/members with aadUserConversationMember entries (email); callers and tests also
# hand in plain strings. All three shapes have to reach the same comparison.
function Get-SeedUpnList {
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter()][AllowNull()][AllowEmptyCollection()]$Items)

    $upns = @()
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        if ($item -is [string]) {
            if (-not [string]::IsNullOrWhiteSpace($item)) { $upns += $item.Trim() }
            continue
        }
        $props = @($item.PSObject.Properties.Name)
        foreach ($name in @('userPrincipalName', 'email', 'upn', 'mail')) {
            if (($props -contains $name) -and $item.$name) {
                $upns += "$($item.$name)".Trim()
                break
            }
        }
    }
    return , @($upns)
}

# UPNs are case-insensitive in Microsoft Entra ID, so a casing difference must never decide a
# tenant-safety verdict.
function Test-SeedUpnInList {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()][AllowNull()][AllowEmptyCollection()]$Upns,
        [Parameter(Mandatory)][string]$Upn
    )

    $key = $Upn.Trim()
    foreach ($candidate in @($Upns)) {
        if ($null -eq $candidate) { continue }
        if ([string]::Equals("$candidate".Trim(), $key, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# Decide what to do with the M365 group behind a dated SharePoint site alias.
#
# A mailNickname is a tenant-wide key that an unrelated group can already hold, so "one group
# matches the alias" is NOT proof that the site belongs to this scenario. Before any document
# or list item is written, the group has to prove all of:
#   * the exact expected mailNickname (the lookup key really is this alias),
#   * the exact expected displayName,
#   * Unified (Microsoft 365) group characteristics — only those provision a SharePoint site,
#   * the demo operator admin among its owners.
# 0 matches -> 'Create'; a proven match -> 'Reuse'; anything else throws. Nothing is renamed,
# re-owned or deleted: the operator resolves the collision (or picks a new dated alias).
#
# OwnerProvider receives the resolved group and must return its owners (engine/Seed-GraphRead.ps1
# Get-SeedGroupOwnerUpns does exactly that). Keeping the Graph read behind a callback lets the
# whole decision be unit tested without touching a tenant.
function Get-SeedSiteGroupVerdict {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][AllowEmptyCollection()][object[]]$ExistingGroups,
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$AdminUpn,
        [Parameter()][AllowNull()][scriptblock]$OwnerProvider
    )

    # 0 -> Create, 1 -> keep verifying, >1 -> throws and lists ids/names only.
    $action = Get-SeedResourceAction -Existing $ExistingGroups -ResourceKind 'site group (mailNickname)' -ResourceKey $Alias
    if ($action -eq 'Create') {
        return [pscustomobject]@{ Action = 'Create'; GroupId = $null; DisplayName = $DisplayName; OwnerUpns = @() }
    }

    $group = @(@($ExistingGroups) | Where-Object { $null -ne $_ })[0]
    $props = @($group.PSObject.Properties.Name)
    $groupId = if ($props -contains 'id') { "$($group.id)" } else { '<no-id>' }
    $actualAlias = if ($props -contains 'mailNickname') { "$($group.mailNickname)".Trim() } else { '' }
    $actualName = if ($props -contains 'displayName') { "$($group.displayName)".Trim() } else { '' }
    $groupTypes = if ($props -contains 'groupTypes') { @(@($group.groupTypes) | ForEach-Object { "$_" }) } else { @() }

    $prefix = "Aborting: the dated site alias '$Alias' resolves to group $groupId"
    $tail = "The seeder never renames, re-owns or deletes a tenant resource: resolve this manually, " +
            "or seed under a new dated alias, then re-run."

    if (-not [string]::Equals($actualAlias, $Alias.Trim(), [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("$prefix, whose mailNickname is '$actualAlias' and not the requested alias. The lookup key " +
               "cannot be trusted, so nothing is written. $tail")
    }
    if (-not [string]::Equals($actualName, $DisplayName.Trim(), [System.StringComparison]::Ordinal)) {
        throw ("$prefix, whose displayName is '$actualName' instead of the declared '$DisplayName'. A " +
               "mailNickname is a tenant-wide key an unrelated site can already hold, so this alias match " +
               "is not proof of identity and no document or list item may be written into it. $tail")
    }
    if (@($groupTypes | Where-Object { [string]::Equals($_, 'Unified', [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
        throw ("$prefix, which is not a Unified (Microsoft 365) group (groupTypes: '$($groupTypes -join ', ')'). " +
               "Only a Unified group provisions the SharePoint site this scenario seeds. $tail")
    }

    $ownerUpns = @()
    if ($OwnerProvider) {
        try {
            # Assigned through a variable first: `@(...)` around a helper that emits an array as
            # one pipeline object would nest it and defeat every UPN comparison.
            $providedOwners = & $OwnerProvider $group
            $ownerUpns = Get-SeedUpnList -Items $providedOwners
        } catch {
            throw ("$prefix, and its owner collection could not be read, so admin ownership cannot be proven: " +
                   "$(Get-SeedGraphErrorText -ErrorObject $_). A site whose ownership is unverifiable is never written to. $tail")
        }
    }
    if (-not (Test-SeedUpnInList -Upns $ownerUpns -Upn $AdminUpn)) {
        throw ("$prefix, which does not carry the demo operator '$AdminUpn' as an owner (owners: " +
               "'$($ownerUpns -join ', ')'). The instructor could not administer the site, and the seeder " +
               "never adds itself or the operator as owner of a resource it did not create. $tail")
    }

    return [pscustomobject]@{
        Action      = 'Reuse'
        GroupId     = $groupId
        DisplayName = $actualName
        OwnerUpns   = @($ownerUpns)
    }
}

# Prove that the demo operator admin already owns an EXISTING team, at both levels Teams uses:
#   * the Microsoft 365 group owner collection, and
#   * the team membership, where the admin entry must carry the 'owner' role.
#
# Both are required: a group owner who is only a team member cannot administer the team in the
# Teams client, and a team owner missing from the group owners loses the site/mailbox rights.
# Shared-tenant policy is fail closed — a wrong role is reported and the run aborts before any
# write. The seeder never promotes a role on a resource it did not create.
function Get-SeedTeamOwnershipVerdict {
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][AllowEmptyCollection()]$GroupOwners,
        [Parameter()][AllowNull()][AllowEmptyCollection()]$TeamMembers,
        [Parameter(Mandatory)][string]$AdminUpn,
        [Parameter(Mandatory)][string]$TeamKey
    )

    $tail = "The seeder never promotes a membership role on a shared tenant and never deletes anything: " +
            "grant the role manually in Teams, or seed under a new dated team name, then re-run."

    $ownerUpns = Get-SeedUpnList -Items $GroupOwners
    if (-not (Test-SeedUpnInList -Upns $ownerUpns -Upn $AdminUpn)) {
        throw ("Aborting: the existing team '$TeamKey' does not list the demo operator '$AdminUpn' among its " +
               "Microsoft 365 group owners (owners: '$($ownerUpns -join ', ')'). $tail")
    }

    $teamOwnerUpns = @()
    foreach ($member in @($TeamMembers)) {
        if ($null -eq $member) { continue }
        $props = @($member.PSObject.Properties.Name)
        $roles = if ($props -contains 'roles') { @(@($member.roles) | ForEach-Object { "$_" }) } else { @() }
        if (@($roles | Where-Object { [string]::Equals($_, 'owner', [System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) { continue }
        # Assigned first: `@(Get-SeedUpnList ...)` nests the emitted array inside another array.
        $memberUpns = Get-SeedUpnList -Items @($member)
        $teamOwnerUpns += @($memberUpns)
    }

    if (-not (Test-SeedUpnInList -Upns $teamOwnerUpns -Upn $AdminUpn)) {
        throw ("Aborting: the existing team '$TeamKey' does not carry the demo operator '$AdminUpn' as a team " +
               "owner (team owners: '$($teamOwnerUpns -join ', ')'). A reused team that left admin as a plain " +
               "member cannot run the demo. $tail")
    }

    return [pscustomobject]@{
        Action         = 'Verified'
        GroupOwnerUpns = @($ownerUpns)
        TeamOwnerUpns  = @($teamOwnerUpns)
    }
}

# ───────────────────────────────────────────────────────
# Known-idempotent Graph error predicates
# ───────────────────────────────────────────────────────

# Flatten anything a Graph catch block can hold into one searchable string.
#
# In PowerShell 7 Invoke-RestMethod puts the Graph JSON payload
# ({"error":{"code":…,"message":…}}) in $_.ErrorDetails.Message, while
# $_.Exception.Message only says "Response status code does not indicate success: 400
# (Bad Request).". Classifying on Exception.Message alone therefore misreads an
# already-completed migration or an existing member as a hard failure, so every catch path
# passes the whole ErrorRecord ($_) and this helper combines both halves.
function Get-SeedGraphErrorText {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyString()][object]$ErrorObject)

    if ($null -eq $ErrorObject) { return '' }
    if ($ErrorObject -is [string]) { return $ErrorObject }

    $parts = @()
    if ($ErrorObject -is [System.Management.Automation.ErrorRecord]) {
        if ($ErrorObject.ErrorDetails -and $ErrorObject.ErrorDetails.Message) { $parts += $ErrorObject.ErrorDetails.Message }
        if ($ErrorObject.Exception) {
            if ($ErrorObject.Exception.Message) { $parts += $ErrorObject.Exception.Message }
            if ($ErrorObject.Exception.InnerException -and $ErrorObject.Exception.InnerException.Message) {
                $parts += $ErrorObject.Exception.InnerException.Message
            }
        }
    } elseif ($ErrorObject -is [System.Exception]) {
        $parts += $ErrorObject.Message
        if ($ErrorObject.InnerException -and $ErrorObject.InnerException.Message) { $parts += $ErrorObject.InnerException.Message }
    } else {
        $parts += "$ErrorObject"
    }

    return (@($parts | Where-Object { $_ }) -join "`n")
}

function Test-SeedMigrationAlreadyComplete {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][Alias('ErrorRecord')][object]$ErrorMessage)
    $text = Get-SeedGraphErrorText -ErrorObject $ErrorMessage
    if ([string]::IsNullOrEmpty($text)) { return $false }
    # "already been finalized" is the wording Graph actually returns when completeMigration is
    # re-posted for a channel or team whose migration finished in an earlier run (observed live,
    # SDD Task 4); the "already completed" / "not in migration" variants are documented.
    return [bool]($text -match 'already been completed|already completed|already been finalized|already finalized|not in migration|not in a migration')
}

function Test-SeedMemberAlreadyExists {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][Alias('ErrorRecord')][object]$ErrorMessage)
    $text = Get-SeedGraphErrorText -ErrorObject $ErrorMessage
    if ([string]::IsNullOrEmpty($text)) { return $false }
    return [bool]($text -match 'already exist')
}

function Test-SeedAlreadyExistsError {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][Alias('ErrorRecord')][object]$ErrorMessage)
    $text = Get-SeedGraphErrorText -ErrorObject $ErrorMessage
    if ([string]::IsNullOrEmpty($text)) { return $false }
    return [bool]($text -match 'already exist|nameAlreadyExists')
}

# A drive folder that does not exist yet answers a children read with 404 itemNotFound. For a
# snapshot reader that means "nothing is stored there", not "the run is broken". Everything else
# — throttling, an authorization failure, a transient 5xx — must keep aborting: a failed read
# silently treated as an empty folder would re-upload every declared file and add a version to
# each of them.
function Test-SeedNotFoundError {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][Alias('ErrorRecord')][object]$ErrorMessage)
    $text = Get-SeedGraphErrorText -ErrorObject $ErrorMessage
    if ([string]::IsNullOrEmpty($text)) { return $false }
    return [bool]($text -match '(?i)itemNotFound|(?i)resourceNotFound|(?i)404\s*\(not found\)')
}

# Graph v1.0 list-channel-messages / list-replies require a ChannelMessage.Read.All or
# ChannelMessage.Read.Group application role. That role is not part of the seeder's documented
# permission set (see config.json.example), so a tenant that can create and migrate the team can
# still be refused the read-back the idempotency verdict depends on. The 403 names the missing
# role, which is what this predicate matches; a generic authorization failure must keep aborting.
function Test-SeedChannelReadForbidden {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][Alias('ErrorRecord')][object]$ErrorMessage)
    $text = Get-SeedGraphErrorText -ErrorObject $ErrorMessage
    if ([string]::IsNullOrEmpty($text)) { return $false }
    if ($text -notmatch 'ChannelMessage\.Read') { return $false }
    return [bool]($text -match '(?i)forbidden|403')
}
