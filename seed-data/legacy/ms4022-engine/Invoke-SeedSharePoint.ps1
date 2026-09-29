param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$SharePointPath
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "SharePointSeedHelpers.psm1") -Force

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$seedData = Get-Content $SharePointPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceDir = (Join-Path (Split-Path $ConfigPath -Parent) $config.filesSourceDir | Resolve-Path).Path
$roleMap = @{}
foreach ($role in $config.roles.PSObject.Properties) {
    $roleMap[$role.Name] = $role.Value
}

function Invoke-SeedGraphRequest {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [object]$Body,
        [byte[]]$RawBody,
        [string]$ContentType = "application/json"
    )

    $headers = @{ Authorization = "Bearer $global:AccessToken"; "Content-Type" = $ContentType }
    $request = @{ Method = $Method; Uri = $Uri; Headers = $headers }
    if ($PSBoundParameters.ContainsKey("Body")) {
        $request.Body = $Body | ConvertTo-Json -Depth 20 -Compress
    }
    if ($PSBoundParameters.ContainsKey("RawBody")) {
        $request.Body = $RawBody
    }
    Invoke-RestMethod @request
}

function Resolve-RoleUris {
    param([string[]]$Roles)

    $uris = @()
    foreach ($role in $Roles) {
        if (-not $roleMap.ContainsKey($role)) {
            throw "Role '$role' is not defined in $ConfigPath."
        }
        $upn = $roleMap[$role].upn
        $encodedUpn = [System.Uri]::EscapeDataString($upn)
        $user = Invoke-SeedGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$encodedUpn"
        $uris += "https://graph.microsoft.com/v1.0/users/$($user.id)"
    }
    return $uris
}

function Ensure-GroupRelationship {
    param(
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][ValidateSet("owners", "members")][string]$Relationship,
        [string[]]$DesiredUris
    )

    if (-not $DesiredUris) {
        return
    }

    $getPage = { param($uri) Invoke-SeedGraphRequest -Method GET -Uri $uri }
    $existingObjects = Get-PagedGraphValues -InitialUri (Get-GroupRelationshipUri -GroupId $GroupId -Relationship $Relationship) -GetPage $getPage

    $missingUris = Get-MissingDirectoryObjectUris -DesiredUris $DesiredUris -ExistingDirectoryObjects $existingObjects
    foreach ($uri in $missingUris) {
        Invoke-SeedGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId/$Relationship/`$ref" -Body @{ "@odata.id" = $uri } | Out-Null
        Write-Host "Added group $Relationship relationship: $uri" -ForegroundColor Cyan
    }
}

function Get-OrCreate-Group {
    param([Parameter(Mandatory)]$Site)

    $owners = Resolve-RoleUris -Roles @($Site.owners)
    if ($owners.Count -eq 0) {
        throw "The group '$($Site.displayName)' needs at least one owner."
    }
    $members = if ($Site.members) { @(Resolve-RoleUris -Roles @($Site.members)) } else { @() }

    $getGroup = {
        param($alias)
        $filter = [System.Uri]::EscapeDataString("mailNickname eq '$alias'")
        Invoke-SeedGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups?`$filter=$filter"
    }
    $existing = & $getGroup $Site.alias
    $existingGroup = @($existing.value) | Select-Object -First 1
    if ($existingGroup) {
        Assert-ExpectedDemoGroup -Group $existingGroup -Alias $Site.alias
        Ensure-GroupRelationship -GroupId $existingGroup.id -Relationship owners -DesiredUris $owners
        Ensure-GroupRelationship -GroupId $existingGroup.id -Relationship members -DesiredUris $members
        Write-Host "Reusing group: $($Site.alias)" -ForegroundColor Yellow
        return $existingGroup
    }

    $body = New-GroupCreatePayload -Site $Site -OwnerUris $owners -MemberUris $members
    Write-Host "Creating group: $($Site.alias)" -ForegroundColor Cyan
    try {
        return Invoke-SeedGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/groups" -Body $body
    } catch {
        $creationFailure = $_
        try {
            $existingGroup = Get-ExistingGroupWithRetry -Alias $Site.alias -GetGroup $getGroup
        } catch {
            throw $creationFailure
        }
        if (-not $existingGroup) {
            throw $creationFailure
        }

        Assert-ExpectedDemoGroup -Group $existingGroup -Alias $Site.alias
        Ensure-GroupRelationship -GroupId $existingGroup.id -Relationship owners -DesiredUris $owners
        Ensure-GroupRelationship -GroupId $existingGroup.id -Relationship members -DesiredUris $members
        Write-Host "Reusing group after replication delay: $($Site.alias)" -ForegroundColor Yellow
        return $existingGroup
    }
}

function Wait-ForSite {
    param([Parameter(Mandatory)][string]$GroupId)

    for ($attempt = 1; $attempt -le 36; $attempt++) {
        try {
            $site = Invoke-SeedGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$GroupId/sites/root"
            if ($site.id) {
                return $site
            }
        } catch {
            if ($attempt -eq 36) {
                throw
            }
        }
        Start-Sleep -Seconds 5
    }
    throw "Timed out while provisioning the SharePoint site for group $GroupId."
}

function Get-OrCreate-DocumentLibraryDrive {
    param(
        [Parameter(Mandatory)][string]$SiteId,
        [Parameter(Mandatory)][string]$LibraryName
    )

    $drives = Invoke-SeedGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/drives"
    $existing = $drives.value | Where-Object { $_.name -eq $LibraryName } | Select-Object -First 1
    if ($existing) {
        return $existing.id
    }

    Write-Host "Creating document library: $LibraryName" -ForegroundColor Cyan
    $payload = New-DocumentLibraryPayload -LibraryName $LibraryName
    Invoke-SeedGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/lists" -Body $payload | Out-Null

    for ($attempt = 1; $attempt -le 12; $attempt++) {
        Start-Sleep -Seconds 5
        $drives = Invoke-SeedGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/drives"
        $created = $drives.value | Where-Object { $_.name -eq $LibraryName } | Select-Object -First 1
        if ($created) {
            return $created.id
        }
    }
    throw "Document library '$LibraryName' was not available after creation."
}

function Upload-Document {
    param(
        [Parameter(Mandatory)][string]$SiteId,
        [string]$DriveId,
        [Parameter(Mandatory)]$Document
    )

    $sourcePath = Join-Path $sourceDir $Document.sourceFilename
    if (-not (Test-Path $sourcePath)) {
        throw "Source file not found: $sourcePath"
    }
    $targetFilename = if ($Document.targetFilename) { $Document.targetFilename } else { Split-Path $Document.sourceFilename -Leaf }
    $uri = Get-DocumentUploadUri -SiteId $SiteId -DriveId $DriveId -Filename $targetFilename
    Invoke-SeedGraphRequest -Method PUT -Uri $uri -RawBody ([System.IO.File]::ReadAllBytes($sourcePath)) -ContentType "application/octet-stream" | Out-Null
    Write-Host "Uploaded: $targetFilename" -ForegroundColor Green
}

function Get-OrCreate-SiteList {
    param(
        [Parameter(Mandatory)][string]$SiteId,
        [Parameter(Mandatory)]$ListConfig
    )

    $lists = Invoke-SeedGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/lists"
    $existing = $lists.value | Where-Object { $_.displayName -eq $ListConfig.displayName } | Select-Object -First 1
    if ($existing) {
        return $existing.id
    }

    Write-Host "Creating list: $($ListConfig.displayName)" -ForegroundColor Cyan
    $payload = New-ListPayload -ListName $ListConfig.displayName -Description $ListConfig.description -Columns @($ListConfig.columns)
    return (Invoke-SeedGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/lists" -Body $payload).id
}

function Add-ListItems {
    param(
        [Parameter(Mandatory)][string]$SiteId,
        [Parameter(Mandatory)][string]$ListId,
        [Parameter(Mandatory)]$ListConfig
    )

    $getPage = { param($uri) Invoke-SeedGraphRequest -Method GET -Uri $uri }
    $itemsUri = Get-ListItemsUri -SiteId $SiteId -ListId $ListId
    $existingItems = Get-PagedGraphValues -InitialUri $itemsUri -GetPage $getPage
    $missingItems = Get-MissingListItems -DesiredItems @($ListConfig.items) -ExistingItems $existingItems -KeyField $ListConfig.keyField
    foreach ($item in $missingItems) {
        $fields = @{}
        foreach ($property in $item.PSObject.Properties) {
            $fields[$property.Name] = $property.Value
        }
        Invoke-SeedGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$ListId/items" -Body @{ fields = $fields } | Out-Null
        Write-Host "Added list item: $($item.($ListConfig.keyField))" -ForegroundColor Green
    }
}

foreach ($siteConfig in $seedData.sites) {
    $group = Get-OrCreate-Group -Site $siteConfig
    $site = Wait-ForSite -GroupId $group.id
    $libraryDrives = @{}

    foreach ($document in $siteConfig.documents) {
        $driveId = $null
        if ($document.libraryName) {
            if (-not $libraryDrives.ContainsKey($document.libraryName)) {
                $libraryDrives[$document.libraryName] = Get-OrCreate-DocumentLibraryDrive -SiteId $site.id -LibraryName $document.libraryName
            }
            $driveId = $libraryDrives[$document.libraryName]
        }
        Upload-Document -SiteId $site.id -DriveId $driveId -Document $document
    }

    foreach ($listConfig in $siteConfig.lists) {
        $listId = Get-OrCreate-SiteList -SiteId $site.id -ListConfig $listConfig
        Add-ListItems -SiteId $site.id -ListId $listId -ListConfig $listConfig
    }
}
