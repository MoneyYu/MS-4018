<#
.SYNOPSIS
    Upload files to OneDrive via Microsoft Graph (Application Permissions).
.DESCRIPTION
    Reads files-manifest.json and uploads files to the specified user's OneDrive.

    Supports nested subfolders via two equivalent ways:
      1. Embed path in localName, e.g. "S1/file.docx" or "S1/sub/file.docx".
      2. Set an explicit "subfolder" field on the file entry, e.g.
         { "localName": "file.docx", "subfolder": "S1 國泰人壽" }

    Use #2 when files are stored flat in DEMO-FILE/ but need to be grouped into
    different folders on OneDrive. The two forms can also be combined.

    Subfolders are created automatically via the OneDrive children endpoint
    (idempotent — existing folders are reused, not overwritten).

    Idempotency:
      A file whose EXACT name is already stored in the target folder is skipped. Re-uploading
      identical bytes is not a no-op — OneDrive keeps a new version of the item and Office
      containers are re-serialised on the way in — so an unconditional re-upload changes the
      stored file on every run of the same dated scenario. Missing files are still uploaded.

    File size handling:
      - <= 4MB : simple PUT
      - >  4MB : upload session with 4MB chunks

    Nothing this script writes is echoed to the pipeline: a Graph DriveItem response carries
    @microsoft.graph.downloadUrl, a pre-authenticated capability URL, which must never end up
    in an operator's run log.
.PARAMETER ConfigPath
    Path to the scenario config.json.
.PARAMETER FilesManifestPath
    Path to the files-manifest.json data file.
.PARAMETER StrictScenario
    Generated Customer Pack mode: create a new folder without replacing collisions and
    require matching local and remote proof plus exact file revisions before a rerun skips.
    Never adopt or repair an existing unmarked folder.
#>
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$FilesManifestPath,
    [switch]$StrictScenario
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\Seed-Idempotency.ps1"
. "$PSScriptRoot\Seed-GraphRead.ps1"
. "$PSScriptRoot\Seed-OneDriveOwnership.ps1"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$manifest = Get-Content $FilesManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Build role→UPN lookup
$roleMap = @{}
foreach ($prop in $config.roles.PSObject.Properties) {
    $roleMap[$prop.Name] = $prop.Value.upn
}

function Invoke-Graph {
    param([string]$Method, [string]$Uri, [object]$Body, [byte[]]$RawBody, [string]$ContentType)
    $headers = @{ Authorization = "Bearer $($global:AccessToken)" }
    if (-not $ContentType) { $headers["Content-Type"] = "application/json" }
    else { $headers["Content-Type"] = $ContentType }

    $params = @{ Method = $Method; Uri = $Uri; Headers = $headers }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 20 -Compress) }
    if ($RawBody) { $params.Body = $RawBody }
    return Invoke-RestMethod @params
}
if ($StrictScenario) {
    $plan = Get-SeedStrictOneDrivePlan -ConfigPath $ConfigPath -FilesManifestPath $FilesManifestPath
    Invoke-SeedStrictOneDriveUpload -Plan $plan
    return
}

# Encode a OneDrive relative path while preserving '/' as path separator.
# Example: "Cathay-MS4019/S1 場景一/file (v2).docx"
#       -> "Cathay-MS4019/S1%20%E5%A0%B4%E6%99%AF%E4%B8%80/file%20(v2).docx"
function Encode-OneDrivePath {
    param([Parameter(Mandatory)][string]$RelativePath)
    $clean = ($RelativePath -replace '\\', '/').Trim('/')
    if (-not $clean) { return "" }
    $encoded = $clean.Split('/') | ForEach-Object { [System.Uri]::EscapeDataString($_) }
    return ($encoded -join '/')
}

# Ensure a folder path exists in the user's OneDrive root, creating each missing
# segment via POST .../drive/root[:/parent:]/children. Idempotent: existing
# folders are reused (conflictBehavior=replace on a folder does NOT overwrite contents).
$folderEnsuredCache = @{}
function Ensure-OneDriveFolder {
    param([Parameter(Mandatory)][string]$Upn, [Parameter(Mandatory)][string]$RelativePath)

    $clean = ($RelativePath -replace '\\', '/').Trim('/')
    if (-not $clean) { return }

    $cacheKey = "$Upn|$clean"
    if ($folderEnsuredCache.ContainsKey($cacheKey)) { return }

    $segments = $clean.Split('/')
    $accumulated = @()
    foreach ($seg in $segments) {
        if (-not $seg) { continue }

        if ($accumulated.Count -eq 0) {
            $parentChildrenUri = "https://graph.microsoft.com/v1.0/users/$Upn/drive/root/children"
        } else {
            $parentEncoded = Encode-OneDrivePath ($accumulated -join '/')
            $parentChildrenUri = "https://graph.microsoft.com/v1.0/users/$Upn/drive/root:/$parentEncoded`:/children"
        }

        $body = @{
            name   = $seg
            folder = @{}
            "@microsoft.graph.conflictBehavior" = "replace"
        }

        try {
            Invoke-Graph -Method POST -Uri $parentChildrenUri -Body $body | Out-Null
        } catch {
            # Only an "already exists" conflict is idempotent here; anything else is a real failure.
            # The whole ErrorRecord is passed: in PowerShell 7 the Graph payload is in ErrorDetails.
            if (Test-SeedAlreadyExistsError -ErrorRecord $_) {
                Write-Host "    (folder '$seg' already exists)" -ForegroundColor DarkGray
            } else {
                throw "Failed to ensure OneDrive folder '$seg' under '$RelativePath' for $Upn : $(Get-SeedGraphErrorText -ErrorObject $_)"
            }
        }

        $accumulated += $seg
    }

    $folderEnsuredCache[$cacheKey] = $true
}

# Snapshot the file names already stored in one OneDrive folder, once per folder. The snapshot
# is what decides upload vs skip, so it is read through the shared paging reader: a truncated
# first page would make a stored file look absent and re-upload it.
$folderChildNamesCache = @{}
function Get-OneDriveFolderFileNames {
    param(
        [Parameter(Mandatory)][string]$Upn,
        [Parameter(Mandatory)][AllowEmptyString()][string]$RelativePath
    )

    $clean = ($RelativePath -replace '\\', '/').Trim('/')
    $cacheKey = "$Upn|$clean"
    if ($folderChildNamesCache.ContainsKey($cacheKey)) { return , @($folderChildNamesCache[$cacheKey]) }

    if ($clean) {
        $encoded = Encode-OneDrivePath $clean
        $uri = "https://graph.microsoft.com/v1.0/users/$Upn/drive/root:/$encoded`:/children?`$select=id,name&`$top=200"
    } else {
        $uri = "https://graph.microsoft.com/v1.0/users/$Upn/drive/root/children?`$select=id,name&`$top=200"
    }

    $names = Get-SeedDriveChildNames -ChildrenUri $uri
    $folderChildNamesCache[$cacheKey] = @($names)
    return , @($names)
}

# Keep the snapshot authoritative after a successful upload, so a manifest that declares the
# same file twice uploads it once.
function Add-OneDriveFolderFileName {
    param(
        [Parameter(Mandatory)][string]$Upn,
        [Parameter(Mandatory)][AllowEmptyString()][string]$RelativePath,
        [Parameter(Mandatory)][string]$Name
    )

    $clean = ($RelativePath -replace '\\', '/').Trim('/')
    $cacheKey = "$Upn|$clean"
    $current = if ($folderChildNamesCache.ContainsKey($cacheKey)) { @($folderChildNamesCache[$cacheKey]) } else { @() }
    $folderChildNamesCache[$cacheKey] = @($current) + @($Name)
}

Write-Host "`n===== Uploading Files to OneDrive =====" -ForegroundColor Cyan

$uploadToUpn = $roleMap[$manifest.uploadToRole]
$targetFolder = ($manifest.targetFolder -replace '\\', '/').Trim('/')

# Resolve the source directory (relative to the scenario config)
$configDir = Split-Path $ConfigPath -Parent
$sourceDir = Join-Path $configDir $config.filesSourceDir | Resolve-Path

Write-Host "  Upload to:   $uploadToUpn / $targetFolder" -ForegroundColor Gray
Write-Host "  Source dir:  $sourceDir" -ForegroundColor Gray

# Pre-create the top-level target folder (avoids 404 on first simple upload).
if ($targetFolder) {
    Ensure-OneDriveFolder -Upn $uploadToUpn -RelativePath $targetFolder
}

$successCount = 0
$skippedCount = 0

foreach ($file in $manifest.files) {
    $localPath = Join-Path $sourceDir $file.localName

    if (-not (Test-Path $localPath)) {
        throw "Declared demo file is missing: $localPath (files-manifest.json entry '$($file.localName)')."
    }

    $fileInfo = Get-Item $localPath
    $fileSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)

    # Parse localName: it may be a plain filename, or a relative path "Sub/file.docx".
    # Both are supported. The last segment is treated as the filename, earlier segments
    # form an implicit OneDrive subfolder path.
    $relName = ($file.localName -replace '\\', '/').Trim('/')
    $segs = $relName.Split('/')
    $fileName = $segs[-1]
    $nameSubPath = if ($segs.Count -gt 1) { ($segs[0..($segs.Count - 2)]) -join '/' } else { "" }

    # Optional explicit subfolder field on the manifest entry.
    # Useful when files are stored flat locally but should be grouped on OneDrive.
    $explicitSubfolder = ""
    if ($file.PSObject.Properties.Name -contains 'subfolder' -and $file.subfolder) {
        $explicitSubfolder = ($file.subfolder -replace '\\', '/').Trim('/')
    }

    # Final OneDrive folder = targetFolder / explicitSubfolder / nameSubPath
    $folderPath = $targetFolder
    if ($explicitSubfolder) { $folderPath = "$folderPath/$explicitSubfolder" }
    if ($nameSubPath)       { $folderPath = "$folderPath/$nameSubPath" }
    $folderPath = $folderPath.Trim('/')

    # Make sure the (sub)folder structure exists before uploading.
    if ($folderPath) {
        Ensure-OneDriveFolder -Upn $uploadToUpn -RelativePath $folderPath
    }

    # Already stored under the exact same name -> leave it alone. A re-PUT would only add a
    # version and re-serialise the file.
    $existingNames = Get-OneDriveFolderFileNames -Upn $uploadToUpn -RelativePath $folderPath
    if (Test-SeedDriveFileExists -ExistingNames $existingNames -Name $fileName) {
        Write-Host "  SKIP: $($file.localName) — already in /$folderPath/ (not re-uploaded)" -ForegroundColor DarkGray
        $skippedCount++
        continue
    }

    # Encode path segments (preserving '/').
    $encodedFolder   = Encode-OneDrivePath $folderPath
    $encodedFileName = [System.Uri]::EscapeDataString($fileName)
    $encodedFullPath = if ($encodedFolder) { "$encodedFolder/$encodedFileName" } else { $encodedFileName }

    Write-Host "  Uploading: $($file.localName) ($fileSizeMB MB) -> /$folderPath/" -ForegroundColor White

    try {
        if ($fileInfo.Length -le 4MB) {
            # Simple upload (< 4MB). The DriveItem answer is discarded on purpose: it carries
            # @microsoft.graph.downloadUrl, a pre-authenticated capability URL.
            $fileBytes = [System.IO.File]::ReadAllBytes($localPath)
            $uploadUri = "https://graph.microsoft.com/v1.0/users/$uploadToUpn/drive/root:/$encodedFullPath`:/content"
            Invoke-Graph -Method PUT -Uri $uploadUri -RawBody $fileBytes -ContentType "application/octet-stream" | Out-Null
        } else {
            # Large file: create upload session
            $sessionUri = "https://graph.microsoft.com/v1.0/users/$uploadToUpn/drive/root:/$encodedFullPath`:/createUploadSession"
            $session = Invoke-Graph -Method POST -Uri $sessionUri -Body @{
                item = @{ "@microsoft.graph.conflictBehavior" = "replace" }
            }
            $uploadUrl = $session.uploadUrl

            # Upload in 4MB chunks
            $chunkSize = 4MB
            $fileStream = [System.IO.File]::OpenRead($localPath)
            $buffer = New-Object byte[] $chunkSize
            $position = 0
            $totalSize = $fileStream.Length

            while ($position -lt $totalSize) {
                $bytesRead = $fileStream.Read($buffer, 0, $chunkSize)
                $chunk = $buffer[0..($bytesRead - 1)]
                $rangeEnd = $position + $bytesRead - 1
                $contentRange = "bytes $position-$rangeEnd/$totalSize"

                $chunkHeaders = @{
                    "Content-Range" = $contentRange
                    "Content-Length" = $bytesRead
                }
                # The final chunk answers with the completed DriveItem (download URL included),
                # so this response is discarded too.
                Invoke-RestMethod -Method PUT -Uri $uploadUrl -Body $chunk -Headers $chunkHeaders -ContentType "application/octet-stream" | Out-Null
                $position += $bytesRead
            }
            $fileStream.Close()
        }
        Write-Host "    -> OK" -ForegroundColor Green
        $successCount++
        Add-OneDriveFolderFileName -Upn $uploadToUpn -RelativePath $folderPath -Name $fileName
    } catch {
        throw "Failed to upload '$($file.localName)' to $uploadToUpn /$folderPath/: $(Get-SeedGraphErrorText -ErrorObject $_)"
    }

    Start-Sleep -Seconds 1
}

Write-Host "`n===== Upload Complete: $successCount file(s) uploaded / $skippedCount already present (any failure aborts the run) =====" -ForegroundColor Cyan
