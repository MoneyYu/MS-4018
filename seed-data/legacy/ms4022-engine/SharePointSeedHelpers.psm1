function New-DocumentLibraryPayload {
    param(
        [Parameter(Mandatory)][string]$LibraryName
    )

    return @{
        displayName = $LibraryName
        list = @{ template = "documentLibrary" }
    }
}

function Get-DocumentUploadUri {
    param(
        [Parameter(Mandatory)][string]$SiteId,
        [string]$DriveId,
        [Parameter(Mandatory)][string]$Filename
    )

    $encodedFilename = [System.Uri]::EscapeDataString($Filename)
    if ($DriveId) {
        return "https://graph.microsoft.com/v1.0/drives/$DriveId/root:/$encodedFilename`:/content"
    }

    return "https://graph.microsoft.com/v1.0/sites/$SiteId/drive/root:/$encodedFilename`:/content"
}

function Assert-ExpectedDemoGroup {
    param(
        [Parameter(Mandatory)]$Group,
        [Parameter(Mandatory)][string]$Alias
    )

    $isExpectedGroup = $Group.mailNickname -eq $Alias -and
        @($Group.groupTypes) -contains "Unified" -and
        $Group.visibility -eq "Private"
    if (-not $isExpectedGroup) {
        throw "Existing group '$Alias' is not the expected private Unified Microsoft 365 Group."
    }
}

function Get-ExistingGroupWithRetry {
    param(
        [Parameter(Mandatory)][string]$Alias,
        [Parameter(Mandatory)][scriptblock]$GetGroup,
        [scriptblock]$Sleep = { param([int]$Seconds) Start-Sleep -Seconds $Seconds },
        [ValidateRange(1, 60)][int]$MaxAttempts = 6,
        [ValidateRange(0, 60)][int]$DelaySeconds = 5
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $response = & $GetGroup $Alias
        $group = @($response.value) | Select-Object -First 1
        if ($group) {
            return $group
        }

        if ($attempt -lt $MaxAttempts) {
            & $Sleep $DelaySeconds
        }
    }

    return $null
}

function Get-MissingDirectoryObjectUris {
    param(
        [string[]]$DesiredUris,
        [object[]]$ExistingDirectoryObjects
    )

    $existingIds = @($ExistingDirectoryObjects | ForEach-Object { $_.id })
    $seenObjectIds = @{}
    return @($DesiredUris | Where-Object {
        $objectId = ([System.Uri]$_).AbsolutePath.Trim("/").Split("/")[-1]
        if ($existingIds -contains $objectId -or $seenObjectIds.ContainsKey($objectId)) {
            return $false
        }
        $seenObjectIds[$objectId] = $true
        return $true
    })
}

function Get-PagedGraphValues {
    param(
        [Parameter(Mandatory)][string]$InitialUri,
        [Parameter(Mandatory)][scriptblock]$GetPage
    )

    $values = @()
    $nextUri = $InitialUri
    while ($nextUri) {
        $response = & $GetPage $nextUri
        $values += @($response.value)
        $nextUri = $response.'@odata.nextLink'
    }
    return @($values)
}

function New-GroupCreatePayload {
    param(
        [Parameter(Mandatory)]$Site,
        [Parameter(Mandatory)][string[]]$OwnerUris,
        [string[]]$MemberUris
    )

    $payload = @{
        displayName         = $Site.displayName
        description         = $Site.description
        groupTypes          = @("Unified")
        mailEnabled         = $true
        mailNickname        = $Site.alias
        securityEnabled     = $false
        visibility          = "Private"
        "owners@odata.bind" = @($OwnerUris)
    }
    if (@($MemberUris).Count -gt 0) {
        $payload["members@odata.bind"] = @($MemberUris)
    }
    return $payload
}

function Get-GroupRelationshipUri {
    param(
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][ValidateSet("owners", "members")][string]$Relationship
    )

    return "https://graph.microsoft.com/v1.0/groups/$GroupId/${Relationship}?`$select=id"
}

function New-ListPayload {
    param(
        [Parameter(Mandatory)][string]$ListName,
        [string]$Description,
        [Parameter(Mandatory)][object[]]$Columns
    )

    return @{
        displayName = $ListName
        description = $Description
        columns     = @($Columns)
        list        = @{ template = "genericList" }
    }
}

function Get-MissingListItems {
    param(
        [object[]]$DesiredItems,
        [object[]]$ExistingItems,
        [Parameter(Mandatory)][string]$KeyField
    )

    $existingKeys = @($ExistingItems | ForEach-Object { $_.fields.$KeyField })
    $seenKeys = @{}
    return @($DesiredItems | Where-Object {
        $key = $_.$KeyField
        if ($existingKeys -contains $key -or $seenKeys.ContainsKey($key)) {
            return $false
        }
        $seenKeys[$key] = $true
        return $true
    })
}

function Get-ListItemsUri {
    param(
        [Parameter(Mandatory)][string]$SiteId,
        [Parameter(Mandatory)][string]$ListId
    )

    return "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/${ListId}/items?`$expand=fields"
}

Export-ModuleMember -Function New-DocumentLibraryPayload, Get-DocumentUploadUri, Assert-ExpectedDemoGroup, Get-ExistingGroupWithRetry, Get-MissingDirectoryObjectUris, Get-PagedGraphValues, New-GroupCreatePayload, Get-GroupRelationshipUri, New-ListPayload, Get-MissingListItems, Get-ListItemsUri
