<#
.SYNOPSIS
    Native PowerShell test harness for the PL-7008 M365 seed engine.
.DESCRIPTION
    No external dependency (no Pester). Exits nonzero when any assertion fails.

    Coverage:
      * Pure helper functions in engine/Seed-Idempotency.ps1 are executed for real
        (cardinality, email-thread state, content normalization/hashing, Teams
        channel state comparison, idempotent-error predicates).
      * Scenario data invariants (dated names, tenant-neutral profiles, message
        counts, no real config.json, binary signatures).
      * AST / source invariants for integration points that must never call live
        Microsoft Graph from a unit test (which helper each engine script consumes,
        replies endpoint usage, both completeMigration levels, catch-blocks that
        must rethrow, no DELETE verbs).
      * One real child-process test: run.ps1 with a missing config must exit
        nonzero and must not print the success banner.
.NOTES
    Run:  pwsh -NoProfile -File seed-data\tests\Test-SeedEngine.ps1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path (Join-Path $_ 'config.json.example') })][string]$FixtureScenarioDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ───────────────────────────────────────────────────────
# Paths
# ───────────────────────────────────────────────────────
$TestsDir    = $PSScriptRoot
$SeedRoot    = Split-Path $TestsDir -Parent
$EngineDir   = Join-Path $SeedRoot 'engine'
$ScenarioDir = (Resolve-Path $FixtureScenarioDir).Path
$ScenarioId  = Split-Path $ScenarioDir -Leaf
$RepoRoot    = Split-Path (Split-Path (Split-Path $ScenarioDir -Parent) -Parent) -Parent
$HelperPath  = Join-Path $EngineDir 'Seed-Idempotency.ps1'

# Engine scripts this scenario actually executes — the fail-fast rules apply to these.
$ScenarioEngineScripts = @(
    'Seed-Idempotency.ps1'
    'Seed-GraphRead.ps1'
    'Connect-GraphApp.ps1'
    'Invoke-SeedPreflight.ps1'
    'Invoke-SeedUserProfiles.ps1'
    'Invoke-UploadFiles.ps1'
    'Invoke-SeedEmails.ps1'
    'Invoke-SeedTeamsChannel.ps1'
    'Invoke-SeedSharePoint.ps1'
)

# Functions whose catch blocks are allowed to swallow (bounded polling loops that
# throw / return $null to a caller which throws once the budget is exhausted).
$PollingFunctionAllowList = @(
    'Wait-ForSiteProvisioning'
    'Wait-SeedForMailboxMessage'
    'Wait-SeedForTeamProvisioning'
)

# ───────────────────────────────────────────────────────
# Assertion primitives
# ───────────────────────────────────────────────────────
$script:Passed = 0
$script:Failed = 0
$script:FailedNames = @()

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "── $Title " -ForegroundColor Cyan
}

function Pass {
    param([string]$Name)
    $script:Passed++
    Write-Host "  [PASS] $Name" -ForegroundColor Green
}

function Fail {
    param([string]$Name, [string]$Detail)
    $script:Failed++
    $script:FailedNames += $Name
    Write-Host "  [FAIL] $Name" -ForegroundColor Red
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkRed }
}

function Assert-Value {
    param([string]$Name, $Expected, [scriptblock]$Actual)
    try { $a = & $Actual } catch { Fail $Name "threw: $($_.Exception.Message)"; return }
    if ($a -eq $Expected) { Pass $Name } else { Fail $Name "expected [$Expected] but got [$a]" }
}

function Assert-True {
    param([string]$Name, [scriptblock]$Condition, [string]$Detail)
    try { $r = & $Condition } catch { Fail $Name "threw: $($_.Exception.Message)"; return }
    if ($r) { Pass $Name } else { Fail $Name $Detail }
}

function Assert-Throws {
    param([string]$Name, [scriptblock]$Script, [Parameter(Mandatory)][string]$Pattern)
    try {
        & $Script | Out-Null
    } catch {
        if ($_.CategoryInfo.Reason -eq 'CommandNotFoundException') {
            Fail $Name "command not found: $($_.Exception.Message)"
            return
        }
        if ($_.Exception.Message -match $Pattern) {
            Pass $Name
        } else {
            Fail $Name "message [$($_.Exception.Message)] does not match /$Pattern/"
        }
        return
    }
    Fail $Name 'no exception was thrown'
}

# ───────────────────────────────────────────────────────
# AST utilities
# ───────────────────────────────────────────────────────
function Get-ScriptAst {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    return [pscustomobject]@{ Ast = $ast; Tokens = $tokens; Errors = $errors }
}

function Get-CommandNameCount {
    param($Ast, [string]$CommandName)
    $found = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    $count = 0
    foreach ($c in $found) {
        $n = $c.GetCommandName()
        if ($n -and $n -eq $CommandName) { $count++ }
    }
    return $count
}

function Get-EnclosingFunctionName {
    param($Node)
    $p = $Node
    while ($p) {
        if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return $p.Name }
        $p = $p.Parent
    }
    return '<script-body>'
}

function Get-SwallowingCatchBlocks {
    param($Ast, [string[]]$AllowedFunctions)
    $result = @()
    $catches = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CatchClauseAst] }, $true)
    foreach ($c in $catches) {
        $fn = Get-EnclosingFunctionName -Node $c
        if ($AllowedFunctions -contains $fn) { continue }
        $throws = $c.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.ThrowStatementAst] }, $true)
        $exits = $c.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] }, $true)
        if ($throws.Count -eq 0 -and $exits.Count -eq 0) {
            $result += "$fn @ line $($c.Extent.StartLineNumber)"
        }
    }
    return , $result
}

# ───────────────────────────────────────────────────────
# Load the helper under test (guarded — RED runs may not have it yet)
# ───────────────────────────────────────────────────────
$script:HelperLoaded = $false
if (Test-Path $HelperPath) {
    try {
        . $HelperPath
        $script:HelperLoaded = $true
    } catch {
        Write-Host "  !! Failed to dot-source $HelperPath : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "PL-7008 seed engine tests" -ForegroundColor White
Write-Host "  Seed root:   $SeedRoot" -ForegroundColor Gray
Write-Host "  Scenario:    $ScenarioId" -ForegroundColor Gray
Write-Host "  Helper file: $(if ($script:HelperLoaded) { 'loaded' } else { 'MISSING' })" -ForegroundColor Gray

# ═══════════════════════════════════════════════════════
Write-Section 'Helper: Seed-Idempotency.ps1 is present and loadable'
# ═══════════════════════════════════════════════════════
Assert-True 'engine/Seed-Idempotency.ps1 exists' { Test-Path $HelperPath } "not found at $HelperPath"
Assert-True 'engine/Seed-Idempotency.ps1 dot-sources cleanly' { $script:HelperLoaded } 'dot-source failed or file missing'

# ═══════════════════════════════════════════════════════
Write-Section 'Cardinality: 0 = create, 1 = reuse, >1 = throw'
# ═══════════════════════════════════════════════════════
$oneTeam = @([pscustomobject]@{ id = 'aaa-111'; displayName = 'PL-7008 IT Helpdesk — 2026-08-31' })
$twoTeams = @(
    [pscustomobject]@{ id = 'aaa-111'; displayName = 'PL-7008 IT Helpdesk — 2026-08-31' }
    [pscustomobject]@{ id = 'bbb-222'; displayName = 'PL-7008 IT Helpdesk — 2026-08-31' }
)

Assert-Value 'Get-SeedResourceAction: 0 existing -> Create' 'Create' {
    Get-SeedResourceAction -Existing @() -ResourceKind 'team group' -ResourceKey 'PL-7008 IT Helpdesk — 2026-08-31'
}
Assert-Value 'Get-SeedResourceAction: 1 existing -> Reuse' 'Reuse' {
    Get-SeedResourceAction -Existing $oneTeam -ResourceKind 'team group' -ResourceKey 'PL-7008 IT Helpdesk — 2026-08-31'
}
Assert-Value 'Get-SeedResourceAction: $null existing -> Create' 'Create' {
    Get-SeedResourceAction -Existing $null -ResourceKind 'team group' -ResourceKey 'x'
}
Assert-Throws 'Get-SeedResourceAction: 2 team groups -> throws (ambiguous)' -Pattern 'Ambiguous' -Script {
    Get-SeedResourceAction -Existing $twoTeams -ResourceKind 'team group' -ResourceKey 'PL-7008 IT Helpdesk — 2026-08-31'
}
Assert-Throws 'Get-SeedResourceAction: duplicate error lists resource ids' -Pattern 'aaa-111.*bbb-222' -Script {
    Get-SeedResourceAction -Existing $twoTeams -ResourceKind 'team group' -ResourceKey 'PL-7008 IT Helpdesk — 2026-08-31'
}
Assert-Throws 'Get-SeedResourceAction: duplicate channels -> throws' -Pattern 'Ambiguous' -Script {
    Get-SeedResourceAction -Existing @(
        [pscustomobject]@{ id = 'ch-1'; displayName = '工單協作' }
        [pscustomobject]@{ id = 'ch-2'; displayName = '工單協作' }
    ) -ResourceKind 'channel' -ResourceKey '工單協作'
}
Assert-True 'Get-SeedResourceAction: never selects one of the duplicates' {
    $msg = ''
    try {
        Get-SeedResourceAction -Existing $twoTeams -ResourceKind 'team group' -ResourceKey 'k' | Out-Null
    } catch { $msg = $_.Exception.Message }
    $msg -notmatch 'Reuse' -and $msg -match 'manual'
} 'error message should refuse to pick and require manual resolution'

# ═══════════════════════════════════════════════════════
Write-Section 'Email thread state: 0 = create, exact = skip, partial/excess = throw'
# ═══════════════════════════════════════════════════════
Assert-Value 'Get-SeedEmailThreadAction: 0 of 4 -> Create' 'Create' {
    Get-SeedEmailThreadAction -ExistingMessageCount 0 -ExpectedMessageCount 4 -ThreadKey 'S'
}
Assert-Value 'Get-SeedEmailThreadAction: 4 of 4 -> Skip' 'Skip' {
    Get-SeedEmailThreadAction -ExistingMessageCount 4 -ExpectedMessageCount 4 -ThreadKey 'S'
}
Assert-Value 'Get-SeedEmailThreadAction: 3 of 3 -> Skip' 'Skip' {
    Get-SeedEmailThreadAction -ExistingMessageCount 3 -ExpectedMessageCount 3 -ThreadKey 'S'
}
Assert-Throws 'Get-SeedEmailThreadAction: 2 of 4 -> throws (partial)' -Pattern 'partial' -Script {
    Get-SeedEmailThreadAction -ExistingMessageCount 2 -ExpectedMessageCount 4 -ThreadKey 'S'
}
Assert-Throws 'Get-SeedEmailThreadAction: 1 of 4 -> throws (partial)' -Pattern 'partial' -Script {
    Get-SeedEmailThreadAction -ExistingMessageCount 1 -ExpectedMessageCount 4 -ThreadKey 'S'
}
Assert-Throws 'Get-SeedEmailThreadAction: 6 of 4 -> throws (ambiguous excess)' -Pattern 'ambiguous|excess' -Script {
    Get-SeedEmailThreadAction -ExistingMessageCount 6 -ExpectedMessageCount 4 -ThreadKey 'S'
}
Assert-True 'Get-SeedEmailThreadAction: partial error names the thread key' {
    $msg = ''
    try {
        Get-SeedEmailThreadAction -ExistingMessageCount 2 -ExpectedMessageCount 4 -ThreadKey '【報修】測試主旨' | Out-Null
    } catch { $msg = $_.Exception.Message }
    $msg -match '【報修】測試主旨'
} 'thread key must appear in the error so the operator can find it'
Assert-True 'Get-SeedEmailThreadAction: partial thread preserves data and suggests fresh dated subjects' {
    $msg = ''
    try {
        Get-SeedEmailThreadAction -ExistingMessageCount 2 -ExpectedMessageCount 4 -ThreadKey 'Ford-20260929' | Out-Null
    } catch { $msg = $_.Exception.Message }
    $msg -match 'partial' -and $msg -match 'new|fresh' -and
    $msg -match 'date|dated' -and $msg -match 'subject' -and
    $msg -notmatch 'remove|delete|clear'
} 'a partial mailbox thread must never prompt an operator to delete tenant mail'

Assert-True 'Email delivery timeout errors preserve partially seeded tenant mail' {
    $emailScript = Get-Content (Join-Path $EngineDir 'Invoke-SeedEmails.ps1') -Raw
    $emailScript -notmatch '(?i)remove it manually before re-running' -and
    ([regex]::Matches($emailScript, 'Preserve the existing messages')).Count -eq 2
} 'both first-message and reply timeout errors must instruct preservation, not deletion'

Assert-True 'Legacy MS4022 runner refuses live execution before reading credentials' {
    $legacyRunner = Join-Path $SeedRoot 'scenarios\ms4022-productsupport\run.ps1'
    $script = Get-Content $legacyRunner -Raw
    $guard = $script.IndexOf('Legacy MS-4022 runner is archived')
    $credentials = $script.IndexOf('$configPath =')
    $guard -ge 0 -and $credentials -gt $guard -and
    $script.Contains('ms4022-productsupport-20260929')
} 'the archived runner must not reach the incompatible hardened engine'

Assert-True 'Engine never POSTs the /users or /invitations collection' {
    $bad = @()
    foreach ($file in (Get-ChildItem $EngineDir -Filter '*.ps1' -File)) {
        $ast = (Get-ScriptAst $file.FullName).Ast
        $commands = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
        foreach ($command in $commands) {
            if ($command.GetCommandName() -notin @('Invoke-Graph', 'Invoke-RestMethod')) { continue }
            $text = $command.Extent.Text
            if ($text -match '(?i)-Method\s+POST' -and
                $text -match '(?i)(?:/users(?:["''\s]|$)|/invitations(?:["''\s]|$))') {
                $bad += "$($file.Name):$($command.Extent.StartLineNumber)"
            }
        }
    }
    $bad.Count -eq 0
} 'only already-existing tenant accounts may be referenced'

# ═══════════════════════════════════════════════════════
Write-Section 'Content normalization + stable SHA-256 hash'
# ═══════════════════════════════════════════════════════
$htmlA1 = '<p>Hello   world</p>'
$htmlA2 = "<p>\n  Hello world\n</p>".Replace('\n', "`r`n")
$htmlA3 = "<p>Hello world</p>`n"
$htmlB  = '<p>Hello worlds</p>'

Assert-True 'Get-SeedContentHash: stable across inconsequential whitespace' {
    (Get-SeedContentHash -Content $htmlA1) -eq (Get-SeedContentHash -Content $htmlA2)
} 'whitespace-only differences must hash identically'
Assert-True 'Get-SeedContentHash: stable across trailing newline' {
    (Get-SeedContentHash -Content $htmlA1) -eq (Get-SeedContentHash -Content $htmlA3)
} 'trailing newline must not change the hash'
Assert-True 'Get-SeedContentHash: differs for different content' {
    (Get-SeedContentHash -Content $htmlA1) -ne (Get-SeedContentHash -Content $htmlB)
} 'different text must hash differently'
Assert-True 'Get-SeedContentHash: 64 lowercase hex characters' {
    (Get-SeedContentHash -Content $htmlA1) -cmatch '^[0-9a-f]{64}$'
} 'expected a lowercase SHA-256 hex digest'
Assert-True 'Get-SeedContentHash: handles CJK content deterministically' {
    (Get-SeedContentHash -Content '<p>工單   協作</p>') -eq (Get-SeedContentHash -Content "<p>`n工單 協作`n</p>")
} 'UTF-8 CJK content must normalize identically'
Assert-True 'ConvertTo-SeedNormalizedContent: idempotent' {
    $once = ConvertTo-SeedNormalizedContent -Content $htmlA2
    $twice = ConvertTo-SeedNormalizedContent -Content $once
    $once -eq $twice
} 'normalizing an already normalized string must be a no-op'
Assert-Value 'ConvertTo-SeedNormalizedContent: collapses inter-tag whitespace' '<ul><li>a</li><li>b</li></ul>' {
    ConvertTo-SeedNormalizedContent -Content "<ul>`r`n  <li> a </li>`r`n  <li>b</li>`r`n</ul>"
}

# ═══════════════════════════════════════════════════════
Write-Section 'OData string literals for $filter (SharePoint list item idempotency)'
# ═══════════════════════════════════════════════════════
# Live defect (SDD Task 4): the SharePoint phase built the Title filter with
# `[System.Uri]::EscapeDataString($Fields.Title -replace "'", "''")`. Inside a method argument
# list the comma separates ARGUMENTS, so PowerShell parsed that as a two-argument call and every
# list-item add threw "Cannot find an overload for EscapeDataString and the argument count: 2".
Assert-Value 'ConvertTo-SeedODataLiteral: plain ASCII is percent-encoded' 'IT%20Support' {
    ConvertTo-SeedODataLiteral -Value 'IT Support'
}
Assert-Value 'ConvertTo-SeedODataLiteral: a single quote is doubled, then encoded' 'O%27%27Brien' {
    ConvertTo-SeedODataLiteral -Value "O'Brien"
}
Assert-Value 'ConvertTo-SeedODataLiteral: empty string stays empty' '' {
    ConvertTo-SeedODataLiteral -Value ''
}
Assert-True 'ConvertTo-SeedODataLiteral: CJK titles survive the round trip' {
    $title = '密碼重設服務'
    (([System.Uri]::UnescapeDataString((ConvertTo-SeedODataLiteral -Value $title))) -eq $title)
} 'every declared list item Title in this scenario is CJK'
Assert-True 'ConvertTo-SeedODataLiteral: encodes characters that would break the query' {
    $encoded = ConvertTo-SeedODataLiteral -Value "a&b c'd"
    ($encoded -notmatch '[&'' ]') -and ([System.Uri]::UnescapeDataString($encoded) -eq "a&b c''d")
} 'an unencoded & or space would truncate or corrupt the OData $filter'
Assert-True 'ConvertTo-SeedODataLiteral: real scenario list item Titles all round-trip' {
    $sp = Get-Content (Join-Path $ScenarioDir 'sharepoint-sites.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $bad = @()
    foreach ($site in @($sp.sites)) {
        foreach ($list in @($site.lists)) {
            foreach ($item in @($list.items)) {
                $encoded = ConvertTo-SeedODataLiteral -Value $item.Title
                if ([System.Uri]::UnescapeDataString($encoded) -ne ($item.Title -replace "'", "''")) { $bad += $item.Title }
            }
        }
    }
    $bad.Count -eq 0
} 'the Title filter is the only idempotency key the list-item phase has'
Assert-True 'ConvertTo-SeedODataLiteral: value-level escape equals whole-expression escape' {
    $alias = "pl7008-it-o'brien"
    $whole = [System.Uri]::EscapeDataString("mailNickname eq '$($alias -replace "'", "''")'")
    $parts = "mailNickname%20eq%20%27" + (ConvertTo-SeedODataLiteral -Value $alias) + "%27"
    $whole -eq $parts
} 'the helper must be a drop-in for the inline form, otherwise group lookups would change'

# ═══════════════════════════════════════════════════════
Write-Section 'SharePoint list items: in-memory Title matching (no non-indexed $filter)'
# ═══════════════════════════════════════════════════════
# Live defect (SDD Task 4): the list-item idempotency check used
# `$filter=fields/Title eq '…'`, and Graph answered 400 invalidRequest — "Field 'Title' cannot
# be referenced in filter or orderby as it is not indexed" — for every item of a freshly created
# list. The documented workaround header is explicitly allowed to fail on large lists, so the
# check now snapshots the list once and matches Titles in memory, exactly like the CJK email
# subject matching in Select-SeedThreadMessages.
Assert-True 'Test-SeedListItemExists: exact Title present -> true' {
    Test-SeedListItemExists -ExistingTitles @('SVC-001', 'SVC-002') -Title 'SVC-002'
} 'an existing item must be skipped, never duplicated'
Assert-True 'Test-SeedListItemExists: Title absent -> false' {
    -not (Test-SeedListItemExists -ExistingTitles @('SVC-001', 'SVC-002') -Title 'SVC-003')
} 'a missing item must be created'
Assert-True 'Test-SeedListItemExists: empty snapshot -> false' {
    -not (Test-SeedListItemExists -ExistingTitles @() -Title 'SVC-001')
} 'an empty list must create every declared item'
Assert-True 'Test-SeedListItemExists: null snapshot -> false' {
    -not (Test-SeedListItemExists -ExistingTitles $null -Title 'SVC-001')
} 'null must not throw'
Assert-True 'Test-SeedListItemExists: CJK Title matches exactly' {
    Test-SeedListItemExists -ExistingTitles @('密碼重設服務', '筆電借用') -Title '密碼重設服務'
} 'every SharePoint Title in this scenario may be CJK'
Assert-True 'Test-SeedListItemExists: surrounding whitespace is ignored' {
    Test-SeedListItemExists -ExistingTitles @('  SVC-001  ') -Title 'SVC-001'
} 'SharePoint may return a Title with padding; a false miss would duplicate the item'
Assert-True 'Test-SeedListItemExists: comparison is case sensitive' {
    -not (Test-SeedListItemExists -ExistingTitles @('SVC-001') -Title 'svc-001')
} 'declared Titles are exact keys; a loose match could skip a genuinely different item'
Assert-True 'Invoke-SeedSharePoint.ps1 no longer filters on the non-indexed Title column' {
    $spScript = Join-Path $EngineDir 'Invoke-SeedSharePoint.ps1'
    (Test-Path $spScript) -and ((Get-Content $spScript -Raw -Encoding UTF8) -notmatch 'fields/Title\s+eq')
} 'Graph rejects a $filter on a non-indexed column with 400 invalidRequest'
Assert-True 'Invoke-SeedSharePoint.ps1 decides list-item state through the shared helper' {
    $spScript = Join-Path $EngineDir 'Invoke-SeedSharePoint.ps1'
    if (-not (Test-Path $spScript)) { return $false }
    $spParsed = Get-ScriptAst $spScript
    (Get-CommandNameCount -Ast $spParsed.Ast -CommandName 'Test-SeedListItemExists') -ge 1
} 'the create/skip decision must live in the tested pure helper'
Assert-True 'Invoke-SeedSharePoint.ps1 pages the list-item snapshot' {
    $spScript = Join-Path $EngineDir 'Invoke-SeedSharePoint.ps1'
    if (-not (Test-Path $spScript)) { return $false }
    $spParsed = Get-ScriptAst $spScript
    (Get-CommandNameCount -Ast $spParsed.Ast -CommandName 'Get-SeedGraphCollection') -ge 1
} 'a truncated first page would make an existing item look absent and duplicate it'

# ═══════════════════════════════════════════════════════
Write-Section 'Drive files: exact-name skip so a re-run creates no new version'
# ═══════════════════════════════════════════════════════
# Live defect (SDD Task 4, fix round 1): every run re-PUT all 5 OneDrive files and all 5
# SharePoint documents. A PUT with identical bytes is not a no-op — SharePoint keeps a new
# version of the file and re-serialises the OOXML container, which is exactly why the DOCX
# `size` drifted by 2-3 bytes between the two verified runs. A file whose exact name is
# already in the target folder must be skipped; a missing one must still be uploaded.
Assert-True 'Test-SeedDriveFileExists: exact name present -> true' {
    Test-SeedDriveFileExists -ExistingNames @('a.pdf', 'b.docx') -Name 'b.docx'
} 'an existing file must be skipped, never re-uploaded'
Assert-True 'Test-SeedDriveFileExists: name absent -> false' {
    -not (Test-SeedDriveFileExists -ExistingNames @('a.pdf', 'b.docx') -Name 'c.docx')
} 'a missing file must still be uploaded'
Assert-True 'Test-SeedDriveFileExists: empty snapshot -> false' {
    -not (Test-SeedDriveFileExists -ExistingNames @() -Name 'a.pdf')
} 'an empty folder must receive every declared file'
Assert-True 'Test-SeedDriveFileExists: null snapshot -> false' {
    -not (Test-SeedDriveFileExists -ExistingNames $null -Name 'a.pdf')
} 'null must not throw'
Assert-True 'Test-SeedDriveFileExists: CJK file name matches exactly' {
    Test-SeedDriveFileExists -ExistingNames @('IT政策_密碼規範.pdf', 'IT_FAQ常見問題.docx') -Name 'IT政策_密碼規範.pdf'
} 'every declared demo file name in this scenario is CJK'
Assert-True 'Test-SeedDriveFileExists: surrounding whitespace is ignored' {
    Test-SeedDriveFileExists -ExistingNames @('  IT_FAQ常見問題.docx ') -Name 'IT_FAQ常見問題.docx'
} 'a padded name must not cause a needless re-upload'
Assert-True 'Test-SeedDriveFileExists: comparison is case sensitive' {
    -not (Test-SeedDriveFileExists -ExistingNames @('IT_FAQ.docx') -Name 'it_faq.docx')
} 'declared file names are exact keys; a loose match could leave a declared file absent'
Assert-True 'Test-SeedDriveFileExists: empty declared name -> false' {
    -not (Test-SeedDriveFileExists -ExistingNames @('a.pdf', '') -Name '  ')
} 'an empty name is never "already present"'

# A folder that does not exist yet answers its children read with 404 itemNotFound; that means
# "nothing is there", not "the run is broken". Everything else must keep aborting, otherwise a
# transient Graph failure would silently look like an empty folder.
Assert-True 'Test-SeedNotFoundError: Graph itemNotFound payload -> true' {
    Test-SeedNotFoundError -ErrorRecord '{"error":{"code":"itemNotFound","message":"The resource could not be found."}}'
} 'a missing folder is an empty snapshot'
Assert-True 'Test-SeedNotFoundError: 404 status text -> true' {
    Test-SeedNotFoundError -ErrorRecord 'Response status code does not indicate success: 404 (Not Found).'
} 'PowerShell 7 reports the status line in Exception.Message'
Assert-True 'Test-SeedNotFoundError: 403 Forbidden -> false' {
    -not (Test-SeedNotFoundError -ErrorRecord '{"error":{"code":"accessDenied","message":"Access denied"}}')
} 'an authorization failure must never be read as an empty folder'
Assert-True 'Test-SeedNotFoundError: throttling -> false' {
    -not (Test-SeedNotFoundError -ErrorRecord 'Response status code does not indicate success: 429 (Too Many Requests).')
} 'a throttled read must abort, not re-upload every file'
Assert-True 'Test-SeedNotFoundError: empty input -> false' {
    -not (Test-SeedNotFoundError -ErrorRecord '')
} 'an empty error must not be classified'

# ═══════════════════════════════════════════════════════
Write-Section 'Scenario data: teams-messages.json plan (6 top-level / 9 replies)'
# ═══════════════════════════════════════════════════════
$teamsJsonPath = Join-Path $ScenarioDir 'teams-messages.json'
$emailsJsonPath = Join-Path $ScenarioDir 'emails.json'
$teamsData = $null
$emailData = $null
if (Test-Path $teamsJsonPath) { $teamsData = Get-Content $teamsJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json }
if (Test-Path $emailsJsonPath) { $emailData = Get-Content $emailsJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json }

Assert-Value 'teams-messages.json: 6 top-level messages counted by helper' 6 {
    (Get-SeedExpectedTeamsPlan -Channels $teamsData.channels).TopLevelCount
}
Assert-Value 'teams-messages.json: 9 nested replies counted by helper' 9 {
    (Get-SeedExpectedTeamsPlan -Channels $teamsData.channels).ReplyCount
}
Assert-Value 'teams-messages.json: single channel 工單協作' '工單協作' {
    (Get-SeedExpectedTeamsPlan -Channels $teamsData.channels).Channels[0].ChannelName
}
Assert-True 'Get-SeedExpectedTeamsPlan: every expected message carries a content hash' {
    $plan = Get-SeedExpectedTeamsPlan -Channels $teamsData.channels
    $all = @()
    foreach ($ch in $plan.Channels) {
        foreach ($m in $ch.Messages) {
            $all += $m.Hash
            $all += $m.ReplyHashes
        }
    }
    ($all.Count -eq 15) -and (($all | Where-Object { $_ -cmatch '^[0-9a-f]{64}$' }).Count -eq 15)
} 'expected 6 + 9 = 15 hashes, all SHA-256 hex'

# ═══════════════════════════════════════════════════════
Write-Section 'Teams channel state: empty = create, complete = skip, partial = abort'
# ═══════════════════════════════════════════════════════
$expTop = @('h1', 'h2')
$expReplies = @{ 'h1' = @('r1a', 'r1b'); 'h2' = @('r2a') }

Assert-Value 'Compare-SeedTeamsChannelState: empty channel -> Create' 'Create' {
    $s = Compare-SeedTeamsChannelState -ExpectedTopLevelHashes $expTop -ExpectedReplyHashes $expReplies `
        -ExistingTopLevelHashes @() -ExistingReplyHashes @{}
    Get-SeedTeamsChannelAction -State $s -ChannelKey '工單協作'
}
Assert-Value 'Compare-SeedTeamsChannelState: complete channel -> Skip' 'Skip' {
    $s = Compare-SeedTeamsChannelState -ExpectedTopLevelHashes $expTop -ExpectedReplyHashes $expReplies `
        -ExistingTopLevelHashes @('h2', 'h1') -ExistingReplyHashes @{ 'h1' = @('r1b', 'r1a'); 'h2' = @('r2a') }
    Get-SeedTeamsChannelAction -State $s -ChannelKey '工單協作'
}
Assert-Throws 'Compare-SeedTeamsChannelState: missing top-level -> abort (no resume)' -Pattern 'Aborting|abort' -Script {
    $s = Compare-SeedTeamsChannelState -ExpectedTopLevelHashes $expTop -ExpectedReplyHashes $expReplies `
        -ExistingTopLevelHashes @('h1') -ExistingReplyHashes @{ 'h1' = @('r1a', 'r1b') }
    Get-SeedTeamsChannelAction -State $s -ChannelKey '工單協作'
}
Assert-Throws 'Compare-SeedTeamsChannelState: missing reply -> abort (no resume)' -Pattern 'Aborting|abort' -Script {
    $s = Compare-SeedTeamsChannelState -ExpectedTopLevelHashes $expTop -ExpectedReplyHashes $expReplies `
        -ExistingTopLevelHashes @('h1', 'h2') -ExistingReplyHashes @{ 'h1' = @('r1a'); 'h2' = @('r2a') }
    Get-SeedTeamsChannelAction -State $s -ChannelKey '工單協作'
}
Assert-True 'Compare-SeedTeamsChannelState: reports which replies are missing' {
    $s = Compare-SeedTeamsChannelState -ExpectedTopLevelHashes $expTop -ExpectedReplyHashes $expReplies `
        -ExistingTopLevelHashes @('h1', 'h2') -ExistingReplyHashes @{ 'h1' = @('r1a'); 'h2' = @('r2a') }
    ($s.MissingTopLevel.Count -eq 0) -and ($s.MissingReplies.Count -eq 1) -and (-not $s.IsComplete) -and (-not $s.IsEmpty)
} 'state object should expose MissingTopLevel / MissingReplies / IsComplete / IsEmpty'

# End-to-end over the real scenario data: rebuild the "tenant" content from
# teams-messages.json with whitespace noise (what Graph typically returns) and prove the
# complete set skips while a single dropped reply aborts.
function New-SeedFakeChannelState {
    param($PlanChannel, [int]$DropReplyAt = -1)
    $top = @()
    $replies = @{}
    $replyIndex = 0
    foreach ($m in $PlanChannel.Messages) {
        $noisyBody = "`r`n  " + ($m.Source.bodyHtml -replace '><', ">`r`n  <") + "  `r`n"
        $hash = Get-SeedContentHash -Content $noisyBody
        $top += $hash
        $rh = @()
        foreach ($r in @($m.Source.replies)) {
            if ($replyIndex -ne $DropReplyAt) {
                $rh += (Get-SeedContentHash -Content ("  " + $r.bodyHtml + "`r`n"))
            }
            $replyIndex++
        }
        $replies[$hash] = $rh
    }
    return [pscustomobject]@{ TopLevelHashes = $top; ReplyHashes = $replies }
}

Assert-Value 'Real scenario data: whitespace-noisy complete channel -> Skip' 'Skip' {
    $planChannel = (Get-SeedExpectedTeamsPlan -Channels $teamsData.channels).Channels[0]
    $expected = @()
    $expectedReplies = @{}
    foreach ($m in $planChannel.Messages) { $expected += $m.Hash; $expectedReplies[$m.Hash] = @($m.ReplyHashes) }
    $fake = New-SeedFakeChannelState -PlanChannel $planChannel
    $s = Compare-SeedTeamsChannelState -ExpectedTopLevelHashes $expected -ExpectedReplyHashes $expectedReplies `
        -ExistingTopLevelHashes $fake.TopLevelHashes -ExistingReplyHashes $fake.ReplyHashes
    Get-SeedTeamsChannelAction -State $s -ChannelKey $planChannel.ChannelName
}
Assert-Throws 'Real scenario data: one dropped reply -> abort' -Pattern 'Aborting' -Script {
    $planChannel = (Get-SeedExpectedTeamsPlan -Channels $teamsData.channels).Channels[0]
    $expected = @()
    $expectedReplies = @{}
    foreach ($m in $planChannel.Messages) { $expected += $m.Hash; $expectedReplies[$m.Hash] = @($m.ReplyHashes) }
    $fake = New-SeedFakeChannelState -PlanChannel $planChannel -DropReplyAt 4
    $s = Compare-SeedTeamsChannelState -ExpectedTopLevelHashes $expected -ExpectedReplyHashes $expectedReplies `
        -ExistingTopLevelHashes $fake.TopLevelHashes -ExistingReplyHashes $fake.ReplyHashes
    Get-SeedTeamsChannelAction -State $s -ChannelKey $planChannel.ChannelName
}

# ═══════════════════════════════════════════════════════
Write-Section 'Idempotent-error predicates'
# ═══════════════════════════════════════════════════════
Assert-True 'Test-SeedMigrationAlreadyComplete: "already been completed" -> true' {
    Test-SeedMigrationAlreadyComplete -ErrorMessage 'Migration has already been completed for this team.'
} 'expected true'
Assert-True 'Test-SeedMigrationAlreadyComplete: "not in migration" -> true' {
    Test-SeedMigrationAlreadyComplete -ErrorMessage 'The channel is not in migration mode.'
} 'expected true'
Assert-True 'Test-SeedMigrationAlreadyComplete: unrelated error -> false' {
    -not (Test-SeedMigrationAlreadyComplete -ErrorMessage 'Response status code does not indicate success: 403 (Forbidden).')
} 'expected false for a real failure'
Assert-True 'Test-SeedMemberAlreadyExists: Graph duplicate-member error -> true' {
    Test-SeedMemberAlreadyExists -ErrorMessage "One or more added object references already exist for the following modified properties: 'members'."
} 'expected true'
Assert-True 'Test-SeedMemberAlreadyExists: unrelated error -> false' {
    -not (Test-SeedMemberAlreadyExists -ErrorMessage 'Insufficient privileges to complete the operation.')
} 'expected false for a real failure'
Assert-True 'Test-SeedAlreadyExistsError: nameAlreadyExists -> true' {
    Test-SeedAlreadyExistsError -ErrorMessage 'nameAlreadyExists: An item with the same name already exists.'
} 'expected true'
Assert-True 'Test-SeedAlreadyExistsError: unrelated error -> false' {
    -not (Test-SeedAlreadyExistsError -ErrorMessage 'Response status code does not indicate success: 500 (Internal Server Error).')
} 'expected false for a real failure'

# ═══════════════════════════════════════════════════════
Write-Section 'Static invariants: engine integration points'
# ═══════════════════════════════════════════════════════
$emailScript = Join-Path $EngineDir 'Invoke-SeedEmails.ps1'
$teamsScript = Join-Path $EngineDir 'Invoke-SeedTeamsChannel.ps1'
$preflightScript = Join-Path $EngineDir 'Invoke-SeedPreflight.ps1'
$graphReadScript = Join-Path $EngineDir 'Seed-GraphRead.ps1'
$runScript = Join-Path $ScenarioDir 'run.ps1'

$emailAst = if (Test-Path $emailScript) { Get-ScriptAst $emailScript } else { $null }
$teamsAst = if (Test-Path $teamsScript) { Get-ScriptAst $teamsScript } else { $null }
$preflightAst = if (Test-Path $preflightScript) { Get-ScriptAst $preflightScript } else { $null }
$graphReadAst = if (Test-Path $graphReadScript) { Get-ScriptAst $graphReadScript } else { $null }
$emailText = if (Test-Path $emailScript) { Get-Content $emailScript -Raw -Encoding UTF8 } else { '' }
$teamsText = if (Test-Path $teamsScript) { Get-Content $teamsScript -Raw -Encoding UTF8 } else { '' }
$preflightText = if (Test-Path $preflightScript) { Get-Content $preflightScript -Raw -Encoding UTF8 } else { '' }
$graphReadText = if (Test-Path $graphReadScript) { Get-Content $graphReadScript -Raw -Encoding UTF8 } else { '' }
$runText = if (Test-Path $runScript) { Get-Content $runScript -Raw -Encoding UTF8 } else { '' }

Assert-True 'Invoke-SeedEmails.ps1 dot-sources Seed-Idempotency.ps1' {
    $emailText -match 'Seed-Idempotency\.ps1'
} 'email script must load the shared helper'
Assert-True 'Invoke-SeedEmails.ps1 consumes Get-SeedEmailThreadAction' {
    $emailAst -and (Get-CommandNameCount -Ast $emailAst.Ast -CommandName 'Get-SeedEmailThreadAction') -ge 1
} 'email script must decide create/skip/throw through the helper'
Assert-True 'Invoke-SeedEmails.ps1 keys the thread on the adminUpn mailbox' {
    $emailText -match 'adminUpn'
} 'thread lookup must run against the admin mailbox (admin is CC on every message)'
Assert-True 'Invoke-SeedEmails.ps1 no longer skips a missing reply target' {
    ($emailText -notmatch 'Skipping\.') -and ($emailText -notmatch 'Could not capture conversationId')
} 'missing conversation id / reply target must throw, not warn-and-continue'

Assert-True 'Invoke-SeedTeamsChannel.ps1 dot-sources Seed-Idempotency.ps1' {
    $teamsText -match 'Seed-Idempotency\.ps1'
} 'teams script must load the shared helper'
# Hashing and the reply fetch moved into the shared read-only reader (engine/Seed-GraphRead.ps1)
# so preflight and the Teams phase inspect the tenant with one implementation. The Teams phase
# must still reach both, directly or through the shared plan/reader.
Assert-True 'Teams phase hashes normalized message content' {
    if (-not $teamsAst) { return $false }
    $direct = (Get-CommandNameCount -Ast $teamsAst.Ast -CommandName 'Get-SeedContentHash') -ge 1
    $viaPlan = (Get-CommandNameCount -Ast $teamsAst.Ast -CommandName 'Get-SeedExpectedTeamsPlan') -ge 1
    $viaReader = $graphReadAst -and (Get-CommandNameCount -Ast $graphReadAst.Ast -CommandName 'Get-SeedContentHash') -ge 1
    $direct -or ($viaPlan -and $viaReader)
} 'teams script must hash normalized message content'
Assert-True 'Teams channel inspection fetches replies via /messages/{id}/replies' {
    $viaReader = ($graphReadText -match 'messages/\$[^/]*/replies|/replies\?|/replies"') -and $teamsAst -and (
        (Get-CommandNameCount -Ast $teamsAst.Ast -CommandName 'Get-SeedChannelMessageState') -ge 1 -or
        (Get-CommandNameCount -Ast $teamsAst.Ast -CommandName 'Get-SeedTeamContentVerdict') -ge 1)
    $direct = $teamsText -match 'messages/\$[^/]*/replies|/replies\?|/replies"'
    $direct -or $viaReader
} 'list-channel-messages alone does not return replies'
Assert-True 'Invoke-SeedTeamsChannel.ps1 consumes the cardinality helper' {
    if (-not $teamsAst) { return $false }
    # The team lookup calls it directly; channel cardinality is decided inside
    # Get-SeedTeamContentVerdict, which is itself covered by the pure duplicate-channel tests.
    $team = (Get-CommandNameCount -Ast $teamsAst.Ast -CommandName 'Get-SeedResourceAction') -ge 1
    $channels = (Get-CommandNameCount -Ast $teamsAst.Ast -CommandName 'Get-SeedTeamContentVerdict') -ge 1 -or
                (Get-CommandNameCount -Ast $teamsAst.Ast -CommandName 'Get-SeedResourceAction') -ge 2
    $team -and $channels
} 'team group and channel lookups must both be decided by the shared cardinality rules'
Assert-True 'Invoke-SeedTeamsChannel.ps1 consumes the channel-state helper' {
    if (-not $teamsAst) { return $false }
    ((Get-CommandNameCount -Ast $teamsAst.Ast -CommandName 'Get-SeedTeamsChannelAction') -ge 1) -or
    ((Get-CommandNameCount -Ast $teamsAst.Ast -CommandName 'Get-SeedTeamContentVerdict') -ge 1)
} 'reused teams must be verified complete or abort'

Assert-True 'Invoke-SeedTeamsChannel.ps1 completes migration at both levels' {
    ([regex]::Matches($teamsText, 'completeMigration')).Count -ge 2
} 'channel-level and team-level completeMigration are both required'
Assert-True 'Both completeMigration calls have explicit already-completed handling' {
    $teamsAst -and (Get-CommandNameCount -Ast $teamsAst.Ast -CommandName 'Test-SeedMigrationAlreadyComplete') -ge 2
} 'each completeMigration call site needs its own already-completed guard'
Assert-True 'Both completeMigration calls are wrapped in try/catch' {
    if (-not $teamsAst) { return $false }
    $tries = $teamsAst.Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.TryStatementAst] }, $true)
    $wrapping = @($tries | Where-Object { $_.Body.Extent.Text -match 'completeMigration' })
    $wrapping.Count -ge 2
} 'expected at least two try blocks containing a completeMigration call'
Assert-True 'Invoke-SeedTeamsChannel.ps1 guards member add with Test-SeedMemberAlreadyExists' {
    $teamsAst -and (Get-CommandNameCount -Ast $teamsAst.Ast -CommandName 'Test-SeedMemberAlreadyExists') -ge 1
} 'adding an existing member must be idempotent, everything else must throw'

Assert-True 'engine/Invoke-SeedPreflight.ps1 exists' { Test-Path $preflightScript } 'preflight collision report is required'
Assert-True 'Preflight reports the dated team name, site alias and email subjects' {
    if (-not (Test-Path $preflightScript)) { return $false }
    $t = Get-Content $preflightScript -Raw -Encoding UTF8
    ($t -match 'teamDisplayName') -and ($t -match 'alias') -and ($t -match 'emailThreads')
} 'preflight must cover all three collision surfaces'
Assert-True 'Preflight consumes both cardinality and email-state helpers' {
    $preflightAst -and
    (Get-CommandNameCount -Ast $preflightAst.Ast -CommandName 'Get-SeedResourceAction') -ge 1 -and
    (Get-CommandNameCount -Ast $preflightAst.Ast -CommandName 'Get-SeedEmailThreadAction') -ge 1
} 'preflight must abort on ambiguous duplicates and partial threads'
Assert-True 'No script this scenario runs issues a DELETE request' {
    $hits = @()
    foreach ($name in $ScenarioEngineScripts) {
        $path = Join-Path $EngineDir $name
        if (-not (Test-Path $path)) { continue }
        $t = Get-Content $path -Raw -Encoding UTF8
        if ($t -match '(?i)-Method\s+["'']?DELETE') { $hits += $name }
    }
    $hits.Count -eq 0
} 'the IT helpdesk scenario must never delete a tenant resource'
Assert-True 'No engine script deletes by display name or wildcard' {
    $hits = @()
    foreach ($f in (Get-ChildItem -Path $EngineDir -Filter '*.ps1' -File)) {
        $lines = Get-Content $f.FullName -Encoding UTF8
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '(?i)-Method\s+["'']?DELETE') {
                if ($lines[$i] -match '(?i)displayName|\*') { $hits += "$($f.Name):$($i + 1)" }
            }
        }
    }
    $hits.Count -eq 0
} 'DELETE must always target an explicit resource id'
Assert-True 'run.ps1 never deletes a tenant resource' {
    $runText -notmatch '(?i)-Method\s+["'']?DELETE'
} 'the scenario runner must not delete anything'

# ── Upload phases: exact-name skip + no Graph response on stdout ──
$uploadScript = Join-Path $EngineDir 'Invoke-UploadFiles.ps1'
$uploadAst = if (Test-Path $uploadScript) { Get-ScriptAst $uploadScript } else { $null }
$uploadText = if (Test-Path $uploadScript) { Get-Content $uploadScript -Raw -Encoding UTF8 } else { '' }
$spScriptPath = Join-Path $EngineDir 'Invoke-SeedSharePoint.ps1'
$spAst = if (Test-Path $spScriptPath) { Get-ScriptAst $spScriptPath } else { $null }
$spText = if (Test-Path $spScriptPath) { Get-Content $spScriptPath -Raw -Encoding UTF8 } else { '' }

Assert-True 'Invoke-UploadFiles.ps1 loads the shared read-only reader' {
    $uploadText -match 'Seed-GraphRead\.ps1'
} 'the folder snapshot must come from the shared paging reader'
Assert-True 'Invoke-UploadFiles.ps1 snapshots the target folder before uploading' {
    $uploadAst -and (Get-CommandNameCount -Ast $uploadAst.Ast -CommandName 'Get-SeedDriveChildNames') -ge 1
} 'the engine must know which files are already there'
Assert-True 'Invoke-UploadFiles.ps1 decides the skip through the shared helper' {
    $uploadAst -and (Get-CommandNameCount -Ast $uploadAst.Ast -CommandName 'Test-SeedDriveFileExists') -ge 1
} 'the upload/skip decision must live in the tested pure helper'
Assert-True 'Invoke-SeedSharePoint.ps1 snapshots the document library before uploading' {
    $spAst -and (Get-CommandNameCount -Ast $spAst.Ast -CommandName 'Get-SeedDriveChildNames') -ge 1
} 'the document library state must be read before any PUT'
Assert-True 'Invoke-SeedSharePoint.ps1 decides the document skip through the shared helper' {
    $spAst -and (Get-CommandNameCount -Ast $spAst.Ast -CommandName 'Test-SeedDriveFileExists') -ge 1
} 'the upload/skip decision must live in the tested pure helper'

# Live defect (SDD Task 4, fix round 1): the OneDrive upload PUT left the Graph DriveItem on the
# pipeline, so every run printed @microsoft.graph.downloadUrl — a PRE-AUTHENTICATED capability
# URL whose `tempauth=` parameter downloads the file without any sign-in — straight into the
# ignored run logs. No write call in a script this scenario executes may reach stdout with its
# response body.
$GraphCallCommands = @('Invoke-Graph', 'Invoke-RestMethod')
function Get-UnsuppressedGraphCalls {
    param($Ast, [string[]]$CommandNames)
    $offenders = @()
    $calls = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($c in $calls) {
        $name = $c.GetCommandName()
        if (-not $name -or $CommandNames -notcontains $name) { continue }

        $pipeline = $c.Parent
        if ($pipeline -isnot [System.Management.Automation.Language.PipelineAst]) { continue }

        $elements = @($pipeline.PipelineElements)
        $last = $elements[$elements.Count - 1]
        if (-not [object]::ReferenceEquals($last, $c)) {
            $lastName = if ($last -is [System.Management.Automation.Language.CommandAst]) { $last.GetCommandName() } else { '<expression>' }
            if ($lastName -eq 'Out-Null') { continue }
            $offenders += "line $($c.Extent.StartLineNumber): piped to '$lastName' instead of Out-Null"
            continue
        }

        $parent = $pipeline.Parent
        if ($parent -is [System.Management.Automation.Language.AssignmentStatementAst] -or
            $parent -is [System.Management.Automation.Language.ReturnStatementAst] -or
            $parent -is [System.Management.Automation.Language.ParenExpressionAst] -or
            $parent -is [System.Management.Automation.Language.SubExpressionAst] -or
            $parent -is [System.Management.Automation.Language.ArrayExpressionAst]) { continue }

        $offenders += "line $($c.Extent.StartLineNumber): $name result reaches stdout"
    }
    return , $offenders
}

foreach ($name in $ScenarioEngineScripts) {
    $path = Join-Path $EngineDir $name
    if (-not (Test-Path $path)) {
        Fail "$name : Graph responses never reach stdout" 'file not found'
        continue
    }
    $parsed = Get-ScriptAst $path
    $leaks = Get-UnsuppressedGraphCalls -Ast $parsed.Ast -CommandNames $GraphCallCommands
    if ($leaks.Count -eq 0) {
        Pass "$name : Graph responses never reach stdout"
    } else {
        Fail "$name : Graph responses never reach stdout" ("unsuppressed Graph call at: " + ($leaks -join '; '))
    }
}

# ═══════════════════════════════════════════════════════
Write-Section 'Fail-fast: catch blocks must rethrow'
# ═══════════════════════════════════════════════════════
foreach ($name in $ScenarioEngineScripts) {
    $path = Join-Path $EngineDir $name
    if (-not (Test-Path $path)) {
        Fail "$name : catch blocks rethrow" 'file not found'
        continue
    }
    $parsed = Get-ScriptAst $path
    $swallowers = Get-SwallowingCatchBlocks -Ast $parsed.Ast -AllowedFunctions $PollingFunctionAllowList
    if ($swallowers.Count -eq 0) {
        Pass "$name : catch blocks rethrow"
    } else {
        Fail "$name : catch blocks rethrow" ("log-and-continue catch at: " + ($swallowers -join '; '))
    }
}

# ═══════════════════════════════════════════════════════
Write-Section 'Fail-fast: static .NET method calls bind their arguments correctly'
# ═══════════════════════════════════════════════════════
# `[System.Uri]::EscapeDataString($x -replace "a", "b")` looks like one argument but parses as
# two, because inside a method argument list the comma is an argument separator and never feeds
# the -replace operator. It parses cleanly and only explodes at runtime, so the guard is a
# structural one: every static call to these single-argument helpers must pass exactly one
# argument.
$SingleArgStaticMethods = @('EscapeDataString', 'UnescapeDataString')
foreach ($name in $ScenarioEngineScripts) {
    $path = Join-Path $EngineDir $name
    if (-not (Test-Path $path)) {
        Fail "$name : single-argument static calls" 'file not found'
        continue
    }
    $parsed = Get-ScriptAst $path
    $offenders = @()
    $calls = $parsed.Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true)
    foreach ($call in $calls) {
        $member = "$($call.Member)"
        if ($SingleArgStaticMethods -notcontains $member) { continue }
        $argCount = if ($call.Arguments) { @($call.Arguments).Count } else { 0 }
        if ($argCount -ne 1) {
            $offenders += "line $($call.Extent.StartLineNumber): $member with $argCount arguments"
        }
    }
    if ($offenders.Count -eq 0) {
        Pass "$name : single-argument static calls"
    } else {
        Fail "$name : single-argument static calls" ($offenders -join '; ')
    }
}

# ═══════════════════════════════════════════════════════
Write-Section 'Fail-fast: run.ps1 phase wrapping + missing config'
# ═══════════════════════════════════════════════════════
Assert-True 'run.ps1 wraps every phase in a fail-fast helper' {
    ([regex]::Matches($runText, 'Invoke-SeedPhase')).Count -ge 6
} 'each phase must run through a wrapper that exits nonzero on failure'
Assert-True 'run.ps1 exits nonzero on failure' {
    $runText -match 'exit\s+1'
} 'run.ps1 must set a nonzero process exit code'
Assert-True 'run.ps1 runs preflight before the first write phase' {
    $pf = $runText.IndexOf('Invoke-SeedPreflight.ps1')
    $up = $runText.IndexOf('Invoke-SeedUserProfiles.ps1')
    ($pf -ge 0) -and ($up -ge 0) -and ($pf -lt $up)
} 'collision report must be printed before any write'

# Real child-process test in an isolated copy so a developer's local config.json
# can never be picked up (this test must never touch the live tenant).
$probeRoot = Join-Path $TestsDir '.tmp-runprobe'
try {
    if (Test-Path $probeRoot) { Remove-Item $probeRoot -Recurse -Force }
    $probeScenario = Join-Path $probeRoot 'scenarios\probe'
    New-Item -ItemType Directory -Force -Path $probeScenario | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $probeRoot 'engine') | Out-Null
    Copy-Item (Join-Path $EngineDir '*.ps1') (Join-Path $probeRoot 'engine') -Force
    if (Test-Path $runScript) { Copy-Item $runScript $probeScenario -Force }

    $probeRun = Join-Path $probeScenario 'run.ps1'
    if (Test-Path $probeRun) {
        $pwshExe = (Get-Process -Id $PID).Path
        if (-not $pwshExe) { $pwshExe = 'pwsh' }
        $probeOut = & $pwshExe -NoProfile -NonInteractive -File $probeRun 2>&1 | Out-String
        $probeCode = $LASTEXITCODE

        Assert-True 'run.ps1 with missing config.json exits nonzero' {
            $probeCode -ne 0
        } "exit code was $probeCode; output: $($probeOut.Trim())"
        Assert-True 'run.ps1 with missing config.json prints no success banner' {
            $probeOut -notmatch 'All phases completed'
        } 'success banner must never appear on a failed run'
        Assert-True 'run.ps1 with missing config.json reports the missing config' {
            $probeOut -match 'config\.json'
        } "output did not mention config.json: $($probeOut.Trim())"
    } else {
        Fail 'run.ps1 with missing config.json exits nonzero' 'run.ps1 not found'
    }
} finally {
    if (Test-Path $probeRoot) { Remove-Item $probeRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

# ═══════════════════════════════════════════════════════
Write-Section 'Scenario identity: dated names, no real config, tenant-neutral profiles'
# ═══════════════════════════════════════════════════════
Assert-True 'scenario folder is pl7008-it-helpdesk-20260831' {
    Test-Path $ScenarioDir
} "expected $ScenarioDir"
Assert-True 'scenario config.json is git-ignored' {
    $gitignore = Join-Path (Split-Path $SeedRoot -Parent) '.gitignore'
    (Test-Path $gitignore) -and
    ((Get-Content $gitignore -Raw) -match '(?m)^\s*seed-data/scenarios/\*/config\.json\s*$')
} 'the operator config carries tenant credentials and must never become committable'
Assert-True 'scenario config.json is not tracked by git' {
    # A local config.json is expected on any machine that actually runs the seeder; what must
    # never happen is that it enters the index. When git is unavailable the ignore-rule
    # assertion above still holds the line.
    $tracked = $null
    try {
        Push-Location $SeedRoot
        $tracked = & git ls-files --error-unmatch "scenarios/$ScenarioId/config.json" 2>$null
    } catch {
        $tracked = $null
    } finally {
        Pop-Location
    }
    [string]::IsNullOrWhiteSpace(($tracked | Out-String))
} 'a real config.json must never be committed'
Assert-True 'scenario keeps config.json.example' {
    Test-Path (Join-Path $ScenarioDir 'config.json.example')
} 'the template must ship'

$examplePath = Join-Path $ScenarioDir 'config.json.example'
$example = if (Test-Path $examplePath) { Get-Content $examplePath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

Assert-Value 'config.json.example teamDisplayName is the dated team name' 'PL-7008 IT Helpdesk — 2026-08-31' { $example.teamDisplayName }
Assert-Value 'config.json.example demoUserUpn is admin@moneyyu.com' 'admin@moneyyu.com' { $example.demoUserUpn }
Assert-Value 'config.json.example adminUpn is admin@moneyyu.com' 'admin@moneyyu.com' { $example.adminUpn }
Assert-Value 'config.json.example Admin role upn is admin@moneyyu.com' 'admin@moneyyu.com' { $example.roles.Admin.upn }
Assert-True 'config.json.example role UPNs all use @moneyyu.com' {
    $bad = @()
    foreach ($p in $example.roles.PSObject.Properties) {
        if ($p.Value.upn -notmatch '@moneyyu\.com$') { $bad += "$($p.Name)=$($p.Value.upn)" }
    }
    $bad.Count -eq 0
} 'every role UPN must be an @moneyyu.com address'
Assert-True 'config.json.example keeps tenantId/clientId/clientSecret as placeholders' {
    ($example.tenantId -match '^<.+>$') -and ($example.clientId -match '^<.+>$') -and ($example.clientSecret -match '^<.+>$')
} 'secrets must remain placeholders'

$spPath = Join-Path $ScenarioDir 'sharepoint-sites.json'
$spData = if (Test-Path $spPath) { Get-Content $spPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
Assert-Value 'sharepoint-sites.json alias is pl7008-it-helpdesk-20260831' 'pl7008-it-helpdesk-20260831' { $spData.sites[0].alias }
Assert-Value 'sharepoint-sites.json displayName is the dated site name' 'PL-7008 — IT Helpdesk — 2026-08-31' { $spData.sites[0].displayName }

$profPath = Join-Path $ScenarioDir 'user-profiles.json'
$profData = if (Test-Path $profPath) { Get-Content $profPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }

$expectedProfiles = @(
    @{ Role = 'ITLead';      Upn = 'ChristieC@moneyyu.com'; JobTitle = '數位轉型專案經理'; Department = '金融事業處 / 數位金融部' }
    @{ Role = 'ITEngineer1'; Upn = 'IsaiahL@moneyyu.com';   JobTitle = '資深系統架構師';   Department = '金融事業處 / 資訊科技部' }
    @{ Role = 'ITEngineer2'; Upn = 'JoniS@moneyyu.com';     JobTitle = '資料工程師';       Department = '金融事業處 / 資訊科技部' }
    @{ Role = 'Employee1';   Upn = 'IrvinS@moneyyu.com';    JobTitle = '風險管理副理';     Department = '金融事業處 / 風險管理部' }
    @{ Role = 'Employee2';   Upn = 'JohannaL@moneyyu.com';  JobTitle = '法遵稽核經理';     Department = '金融事業處 / 法令遵循部' }
    @{ Role = 'Employee3';   Upn = 'LidiaH@moneyyu.com';    JobTitle = '金融事業處 副總';  Department = '金融事業處' }
)

foreach ($ep in $expectedProfiles) {
    Assert-True "user-profiles.json: $($ep.Role) re-asserts tenant default ($($ep.JobTitle))" {
        $all = @()
        foreach ($ind in $profData.industries.PSObject.Properties) {
            $p = $ind.Value.profiles.PSObject.Properties | Where-Object { $_.Name -eq $ep.Role }
            if (-not $p) { return $false }
            $all += $p.Value
        }
        if ($all.Count -eq 0) { return $false }
        $bad = @($all | Where-Object {
            $_.upn -ne $ep.Upn -or $_.jobTitle -ne $ep.JobTitle -or $_.department -ne $ep.Department
        })
        $bad.Count -eq 0
    } "expected $($ep.Upn) / $($ep.JobTitle) / $($ep.Department) in every industry section"
}

Assert-True 'user-profiles.json: no Admin entry (admin keeps its operator identity)' {
    $hasAdmin = $false
    foreach ($ind in $profData.industries.PSObject.Properties) {
        if ($ind.Value.profiles.PSObject.Properties.Name -contains 'Admin') { $hasAdmin = $true }
    }
    -not $hasAdmin
} 'admin@moneyyu.com must never be assigned a role profile'
Assert-True 'user-profiles.json: no customer branding in persistent identity' {
    $t = Get-Content $profPath -Raw -Encoding UTF8
    $t -notmatch '國泰|Cathay'
} 'persistent tenant identity must stay customer-neutral'

Assert-True 'run.ps1 -Industry set matches the shipped industry sections' {
    $declared = @($profData.industries.PSObject.Properties.Name)
    $ok = $true
    foreach ($d in $declared) { if ($runText -notmatch [regex]::Escape($d)) { $ok = $false } }
    $ok
} 'every industry offered by run.ps1 must exist in user-profiles.json'

# ═══════════════════════════════════════════════════════
Write-Section 'Scenario data: email threads and DEMO-FILE binaries'
# ═══════════════════════════════════════════════════════
Assert-Value 'emails.json: 2 threads' 2 { $emailData.emailThreads.Count }
Assert-Value 'emails.json: thread 1 first subject' '【報修】我的公司筆電開機後黑屏，急需處理' {
    ($emailData.emailThreads[0].emails | Sort-Object { $_.order } | Select-Object -First 1).subject
}
Assert-Value 'emails.json: thread 1 expected message count' 4 { $emailData.emailThreads[0].emails.Count }
Assert-Value 'emails.json: thread 2 first subject' '【設備借用】下週外部會議室需借便攜投影機 + HDMI 線' {
    ($emailData.emailThreads[1].emails | Sort-Object { $_.order } | Select-Object -First 1).subject
}
Assert-Value 'emails.json: thread 2 expected message count' 3 { $emailData.emailThreads[1].emails.Count }
Assert-True 'emails.json: admin is CC on every message' {
    $bad = @()
    foreach ($t in $emailData.emailThreads) {
        foreach ($m in $t.emails) {
            if (@($m.ccRoles) -notcontains 'Admin') { $bad += $m.subject }
        }
    }
    $bad.Count -eq 0
} 'thread state is keyed off the admin mailbox, so admin must be CC everywhere'

$demoDir = Join-Path $ScenarioDir 'DEMO-FILE'
Assert-Value 'DEMO-FILE: 5 binaries present' 5 {
    if (Test-Path $demoDir) { @(Get-ChildItem $demoDir -File).Count } else { 0 }
}
Assert-True 'DEMO-FILE: every .pdf starts with %PDF-' {
    $bad = @()
    foreach ($f in (Get-ChildItem $demoDir -File -Filter '*.pdf')) {
        $b = [System.IO.File]::ReadAllBytes($f.FullName)[0..4]
        if ([System.Text.Encoding]::ASCII.GetString($b) -ne '%PDF-') { $bad += $f.Name }
    }
    $bad.Count -eq 0
} 'PDF signature check failed'
Assert-True 'DEMO-FILE: every .docx starts with the ZIP magic PK' {
    $bad = @()
    foreach ($f in (Get-ChildItem $demoDir -File -Filter '*.docx')) {
        $b = [System.IO.File]::ReadAllBytes($f.FullName)[0..1]
        if ($b[0] -ne 0x50 -or $b[1] -ne 0x4B) { $bad += $f.Name }
    }
    $bad.Count -eq 0
} 'DOCX (ZIP) signature check failed'
Assert-True 'files-manifest.json references only files that exist' {
    $mf = Get-Content (Join-Path $ScenarioDir 'files-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $bad = @()
    foreach ($f in $mf.files) {
        if (-not (Test-Path (Join-Path $demoDir $f.localName))) { $bad += $f.localName }
    }
    $bad.Count -eq 0
} 'a manifest entry points at a missing binary'

# ═══════════════════════════════════════════════════════
Write-Section 'Graph ErrorRecord classification (real PowerShell 7 catch-path shape)'
# ═══════════════════════════════════════════════════════
# PowerShell 7 puts the Graph JSON payload in $_.ErrorDetails.Message; $_.Exception.Message
# only carries "Response status code does not indicate success: 400 (Bad Request).".
# A predicate fed just .Exception.Message therefore misclassifies an already-completed
# migration or an existing member as a hard failure.
function New-TestGraphErrorRecord {
    param(
        [Parameter(Mandatory)][string]$Json,
        [string]$Plain = 'Response status code does not indicate success: 400 (Bad Request).'
    )
    $ex = [System.Net.Http.HttpRequestException]::new($Plain)
    $record = [System.Management.Automation.ErrorRecord]::new(
        $ex, 'GraphHttpError', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
    $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Json)
    return $record
}

$errMigrationDone = New-TestGraphErrorRecord -Json '{"error":{"code":"Request_BadRequest","message":"Migration has already been completed for this team."}}'
$errNotInMigration = New-TestGraphErrorRecord -Json '{"error":{"code":"Request_BadRequest","message":"The team is not in migration mode."}}'
# Exact payload observed live (SDD Task 4, moneyyu tenant) when completeMigration is re-posted
# for a channel whose migration finished in an earlier run.
$errChannelFinalized = New-TestGraphErrorRecord -Json '{"error":{"code":"BadRequest","message":"Channel has already been finalized."}}'
$errTeamFinalized = New-TestGraphErrorRecord -Json '{"error":{"code":"BadRequest","message":"Team has already been finalized."}}'
$errMemberExists = New-TestGraphErrorRecord -Json '{"error":{"code":"Request_BadRequest","message":"One or more added object references already exist for the following modified properties: ''members''."}}'
$errNameExists = New-TestGraphErrorRecord -Json '{"error":{"code":"nameAlreadyExists","message":"An item with the same name already exists under the parent."}}'
$errForbidden = New-TestGraphErrorRecord -Json '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}' -Plain 'Response status code does not indicate success: 403 (Forbidden).'
# Live 403 from the moneyyu tenant (SDD Task 4): v1.0 list-channel-messages demands a
# ChannelMessage.Read.* role that the seeder's documented application permission set does not
# contain, while the same read succeeds on beta under Group.ReadWrite.All.
$errChannelReadRole = New-TestGraphErrorRecord -Json ('{"error":{"code":"Forbidden","message":"Missing role permissions on the request. ' +
    'API requires one of ''ChannelMessage.Read.All, ChannelMessage.Read.Group''. Roles on the request ''Teamwork.Migrate.All, ' +
    'Mail.ReadWrite, User.ReadWrite.All, Sites.ReadWrite.All, Group.ReadWrite.All''."}}') -Plain 'Response status code does not indicate success: 403 (Forbidden).'

Assert-True 'fixture: the Graph payload lives only in ErrorDetails.Message' {
    ($errMigrationDone.Exception.Message -notmatch 'already been completed') -and
    ($errMigrationDone.ErrorDetails.Message -match 'already been completed')
} 'the fixture must reproduce the real PowerShell 7 shape, otherwise the test is vacuous'
Assert-True 'Get-SeedGraphErrorText: combines ErrorDetails.Message and Exception.Message' {
    $t = Get-SeedGraphErrorText -ErrorObject $errMigrationDone
    ($t -match 'already been completed') -and ($t -match '400')
} 'both halves of the error must reach the caller'
Assert-True 'Get-SeedGraphErrorText: plain string passes through unchanged' {
    (Get-SeedGraphErrorText -ErrorObject 'plain text error') -eq 'plain text error'
} 'string input must keep working for legacy call sites'
Assert-True 'Get-SeedGraphErrorText: bare exception -> its message' {
    (Get-SeedGraphErrorText -ErrorObject ([System.InvalidOperationException]::new('boom'))) -match 'boom'
} 'exception input must be accepted'
Assert-True 'Get-SeedGraphErrorText: $null -> empty string' {
    (Get-SeedGraphErrorText -ErrorObject $null) -eq ''
} 'null must not throw'
Assert-True 'Test-SeedMigrationAlreadyComplete: ErrorRecord (JSON only in ErrorDetails) -> true' {
    Test-SeedMigrationAlreadyComplete -ErrorRecord $errMigrationDone
} 'an already-completed migration must be treated as success'
Assert-True 'Test-SeedMigrationAlreadyComplete: "not in migration" ErrorRecord -> true' {
    Test-SeedMigrationAlreadyComplete -ErrorRecord $errNotInMigration
} 'a team that already left migration mode must be treated as success'
Assert-True 'Test-SeedMigrationAlreadyComplete: 403 ErrorRecord -> false' {
    -not (Test-SeedMigrationAlreadyComplete -ErrorRecord $errForbidden)
} 'a real failure must still throw'
Assert-True 'Test-SeedMigrationAlreadyComplete: "Channel has already been finalized" -> true' {
    Test-SeedMigrationAlreadyComplete -ErrorRecord $errChannelFinalized
} 're-posting completeMigration for a finished channel is the idempotent path, not a failure'
Assert-True 'Test-SeedMigrationAlreadyComplete: "Team has already been finalized" -> true' {
    Test-SeedMigrationAlreadyComplete -ErrorRecord $errTeamFinalized
} 'the team level reports the same finalized wording as the channel level'
Assert-True 'Test-SeedMemberAlreadyExists: ErrorRecord (JSON only in ErrorDetails) -> true' {
    Test-SeedMemberAlreadyExists -ErrorRecord $errMemberExists
} 'an existing member must be idempotent'
Assert-True 'Test-SeedMemberAlreadyExists: 403 ErrorRecord -> false' {
    -not (Test-SeedMemberAlreadyExists -ErrorRecord $errForbidden)
} 'a real membership failure must still throw'
Assert-True 'Test-SeedAlreadyExistsError: ErrorRecord (JSON only in ErrorDetails) -> true' {
    Test-SeedAlreadyExistsError -ErrorRecord $errNameExists
} 'an existing folder/list must be idempotent'
Assert-True 'Predicates fed only .Exception.Message would misclassify (regression proof)' {
    -not (Test-SeedMigrationAlreadyComplete -ErrorMessage $errMigrationDone.Exception.Message)
} 'this is why every catch path must pass $_ and not $_.Exception.Message'
Assert-True 'Test-SeedChannelReadForbidden: missing ChannelMessage.Read role -> true' {
    Test-SeedChannelReadForbidden -ErrorRecord $errChannelReadRole
} 'the v1.0 channel read must be recognised as a permission gap, not a tenant defect'
Assert-True 'Test-SeedChannelReadForbidden: generic 403 -> false' {
    -not (Test-SeedChannelReadForbidden -ErrorRecord $errForbidden)
} 'an unrelated authorization failure must still abort the run'
Assert-True 'Test-SeedChannelReadForbidden: unrelated error -> false' {
    -not (Test-SeedChannelReadForbidden -ErrorRecord $errMigrationDone)
} 'only the missing-role 403 may trigger the read fallback'
Assert-True 'Test-SeedChannelReadForbidden: $null -> false' {
    -not (Test-SeedChannelReadForbidden -ErrorRecord $null)
} 'null must not throw'

# ═══════════════════════════════════════════════════════
Write-Section 'Fail-fast: Graph catch paths pass the whole ErrorRecord'
# ═══════════════════════════════════════════════════════
$IdempotencyPredicates = @('Test-SeedMigrationAlreadyComplete', 'Test-SeedMemberAlreadyExists', 'Test-SeedAlreadyExistsError')

function Get-PredicateCallSites {
    param($Ast, [string[]]$CommandNames)
    $sites = @()
    $commands = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($c in $commands) {
        $name = $c.GetCommandName()
        if (-not $name -or $CommandNames -notcontains $name) { continue }
        $values = @()
        for ($i = 1; $i -lt $c.CommandElements.Count; $i++) {
            $el = $c.CommandElements[$i]
            if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
                if ($el.Argument) { $values += $el.Argument.Extent.Text }
                continue
            }
            $values += $el.Extent.Text
        }
        $sites += [pscustomobject]@{ Command = $name; Line = $c.Extent.StartLineNumber; Values = $values }
    }
    return $sites
}

foreach ($name in $ScenarioEngineScripts) {
    $path = Join-Path $EngineDir $name
    if (-not (Test-Path $path)) { continue }
    $parsed = Get-ScriptAst $path
    $sites = @(Get-PredicateCallSites -Ast $parsed.Ast -CommandNames $IdempotencyPredicates)
    if ($sites.Count -eq 0) { continue }
    $bad = @($sites | Where-Object {
        $v = @($_.Values)
        ($v.Count -ne 1) -or ($v[0] -notin @('$_', '$PSItem'))
    })
    Assert-True "$name : idempotent-error predicates receive the ErrorRecord (`$_)" {
        $bad.Count -eq 0
    } ("call sites passing something else: " + (($bad | ForEach-Object { "line $($_.Line): $($_.Command) $($_.Values -join ' ')" }) -join '; '))
}

Assert-True 'No Graph catch path reports only $_.Exception.Message' {
    $hits = @()
    foreach ($name in $ScenarioEngineScripts) {
        $path = Join-Path $EngineDir $name
        if (-not (Test-Path $path)) { continue }
        $lines = Get-Content $path -Encoding UTF8
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*#') { continue }
            if ($lines[$i] -match '\$_\.Exception\.Message') { $hits += "$name : $($i + 1)" }
        }
    }
    $hits.Count -eq 0
} 'the Graph payload lives in ErrorDetails.Message; report through Get-SeedGraphErrorText'

# ═══════════════════════════════════════════════════════
Write-Section 'Inbox thread lookup: manual exact matching (no OData subject filter)'
# ═══════════════════════════════════════════════════════
$firstSubjectA = '【報修】我的公司筆電開機後黑屏，急需處理'
$firstSubjectB = '【設備借用】下週外部會議室需借便攜投影機 + HDMI 線'
$inboxFixture = @(
    [pscustomobject]@{ id = 'm1'; subject = $firstSubjectA;       conversationId = 'conv-a' }
    [pscustomobject]@{ id = 'm2'; subject = "RE: $firstSubjectA"; conversationId = 'conv-a' }
    [pscustomobject]@{ id = 'm3'; subject = "RE: $firstSubjectA"; conversationId = 'conv-a' }
    [pscustomobject]@{ id = 'm4'; subject = "RE: $firstSubjectA"; conversationId = 'conv-a' }
    [pscustomobject]@{ id = 'm5'; subject = $firstSubjectB;       conversationId = 'conv-b' }
    [pscustomobject]@{ id = 'm6'; subject = '【公告】完全無關的信'; conversationId = 'conv-c' }
)

Assert-Value 'Select-SeedThreadMessages: complete CJK thread is counted exactly' 4 {
    (Select-SeedThreadMessages -Messages $inboxFixture -FirstSubject $firstSubjectA).MessageCount
}
Assert-Value 'Select-SeedThreadMessages: second thread is counted independently' 1 {
    (Select-SeedThreadMessages -Messages $inboxFixture -FirstSubject $firstSubjectB).MessageCount
}
Assert-Value 'Select-SeedThreadMessages: absent subject -> 0' 0 {
    (Select-SeedThreadMessages -Messages $inboxFixture -FirstSubject '【報修】不存在的主旨').MessageCount
}
Assert-Value 'Select-SeedThreadMessages: empty mailbox -> 0' 0 {
    (Select-SeedThreadMessages -Messages @() -FirstSubject $firstSubjectA).MessageCount
}
Assert-Value 'Select-SeedThreadMessages: matching is exact, not prefix/substring' 0 {
    $repliesOnly = @($inboxFixture | Where-Object { $_.id -in @('m2', 'm3', 'm4') })
    (Select-SeedThreadMessages -Messages $repliesOnly -FirstSubject $firstSubjectA).MessageCount
}
Assert-Value 'Select-SeedThreadMessages: tolerates surrounding whitespace from Graph' 4 {
    $padded = @($inboxFixture | ForEach-Object {
        [pscustomobject]@{ id = $_.id; subject = " $($_.subject) "; conversationId = $_.conversationId }
    })
    (Select-SeedThreadMessages -Messages $padded -FirstSubject $firstSubjectA).MessageCount
}
Assert-Value 'Select-SeedThreadMessages: reports the matched conversation id' 'conv-a' {
    (Select-SeedThreadMessages -Messages $inboxFixture -FirstSubject $firstSubjectA).ConversationIds -join ','
}
Assert-True 'Select-SeedThreadMessages: duplicated thread surfaces both conversations' {
    $dup = $inboxFixture + @(
        [pscustomobject]@{ id = 'd1'; subject = $firstSubjectA; conversationId = 'conv-dup' }
        [pscustomobject]@{ id = 'd2'; subject = "RE: $firstSubjectA"; conversationId = 'conv-dup' }
    )
    $state = Select-SeedThreadMessages -Messages $dup -FirstSubject $firstSubjectA
    (@($state.ConversationIds).Count -eq 2) -and ($state.MessageCount -eq 6)
} 'a duplicated thread must be reported as excess, never silently reused'
Assert-Throws 'Inbox state + Get-SeedEmailThreadAction: duplicated thread -> throws' -Pattern 'ambiguous|excess' -Script {
    $dup = $inboxFixture + @(
        [pscustomobject]@{ id = 'd1'; subject = $firstSubjectA; conversationId = 'conv-dup' }
        [pscustomobject]@{ id = 'd2'; subject = "RE: $firstSubjectA"; conversationId = 'conv-dup' }
    )
    $state = Select-SeedThreadMessages -Messages $dup -FirstSubject $firstSubjectA
    Get-SeedEmailThreadAction -ExistingMessageCount $state.MessageCount -ExpectedMessageCount 4 -ThreadKey $firstSubjectA
}
Assert-Throws 'Inbox state + Get-SeedEmailThreadAction: partial thread -> throws' -Pattern 'Partial|partial' -Script {
    $partial = @($inboxFixture | Where-Object { $_.id -in @('m1', 'm2') })
    $state = Select-SeedThreadMessages -Messages $partial -FirstSubject $firstSubjectA
    Get-SeedEmailThreadAction -ExistingMessageCount $state.MessageCount -ExpectedMessageCount 4 -ThreadKey $firstSubjectA
}

# ═══════════════════════════════════════════════════════
Write-Section 'Teams channel state: unexpected/extra content also aborts'
# ═══════════════════════════════════════════════════════
Assert-True 'Compare-SeedTeamsChannelState: exposes extra top-level content' {
    $s = Compare-SeedTeamsChannelState -ExpectedTopLevelHashes $expTop -ExpectedReplyHashes $expReplies `
        -ExistingTopLevelHashes @('h1', 'h2', 'h-unknown') -ExistingReplyHashes @{ 'h1' = @('r1a', 'r1b'); 'h2' = @('r2a') }
    (@($s.ExtraTopLevel).Count -eq 1) -and ($s.HasUnexpected)
} 'unexpected messages must be visible in the state object'
Assert-Throws 'Get-SeedTeamsChannelAction: unexpected extra message -> abort' -Pattern 'Aborting|unexpected|excess' -Script {
    $s = Compare-SeedTeamsChannelState -ExpectedTopLevelHashes $expTop -ExpectedReplyHashes $expReplies `
        -ExistingTopLevelHashes @('h1', 'h2', 'h-unknown') -ExistingReplyHashes @{ 'h1' = @('r1a', 'r1b'); 'h2' = @('r2a') }
    Get-SeedTeamsChannelAction -State $s -ChannelKey '工單協作'
}
Assert-Throws 'Get-SeedTeamsChannelAction: duplicated expected message -> abort' -Pattern 'Aborting|unexpected|excess' -Script {
    $s = Compare-SeedTeamsChannelState -ExpectedTopLevelHashes $expTop -ExpectedReplyHashes $expReplies `
        -ExistingTopLevelHashes @('h1', 'h1', 'h2') -ExistingReplyHashes @{ 'h1' = @('r1a', 'r1b'); 'h2' = @('r2a') }
    Get-SeedTeamsChannelAction -State $s -ChannelKey '工單協作'
}
Assert-Throws 'Get-SeedTeamsChannelAction: unexpected extra reply -> abort' -Pattern 'Aborting|unexpected|excess' -Script {
    $s = Compare-SeedTeamsChannelState -ExpectedTopLevelHashes $expTop -ExpectedReplyHashes $expReplies `
        -ExistingTopLevelHashes @('h1', 'h2') -ExistingReplyHashes @{ 'h1' = @('r1a', 'r1b', 'r-unknown'); 'h2' = @('r2a') }
    Get-SeedTeamsChannelAction -State $s -ChannelKey '工單協作'
}
Assert-Value 'Get-SeedTeamsChannelAction: exact match still skips' 'Skip' {
    $s = Compare-SeedTeamsChannelState -ExpectedTopLevelHashes $expTop -ExpectedReplyHashes $expReplies `
        -ExistingTopLevelHashes @('h2', 'h1') -ExistingReplyHashes @{ 'h1' = @('r1b', 'r1a'); 'h2' = @('r2a') }
    Get-SeedTeamsChannelAction -State $s -ChannelKey '工單協作'
}

# ═══════════════════════════════════════════════════════
Write-Section 'Team content verdict: preflight verification of a reused dated team'
# ═══════════════════════════════════════════════════════
$verdictPlanChannels = if ($teamsData) { (Get-SeedExpectedTeamsPlan -Channels $teamsData.channels).Channels } else { @() }
$verdictChannelName = if ($verdictPlanChannels.Count -gt 0) { $verdictPlanChannels[0].ChannelName } else { '工單協作' }
$verdictExisting = @(
    [pscustomobject]@{ id = 'ch-general'; displayName = 'General' }
    [pscustomobject]@{ id = 'ch-0001'; displayName = $verdictChannelName }
)
$verdictComplete = { param($Channel) New-SeedFakeChannelState -PlanChannel $verdictPlanChannels[0] }
$verdictMissingReply = { param($Channel) New-SeedFakeChannelState -PlanChannel $verdictPlanChannels[0] -DropReplyAt 3 }
$verdictEmpty = { param($Channel) [pscustomobject]@{ TopLevelHashes = @(); ReplyHashes = @{} } }

Assert-Value 'Get-SeedTeamContentVerdict: complete reused team -> Skip' 'Skip' {
    $v = Get-SeedTeamContentVerdict -PlanChannels $verdictPlanChannels -ExistingChannels $verdictExisting `
        -ChannelStateProvider $verdictComplete -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31'
    @($v.Channels)[0].MessageAction
}
Assert-Value 'Get-SeedTeamContentVerdict: verdict carries the resolved channel id' 'ch-0001' {
    $v = Get-SeedTeamContentVerdict -PlanChannels $verdictPlanChannels -ExistingChannels $verdictExisting `
        -ChannelStateProvider $verdictComplete -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31'
    @($v.Channels)[0].ChannelId
}
Assert-Throws 'Get-SeedTeamContentVerdict: one dropped reply -> abort' -Pattern 'Aborting|abort' -Script {
    Get-SeedTeamContentVerdict -PlanChannels $verdictPlanChannels -ExistingChannels $verdictExisting `
        -ChannelStateProvider $verdictMissingReply -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31'
}
Assert-Throws 'Get-SeedTeamContentVerdict: empty channel on an existing team -> abort' -Pattern 'Aborting|abort' -Script {
    Get-SeedTeamContentVerdict -PlanChannels $verdictPlanChannels -ExistingChannels $verdictExisting `
        -ChannelStateProvider $verdictEmpty -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31'
}
Assert-Throws 'Get-SeedTeamContentVerdict: declared channel missing -> abort' -Pattern 'Aborting|abort|missing' -Script {
    Get-SeedTeamContentVerdict -PlanChannels $verdictPlanChannels `
        -ExistingChannels @([pscustomobject]@{ id = 'ch-general'; displayName = 'General' }) `
        -ChannelStateProvider $verdictComplete -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31'
}
Assert-Throws 'Get-SeedTeamContentVerdict: duplicate declared channel -> abort' -Pattern 'Ambiguous|ambiguous' -Script {
    Get-SeedTeamContentVerdict -PlanChannels $verdictPlanChannels -ExistingChannels ($verdictExisting + @(
        [pscustomobject]@{ id = 'ch-dupe'; displayName = $verdictChannelName })) `
        -ChannelStateProvider $verdictComplete -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31'
}

# ═══════════════════════════════════════════════════════
Write-Section 'Team content verdict: channel cardinality must be exact'
# ═══════════════════════════════════════════════════════
# An extra channel is content the scenario never declared. It cannot be verified, it changes
# what the demo shows, and the seeder must never delete it — so a reused team carrying one has
# to abort before migration completion and membership are written.
Assert-Throws 'Get-SeedTeamContentVerdict: an undeclared extra channel -> abort' -Pattern 'Aborting|unexpected|extra' -Script {
    Get-SeedTeamContentVerdict -PlanChannels $verdictPlanChannels `
        -ExistingChannels ($verdictExisting + @([pscustomobject]@{ id = 'ch-extra'; displayName = '臨時討論' })) `
        -ChannelStateProvider $verdictComplete -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31'
}
Assert-Throws 'Get-SeedTeamContentVerdict: missing General channel -> abort' -Pattern 'Aborting|General' -Script {
    Get-SeedTeamContentVerdict -PlanChannels $verdictPlanChannels `
        -ExistingChannels @([pscustomobject]@{ id = 'ch-0001'; displayName = $verdictChannelName }) `
        -ChannelStateProvider $verdictComplete -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31'
}
Assert-Throws 'Get-SeedTeamContentVerdict: duplicated General channel -> abort' -Pattern 'Aborting|General|Ambiguous' -Script {
    Get-SeedTeamContentVerdict -PlanChannels $verdictPlanChannels `
        -ExistingChannels ($verdictExisting + @([pscustomobject]@{ id = 'ch-general-2'; displayName = 'General' })) `
        -ChannelStateProvider $verdictComplete -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31'
}
Assert-True 'Get-SeedTeamContentVerdict: the extra-channel abort happens before any channel state is read' {
    $script:ChannelStateReads = 0
    try {
        Get-SeedTeamContentVerdict -PlanChannels $verdictPlanChannels `
            -ExistingChannels ($verdictExisting + @([pscustomobject]@{ id = 'ch-extra'; displayName = '臨時討論' })) `
            -ChannelStateProvider { param($Channel) $script:ChannelStateReads++; New-SeedFakeChannelState -PlanChannel $verdictPlanChannels[0] } `
            -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31' | Out-Null
    } catch { }
    $script:ChannelStateReads -eq 0
} 'cardinality is the cheapest check and must gate the message reads'
Assert-Value 'Get-SeedTeamContentVerdict: exactly General + declared channel still -> Skip' 'Skip' {
    (Get-SeedTeamContentVerdict -PlanChannels $verdictPlanChannels -ExistingChannels $verdictExisting `
        -ChannelStateProvider $verdictComplete -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31').MessageAction
}

# ═══════════════════════════════════════════════════════
Write-Section 'Reused site identity: a matching alias alone must never authorize a write'
# ═══════════════════════════════════════════════════════
# A mailNickname is a tenant-wide key an unrelated group can already hold. Before Phase 7 writes
# a document or a list item into a site, the group behind the alias has to prove it is the
# scenario's own site: exact alias, exact displayName, a Unified (M365) group, and the operator
# admin among its owners.
$siteAlias       = 'pl7008-it-helpdesk-20260831'
$siteDisplayName = 'PL-7008 — IT Helpdesk — 2026-08-31'
$siteAdminUpn    = 'admin@moneyyu.com'
$siteGroupOk     = [pscustomobject]@{ id = 'grp-site-1'; displayName = $siteDisplayName; mailNickname = $siteAlias; groupTypes = @('Unified') }
$siteOwnersOk    = { param($Group) @('ChristieC@moneyyu.com', 'admin@moneyyu.com') }
$siteOwnersNoAdmin = { param($Group) @('ChristieC@moneyyu.com') }

Assert-Value 'Get-SeedSiteGroupVerdict: no group holds the alias -> Create' 'Create' {
    (Get-SeedSiteGroupVerdict -ExistingGroups @() -Alias $siteAlias -DisplayName $siteDisplayName `
        -AdminUpn $siteAdminUpn -OwnerProvider $siteOwnersOk).Action
}
Assert-Value 'Get-SeedSiteGroupVerdict: exact identity + admin owner -> Reuse' 'Reuse' {
    (Get-SeedSiteGroupVerdict -ExistingGroups @($siteGroupOk) -Alias $siteAlias -DisplayName $siteDisplayName `
        -AdminUpn $siteAdminUpn -OwnerProvider $siteOwnersOk).Action
}
Assert-Value 'Get-SeedSiteGroupVerdict: the verdict carries the resolved group id' 'grp-site-1' {
    (Get-SeedSiteGroupVerdict -ExistingGroups @($siteGroupOk) -Alias $siteAlias -DisplayName $siteDisplayName `
        -AdminUpn $siteAdminUpn -OwnerProvider $siteOwnersOk).GroupId
}
Assert-True 'Get-SeedSiteGroupVerdict: an admin owner is matched case-insensitively' {
    $g = [pscustomobject]@{ id = 'grp-site-1'; displayName = $siteDisplayName; mailNickname = $siteAlias; groupTypes = @('Unified') }
    (Get-SeedSiteGroupVerdict -ExistingGroups @($g) -Alias $siteAlias -DisplayName $siteDisplayName `
        -AdminUpn $siteAdminUpn -OwnerProvider { param($Group) @('Admin@MoneyYu.com') }).Action -eq 'Reuse'
} 'UPNs are case-insensitive in Entra ID'
Assert-Throws 'Get-SeedSiteGroupVerdict: displayName mismatch -> abort' -Pattern 'displayName|Aborting' -Script {
    $g = [pscustomobject]@{ id = 'grp-other'; displayName = '行銷部共用區'; mailNickname = $siteAlias; groupTypes = @('Unified') }
    Get-SeedSiteGroupVerdict -ExistingGroups @($g) -Alias $siteAlias -DisplayName $siteDisplayName `
        -AdminUpn $siteAdminUpn -OwnerProvider $siteOwnersOk
}
Assert-Throws 'Get-SeedSiteGroupVerdict: non-Unified group -> abort' -Pattern 'Unified|Aborting' -Script {
    $g = [pscustomobject]@{ id = 'grp-sec'; displayName = $siteDisplayName; mailNickname = $siteAlias; groupTypes = @() }
    Get-SeedSiteGroupVerdict -ExistingGroups @($g) -Alias $siteAlias -DisplayName $siteDisplayName `
        -AdminUpn $siteAdminUpn -OwnerProvider $siteOwnersOk
}
Assert-Throws 'Get-SeedSiteGroupVerdict: admin is not an owner -> abort' -Pattern 'owner|Aborting' -Script {
    Get-SeedSiteGroupVerdict -ExistingGroups @($siteGroupOk) -Alias $siteAlias -DisplayName $siteDisplayName `
        -AdminUpn $siteAdminUpn -OwnerProvider $siteOwnersNoAdmin
}
Assert-Throws 'Get-SeedSiteGroupVerdict: alias mismatch -> abort' -Pattern 'alias|mailNickname|Aborting' -Script {
    $g = [pscustomobject]@{ id = 'grp-site-1'; displayName = $siteDisplayName; mailNickname = 'pl7008-it-helpdesk-20260101'; groupTypes = @('Unified') }
    Get-SeedSiteGroupVerdict -ExistingGroups @($g) -Alias $siteAlias -DisplayName $siteDisplayName `
        -AdminUpn $siteAdminUpn -OwnerProvider $siteOwnersOk
}
Assert-Throws 'Get-SeedSiteGroupVerdict: two groups share the alias -> abort without choosing' -Pattern 'Ambiguous|ambiguous' -Script {
    $g2 = [pscustomobject]@{ id = 'grp-site-2'; displayName = $siteDisplayName; mailNickname = $siteAlias; groupTypes = @('Unified') }
    Get-SeedSiteGroupVerdict -ExistingGroups @($siteGroupOk, $g2) -Alias $siteAlias -DisplayName $siteDisplayName `
        -AdminUpn $siteAdminUpn -OwnerProvider $siteOwnersOk
}
Assert-Throws 'Get-SeedSiteGroupVerdict: an unreadable owner collection -> abort (never assume ownership)' -Pattern 'owner|Aborting|forbidden' -Script {
    Get-SeedSiteGroupVerdict -ExistingGroups @($siteGroupOk) -Alias $siteAlias -DisplayName $siteDisplayName `
        -AdminUpn $siteAdminUpn -OwnerProvider { param($Group) throw 'Response status code does not indicate success: 403 (Forbidden).' }
}

# ═══════════════════════════════════════════════════════
Write-Section 'Reused Team ownership: admin must already be owner at both levels'
# ═══════════════════════════════════════════════════════
# Shared-tenant policy is fail closed: a reused team whose admin is only a member is reported
# and aborted, never promoted by the seeder.
$teamOwnersOk      = @('admin@moneyyu.com')
$teamMembersOwner  = @(
    [pscustomobject]@{ id = 'mem-1'; email = 'admin@moneyyu.com'; roles = @('owner') }
    [pscustomobject]@{ id = 'mem-2'; email = 'ChristieC@moneyyu.com'; roles = @() }
)
$teamMembersNoOwner = @(
    [pscustomobject]@{ id = 'mem-1'; email = 'admin@moneyyu.com'; roles = @() }
    [pscustomobject]@{ id = 'mem-2'; email = 'ChristieC@moneyyu.com'; roles = @('owner') }
)

Assert-Value 'Get-SeedTeamOwnershipVerdict: admin owns group and team -> Verified' 'Verified' {
    (Get-SeedTeamOwnershipVerdict -GroupOwners $teamOwnersOk -TeamMembers $teamMembersOwner `
        -AdminUpn $siteAdminUpn -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31').Action
}
Assert-True 'Get-SeedTeamOwnershipVerdict: reports the resolved owner UPNs' {
    $v = Get-SeedTeamOwnershipVerdict -GroupOwners $teamOwnersOk -TeamMembers $teamMembersOwner `
        -AdminUpn $siteAdminUpn -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31'
    (@($v.GroupOwnerUpns) -contains 'admin@moneyyu.com') -and (@($v.TeamOwnerUpns) -contains 'admin@moneyyu.com')
} 'the verdict must expose what it proved'
Assert-True 'Get-SeedTeamOwnershipVerdict: owner objects are accepted as well as UPN strings' {
    $owners = @([pscustomobject]@{ id = 'u1'; userPrincipalName = 'admin@moneyyu.com' })
    (Get-SeedTeamOwnershipVerdict -GroupOwners $owners -TeamMembers $teamMembersOwner `
        -AdminUpn $siteAdminUpn -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31').Action -eq 'Verified'
} 'Graph returns owner objects, the helper must read userPrincipalName'
Assert-Throws 'Get-SeedTeamOwnershipVerdict: admin missing from group owners -> abort' -Pattern 'owner|Aborting' -Script {
    Get-SeedTeamOwnershipVerdict -GroupOwners @('ChristieC@moneyyu.com') -TeamMembers $teamMembersOwner `
        -AdminUpn $siteAdminUpn -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31'
}
Assert-Throws 'Get-SeedTeamOwnershipVerdict: admin is a member without the owner role -> abort' -Pattern 'owner|Aborting' -Script {
    Get-SeedTeamOwnershipVerdict -GroupOwners $teamOwnersOk -TeamMembers $teamMembersNoOwner `
        -AdminUpn $siteAdminUpn -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31'
}
Assert-Throws 'Get-SeedTeamOwnershipVerdict: admin absent from team membership -> abort' -Pattern 'owner|member|Aborting' -Script {
    Get-SeedTeamOwnershipVerdict -GroupOwners $teamOwnersOk `
        -TeamMembers @([pscustomobject]@{ id = 'mem-2'; email = 'ChristieC@moneyyu.com'; roles = @('owner') }) `
        -AdminUpn $siteAdminUpn -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31'
}
Assert-Throws 'Get-SeedTeamOwnershipVerdict: an empty membership collection -> abort' -Pattern 'owner|member|Aborting' -Script {
    Get-SeedTeamOwnershipVerdict -GroupOwners $teamOwnersOk -TeamMembers @() `
        -AdminUpn $siteAdminUpn -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31'
}
Assert-True 'Get-SeedTeamOwnershipVerdict: the owner role is matched case-insensitively' {
    $members = @([pscustomobject]@{ id = 'mem-1'; email = 'Admin@MoneyYu.com'; roles = @('Owner') })
    (Get-SeedTeamOwnershipVerdict -GroupOwners $teamOwnersOk -TeamMembers $members `
        -AdminUpn $siteAdminUpn -TeamKey 'PL-7008 IT Helpdesk — 2026-08-31').Action -eq 'Verified'
} 'Graph casing must not decide a tenant safety verdict'

# ═══════════════════════════════════════════════════════
Write-Section 'Static invariants: reused resources are proven, never promoted'
# ═══════════════════════════════════════════════════════
Assert-True 'Preflight proves the site group identity before Phase 1' {
    $preflightAst -and (Get-CommandNameCount -Ast $preflightAst.Ast -CommandName 'Get-SeedSiteGroupVerdict') -ge 1
} 'an alias match alone must not be reported as a safe Reuse'
Assert-True 'Preflight proves admin ownership of a reused team before Phase 1' {
    $preflightAst -and (Get-CommandNameCount -Ast $preflightAst.Ast -CommandName 'Get-SeedTeamOwnershipVerdict') -ge 1
} 'a reused team that left admin as a plain member must abort before any write'
Assert-True 'Preflight reads the group owner collection' {
    $preflightAst -and (Get-CommandNameCount -Ast $preflightAst.Ast -CommandName 'Get-SeedGroupOwnerUpns') -ge 1
} 'ownership cannot be assumed from the group object'
Assert-True 'Invoke-SeedSharePoint.ps1 repeats the identity proof before writing' {
    $spAst -and (Get-CommandNameCount -Ast $spAst.Ast -CommandName 'Get-SeedSiteGroupVerdict') -ge 1
} 'defense in depth: Phase 7 must not trust a preflight that ran minutes earlier'
Assert-True 'Invoke-SeedTeamsChannel.ps1 repeats the ownership proof before writing' {
    $teamsAst -and (Get-CommandNameCount -Ast $teamsAst.Ast -CommandName 'Get-SeedTeamOwnershipVerdict') -ge 1
} 'defense in depth: Phase 4 must re-prove admin ownership of a reused team'
Assert-True 'No engine script promotes a membership role on a reused resource' {
    $hits = @()
    foreach ($name in $ScenarioEngineScripts) {
        $path = Join-Path $EngineDir $name
        if (-not (Test-Path $path)) { continue }
        $t = Get-Content $path -Raw -Encoding UTF8
        foreach ($m in [regex]::Matches($t, '(?i)-Method\s+["'']?(PATCH|PUT)[^\r\n]*')) {
            if ($m.Value -match '(?i)/members|/owners') { $hits += "$name : $($m.Value.Trim())" }
        }
    }
    $hits.Count -eq 0
} 'shared-tenant policy is fail closed: report a wrong role, never repair it'

# ═══════════════════════════════════════════════════════
Write-Section 'Committed guidance: Graph application permissions match what the engine calls'
# ═══════════════════════════════════════════════════════
$PermissionVocabulary = '(?<![A-Za-z.])(?:User|Mail|ChannelMessage|Teamwork|TeamMember|Team|Group|GroupMember|Files|Sites|Directory)\.(?:Read|ReadWrite|Send|Migrate|Manage|FullControl)[A-Za-z.]*(?<![.])'
$ExpectedPermissions = @(
    'User.ReadWrite.All'
    'Mail.Send'
    'Mail.ReadWrite'
    'Teamwork.Migrate.All'
    'TeamMember.ReadWrite.All'
    'Group.ReadWrite.All'
    'Files.ReadWrite.All'
    'Sites.Manage.All'
    'Sites.ReadWrite.All'
    'Sites.FullControl.All'
) | Sort-Object

$PermissionDocs = [ordered]@{
    'scenario config.json.example' = Join-Path $ScenarioDir 'config.json.example'
    'scenario README.md'           = Join-Path $ScenarioDir 'README.md'
    'docs/demo-environment.md'     = Join-Path $RepoRoot 'docs\demo-environment.md'
    'docs/demo-environment.zh-TW.md' = Join-Path $RepoRoot 'docs\demo-environment.zh-TW.md'
}

function Get-DeclaredPermissions {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    $t = Get-Content $Path -Raw -Encoding UTF8
    return @([regex]::Matches($t, $PermissionVocabulary) | ForEach-Object { $_.Value } | Sort-Object -Unique)
}

foreach ($doc in $PermissionDocs.GetEnumerator()) {
    $docName = $doc.Key
    $docPath = $doc.Value
    Assert-True "$docName does not list the delegated-only ChannelMessage.Send" {
        (Get-DeclaredPermissions -Path $docPath) -notcontains 'ChannelMessage.Send'
    } 'ChannelMessage.Send has no application variant; the engine writes messages through Teamwork.Migrate.All'
    Assert-True "$docName keeps Teamwork.Migrate.All" {
        (Get-DeclaredPermissions -Path $docPath) -contains 'Teamwork.Migrate.All'
    } 'historical channel messages are written through the migration API'
    Assert-True "$docName documents TeamMember.ReadWrite.All for the team owner membership write" {
        (Get-DeclaredPermissions -Path $docPath) -contains 'TeamMember.ReadWrite.All'
    } 'POST /teams/{id}/members with roles ["owner"] needs TeamMember.ReadWrite.All (https://learn.microsoft.com/graph/api/team-post-members); the same role also covers the preflight membership read'
    Assert-True "$docName does not list the read-only TeamMember.Read.All" {
        (Get-DeclaredPermissions -Path $docPath) -notcontains 'TeamMember.Read.All'
    } 'a read-only membership role cannot satisfy the owner membership POST the engine issues; consenting it alone makes Phase 4 fail at run time'
    Assert-True "$docName declares exactly the documented application permission set" {
        $declared = @(Get-DeclaredPermissions -Path $docPath)
        (@(Compare-Object -ReferenceObject $ExpectedPermissions -DifferenceObject $declared).Count -eq 0)
    } "expected: $($ExpectedPermissions -join ', ')"
}
Assert-True 'EN and zh-TW demo-environment permission lists are fact-equivalent' {
    $en = @(Get-DeclaredPermissions -Path (Join-Path $RepoRoot 'docs\demo-environment.md'))
    $zh = @(Get-DeclaredPermissions -Path (Join-Path $RepoRoot 'docs\demo-environment.zh-TW.md'))
    ($en.Count -gt 0) -and (@(Compare-Object -ReferenceObject $en -DifferenceObject $zh).Count -eq 0)
} 'a translated permission list that drifts is a live consent failure waiting to happen'

# The permission list is derived from what the engine calls, so the write call and the documented
# role must be checked together: Phase 4 POSTs a team membership carrying roles ["owner"], and the
# application permission for that endpoint is TeamMember.ReadWrite.All, not the read-only role.
# https://learn.microsoft.com/graph/api/team-post-members
Assert-True 'Teams phase POSTs a team membership with the owner role' {
    $teamsText = Get-Content (Join-Path $EngineDir 'Invoke-SeedTeamsChannel.ps1') -Raw -Encoding UTF8
    ($teamsText -match "(?s)-Method\s+POST\s+-Uri\s+[^\r\n]*teams/\`$teamId/members") -and
    ($teamsText -match "memberRoles\s*=\s*@\('owner'\)")
} 'the owner membership write is what forces the ReadWrite membership permission'
Assert-True 'every guidance file grants the membership permission the owner POST requires' {
    $missing = @()
    foreach ($doc in $PermissionDocs.GetEnumerator()) {
        $declared = @(Get-DeclaredPermissions -Path $doc.Value)
        if ($declared -notcontains 'TeamMember.ReadWrite.All') { $missing += $doc.Key }
    }
    $missing.Count -eq 0
} 'documenting only TeamMember.Read.All would pass consent review and then fail on the owner POST'

# ═══════════════════════════════════════════════════════
Write-Section 'Committed live proof: bounded no-write claims, not absolute ones'
# ═══════════════════════════════════════════════════════
# The two authorized reruns were idempotent, not silent: the live logs show Phase 1 PATCHing every
# role profile ("-> Updated"), and the Teams phase re-issuing completeMigration plus the team-member
# POSTs. Committed evidence may therefore claim "no new resources / duplicates / list items /
# messages / files" and identical snapshots, but never "wrote nothing".
$LiveProofDocs = [ordered]@{
    'docs/demo-environment.md'       = Join-Path $RepoRoot 'docs\demo-environment.md'
    'docs/demo-environment.zh-TW.md' = Join-Path $RepoRoot 'docs\demo-environment.zh-TW.md'
    'm365-demo-data-seeding/SKILL.md' = Join-Path $RepoRoot '.github\skills\m365-demo-data-seeding\SKILL.md'
}
$AbsoluteZeroWriteClaims = 'wrote nothing|writes? nothing|write-free|no writes|zero writes|without writing anything|沒有任何寫入|完全沒有寫入|零寫入|未執行任何寫入'

function Get-LiveProofBlock {
    # The live proof is one contiguous block of non-empty lines; it is anchored on the measured
    # snapshot-leaf count, which occurs exactly once per file. The block is returned with its
    # wrapping collapsed so an assertion never depends on where a sentence happens to wrap.
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '' }
    $lines = @(Get-Content $Path -Encoding UTF8)
    $idx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '196') { $idx = $i; break }
    }
    if ($idx -lt 0) { return '' }
    $start = $idx
    while ($start -gt 0 -and $lines[$start - 1].Trim() -ne '') { $start-- }
    $end = $idx
    while ($end -lt ($lines.Count - 1) -and $lines[$end + 1].Trim() -ne '') { $end++ }
    return ((($lines[$start..$end]) -join ' ') -replace '\s+', ' ')
}

foreach ($proof in $LiveProofDocs.GetEnumerator()) {
    $proofName = $proof.Key
    $proofPath = $proof.Value
    Assert-True "$proofName live proof block is present and anchored on the measured 196 leaves" {
        $block = Get-LiveProofBlock -Path $proofPath
        ($block.Length -gt 0) -and ($block -match '196') -and ($block -match '72')
    } 'the measured snapshot-leaf count and the 72/72 verification must stay in the committed proof'
    Assert-True "$proofName live proof makes no absolute zero-write claim" {
        $block = Get-LiveProofBlock -Path $proofPath
        ($block.Length -gt 0) -and ($block -notmatch $AbsoluteZeroWriteClaims)
    } 'the logs show profile PATCH and idempotent completeMigration/member calls on every run; claiming the runs wrote nothing is false evidence'
    Assert-True "$proofName live proof names the write calls a rerun still issues" {
        $block = Get-LiveProofBlock -Path $proofPath
        ($block -match 'PATCH') -and ($block -match 'completeMigration') -and ($block -match '(?i)member')
    } 'a reader must be told which calls re-run: the profile PATCH and the idempotent completeMigration/member calls'
    Assert-True "$proofName live proof bounds the no-write claim to observable state" {
        $block = Get-LiveProofBlock -Path $proofPath
        if ($proofName -eq 'docs/demo-environment.zh-TW.md') {
            # CJK prose carries no word spacing, so compare against the space-stripped block.
            $cjk = ($block -replace '\s', '')
            ($cjk -match '沒有新增任何資源') -and ($cjk -match '沒有重複項目') -and
            ($cjk -match 'listitem') -and ($cjk -match '訊息') -and ($cjk -match '檔案')
        } else {
            ($block -match '(?i)no new\s*\**\s*resources') -and ($block -match '(?i)duplicate') -and
            ($block -match '(?i)list items') -and ($block -match '(?i)messages') -and ($block -match '(?i)files')
        }
    } 'state exactly what did not happen: no new resources, duplicates, list items, messages or files'
    Assert-True "$proofName live proof keeps the identical first-vs-second snapshot statement" {
        $block = Get-LiveProofBlock -Path $proofPath
        ($block -match '(?i)0 differences|zero\*{0,2} differences|\*{0,2}zero\*{0,2}\s*(differences|差異)|零差異')
    } 'the identical 196-leaf snapshots are what the idempotency claim rests on'
}
Assert-True 'EN and zh-TW live proofs quote the same measured numbers' {
    $en = Get-LiveProofBlock -Path (Join-Path $RepoRoot 'docs\demo-environment.md')
    $zh = Get-LiveProofBlock -Path (Join-Path $RepoRoot 'docs\demo-environment.zh-TW.md')
    $enNums = @([regex]::Matches($en, '\d+') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    $zhNums = @([regex]::Matches($zh, '\d+') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    ($enNums.Count -gt 0) -and (@(Compare-Object -ReferenceObject $enNums -DifferenceObject $zhNums).Count -eq 0)
} 'a translated evidence paragraph that drifts numerically is unverifiable'

# ═══════════════════════════════════════════════════════
Write-Section 'Scenario data: IT Tickets cover every ticket number the narrative claims'
# ═══════════════════════════════════════════════════════
$itTicketsList = $null
if ($spData) {
    $itTicketsList = @(@($spData.sites)[0].lists | Where-Object { $_.displayName -eq 'IT Tickets' })[0]
}
$itTicketTitles = @(@($itTicketsList.items) | ForEach-Object { "$($_.Title)" })

Assert-Value 'sharepoint-sites.json: IT Tickets declares 11 items' 11 { @($itTicketsList.items).Count }
Assert-True 'sharepoint-sites.json: IT Tickets runs TKT-100001..TKT-100011 with no gap or duplicate' {
    $expected = @(1..11 | ForEach-Object { 'TKT-{0:D6}' -f (100000 + $_) })
    (@(Compare-Object -ReferenceObject $expected -DifferenceObject @($itTicketTitles | Sort-Object)).Count -eq 0) -and
    (@($itTicketTitles | Sort-Object -Unique).Count -eq $itTicketTitles.Count)
} 'the regex entity TKT-\d{6} must resolve for every declared ticket'
Assert-True 'every TKT number named in emails.json exists in the IT Tickets list' {
    $raw = Get-Content $emailsJsonPath -Raw -Encoding UTF8
    $referenced = @([regex]::Matches($raw, 'TKT-\d{6}') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    ($referenced.Count -gt 0) -and (@($referenced | Where-Object { $itTicketTitles -notcontains $_ }).Count -eq 0)
} 'an email that says a ticket was created must be demonstrable in the list'
Assert-True 'every TKT number named in teams-messages.json exists in the IT Tickets list' {
    $raw = Get-Content $teamsJsonPath -Raw -Encoding UTF8
    $referenced = @([regex]::Matches($raw, 'TKT-\d{6}') | ForEach-Object { $_.Value } | Sort-Object -Unique)
    ($referenced.Count -gt 0) -and (@($referenced | Where-Object { $itTicketTitles -notcontains $_ }).Count -eq 0)
} 'channel messages quote ticket numbers the agent must be able to look up'
Assert-True 'TKT-100011 is the laptop black-screen incident from email thread 1' {
    $item = @(@($itTicketsList.items) | Where-Object { "$($_.Title)" -eq 'TKT-100011' })[0]
    ($null -ne $item) -and
    ("$($item.RequestedBy)" -eq 'Irvin Sayers') -and
    ("$($item.AssignedTo)" -eq 'Isaiah Langer') -and
    ("$($item.Urgency)" -eq 'High') -and
    ("$($item.Subject)" -match '黑屏|筆電')
} 'the ticket the email says was created must describe the same incident'
Assert-True 'sharepoint-sites.json notes state the TKT-100001 ~ TKT-100011 range' {
    $raw = Get-Content $spPath -Raw -Encoding UTF8
    $raw -match 'TKT-100001\s*~\s*TKT-100011'
} 'the data file must not advertise a range it no longer holds'
Assert-True 'scenario README states 11 IT Tickets over the full range' {
    $readme = Get-Content (Join-Path $ScenarioDir 'README.md') -Raw -Encoding UTF8
    ($readme -match '11\s*筆工單') -and ($readme -match 'TKT-100001\s*~\s*TKT-100011') -and ($readme -notmatch 'TKT-100001\s*~\s*TKT-100010')
} 'the scenario README count/range must match the data'
Assert-True 'docs/demo-environment.md states 11 IT Tickets' {
    $t = Get-Content (Join-Path $RepoRoot 'docs\demo-environment.md') -Raw -Encoding UTF8
    ($t -match 'IT Tickets \(\*\*11\*\* items\)') -and ($t -notmatch 'IT Tickets \(\*\*10\*\* items\)')
} 'the trainer guide count must match the data'
Assert-True 'docs/demo-environment.zh-TW.md states 11 IT Tickets' {
    $t = Get-Content (Join-Path $RepoRoot 'docs\demo-environment.zh-TW.md') -Raw -Encoding UTF8
    ($t -match 'IT Tickets（\*\*11\*\* 筆）') -and ($t -notmatch 'IT Tickets（\*\*10\*\* 筆）')
} 'both language guides must state the same count'

# ═══════════════════════════════════════════════════════
Write-Section 'Static invariants: preflight verifies content, mail lookups are Inbox-scoped'
# ═══════════════════════════════════════════════════════
Assert-True 'engine/Seed-GraphRead.ps1 exists (shared read-only Graph collection helpers)' {
    Test-Path $graphReadScript
} 'preflight and the Teams phase must share one inspection implementation'
Assert-True 'Seed-GraphRead.ps1 follows @odata.nextLink' {
    $graphReadText -match '@odata\.nextLink'
} 'every collection read must page'
Assert-True 'Seed-GraphRead.ps1 fetches replies per parent message' {
    $graphReadText -match '/replies'
} 'list-channel-messages never returns replies'
Assert-True 'Preflight verifies the reused team content before any write phase' {
    $preflightAst -and (Get-CommandNameCount -Ast $preflightAst.Ast -CommandName 'Get-SeedTeamContentVerdict') -ge 1
} 'preflight must check channel cardinality plus top-level AND reply hashes'
Assert-True 'Preflight inspects channel message state' {
    $preflightAst -and (Get-CommandNameCount -Ast $preflightAst.Ast -CommandName 'Get-SeedChannelMessageState') -ge 1
} 'preflight must read the tenant message/reply set, not just the group'
Assert-True 'Preflight and the Teams phase share the channel-state reader' {
    $graphReadAst -and (Get-CommandNameCount -Ast $graphReadAst.Ast -CommandName 'Get-SeedGraphCollection') -ge 2
} 'the shared reader is the single source of truth for channel/reply inspection'
Assert-True 'Teams phase completes migration for a reused team too (no isNewTeam gate)' {
    if (-not $teamsAst) { return $false }
    $tries = $teamsAst.Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.TryStatementAst] }, $true)
    $migrationTries = @($tries | Where-Object { $_.Body.Extent.Text -match 'completeMigration' })
    if ($migrationTries.Count -lt 2) { return $false }
    $gated = @($migrationTries | Where-Object {
        $p = $_.Parent
        $found = $false
        while ($p) {
            if ($p -is [System.Management.Automation.Language.IfStatementAst] -and $p.Clauses[0].Item1.Extent.Text -match 'isNewTeam') { $found = $true }
            $p = $p.Parent
        }
        $found
    })
    $gated.Count -eq 0
} 'both completeMigration levels must run for a complete reused team as well'

$mailScripts = @('Invoke-SeedEmails.ps1', 'Invoke-SeedPreflight.ps1', 'Seed-GraphRead.ps1')
Assert-True 'No mail lookup interpolates a CJK subject into an OData $filter' {
    $hits = @()
    foreach ($name in $mailScripts) {
        $path = Join-Path $EngineDir $name
        if (-not (Test-Path $path)) { continue }
        $t = Get-Content $path -Raw -Encoding UTF8
        if ($t -match '(?i)subject\s+eq') { $hits += $name }
    }
    $hits.Count -eq 0
} 'subjects must be matched manually against fetched messages'
Assert-True 'Every mailbox collection URL is Inbox-scoped' {
    $bad = @()
    foreach ($name in $mailScripts) {
        $path = Join-Path $EngineDir $name
        if (-not (Test-Path $path)) { continue }
        $t = Get-Content $path -Raw -Encoding UTF8
        foreach ($m in [regex]::Matches($t, 'https://graph\.microsoft\.com/v1\.0/users/[^"'']*')) {
            $url = $m.Value
            # Only collection reads matter here; /messages/{id}/reply targets one known message.
            if ($url -notmatch '/messages(\?|$)') { continue }
            if ($url -notmatch '(?i)mailFolders') { $bad += "$name : $url" }
        }
    }
    $bad.Count -eq 0
} 'the unscoped /messages collection includes Deleted Items and Sent Items'
Assert-True 'No script reads the Deleted Items folder' {
    $hits = @()
    foreach ($f in (Get-ChildItem -Path $EngineDir -Filter '*.ps1' -File)) {
        $t = Get-Content $f.FullName -Raw -Encoding UTF8
        if ($t -match '(?i)deleteditems|recoverableitems') { $hits += $f.Name }
    }
    $hits.Count -eq 0
} 'deleted mail must never satisfy a thread-state decision'
Assert-True 'Invoke-SeedEmails.ps1 consumes the shared Inbox thread state reader' {
    $emailAst -and (Get-CommandNameCount -Ast $emailAst.Ast -CommandName 'Get-SeedInboxThreadState') -ge 1
} 'both preflight and the email phase must use one implementation'
Assert-True 'Preflight consumes the shared Inbox reader' {
    $preflightAst -and (
        (Get-CommandNameCount -Ast $preflightAst.Ast -CommandName 'Get-SeedInboxMessages') -ge 1 -or
        (Get-CommandNameCount -Ast $preflightAst.Ast -CommandName 'Get-SeedInboxThreadState') -ge 1)
} 'preflight must count Inbox messages, not the whole mailbox'
Assert-True 'run.ps1 runs preflight before every mutating phase' {
    $pf = $runText.IndexOf('Invoke-SeedPreflight.ps1')
    if ($pf -lt 0) { return $false }
    $mutating = @('Invoke-SeedUserProfiles.ps1', 'Invoke-UploadFiles.ps1', 'Invoke-SeedEmails.ps1',
                  'Invoke-SeedTeamsChannel.ps1', 'Invoke-SeedSharePoint.ps1')
    $bad = @()
    foreach ($m in $mutating) {
        $idx = $runText.IndexOf($m)
        if ($idx -lt 0 -or $idx -lt $pf) { $bad += $m }
    }
    $bad.Count -eq 0
} 'no profile/OneDrive/email/Teams/SharePoint write may precede the preflight verification'

# ═══════════════════════════════════════════════════════
Write-Section 'Offline Graph probes: real engine scripts against a stubbed tenant'
# ═══════════════════════════════════════════════════════
$ProbeScript = Join-Path $TestsDir 'Invoke-SeedGraphProbe.ps1'
$ProbeRoot = Join-Path $TestsDir '.tmp-graphprobe'
$script:ProbeCache = @{}

function Invoke-SeedGraphProbe {
    param(
        [Parameter(Mandatory)][ValidateSet('Preflight', 'Teams', 'SharePoint', 'Upload', 'Emails')][string]$Target,
        [Parameter(Mandatory)][string]$Mode,
        [string[]]$Surfaces = @('Emails', 'Teams', 'SharePoint')
    )
    $key = "$Target/$Mode/$($Surfaces -join ',')"
    if ($script:ProbeCache.ContainsKey($key)) { return $script:ProbeCache[$key] }

    New-Item -ItemType Directory -Force -Path $ProbeRoot | Out-Null
    $configDir = if ($Mode -match '^Strict' -or $Surfaces -contains 'Files') {
        Join-Path $ProbeRoot ("$Mode-$([Guid]::NewGuid().ToString('N'))")
    } else { $ProbeRoot }
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    $probeConfig = Join-Path $configDir 'config.json.example'
    Copy-Item (Join-Path $ScenarioDir 'config.json.example') $probeConfig -Force
    # The SharePoint phase resolves filesSourceDir relative to the config, and the probe config
    # lives in a temp folder, so the DEMO-FILE path is rewritten to reach the real scenario copy.
    $probeCfg = Get-Content $probeConfig -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($Mode -match '^Strict' -or $Surfaces -contains 'Files') {
        $strictFiles = Join-Path $configDir 'DEMO-FILE'
        New-Item -ItemType Directory -Path $strictFiles | Out-Null
        Get-ChildItem (Join-Path $ScenarioDir 'DEMO-FILE') -File | Select-Object -First 2 |
            Copy-Item -Destination $strictFiles
        $probeCfg.filesSourceDir = 'DEMO-FILE'
    } else {
        $probeCfg.filesSourceDir = [System.IO.Path]::GetRelativePath($configDir, (Join-Path $ScenarioDir 'DEMO-FILE'))
    }
    $probeCfg | ConvertTo-Json -Depth 10 | Set-Content -Path $probeConfig -Encoding UTF8
    $resultPath = Join-Path $ProbeRoot "result-$Target-$Mode-$($Surfaces -join '-').json"
    if (Test-Path $resultPath) { Remove-Item $resultPath -Force }

    $pwshExe = (Get-Process -Id $PID).Path
    if (-not $pwshExe) { $pwshExe = 'pwsh' }
    $probeOut = & $pwshExe -NoProfile -NonInteractive -File $ProbeScript -Target $Target -Mode $Mode `
        -EngineDir $EngineDir -ScenarioDir $ScenarioDir -ConfigPath $probeConfig -ResultPath $resultPath `
        -Surfaces ($Surfaces -join ',') 2>&1 | Out-String
    $probeCode = $LASTEXITCODE

    $result = $null
    if (Test-Path $resultPath) {
        try { $result = Get-Content $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $result = $null }
    }
    if (-not $result) {
        $result = [pscustomobject]@{
            Target = $Target; Mode = $Mode; Threw = $true; ProbeFailed = $true
            ErrorMessage = "probe process failed (exit $probeCode): $($probeOut.Trim())"
            Requests = @(); Findings = @(); TeamsResult = $null
        }
    }
    # The child process stdout is evidence in its own right: anything the engine leaves on the
    # pipeline lands here, and in a live run it lands in the operator's log file.
    $result | Add-Member -NotePropertyName 'Stdout' -NotePropertyValue "$probeOut" -Force
    $script:ProbeCache[$key] = $result
    return $result
}

function Get-ProbeStdout {
    param($Probe)
    if (@($Probe.PSObject.Properties.Name) -contains 'Stdout') { return "$($Probe.Stdout)" }
    return ''
}

function Get-ProbeRequestCount {
    param($Probe, [string]$Method, [string]$UriPattern)
    return @(@($Probe.Requests) | Where-Object { $_.Method -eq $Method -and $_.Uri -match $UriPattern }).Count
}

function Get-ProbeFindingAction {
    param($Probe, [string]$Kind, [string]$KeyPattern)
    $f = @(@($Probe.Findings) | Where-Object { $_.Kind -eq $Kind -and $_.Key -match $KeyPattern })
    if ($f.Count -eq 0) { return '<none>' }
    return $f[0].Action
}

function Get-ProbeRequestBodies {
    param($Probe, [string]$Method, [string]$UriPattern)
    return @(@($Probe.Requests) | Where-Object { $_.Method -eq $Method -and $_.Uri -match $UriPattern } |
             ForEach-Object { "$($_.Body)" })
}

try {
    Assert-True 'probe harness: Invoke-SeedGraphProbe.ps1 is present' { Test-Path $ProbeScript } 'the offline Graph probe is required'

    Write-Section 'Cross-mailbox Outlook threading and post-send read errors'
    $crossMailbox = Invoke-SeedGraphProbe -Target Emails -Mode MailCrossMailbox
    Assert-True 'Outlook: mailbox-local conversation IDs do not prevent all replies' {
        -not $crossMailbox.Threw -and
        (Get-ProbeRequestCount $crossMailbox POST '/sendMail$') -eq 2 -and
        (Get-ProbeRequestCount $crossMailbox POST '/reply$') -eq 5
    } "got: $($crossMailbox.ErrorMessage)"
    Assert-True 'Outlook: Inbox poll selects cross-mailbox internetMessageId' {
        (Get-ProbeRequestCount $crossMailbox GET 'mailFolders/inbox/messages\?.*internetMessageId') -gt 0
    } 'the reply target must be resolved by a shared Message-ID, not a mailbox-local conversation ID'

    $temporaryRead = Invoke-SeedGraphProbe -Target Emails -Mode MailRead503
    Assert-True 'Outlook: 503 after send retries GET but never repeats mail POST' {
        -not $temporaryRead.Threw -and
        (Get-ProbeRequestCount $temporaryRead POST '/sendMail$') -eq 2 -and
        (Get-ProbeRequestCount $temporaryRead POST '/reply$') -eq 5
    } "got: $($temporaryRead.ErrorMessage)"

    $forbiddenRead = Invoke-SeedGraphProbe -Target Emails -Mode MailRead403
    Assert-True 'Outlook: 403 after send aborts without resending' {
        $forbiddenRead.Threw -and $forbiddenRead.ErrorMessage -match '403|Forbidden' -and
        (Get-ProbeRequestCount $forbiddenRead POST '/sendMail$') -eq 1 -and
        (Get-ProbeRequestCount $forbiddenRead POST '/reply$') -eq 0
    } "got: $($forbiddenRead.ErrorMessage)"

    Write-Section 'Ford engine: identity, declared surfaces and reused SharePoint access'
    $mismatchedAdmin = Invoke-SeedGraphProbe -Target Preflight -Mode MismatchedAdminRole
    Assert-True 'Preflight refuses an Admin role that differs from adminUpn' {
        $mismatchedAdmin.Threw -and $mismatchedAdmin.ErrorMessage -match 'roles.Admin.upn|adminUpn'
    } "got: $($mismatchedAdmin.ErrorMessage)"
    Assert-Value 'Preflight rejects mismatched Admin before any Graph request' 0 {
        @($mismatchedAdmin.Requests).Count
    }
    $mismatchedDemoUser = Invoke-SeedGraphProbe -Target Preflight -Mode MismatchedDemoUser
    Assert-True 'Preflight refuses a demoUserUpn that differs from adminUpn' {
        $mismatchedDemoUser.Threw -and $mismatchedDemoUser.ErrorMessage -match 'demoUserUpn|adminUpn'
    } "got: $($mismatchedDemoUser.ErrorMessage)"
    Assert-Value 'Preflight rejects mismatched demo operator before any Graph request' 0 {
        @($mismatchedDemoUser.Requests).Count
    }
    foreach ($mode in @('MissingMailSendRole', 'WrongTenantToken')) {
        $probe = Invoke-SeedGraphProbe -Target Preflight -Mode $mode
        Assert-True "Preflight ($mode): rejects inadequate app token before Graph requests" {
            $probe.Threw -and $probe.ErrorMessage -match 'permission|role|tenant'
        } "got: $($probe.ErrorMessage)"
        Assert-Value "Preflight ($mode): makes no Graph requests" 0 {
            @($probe.Requests).Count
        }
    }
    $foreignFolder = Invoke-SeedGraphProbe -Target Preflight -Mode ForeignOneDriveFolder -Surfaces @('Files')
    Assert-True 'Preflight refuses an unmarked OneDrive folder before any write' {
        $foreignFolder.Threw -and $foreignFolder.ErrorMessage -match 'local scenario receipt' -and
        (Get-ProbeRequestCount $foreignFolder GET '/drive/root:/') -eq 1
    } "got: $($foreignFolder.ErrorMessage)"
    Assert-Value 'Preflight foreign OneDrive folder sends no writes' 0 {
        @($foreignFolder.Requests | Where-Object { $_.Method -ne 'GET' }).Count
    }
    $newFolder = Invoke-SeedGraphProbe -Target Preflight -Mode NewOneDriveFolder -Surfaces @('Files')
    Assert-True 'Preflight allows a missing OneDrive target folder' {
        -not $newFolder.Threw
    } "got: $($newFolder.ErrorMessage)"
    Assert-Value 'Preflight inspects the OneDrive folder only once after validating all accounts' 1 {
        Get-ProbeRequestCount $newFolder GET '/drive/root:/'
    }
    $strictForeign = Invoke-SeedGraphProbe -Target Upload -Mode StrictForeignFolder
    Assert-True 'Strict upload refuses foreign OneDrive folder without receipt' {
        $strictForeign.Threw -and $strictForeign.ErrorMessage -match 'receipt'
    } "got: $($strictForeign.ErrorMessage)"
    Assert-Value 'Strict upload makes no writes to foreign OneDrive folder' 0 {
        @($strictForeign.Requests | Where-Object { $_.Method -ne 'GET' }).Count
    }
    $strictRerun = Invoke-SeedGraphProbe -Target Upload -Mode StrictRerun
    Assert-True 'Strict upload creates proof and rerun skips without mutating tenant' {
        -not $strictRerun.Threw -and
        (Get-ProbeRequestCount $strictRerun POST '/drive/root/children$') -eq 1 -and
        (Get-ProbeRequestCount $strictRerun POST '/createUploadSession$') -eq 3 -and
        (Get-ProbeRequestCount $strictRerun PUT '^https://stub-upload\.invalid/') -eq 3
    } "got: $($strictRerun.ErrorMessage)"
    $outsideSource = Invoke-SeedGraphProbe -Target Upload -Mode StrictOutsideSource
    Assert-True 'Strict upload rejects sources outside the scenario root' {
        $outsideSource.Threw -and $outsideSource.ErrorMessage -match 'inside the scenario'
    } "got: $($outsideSource.ErrorMessage)"
    Assert-Value 'Strict upload rejects outside sources before Graph requests' 0 {
        @($outsideSource.Requests).Count
    }
    $binaryProof = Invoke-SeedGraphProbe -Target Upload -Mode StrictProofBytes
    Assert-True 'Strict upload verifies a binary Graph proof on rerun' {
        -not $binaryProof.Threw
    } "got: $($binaryProof.ErrorMessage)"
    foreach ($mode in @('MissingRole', 'DisabledRole', 'MissingAdmin', 'DisabledAdmin')) {
        $probe = Invoke-SeedGraphProbe -Target Preflight -Mode $mode
        Assert-True "Preflight ($mode): aborts naming an unavailable account" {
            $probe.Threw -and $probe.ErrorMessage -match 'ITLead|Admin|admin@moneyyu.com' -and
            $probe.ErrorMessage -match 'missing|not found|disabled|accountEnabled'
        } "got: $($probe.ErrorMessage)"
        Assert-Value "Preflight ($mode): does not query other surfaces before role validation" 0 {
            @(@($probe.Requests) | Where-Object { $_.Uri -match '/groups|mailFolders|/teams/' }).Count
        }
        Assert-Value "Preflight ($mode): issues no write" 0 {
            @(@($probe.Requests) | Where-Object { $_.Method -ne 'GET' }).Count
        }
    }
    $onlyTeams = Invoke-SeedGraphProbe -Target Preflight -Mode 'NewTeam' -Surfaces @('Teams')
    Assert-True 'Preflight (Teams only): succeeds without email and site declarations' {
        -not $onlyTeams.Threw
    } "got: $($onlyTeams.ErrorMessage)"
    Assert-Value 'Preflight (Teams only): does not inspect SharePoint or Inbox' 0 {
        @(@($onlyTeams.Requests) | Where-Object { $_.Uri -match 'mailFolders|mailNickname%20eq' }).Count
    }
    $onlySite = Invoke-SeedGraphProbe -Target Preflight -Mode 'SharePointSeeded' -Surfaces @('SharePoint')
    Assert-True 'Preflight (SharePoint only): succeeds without teamDisplayName or email files' {
        -not $onlySite.Threw
    } "got: $($onlySite.ErrorMessage)"
    Assert-Value 'Preflight (SharePoint only): does not inspect Teams or Inbox' 0 {
        @(@($onlySite.Requests) | Where-Object { $_.Uri -match 'mailFolders|displayName%20eq|/teams/' }).Count
    }
    Assert-True 'Preflight (SharePoint only): reads direct group membership without an advanced cast' {
        (Get-ProbeRequestCount -Probe $onlySite -Method 'GET' -UriPattern '/groups/[^/]+/members(\?|$)') -ge 1
    } 'OData casts require ConsistencyLevel and $count, and can use an eventually consistent index'
    $spoof = Invoke-SeedGraphProbe -Target Preflight -Mode 'GroupMemberSpoof' -Surfaces @('SharePoint')
    Assert-True 'Preflight: a group mail cannot impersonate a missing user member' {
        $spoof.Threw -and $spoof.ErrorMessage -match 'missing declared member'
    } "got: $($spoof.ErrorMessage)"
    foreach ($mode in @('SiteMissingOwner', 'SiteMissingMember')) {
        $probe = Invoke-SeedGraphProbe -Target Preflight -Mode $mode -Surfaces @('SharePoint')
        Assert-True "Preflight ($mode): aborts before writes on missing declared access" {
            $probe.Threw -and $probe.ErrorMessage -match 'owner|member|role'
        } "got: $($probe.ErrorMessage)"
    }
    foreach ($mode in @('SharePointMissingOwner', 'SharePointMissingMember', 'SharePointMembersForbidden')) {
        $probe = Invoke-SeedGraphProbe -Target SharePoint -Mode $mode
        Assert-True "Phase 7 ($mode): aborts instead of silently granting access" {
            $probe.Threw -and $probe.ErrorMessage -match 'owner|member|permission'
        } "got: $($probe.ErrorMessage)"
        Assert-Value "Phase 7 ($mode): no write before access proof" 0 {
            @(@($probe.Requests) | Where-Object { $_.Method -ne 'GET' }).Count
        }
    }
    $libraryFresh = Invoke-SeedGraphProbe -Target SharePoint -Mode 'NamedLibraryFresh'
    Assert-True 'Phase 7 (named Products library): creates a documentLibrary list' {
        -not $libraryFresh.Threw -and
        @(@($libraryFresh.Requests) | Where-Object { $_.Method -eq 'POST' -and $_.Uri -match '/sites/[^/]+/lists$' -and $_.Body -match '"template"\s*:\s*"documentLibrary"' }).Count -eq 1
    } "got: $($libraryFresh.ErrorMessage)"
    Assert-True 'Phase 7 (named Products library): uploads into its drive' {
        @(@($libraryFresh.Requests) | Where-Object { $_.Method -eq 'PUT' -and $_.Uri -match '/drives/stub-products-drive/root:' }).Count -gt 0
    } 'named files must not land in the default site drive'
    $librarySeeded = Invoke-SeedGraphProbe -Target SharePoint -Mode 'NamedLibrarySeeded'
    Assert-True 'Phase 7 (existing Products library): reuses the named drive without writes' {
        -not $librarySeeded.Threw -and
        @(@($librarySeeded.Requests) | Where-Object { $_.Method -ne 'GET' }).Count -eq 0
    } "got: $($librarySeeded.ErrorMessage)"
    Assert-True 'Phase 7 (existing Products library): reads its own children' {
        (Get-ProbeRequestCount -Probe $librarySeeded -Method 'GET' -UriPattern '/drives/stub-products-drive/root/children') -gt 0
    } 'idempotency must check the named drive, not the default site drive'

    # --- Preflight: a complete reused team + complete Inbox threads ---
    $pfComplete = Invoke-SeedGraphProbe -Target Preflight -Mode 'TeamCompleteMailComplete'
    Assert-True 'Preflight probe (complete tenant): does not abort' {
        -not $pfComplete.Threw
    } "preflight threw: $($pfComplete.ErrorMessage)"
    Assert-True 'Preflight probe: issues only GET requests (read-only)' {
        @(@($pfComplete.Requests) | Where-Object { $_.Method -ne 'GET' }).Count -eq 0
    } 'the collision report must never write'
    Assert-True 'Preflight probe: lists the reused team channels' {
        (Get-ProbeRequestCount -Probe $pfComplete -Method 'GET' -UriPattern '/teams/[^/]+/channels($|\?)') -ge 1
    } 'channel cardinality must be inspected before any write phase'
    Assert-True 'Preflight probe: reads top-level channel messages' {
        (Get-ProbeRequestCount -Probe $pfComplete -Method 'GET' -UriPattern '/channels/[^/]+/messages') -ge 1
    } 'top-level content hashes must be verified in preflight'
    Assert-True 'Preflight probe: reads replies for every parent message' {
        (Get-ProbeRequestCount -Probe $pfComplete -Method 'GET' -UriPattern '/messages/[^/]+/replies') -ge 6
    } 'reply hashes must be verified in preflight, one fetch per parent'
    Assert-True 'Preflight probe: follows @odata.nextLink for channel messages' {
        (Get-ProbeRequestCount -Probe $pfComplete -Method 'GET' -UriPattern 'skiptoken') -ge 1
    } 'a paged channel must not look incomplete'
    Assert-True 'Preflight probe: mailbox reads are Inbox-scoped' {
        $mail = @(@($pfComplete.Requests) | Where-Object { $_.Uri -match '/users/[^/]+/(mailFolders|messages)' })
        ($mail.Count -ge 1) -and (@($mail | Where-Object { $_.Uri -notmatch '(?i)mailFolders/[^/?]*inbox' }).Count -eq 0)
    } 'the unscoped mailbox collection includes Deleted Items'
    Assert-True 'Preflight probe: no OData subject filter is sent' {
        @(@($pfComplete.Requests) | Where-Object { $_.Uri -match '(?i)subject%20eq' }).Count -eq 0
    } 'CJK subjects must be matched manually'
    Assert-Value 'Preflight probe: reused complete team is reported Reuse' 'Reuse' {
        Get-ProbeFindingAction -Probe $pfComplete -Kind 'TeamGroup' -KeyPattern 'PL-7008'
    }
    Assert-Value 'Preflight probe: complete thread 1 is reported Skip' 'Skip' {
        Get-ProbeFindingAction -Probe $pfComplete -Kind 'EmailThread' -KeyPattern '報修'
    }

    # --- Preflight: incomplete team content must abort BEFORE Phase 1 ---
    $pfMissingReply = Invoke-SeedGraphProbe -Target Preflight -Mode 'TeamMissingReply'
    Assert-True 'Preflight probe (one reply missing): aborts' {
        $pfMissingReply.Threw -and ($pfMissingReply.ErrorMessage -match 'Aborting|abort')
    } "expected an abort, got: $($pfMissingReply.ErrorMessage)"

    $pfExtra = Invoke-SeedGraphProbe -Target Preflight -Mode 'TeamExtraMessage'
    Assert-True 'Preflight probe (unexpected extra message): aborts' {
        $pfExtra.Threw
    } "expected an abort, got: $($pfExtra.ErrorMessage)"

    $pfMissingChannel = Invoke-SeedGraphProbe -Target Preflight -Mode 'TeamMissingChannel'
    Assert-True 'Preflight probe (declared channel missing): aborts' {
        $pfMissingChannel.Threw
    } "expected an abort, got: $($pfMissingChannel.ErrorMessage)"

    $pfDupChannel = Invoke-SeedGraphProbe -Target Preflight -Mode 'TeamDuplicateChannel'
    Assert-True 'Preflight probe (duplicate channel): aborts without choosing one' {
        $pfDupChannel.Threw -and ($pfDupChannel.ErrorMessage -match 'Ambiguous|ambiguous')
    } "expected an ambiguity abort, got: $($pfDupChannel.ErrorMessage)"

    # --- Preflight: mail state comes from the Inbox only ---
    $pfDeleted = Invoke-SeedGraphProbe -Target Preflight -Mode 'MailDeletedOnly'
    Assert-True 'Preflight probe (thread only in Deleted Items): does not abort' {
        -not $pfDeleted.Threw
    } "preflight threw: $($pfDeleted.ErrorMessage)"
    Assert-Value 'Preflight probe: deleted thread is reported Create, not Skip' 'Create' {
        Get-ProbeFindingAction -Probe $pfDeleted -Kind 'EmailThread' -KeyPattern '報修'
    }
    Assert-True 'Preflight probe: never queries the unscoped mailbox collection' {
        @(@($pfDeleted.Requests) | Where-Object { $_.Uri -match '/users/[^/]+/messages' }).Count -eq 0
    } 'Deleted Items must not be able to satisfy a thread-state decision'

    $pfPartial = Invoke-SeedGraphProbe -Target Preflight -Mode 'MailPartial'
    Assert-True 'Preflight probe (2 of 4 in the Inbox): aborts on the partial thread' {
        $pfPartial.Threw -and ($pfPartial.ErrorMessage -match 'Partial|partial')
    } "expected a partial-thread abort, got: $($pfPartial.ErrorMessage)"

    $pfPaged = Invoke-SeedGraphProbe -Target Preflight -Mode 'MailPaged'
    Assert-True 'Preflight probe (paged Inbox): follows @odata.nextLink' {
        (Get-ProbeRequestCount -Probe $pfPaged -Method 'GET' -UriPattern 'mailFolders/[^/?]*inbox.*skiptoken') -ge 1
    } 'a thread on page 2 must still be found'
    Assert-Value 'Preflight probe (paged Inbox): complete thread 1 is reported Skip' 'Skip' {
        Get-ProbeFindingAction -Probe $pfPaged -Kind 'EmailThread' -KeyPattern '報修'
    }
    Assert-Value 'Preflight probe (paged Inbox): complete thread 2 is reported Skip' 'Skip' {
        Get-ProbeFindingAction -Probe $pfPaged -Kind 'EmailThread' -KeyPattern '設備借用'
    }

    # --- Preflight / Teams: v1.0 channel reads blocked by a missing ChannelMessage.Read role ---
    # Live behaviour (SDD Task 4, moneyyu tenant): the seeder's documented application permission
    # set grants Group.ReadWrite.All + Teamwork.Migrate.All but no ChannelMessage.Read.*, so the
    # v1.0 list-channel-messages read answers 403 and every re-run of an existing dated team
    # aborted in Phase 0.5. The identical beta read is allowed, so the read-only verification must
    # fall back rather than treat a healthy tenant as broken.
    $pfBeta = Invoke-SeedGraphProbe -Target Preflight -Mode 'ChannelReadNeedsBeta'
    Assert-True 'Preflight probe (v1.0 channel read forbidden): does not abort' {
        -not $pfBeta.Threw
    } "preflight threw: $($pfBeta.ErrorMessage)"
    Assert-True 'Preflight probe (v1.0 channel read forbidden): falls back to the beta read' {
        (Get-ProbeRequestCount -Probe $pfBeta -Method 'GET' -UriPattern '/beta/teams/[^/]+/channels/[^/]+/messages') -ge 1
    } 'the beta channel read is the only one the granted roles allow'
    Assert-True 'Preflight probe (v1.0 channel read forbidden): stays read-only' {
        @(@($pfBeta.Requests) | Where-Object { $_.Method -ne 'GET' }).Count -eq 0
    } 'the fallback must not turn the collision report into a write'
    Assert-Value 'Preflight probe (v1.0 channel read forbidden): channel content still verifies as Skip' 'Skip' {
        Get-ProbeFindingAction -Probe $pfBeta -Kind 'TeamChannel' -KeyPattern '工單協作'
    }
    Assert-True 'Preflight probe (v1.0 channel read forbidden): probes v1.0 before beta' {
        $v1 = Get-ProbeRequestCount -Probe $pfBeta -Method 'GET' -UriPattern '/v1\.0/teams/[^/]+/channels/[^/]+/messages'
        $v1 -eq 1
    } 'v1.0 must be tried once and the resolved version reused for the rest of the run'

    $teamsBeta = Invoke-SeedGraphProbe -Target Teams -Mode 'ChannelReadNeedsBeta'
    Assert-True 'Teams probe (v1.0 channel read forbidden): run succeeds' {
        -not $teamsBeta.Threw
    } "teams phase threw: $($teamsBeta.ErrorMessage)"
    Assert-True 'Teams probe (v1.0 channel read forbidden): skips messages instead of duplicating them' {
        @(@($teamsBeta.Requests) | Where-Object { $_.Method -eq 'POST' -and $_.Uri -match '/channels/[^/]+/messages' }).Count -eq 0
    } 'a complete channel read over beta must still produce the Skip verdict'

    # --- Teams: re-posting completeMigration answers with the "finalized" wording ---
    $teamsFinalized = Invoke-SeedGraphProbe -Target Teams -Mode 'MigrationFinalizedWording'
    Assert-True 'Teams probe (already finalized wording): run succeeds' {
        -not $teamsFinalized.Threw
    } "a repeated completeMigration must be idempotent, got: $($teamsFinalized.ErrorMessage)"
    Assert-True 'Teams probe (already finalized wording): still reaches membership' {
        (Get-ProbeRequestCount -Probe $teamsFinalized -Method 'POST' -UriPattern '/teams/[^/]+/members$') -ge 1
    } 'the finalized channel must not stop the run before members are added'

    # --- Teams: a complete reused team must still complete migration at BOTH levels ---
    $teamsReuse = Invoke-SeedGraphProbe -Target Teams -Mode 'ReusedCompleteTeam'
    Assert-True 'Teams probe (complete reused team): run succeeds' {
        -not $teamsReuse.Threw
    } "teams phase threw: $($teamsReuse.ErrorMessage)"
    Assert-True 'Teams probe: channel-level completeMigration runs for a reused team' {
        (Get-ProbeRequestCount -Probe $teamsReuse -Method 'POST' -UriPattern '/channels/[^/]+/completeMigration') -ge 2
    } 'every channel, including General, must be completed before membership'
    Assert-True 'Teams probe: team-level completeMigration runs for a reused team' {
        (Get-ProbeRequestCount -Probe $teamsReuse -Method 'POST' -UriPattern '/teams/[^/]+/completeMigration') -ge 1
    } 'a team left in migration mode cannot accept members'
    Assert-True 'Teams probe: already-completed migration (ErrorDetails JSON) is treated as success' {
        -not $teamsReuse.Threw
    } 'the stub answers completeMigration with a 400 whose payload is only in ErrorDetails.Message'
    Assert-True 'Teams probe: membership is added after both migration levels' {
        $reqs = @($teamsReuse.Requests)
        $lastMigration = -1
        $firstMember = -1
        for ($i = 0; $i -lt $reqs.Count; $i++) {
            if ($reqs[$i].Method -eq 'POST' -and $reqs[$i].Uri -match 'completeMigration') { $lastMigration = $i }
            if ($firstMember -lt 0 -and $reqs[$i].Method -eq 'POST' -and $reqs[$i].Uri -match '/teams/[^/]+/members$') { $firstMember = $i }
        }
        ($lastMigration -ge 0) -and ($firstMember -gt $lastMigration)
    } 'membership must not be attempted while the team is still in migration mode'
    Assert-True 'Teams probe: existing members (ErrorDetails JSON) do not fail the run' {
        (Get-ProbeRequestCount -Probe $teamsReuse -Method 'POST' -UriPattern '/teams/[^/]+/members$') -ge 7
    } 'every declared role must be re-asserted idempotently'
    Assert-True 'Teams probe: no message is re-posted to a complete channel' {
        (Get-ProbeRequestCount -Probe $teamsReuse -Method 'POST' -UriPattern '/channels/[^/]+/messages') -eq 0
    } 'a complete channel must skip message creation'
    Assert-Value 'Teams probe: reused team reports Skip for the seeded channel' 'Skip' {
        if ($teamsReuse.TeamsResult) { @($teamsReuse.TeamsResult.Channels)[0].MessageAction } else { '<none>' }
    }

    # --- Teams: an incomplete reused team still aborts (controller ruling) ---
    $teamsIncomplete = Invoke-SeedGraphProbe -Target Teams -Mode 'ReusedIncompleteTeam'
    Assert-True 'Teams probe (incomplete reused team): aborts' {
        $teamsIncomplete.Threw -and ($teamsIncomplete.ErrorMessage -match 'Aborting|abort')
    } "expected the no-resume abort, got: $($teamsIncomplete.ErrorMessage)"
    Assert-True 'Teams probe (incomplete reused team): writes nothing' {
        @(@($teamsIncomplete.Requests) | Where-Object { $_.Method -ne 'GET' }).Count -eq 0
    } 'the abort must happen before any POST'

    # --- Teams: the create path still posts the full declared set ---
    $teamsNew = Invoke-SeedGraphProbe -Target Teams -Mode 'NewTeam'
    Assert-True 'Teams probe (new team): run succeeds' {
        -not $teamsNew.Threw
    } "teams phase threw: $($teamsNew.ErrorMessage)"
    Assert-Value 'Teams probe (new team): posts 6 top-level messages' 6 {
        Get-ProbeRequestCount -Probe $teamsNew -Method 'POST' -UriPattern '/channels/[^/]+/messages$'
    }
    Assert-Value 'Teams probe (new team): posts 9 replies' 9 {
        Get-ProbeRequestCount -Probe $teamsNew -Method 'POST' -UriPattern '/messages/[^/]+/replies$'
    }
    Assert-True 'Teams probe (new team): creates the team and the declared channel' {
        ((Get-ProbeRequestCount -Probe $teamsNew -Method 'POST' -UriPattern '/v1\.0/teams$') -eq 1) -and
        ((Get-ProbeRequestCount -Probe $teamsNew -Method 'POST' -UriPattern '/teams/[^/]+/channels$') -eq 1)
    } 'a missing team must be created in migration mode'
    Assert-True 'Teams probe (new team): completes migration after the messages' {
        $reqs = @($teamsNew.Requests)
        $lastMessage = -1
        $firstMigration = -1
        for ($i = 0; $i -lt $reqs.Count; $i++) {
            if ($reqs[$i].Method -eq 'POST' -and $reqs[$i].Uri -match '/messages') { $lastMessage = $i }
            if ($firstMigration -lt 0 -and $reqs[$i].Method -eq 'POST' -and $reqs[$i].Uri -match 'completeMigration') { $firstMigration = $i }
        }
        ($lastMessage -ge 0) -and ($firstMigration -gt $lastMessage)
    } 'historical timestamps can only be written while migration is still open'
    Assert-True 'Teams probe (new team): does not inspect channel content' {
        (Get-ProbeRequestCount -Probe $teamsNew -Method 'GET' -UriPattern '/channels/[^/]+/messages') -eq 0
    } 'a freshly created team has nothing to verify'

    # --- Teams membership payload: aadUserConversationMember.roles is a String collection ---
    # Live defect (SDD Task 4, first run): `$roles = if (...) { @("owner") } else { @() }`
    # assigns the OUTPUT of an if statement, and PowerShell unwraps a single-element array to a
    # scalar and an empty array to $null. Graph then rejected the member add with
    # "Could not cast or convert from System.String to System.Collections.Generic.IEnumerable`1
    # [System.String]". The wire payload — not the PowerShell literal — is what has to be an array.
    Assert-Value 'Teams probe (new team): posts one membership per configured role' 7 {
        Get-ProbeRequestCount -Probe $teamsNew -Method 'POST' -UriPattern '/teams/[^/]+/members$'
    }
    Assert-True 'Teams probe (new team): every member payload sends roles as a JSON array' {
        $bodies = Get-ProbeRequestBodies -Probe $teamsNew -Method 'POST' -UriPattern '/teams/[^/]+/members$'
        ($bodies.Count -eq 7) -and (@($bodies | Where-Object { $_ -notmatch '"roles"\s*:\s*\[' }).Count -eq 0)
    } 'a scalar or null roles value makes Graph reject the membership with a 400 BadRequest'
    Assert-Value 'Teams probe (new team): the owner is sent as roles ["owner"]' 1 {
        $bodies = Get-ProbeRequestBodies -Probe $teamsNew -Method 'POST' -UriPattern '/teams/[^/]+/members$'
        @($bodies | Where-Object { $_ -match '"roles"\s*:\s*\[\s*"owner"\s*\]' }).Count
    }
    Assert-Value 'Teams probe (new team): plain members are sent as an empty roles array' 6 {
        $bodies = Get-ProbeRequestBodies -Probe $teamsNew -Method 'POST' -UriPattern '/teams/[^/]+/members$'
        @($bodies | Where-Object { $_ -match '"roles"\s*:\s*\[\s*\]' }).Count
    }
    Assert-True 'Teams probe (new team): the owner payload targets the configured admin' {
        $config = Get-Content (Join-Path $ScenarioDir 'config.json.example') -Raw -Encoding UTF8 | ConvertFrom-Json
        $adminStubId = 'stub-user-' + ($config.adminUpn -replace '[^a-zA-Z0-9]', '-')
        $bodies = Get-ProbeRequestBodies -Probe $teamsNew -Method 'POST' -UriPattern '/teams/[^/]+/members$'
        $ownerBodies = @($bodies | Where-Object { $_ -match '"roles"\s*:\s*\[\s*"owner"\s*\]' })
        ($ownerBodies.Count -eq 1) -and ($ownerBodies[0] -match [regex]::Escape($adminStubId))
    } 'only the demo/admin account may be seeded as team owner'

    # --- SharePoint: first run writes everything, a second run must write no list content ---
    $declaredListCount = 0
    $declaredItemCount = 0
    $spDeclared = Get-Content (Join-Path $ScenarioDir 'sharepoint-sites.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $mfDeclared = Get-Content (Join-Path $ScenarioDir 'files-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($site in @($spDeclared.sites)) {
        foreach ($list in @($site.lists)) {
            $declaredListCount++
            $declaredItemCount += @($list.items).Count
        }
    }

    $spFresh = Invoke-SeedGraphProbe -Target SharePoint -Mode 'SharePointFresh'
    Assert-True 'SharePoint probe (empty tenant): run succeeds' {
        -not $spFresh.Threw
    } "sharepoint phase threw: $($spFresh.ErrorMessage)"
    Assert-Value 'SharePoint probe (empty tenant): creates the site group once' 1 {
        Get-ProbeRequestCount -Probe $spFresh -Method 'POST' -UriPattern '/v1\.0/groups$'
    }
    Assert-Value 'SharePoint probe (empty tenant): creates every declared list' $declaredListCount {
        Get-ProbeRequestCount -Probe $spFresh -Method 'POST' -UriPattern '/sites/[^/]+/lists$'
    }
    Assert-Value 'SharePoint probe (empty tenant): posts every declared item' $declaredItemCount {
        Get-ProbeRequestCount -Probe $spFresh -Method 'POST' -UriPattern '/sites/[^/]+/lists/[^/]+/items$'
    }
    Assert-True 'SharePoint probe (empty tenant): never deletes anything' {
        @(@($spFresh.Requests) | Where-Object { $_.Method -eq 'DELETE' }).Count -eq 0
    } 'the seeder must never delete a tenant resource'

    # This is the run-2 property the live task has to prove: a second run over an already seeded
    # site must not add a single list item. A snapshot that loses its shape on the way back from
    # the reader would match nothing and silently double every list.
    $spSeeded = Invoke-SeedGraphProbe -Target SharePoint -Mode 'SharePointSeeded'
    Assert-True 'SharePoint probe (already seeded): run succeeds' {
        -not $spSeeded.Threw
    } "sharepoint phase threw: $($spSeeded.ErrorMessage)"
    Assert-Value 'SharePoint probe (already seeded): creates no group' 0 {
        Get-ProbeRequestCount -Probe $spSeeded -Method 'POST' -UriPattern '/v1\.0/groups$'
    }
    Assert-Value 'SharePoint probe (already seeded): creates no list' 0 {
        Get-ProbeRequestCount -Probe $spSeeded -Method 'POST' -UriPattern '/sites/[^/]+/lists$'
    }
    Assert-Value 'SharePoint probe (already seeded): adds no list item' 0 {
        Get-ProbeRequestCount -Probe $spSeeded -Method 'POST' -UriPattern '/sites/[^/]+/lists/[^/]+/items$'
    }
    Assert-True 'SharePoint probe (already seeded): reuses the existing group and site' {
        @($spSeeded.SharePointResult).Count -eq 1 -and
        "$(@($spSeeded.SharePointResult)[0].GroupId)" -eq 'stub-group-0001'
    } 'an existing alias must be reused, never re-created'

    $spPaged = Invoke-SeedGraphProbe -Target SharePoint -Mode 'SharePointSeededPaged'
    Assert-True 'SharePoint probe (already seeded, paged snapshot): run succeeds' {
        -not $spPaged.Threw
    } "sharepoint phase threw: $($spPaged.ErrorMessage)"
    Assert-Value 'SharePoint probe (already seeded, paged snapshot): still adds no list item' 0 {
        Get-ProbeRequestCount -Probe $spPaged -Method 'POST' -UriPattern '/sites/[^/]+/lists/[^/]+/items$'
    }
    Assert-True 'SharePoint probe (already seeded, paged snapshot): follows @odata.nextLink' {
        (Get-ProbeRequestCount -Probe $spPaged -Method 'GET' -UriPattern '/sites/[^/]+/lists/[^/]+/items.*skiptoken') -ge 1
    } 'a truncated first page would make existing items look absent and duplicate them'

    # --- SharePoint documents: an existing exact filename must never be re-uploaded ---
    # Live defect (SDD Task 4, fix round 1): Phase 2 PUT all 5 declared documents on every run.
    # The PUT is not a no-op — SharePoint keeps a new version and re-serialises the OOXML
    # container, which is the measured 2-3 byte DOCX `size` drift between the two verified runs.
    $declaredDocCount = 0
    foreach ($site in @($spDeclared.sites)) { $declaredDocCount += @($site.documents).Count }

    Assert-Value 'SharePoint probe (empty tenant): uploads every declared document' $declaredDocCount {
        Get-ProbeRequestCount -Probe $spFresh -Method 'PUT' -UriPattern '/sites/[^/]+/drive/root:/.+:/content$'
    }
    Assert-True 'SharePoint probe (empty tenant): reads the document library before uploading' {
        (Get-ProbeRequestCount -Probe $spFresh -Method 'GET' -UriPattern '/sites/[^/]+/drive/root/children') -ge 1
    } 'the engine must know which documents are already there'
    Assert-Value 'SharePoint probe (already seeded): re-uploads no document' 0 {
        Get-ProbeRequestCount -Probe $spSeeded -Method 'PUT' -UriPattern '/sites/[^/]+/drive/root:/.+:/content$'
    }
    Assert-Value 'SharePoint probe (already seeded, paged library): re-uploads no document' 0 {
        Get-ProbeRequestCount -Probe $spPaged -Method 'PUT' -UriPattern '/sites/[^/]+/drive/root:/.+:/content$'
    }
    Assert-True 'SharePoint probe (already seeded, paged library): pages the document snapshot' {
        (Get-ProbeRequestCount -Probe $spPaged -Method 'GET' -UriPattern '/sites/[^/]+/drive/root/children.*skiptoken') -ge 1
    } 'a truncated first page would re-upload every document but the first'

    $spDocsPartial = Invoke-SeedGraphProbe -Target SharePoint -Mode 'SharePointDocsPartial'
    Assert-True 'SharePoint probe (2 of 5 documents present): run succeeds' {
        -not $spDocsPartial.Threw
    } "sharepoint phase threw: $($spDocsPartial.ErrorMessage)"
    Assert-Value 'SharePoint probe (2 of 5 documents present): uploads only the 3 missing ones' 3 {
        Get-ProbeRequestCount -Probe $spDocsPartial -Method 'PUT' -UriPattern '/sites/[^/]+/drive/root:/.+:/content$'
    }
    Assert-True 'SharePoint probe (2 of 5 documents present): uploads exactly the missing names' {
        $declaredDocNames = @()
        foreach ($site in @($spDeclared.sites)) { $declaredDocNames += @($site.documents | ForEach-Object { "$($_.sourceFilename)" }) }
        $present = @($declaredDocNames | Select-Object -First 2)
        $missing = @($declaredDocNames | Select-Object -Skip 2)
        $puts = @(@($spDocsPartial.Requests) | Where-Object { $_.Method -eq 'PUT' -and $_.Uri -match '/sites/[^/]+/drive/root:/.+:/content$' } |
                  ForEach-Object { [System.Uri]::UnescapeDataString((($_.Uri -replace '.*/drive/root:/', '') -replace ':/content$', '')) })
        (@($puts | Where-Object { $present -contains $_ }).Count -eq 0) -and
        (@($missing | Where-Object { $puts -contains $_ }).Count -eq $missing.Count)
    } 'a present document must be skipped and a missing one must still be uploaded'
    Assert-True 'SharePoint probe: the upload response never reaches stdout' {
        $out = Get-ProbeStdout -Probe $spFresh
        ($out -notmatch '(?i)downloadUrl') -and ($out -notmatch '(?i)tempauth=') -and ($out -notmatch 'STUBTEMPAUTHTOKEN')
    } 'a printed DriveItem puts a pre-authenticated download URL into the run log'

    # --- OneDrive upload phase: same exact-name skip, same stdout hygiene ---
    $declaredOneDriveNames = @(@($mfDeclared.files) | ForEach-Object { ((($_.localName -replace '\\', '/').Trim('/')) -split '/')[-1] })

    $upFresh = Invoke-SeedGraphProbe -Target Upload -Mode 'OneDriveFresh'
    Assert-True 'Upload probe (empty folder): run succeeds' {
        -not $upFresh.Threw
    } "upload phase threw: $($upFresh.ErrorMessage)"
    Assert-Value 'Upload probe (empty folder): uploads every declared file' $declaredOneDriveNames.Count {
        Get-ProbeRequestCount -Probe $upFresh -Method 'PUT' -UriPattern '/users/[^/]+/drive/root:/.+:/content$'
    }
    Assert-True 'Upload probe (empty folder): reads the folder before uploading' {
        (Get-ProbeRequestCount -Probe $upFresh -Method 'GET' -UriPattern '/users/[^/]+/drive/root:/[^:]+:/children') -ge 1
    } 'the engine must know which files are already there'
    Assert-True 'Upload probe (empty folder): never deletes anything' {
        @(@($upFresh.Requests) | Where-Object { $_.Method -eq 'DELETE' }).Count -eq 0
    } 'the seeder must never delete a tenant resource'
    Assert-True 'Upload probe (empty folder): the upload response never reaches stdout' {
        $out = Get-ProbeStdout -Probe $upFresh
        ($out -notmatch '(?i)downloadUrl') -and ($out -notmatch '(?i)tempauth=') -and ($out -notmatch 'STUBTEMPAUTHTOKEN')
    } 'a printed DriveItem puts a pre-authenticated download URL into the run log'

    $upSeeded = Invoke-SeedGraphProbe -Target Upload -Mode 'OneDriveSeeded'
    Assert-True 'Upload probe (already seeded): run succeeds' {
        -not $upSeeded.Threw
    } "upload phase threw: $($upSeeded.ErrorMessage)"
    Assert-Value 'Upload probe (already seeded): uploads nothing' 0 {
        Get-ProbeRequestCount -Probe $upSeeded -Method 'PUT' -UriPattern '/users/[^/]+/drive/root:/.+:/content$'
    }
    Assert-True 'Upload probe (already seeded): the existing folder is reused, not re-created' {
        @(@($upSeeded.Requests) | Where-Object { $_.Method -eq 'DELETE' }).Count -eq 0
    } 'an existing folder answers nameAlreadyExists and must be treated as idempotent'

    $upPaged = Invoke-SeedGraphProbe -Target Upload -Mode 'OneDriveSeededPaged'
    Assert-True 'Upload probe (already seeded, paged folder): run succeeds' {
        -not $upPaged.Threw
    } "upload phase threw: $($upPaged.ErrorMessage)"
    Assert-Value 'Upload probe (already seeded, paged folder): still uploads nothing' 0 {
        Get-ProbeRequestCount -Probe $upPaged -Method 'PUT' -UriPattern '/users/[^/]+/drive/root:/.+:/content$'
    }
    Assert-True 'Upload probe (already seeded, paged folder): follows @odata.nextLink' {
        (Get-ProbeRequestCount -Probe $upPaged -Method 'GET' -UriPattern '/users/[^/]+/drive/root:/[^:]+:/children.*skiptoken') -ge 1
    } 'a truncated first page would re-upload every file but the first'

    $upPartial = Invoke-SeedGraphProbe -Target Upload -Mode 'OneDrivePartial'
    Assert-True 'Upload probe (2 of 5 files present): run succeeds' {
        -not $upPartial.Threw
    } "upload phase threw: $($upPartial.ErrorMessage)"
    Assert-Value 'Upload probe (2 of 5 files present): uploads only the 3 missing ones' 3 {
        Get-ProbeRequestCount -Probe $upPartial -Method 'PUT' -UriPattern '/users/[^/]+/drive/root:/.+:/content$'
    }
    Assert-True 'Upload probe (2 of 5 files present): uploads exactly the missing names' {
        $present = @($declaredOneDriveNames | Select-Object -First 2)
        $missing = @($declaredOneDriveNames | Select-Object -Skip 2)
        $puts = @(@($upPartial.Requests) | Where-Object { $_.Method -eq 'PUT' -and $_.Uri -match '/users/[^/]+/drive/root:/.+:/content$' } |
                  ForEach-Object { [System.Uri]::UnescapeDataString(((($_.Uri -replace '.*/drive/root:/', '') -replace ':/content$', '') -split '/')[-1]) })
        (@($puts | Where-Object { $present -contains $_ }).Count -eq 0) -and
        (@($missing | Where-Object { $puts -contains $_ }).Count -eq $missing.Count)
    } 'a present file must be skipped and a missing one must still be uploaded'

    $upUnreadable = Invoke-SeedGraphProbe -Target Upload -Mode 'OneDriveFolderUnreadable'
    Assert-True 'Upload probe (folder children 404): run succeeds' {
        -not $upUnreadable.Threw
    } "a missing folder must mean an empty snapshot, got: $($upUnreadable.ErrorMessage)"
    Assert-Value 'Upload probe (folder children 404): uploads every declared file' $declaredOneDriveNames.Count {
        Get-ProbeRequestCount -Probe $upUnreadable -Method 'PUT' -UriPattern '/users/[^/]+/drive/root:/.+:/content$'
    }

    # --- Reused identity: an alias collision must abort before Phase 1 and before Phase 7 ---
    # A dated alias is a tenant-wide key. If it resolves to a group that is not this scenario's
    # site (different displayName, not a Unified M365 group, or without the operator admin as
    # owner), the run must stop while it is still read-only.
    $pfSiteName = Invoke-SeedGraphProbe -Target Preflight -Mode 'SiteAliasDisplayNameMismatch'
    Assert-True 'Preflight probe (alias held by a differently named group): aborts' {
        $pfSiteName.Threw
    } "expected an identity abort, got: $($pfSiteName.ErrorMessage)"
    Assert-True 'Preflight probe (alias held by a differently named group): stays read-only' {
        @(@($pfSiteName.Requests) | Where-Object { $_.Method -ne 'GET' }).Count -eq 0
    } 'the collision report must never write'

    $pfSiteType = Invoke-SeedGraphProbe -Target Preflight -Mode 'SiteAliasNotUnified'
    Assert-True 'Preflight probe (alias held by a non-Unified group): aborts' {
        $pfSiteType.Threw
    } "expected an identity abort, got: $($pfSiteType.ErrorMessage)"

    $pfSiteOwner = Invoke-SeedGraphProbe -Target Preflight -Mode 'SiteAliasNoAdminOwner'
    Assert-True 'Preflight probe (site group without the admin owner): aborts' {
        $pfSiteOwner.Threw
    } "expected an ownership abort, got: $($pfSiteOwner.ErrorMessage)"
    Assert-True 'Preflight probe: reads the site group owner collection' {
        (Get-ProbeRequestCount -Probe $pfComplete -Method 'GET' -UriPattern '/groups/[^/]+/owners') -ge 1
    } 'ownership must be proven, not assumed'

    $spSiteName = Invoke-SeedGraphProbe -Target SharePoint -Mode 'SharePointAliasDisplayNameMismatch'
    Assert-True 'SharePoint probe (alias held by a differently named group): aborts' {
        $spSiteName.Threw
    } "expected an identity abort, got: $($spSiteName.ErrorMessage)"
    Assert-True 'SharePoint probe (alias held by a differently named group): writes nothing' {
        @(@($spSiteName.Requests) | Where-Object { $_.Method -ne 'GET' }).Count -eq 0
    } 'no document, list or item may be written into an unrelated site'

    $spSiteOwner = Invoke-SeedGraphProbe -Target SharePoint -Mode 'SharePointAliasNoAdminOwner'
    Assert-True 'SharePoint probe (site group without the admin owner): aborts' {
        $spSiteOwner.Threw
    } "expected an ownership abort, got: $($spSiteOwner.ErrorMessage)"
    Assert-True 'SharePoint probe (site group without the admin owner): writes nothing' {
        @(@($spSiteOwner.Requests) | Where-Object { $_.Method -ne 'GET' }).Count -eq 0
    } 'the abort must happen before the first PUT or POST'

    # --- Reused team ownership: admin must already be owner, and is never promoted ---
    $pfTeamOwner = Invoke-SeedGraphProbe -Target Preflight -Mode 'TeamAdminNotOwner'
    Assert-True 'Preflight probe (admin is only a team member): aborts' {
        $pfTeamOwner.Threw
    } "expected an ownership abort, got: $($pfTeamOwner.ErrorMessage)"
    Assert-True 'Preflight probe: reads the team membership roles of a reused team' {
        (Get-ProbeRequestCount -Probe $pfComplete -Method 'GET' -UriPattern '/teams/[^/]+/members') -ge 1
    } 'the owner role lives on the team membership, not on the group'

    $teamsNotOwner = Invoke-SeedGraphProbe -Target Teams -Mode 'TeamAdminNotOwner'
    Assert-True 'Teams probe (admin is only a team member): aborts' {
        $teamsNotOwner.Threw
    } "expected an ownership abort, got: $($teamsNotOwner.ErrorMessage)"
    Assert-True 'Teams probe (admin is only a team member): writes nothing' {
        @(@($teamsNotOwner.Requests) | Where-Object { $_.Method -ne 'GET' }).Count -eq 0
    } 'a reused team with the wrong owner must not be migrated, promoted or written to'

    # --- An unreadable ownership proof must fail closed AND name the missing permission ---
    # An app registration consented against an older permission list can create and migrate the
    # team but cannot read GET /teams/{id}/members. Aborting is correct; aborting with a bare 403
    # would send the operator hunting for the wrong problem.
    $pfMembersForbidden = Invoke-SeedGraphProbe -Target Preflight -Mode 'TeamMembersForbidden'
    Assert-True 'Preflight probe (team membership read forbidden): aborts' {
        $pfMembersForbidden.Threw
    } "an unprovable owner role must fail closed, got: $($pfMembersForbidden.ErrorMessage)"
    Assert-True 'Preflight probe (team membership read forbidden): names TeamMember.ReadWrite.All' {
        # Graph echoes its own role list in the 403 body, so match the seeder's own guidance
        # sentence rather than the quoted payload.
        ($pfMembersForbidden.ErrorMessage -match 'TeamMember\.ReadWrite\.All application permission') -and
        ($pfMembersForbidden.ErrorMessage -notmatch 'TeamMember\.Read\.All application permission')
    } "the abort must point at the permission the documented list grants, got: $($pfMembersForbidden.ErrorMessage)"
    Assert-True 'Preflight probe (team membership read forbidden): writes nothing' {
        @(@($pfMembersForbidden.Requests) | Where-Object { $_.Method -ne 'GET' }).Count -eq 0
    } 'the collision report must never write'

    $pfOwnersForbidden = Invoke-SeedGraphProbe -Target Preflight -Mode 'TeamGroupOwnersForbidden'
    Assert-True 'Preflight probe (group owner read forbidden): aborts' {
        $pfOwnersForbidden.Threw
    } "an unprovable group owner must fail closed, got: $($pfOwnersForbidden.ErrorMessage)"
    Assert-True 'Preflight probe (group owner read forbidden): names the owner-read permission' {
        $pfOwnersForbidden.ErrorMessage -match 'Group\.ReadWrite\.All|GroupMember\.Read\.All'
    } "the abort must name the permission the read needs, got: $($pfOwnersForbidden.ErrorMessage)"

    $pfExtraChannel = Invoke-SeedGraphProbe -Target Preflight -Mode 'TeamExtraChannel'
    Assert-True 'Preflight probe (undeclared extra channel): aborts' {
        $pfExtraChannel.Threw
    } "expected a channel-cardinality abort, got: $($pfExtraChannel.ErrorMessage)"

    $teamsExtraChannel = Invoke-SeedGraphProbe -Target Teams -Mode 'TeamExtraChannel'
    Assert-True 'Teams probe (undeclared extra channel): aborts before migration and membership' {
        $teamsExtraChannel.Threw -and
        (@(@($teamsExtraChannel.Requests) | Where-Object { $_.Method -ne 'GET' }).Count -eq 0)
    } "expected an abort with no write, got: $($teamsExtraChannel.ErrorMessage)"
} finally {
    if (Test-Path $ProbeRoot) { Remove-Item $ProbeRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

# ═══════════════════════════════════════════════════════
Write-Section 'Every .ps1 parses'
# ═══════════════════════════════════════════════════════
$allScripts = @()
$allScripts += Get-ChildItem -Path $EngineDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue
$allScripts += Get-ChildItem -Path $TestsDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue
$allScripts += Get-ChildItem -Path $ScenarioDir -Filter '*.ps1' -File -ErrorAction SilentlyContinue
foreach ($f in $allScripts) {
    $parsed = Get-ScriptAst $f.FullName
    if ($parsed.Errors -and $parsed.Errors.Count -gt 0) {
        Fail "AST parse: $($f.Name)" ($parsed.Errors[0].Message)
    } else {
        Pass "AST parse: $($f.Name)"
    }
}

# ═══════════════════════════════════════════════════════
Write-Section 'Committed live proof: the quoted offline suite size is the measured one'
# ═══════════════════════════════════════════════════════
# Runs last on purpose: the documented count can only be compared once every other assertion has
# executed. The three assertions below are part of the total they check, so they are added up front
# — the number quoted in the guidance is then exactly what a reader gets from
# `pwsh -NoProfile -File seed-data\tests\Test-SeedEngine.ps1`.
if ($SeedRoot -eq (Join-Path $RepoRoot 'seed-data')) {
    $ExpectedSuiteSize = $script:Passed + $script:Failed + $LiveProofDocs.Count
    foreach ($proof in $LiveProofDocs.GetEnumerator()) {
        Assert-True "$($proof.Key) quotes the measured offline suite size ($ExpectedSuiteSize)" {
            $block = Get-LiveProofBlock -Path $proof.Value
            $block -match "$ExpectedSuiteSize\s*\**\s*/\s*\**\s*$ExpectedSuiteSize"
        } "a stale offline test count is unverifiable evidence; expected $ExpectedSuiteSize/$ExpectedSuiteSize"
    }
} else {
    Write-Host '  Reference live-proof count is not asserted for a different engine.' -ForegroundColor Gray
}

# ═══════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════
Write-Host ""
Write-Host "════════════════════════════════════════════" -ForegroundColor White
Write-Host "  Passed: $script:Passed" -ForegroundColor Green
if ($script:Failed -gt 0) {
    Write-Host "  Failed: $script:Failed" -ForegroundColor Red
    foreach ($n in $script:FailedNames) { Write-Host "    - $n" -ForegroundColor Red }
} else {
    Write-Host "  Failed: 0" -ForegroundColor Green
}
Write-Host "════════════════════════════════════════════" -ForegroundColor White

if ($script:Failed -gt 0) { exit 1 }
exit 0
