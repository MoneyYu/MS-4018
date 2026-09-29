param([switch]$PreflightOnly)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$engine = Join-Path $root "..\..\engine"
$configPath = Join-Path $root "config.json"
if (-not (Test-Path $configPath)) { throw "Copy config.json.example to config.json first." }
$conn = & (Join-Path $engine "Connect-GraphApp.ps1") -ConfigPath $configPath
$global:AccessToken = $conn.AccessToken
if (-not $global:AccessToken) { throw "No Graph access token returned." }
$preflight = @{ ConfigPath = $configPath }
$preflight.SharePointPath = Join-Path $root "sharepoint-sites.json"
& (Join-Path $engine "Invoke-SeedPreflight.ps1") @preflight
if ($PreflightOnly) { Write-Host "Read-only preflight complete."; return }
$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.filesSourceDir -or [System.IO.Path]::IsPathRooted($config.filesSourceDir)) { throw "filesSourceDir must be relative to the scenario root." }
$rootFull = [System.IO.Path]::GetFullPath($root)
$source = [System.IO.Path]::GetFullPath((Join-Path $root $config.filesSourceDir))
if (-not $source.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) { throw "filesSourceDir must stay inside the scenario root." }
$zip = Join-Path (Split-Path $source -Parent) "Products.zip"
if (-not (Test-Path $source)) {
    New-Item -ItemType Directory -Path $source -Force | Out-Null
    Invoke-WebRequest -Uri "https://github.com/MicrosoftLearning/MS-4022-Extend-Microsoft-365-Copilot-in-Copilot-Studio/raw/refs/heads/master/Allfiles/Products.zip" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $source
}
$extra = Join-Path $source "Eagle Air Product Roadmap.xlsx"
if (-not (Test-Path $extra)) { Invoke-WebRequest -Uri "https://github.com/MicrosoftLearning/MS-4022-Extend-Microsoft-365-Copilot-in-Copilot-Studio/raw/refs/heads/master/Allfiles/Eagle%20Air%20Product%20Roadmap.xlsx" -OutFile $extra }
$sourceFiles = @(Get-ChildItem -Path $source -File -Recurse)
if ($sourceFiles.Count -ne 9) { throw "Incomplete lab source: expected 9 documents; check source directory without deleting files." }
$siteConfig = Get-Content (Join-Path $root "sharepoint-sites.json") -Raw | ConvertFrom-Json
$siteConfig.sites[0].documents = @($sourceFiles | ForEach-Object {
    @{ sourceFilename = [System.IO.Path]::GetRelativePath($source, $_.FullName); targetFilename = $_.Name }
})
if (-not $siteConfig.sites[0].documents.Count) { throw "No source documents found." }
$siteConfig | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $root "sharepoint-runtime.json") -Encoding utf8
$sharepointPath = Join-Path $root "sharepoint-runtime.json"
& (Join-Path $engine "Invoke-SeedSharePoint.ps1") -ConfigPath $configPath -SharePointPath $sharepointPath
Write-Host "Seeding phases completed. Verify tenant state read-only."
