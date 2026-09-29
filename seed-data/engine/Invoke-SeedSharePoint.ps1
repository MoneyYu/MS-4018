<#
.SYNOPSIS
    Provision SharePoint sites (M365 Groups) and seed documents + lists + items
    via Microsoft Graph (Application Permissions). Fully idempotent.

.DESCRIPTION
    Workflow:
      Phase 1 — For each site config:
                GET /groups?$filter=mailNickname eq 'X' (idempotent).
                If exists → the group must PROVE it is this scenario's site (exact alias, exact
                       displayName, Unified M365 group, admin among the owners) before it is
                       reused; any mismatch aborts before a single write.
                Else → POST /groups (with owners + members), then poll
                       /groups/{id}/sites/root for up to 180 sec.
      Phase 2 — For each document, copy from DEMO-FILE/{sourceFilename}
                and PUT to /sites/{siteId}/drive/root:/{filename}:/content.
                A document whose EXACT filename is already in the library is skipped:
                a re-PUT keeps a new version and re-serialises Office containers, so the
                stored file would change on every run. Missing documents are still uploaded.
                A site's optional documentLibrary selects (or creates) a named library;
                otherwise the existing default site drive is used.
      Phase 3 — For each list:
                Try GET /sites/{siteId}/lists/{listName} (idempotent).
                If not exists → POST with columns.
                Snapshot the list's existing item Titles once (paged), then POST
                only the declared items whose Title is not already present.

    All operations use App permissions; required scopes:
      - Group.ReadWrite.All        (already granted)
      - Files.ReadWrite.All        (already granted)
      - Sites.Manage.All           (NEW — required for list/columns)
      - Sites.ReadWrite.All        (NEW — required for list items + drive upload)

    Person/User columns are intentionally avoided (Text storing displayName
    instead) — simplifies idempotency without lookupId resolution.

.PARAMETER ConfigPath
    Path to scenario config.json.

.PARAMETER SharePointPath
    Path to sharepoint-sites.json data file.

.NOTES
    If you see HTTP 401/403 on first run, missing permissions are likely:
      - Sites.Manage.All
      - Sites.ReadWrite.All
    Add them to the App registration consent, then re-run.
#>
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$SharePointPath
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\Seed-Idempotency.ps1"
. "$PSScriptRoot\Seed-GraphRead.ps1"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$spData = Get-Content $SharePointPath -Raw -Encoding UTF8 | ConvertFrom-Json

$adminUpn = $config.adminUpn
if (-not $adminUpn) { throw "config.json is missing 'adminUpn' - a reused site group must be provably owned by the demo operator." }

# Build role→user info lookup
$roleMap = @{}
foreach ($prop in $config.roles.PSObject.Properties) {
    $roleMap[$prop.Name] = $prop.Value
}

# Resolve DEMO-FILE source dir
$configDir = Split-Path $ConfigPath -Parent
$sourceDir = Join-Path $configDir $config.filesSourceDir | Resolve-Path

# ───────────────────────────────────────────────────────
# Helpers
# ───────────────────────────────────────────────────────

function Invoke-Graph {
    param(
        [string]$Method,
        [string]$Uri,
        [object]$Body,
        [byte[]]$RawBody,
        [string]$ContentType
    )
    $headers = @{ Authorization = "Bearer $($global:AccessToken)" }
    if ($RawBody) {
        $headers["Content-Type"] = if ($ContentType) { $ContentType } else { "application/octet-stream" }
    } else {
        $headers["Content-Type"] = if ($ContentType) { $ContentType } else { "application/json" }
    }

    $params = @{ Method = $Method; Uri = $Uri; Headers = $headers }
    if ($Body) {
        $jsonBody = $Body | ConvertTo-Json -Depth 20 -Compress
        $params.Body = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
    }
    if ($RawBody) {
        $params.Body = $RawBody
    }
    return Invoke-RestMethod @params
}

function Get-UserId {
    param([Parameter(Mandatory)][string]$Upn)
    $u = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$Upn"
    return $u.id
}

# Resolve a list of role names to Graph user @odata.bind URIs
function Resolve-RolesToBindUris {
    param([Parameter(Mandatory)][string[]]$Roles)
    $uris = @()
    foreach ($r in $Roles) {
        if (-not $roleMap.ContainsKey($r)) {
            throw "Role '$r' referenced by sharepoint-sites.json is not defined in config.json roles."
        }
        $upn = $roleMap[$r].upn
        $uid = Get-UserId -Upn $upn
        $uris += "https://graph.microsoft.com/v1.0/users/$uid"
    }
    return $uris
}

# Get-or-create an M365 Group keyed by mailNickname, returns group object.
# Idempotent — re-running reuses existing group.
function Get-OrCreate-M365Group {
    param(
        [Parameter(Mandatory)][string]$MailNickname,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$Description,
        [string[]]$OwnerRoles = @(),
        [string[]]$MemberRoles = @()
    )

    # 1. Idempotent lookup keyed on the exact mailNickname (never a wildcard). An alias match is
    #    NOT identity: a mailNickname is a tenant-wide key an unrelated group can already hold,
    #    so the resolved group must also prove the exact displayName, Unified (Microsoft 365)
    #    group characteristics and the demo operator admin among its owners before a single
    #    document or list item is written into its site. Preflight ran the same proof; this is
    #    the defense-in-depth repeat immediately before the write window.
    $filter = "mailNickname%20eq%20%27" + (ConvertTo-SeedODataLiteral -Value $MailNickname) + "%27"
    $r = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName,mailNickname,groupTypes"
    $matchedGroups = @($r.value)
    $verdict = Get-SeedSiteGroupVerdict -ExistingGroups $matchedGroups `
                                        -Alias $MailNickname `
                                        -DisplayName $DisplayName `
                                        -AdminUpn $adminUpn `
                                        -OwnerProvider { param($Group) Get-SeedGroupOwnerUpns -GroupId $Group.id }

    if ($verdict.Action -eq 'Reuse') {
        $existing = $matchedGroups[0]
        Assert-SeedSiteGroupRoles -GroupId $verdict.GroupId -Alias $MailNickname `
            -OwnerRoles $OwnerRoles -MemberRoles $MemberRoles `
            -RoleMap $roleMap -OwnerUpns $verdict.OwnerUpns
        Write-Host "    EXISTS: $DisplayName ($($verdict.GroupId)) — identity and admin ownership verified, reusing" -ForegroundColor Yellow
        Write-Host "      owners: $(@($verdict.OwnerUpns) -join ', ')" -ForegroundColor DarkGray
        return $existing
    }

    # 2. Build owners / members @odata.bind arrays
    $ownerUris  = Resolve-RolesToBindUris -Roles $OwnerRoles
    $memberUris = Resolve-RolesToBindUris -Roles $MemberRoles

    if ($ownerUris.Count -eq 0) {
        throw "Cannot create group '$DisplayName' without at least one owner. App-only POST without owner = anonymous group + no SharePoint provisioning."
    }

    $body = @{
        displayName     = $DisplayName
        description     = $Description
        groupTypes      = @("Unified")
        mailEnabled     = $true
        mailNickname    = $MailNickname
        securityEnabled = $false
        visibility      = "Private"
        "owners@odata.bind"  = @($ownerUris)
    }
    if ($memberUris.Count -gt 0) {
        $body["members@odata.bind"] = @($memberUris)
    }

    Write-Host "    CREATE: $DisplayName" -ForegroundColor White
    $created = Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/groups" -Body $body
    return $created
}

function Get-OrCreate-SeedDocumentLibraryDrive {
    param(
        [Parameter(Mandatory)][string]$SiteId,
        [Parameter(Mandatory)][string]$LibraryName
    )

    $uri = "https://graph.microsoft.com/v1.0/sites/$SiteId/drives"
    $drives = Get-SeedGraphCollection -Uri $uri
    $matches = @($drives | Where-Object { $_.name -eq $LibraryName })
    if ($matches.Count -gt 1) { throw "Ambiguous document library '$LibraryName' on site $SiteId." }
    if ($matches.Count -eq 1) {
        if (-not $matches[0].id) { throw "Document library '$LibraryName' on site $SiteId has no drive ID." }
        return "$($matches[0].id)"
    }

    Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/lists" `
        -Body @{ displayName = $LibraryName; list = @{ template = 'documentLibrary' } } | Out-Null
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
        Start-Sleep -Seconds 5
        $drives = Get-SeedGraphCollection -Uri $uri
        $matches = @($drives | Where-Object { $_.name -eq $LibraryName })
        if ($matches.Count -gt 1) { throw "Ambiguous document library '$LibraryName' on site $SiteId." }
        if ($matches.Count -eq 1 -and $matches[0].id) { return "$($matches[0].id)" }
    }
    throw "Document library '$LibraryName' was not available on site $SiteId after creation."
}

# Wait until SharePoint site is provisioned for the group, return site object.
function Wait-ForSiteProvisioning {
    param(
        [Parameter(Mandatory)][string]$GroupId,
        [int]$MaxSeconds = 180,
        [int]$IntervalSec = 5
    )
    $elapsed = 0
    while ($elapsed -lt $MaxSeconds) {
        try {
            $site = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId/sites/root"
            if ($site.id) {
                return $site
            }
        } catch {
            # 404 — site not provisioned yet
        }
        Start-Sleep -Seconds $IntervalSec
        $elapsed += $IntervalSec
    }
    throw "Site provisioning timeout for group $GroupId (waited $MaxSeconds sec)."
}

# Upload a single file from DEMO-FILE/{sourceFilename} to site drive root.
# Returns $true when the document was uploaded, $false when an identically named document was
# already in the library. The Graph answer is discarded: a DriveItem carries
# @microsoft.graph.downloadUrl, a pre-authenticated capability URL that must never be printed.
function Upload-SiteDocument {
    param(
        [Parameter(Mandatory)][string]$SiteId,
        [Parameter(Mandatory)][string]$SourceFilename,
        [string]$DriveId,
        [Parameter()][AllowNull()][AllowEmptyCollection()][string[]]$ExistingNames
    )
    $localPath = Join-Path $sourceDir $SourceFilename
    if (-not (Test-Path $localPath)) {
        throw "Declared site document is missing: $localPath (sharepoint-sites.json sourceFilename '$SourceFilename')."
    }

    if (Test-SeedDriveFileExists -ExistingNames $ExistingNames -Name $SourceFilename) {
        Write-Host "      SKIP: $SourceFilename — already in the document library (not re-uploaded)" -ForegroundColor DarkGray
        return $false
    }

    $fileBytes = [System.IO.File]::ReadAllBytes($localPath)
    $encodedName = [System.Uri]::EscapeDataString($SourceFilename)
    $uri = if ($DriveId) {
        "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/$encodedName`:/content"
    } else {
        "https://graph.microsoft.com/v1.0/sites/$SiteId/drive/root:/$encodedName`:/content"
    }

    try {
        Invoke-Graph -Method PUT -Uri $uri -RawBody $fileBytes -ContentType "application/octet-stream" | Out-Null
        Write-Host "      OK: $SourceFilename" -ForegroundColor Green
        return $true
    } catch {
        throw "Failed to upload '$SourceFilename' to site $SiteId : $(Get-SeedGraphErrorText -ErrorObject $_)"
    }
}

# Translate a column definition to Graph Lists column schema.
function ConvertTo-ColumnSchema {
    param([Parameter(Mandatory)]$Col)
    $base = @{ name = $Col.name }
    if ($Col.displayName) { $base.displayName = $Col.displayName }

    switch ($Col.type) {
        "Text"     { $base.text     = @{} }
        "Note"     { $base.text     = @{ allowMultipleLines = $true; appendChangesToExistingText = $false; linesForEditing = 6 } }
        "Number"   { $base.number   = @{} }
        "DateTime" { $base.dateTime = @{ format = "dateOnly" } }
        "Choice"   { $base.choice   = @{ choices = @($Col.choices); displayAs = "dropDownMenu" } }
        default    { throw "Unknown column type: $($Col.type)" }
    }
    return $base
}

# Get-or-create a list. Idempotent on displayName within site.
function Get-OrCreate-List {
    param(
        [Parameter(Mandatory)][string]$SiteId,
        [Parameter(Mandatory)]$ListConfig
    )

    $listName = $ListConfig.displayName

    # 1. Idempotent lookup — list all and match the exact displayName
    $lists = Invoke-Graph -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/lists"
    $matchedLists = @($lists.value | Where-Object { $_.displayName -eq $listName })
    $action = Get-SeedResourceAction -Existing $matchedLists -ResourceKind 'list' -ResourceKey $listName
    if ($action -eq 'Reuse') {
        Write-Host "      EXISTS list: $listName ($($matchedLists[0].id)) — reusing" -ForegroundColor Yellow
        return $matchedLists[0]
    }

    # 2. Build column schemas (skip 'Title' — comes by default; we just rename if needed)
    $columns = @()
    $titleDisplayName = $null
    foreach ($col in $ListConfig.columns) {
        if ($col.name -eq "Title") {
            $titleDisplayName = $col.displayName
            continue
        }
        $columns += ConvertTo-ColumnSchema -Col $col
    }

    # 3. Create the list
    $body = @{
        displayName = $listName
        list        = @{ template = "genericList" }
        columns     = $columns
    }

    Write-Host "      CREATE list: $listName ($($columns.Count) custom columns)" -ForegroundColor White
    $created = Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/lists" -Body $body

    # 4. If Title displayName needs renaming (e.g. 法規編號 instead of Title)
    if ($titleDisplayName) {
        $titleColUri = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$($created.id)/columns/Title"
        Invoke-Graph -Method PATCH -Uri $titleColUri -Body @{ displayName = $titleDisplayName } | Out-Null
    }

    return $created
}

# Add a list item if no item with same Title exists.
function Add-ListItemIfNotExists {
    param(
        [Parameter(Mandatory)][string]$SiteId,
        [Parameter(Mandatory)][string]$ListId,
        [Parameter(Mandatory)]$Fields,
        [Parameter()][AllowNull()][AllowEmptyCollection()][string[]]$ExistingTitles
    )

    if (-not $Fields.Title) {
        throw "List item must have a 'Title' field for idempotency."
    }

    if (Test-SeedListItemExists -ExistingTitles $ExistingTitles -Title $Fields.Title) {
        Write-Host "        SKIP (Title='$($Fields.Title)' exists)" -ForegroundColor DarkGray
        return $false
    }

    $body = @{ fields = $Fields }
    try {
        Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$ListId/items" -Body $body | Out-Null
        Write-Host "        ADD: $($Fields.Title)" -ForegroundColor Green
        return $true
    } catch {
        throw "Failed to add list item '$($Fields.Title)' to list $ListId on site $SiteId : $(Get-SeedGraphErrorText -ErrorObject $_)"
    }
}

# Snapshot every existing Title in a list, following @odata.nextLink. Read-only.
#
# Title is not indexed on a freshly created Graph list, so an OData filter on that column is
# refused with 400 invalidRequest; the snapshot is fetched once per list and matched in memory,
# the same way CJK email subjects are matched in engine/Seed-Idempotency.ps1.
function Get-SeedListItemTitles {
    param(
        [Parameter(Mandatory)][string]$SiteId,
        [Parameter(Mandatory)][string]$ListId
    )

    $uri = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$ListId/items?`$expand=fields(`$select=Title)&`$top=200"
    $items = Get-SeedGraphCollection -Uri $uri
    $titles = @()
    foreach ($item in @($items)) {
        if ($item.fields -and $item.fields.PSObject.Properties.Name -contains 'Title' -and $null -ne $item.fields.Title) {
            $titles += "$($item.fields.Title)"
        }
    }
    return , @($titles)
}

# ───────────────────────────────────────────────────────
# Main loop
# ───────────────────────────────────────────────────────

Write-Host "`n===== Seeding SharePoint Sites =====" -ForegroundColor Cyan
Write-Host "  Source dir: $sourceDir" -ForegroundColor Gray
Write-Host "  Sites: $($spData.sites.Count)" -ForegroundColor Gray

$global:SeedSharePointResults = @()

foreach ($site in $spData.sites) {
    Write-Host "`n  ─── Site: $($site.displayName) ($($site.alias)) ───" -ForegroundColor Magenta

    # Phase 1: ensure group + site exist
    $group = Get-OrCreate-M365Group `
        -MailNickname $site.alias `
        -DisplayName  $site.displayName `
        -Description  $site.description `
        -OwnerRoles   $site.owners `
        -MemberRoles  $site.members

    Write-Host "    Resolving site for group $($group.id)..." -ForegroundColor White
    $siteObj = Wait-ForSiteProvisioning -GroupId $group.id -MaxSeconds 180 -IntervalSec 5
    Write-Host "    SiteId: $($siteObj.id)" -ForegroundColor Gray
    $siteId = $siteObj.id
    $global:SeedSharePointResults += [pscustomobject]@{
        Alias   = $site.alias
        GroupId = $group.id
        SiteId  = $siteId
    }

    # Phase 2: upload documents
    $driveId = $null
    if ($site.documentLibrary) {
        $driveId = Get-OrCreate-SeedDocumentLibraryDrive -SiteId $siteId -LibraryName $site.documentLibrary
    }
    if ($site.documents -and $site.documents.Count -gt 0) {
        Write-Host "    Uploading $($site.documents.Count) documents..." -ForegroundColor White
        $driveRoot = if ($driveId) { "https://graph.microsoft.com/v1.0/drives/$driveId" } else { "https://graph.microsoft.com/v1.0/sites/$siteId/drive" }
        $existingDocNames = Get-SeedDriveChildNames -ChildrenUri "$driveRoot/root/children?`$select=id,name&`$top=200"
        Write-Host "      Existing documents: $(@($existingDocNames).Count)" -ForegroundColor DarkGray
        $okDocs = 0
        $skippedDocs = 0
        foreach ($doc in $site.documents) {
            $uploaded = Upload-SiteDocument -SiteId $siteId -SourceFilename $doc.sourceFilename -DriveId $driveId -ExistingNames $existingDocNames
            if ($uploaded) {
                $okDocs++
                # Keep the snapshot authoritative for the rest of this site.
                $existingDocNames = @($existingDocNames) + @("$($doc.sourceFilename)")
            } else {
                $skippedDocs++
            }
        }
        Write-Host "    Documents: $okDocs uploaded / $skippedDocs already present (any failure aborts the run)" -ForegroundColor Gray
    }

    # Phase 3: lists + items
    if ($site.lists -and $site.lists.Count -gt 0) {
        Write-Host "    Creating $($site.lists.Count) lists..." -ForegroundColor White
        foreach ($lst in $site.lists) {
            $listObj = Get-OrCreate-List -SiteId $siteId -ListConfig $lst
            $listId = $listObj.id

            if ($lst.items -and $lst.items.Count -gt 0) {
                Write-Host "      Adding $($lst.items.Count) items to '$($lst.displayName)'..." -ForegroundColor White
                $existingTitles = Get-SeedListItemTitles -SiteId $siteId -ListId $listId
                Write-Host "      Existing items: $($existingTitles.Count)" -ForegroundColor DarkGray
                $added = 0
                $skipped = 0
                foreach ($item in $lst.items) {
                    # Convert PSCustomObject to hashtable so ConvertTo-Json -Depth handles fields
                    $h = @{}
                    foreach ($p in $item.PSObject.Properties) { $h[$p.Name] = $p.Value }

                    $r = Add-ListItemIfNotExists -SiteId $siteId -ListId $listId -Fields $h -ExistingTitles $existingTitles
                    if ($r) {
                        $added++
                        # Keep the snapshot authoritative for the rest of this list.
                        $existingTitles += "$($h.Title)"
                    } else {
                        $skipped++
                    }
                    Start-Sleep -Milliseconds 300
                }
                Write-Host "      Items: $added added / $skipped skipped" -ForegroundColor Gray
            }
        }
    }
}

Write-Host "`n===== SharePoint Seed Complete =====" -ForegroundColor Cyan
foreach ($s in $global:SeedSharePointResults) {
    Write-Host "  $($s.Alias) -> groupId $($s.GroupId) | siteId $($s.SiteId)" -ForegroundColor Green
}
