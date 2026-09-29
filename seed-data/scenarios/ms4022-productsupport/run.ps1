param(
    [ValidatePattern("^\d{8}$")][string]$Date = (Get-Date -Format "yyyyMMdd"),
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$scenarioRoot = $PSScriptRoot
$siteAlias = "ms4022-productsupport-$Date"
$siteName = "MS-4022 - Product support - $Date"

function Get-ScenarioSourcePaths {
    param(
        [Parameter(Mandatory)][string]$ScenarioRoot,
        [Parameter(Mandatory)][string]$FilesSourceDir
    )

    if ([System.IO.Path]::IsPathRooted($FilesSourceDir)) {
        throw "filesSourceDir must be relative to the scenario root."
    }

    $productSourceDir = Join-Path $ScenarioRoot $FilesSourceDir
    $sourceParent = Split-Path $productSourceDir -Parent
    return [pscustomobject]@{
        ProductSourceDir = $productSourceDir
        ZipPath          = Join-Path $sourceParent "Products.zip"
    }
}

if ($WhatIf) {
    Write-Output "Legacy MS-4022 runner is archived; it does not execute against the hardened engine."
    Write-Output "Use scenarios/ms4022-productsupport-20260929/run.ps1 -PreflightOnly instead."
    return
}

throw "Legacy MS-4022 runner is archived; live execution is disabled. Use scenarios/ms4022-productsupport-20260929/run.ps1 -PreflightOnly instead."

$configPath = Join-Path $scenarioRoot "config.json"
if (-not (Test-Path $configPath)) {
    throw "Copy config.json.example to config.json and supply your tenant app credentials."
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json
$sourcePaths = Get-ScenarioSourcePaths -ScenarioRoot $scenarioRoot -FilesSourceDir $config.filesSourceDir
$productSourceDir = $sourcePaths.ProductSourceDir
if (-not (Test-Path $productSourceDir)) {
    New-Item -ItemType Directory -Path (Split-Path $sourcePaths.ZipPath -Parent) -Force | Out-Null
    Invoke-WebRequest -Uri "https://github.com/MicrosoftLearning/MS-4022-Extend-Microsoft-365-Copilot-in-Copilot-Studio/raw/refs/heads/master/Allfiles/Products.zip" -OutFile $sourcePaths.ZipPath
    Expand-Archive -Path $sourcePaths.ZipPath -DestinationPath $productSourceDir -Force
}

$roadmapPath = Join-Path $productSourceDir "Eagle Air Product Roadmap.xlsx"
if (-not (Test-Path $roadmapPath)) {
    Invoke-WebRequest -Uri "https://github.com/MicrosoftLearning/MS-4022-Extend-Microsoft-365-Copilot-in-Copilot-Studio/raw/refs/heads/master/Allfiles/Eagle%20Air%20Product%20Roadmap.xlsx" -OutFile $roadmapPath
}

$template = Get-Content (Join-Path $scenarioRoot "sharepoint-sites.json") -Raw
$seedData = $template.Replace("{{DATE}}", $Date) | ConvertFrom-Json
$documents = Get-ChildItem -Path $productSourceDir -File -Recurse | ForEach-Object {
    [pscustomobject]@{
        sourceFilename = [System.IO.Path]::GetRelativePath($productSourceDir, $_.FullName)
        targetFilename = $_.Name
        libraryName    = "Products"
    }
}
if ($documents.Count -eq 0) {
    throw "No lab sample files were extracted to $productSourceDir."
}
$seedData.sites[0].documents = @($documents)

$seedPath = [System.IO.Path]::GetTempFileName()
try {
    $seedData | ConvertTo-Json -Depth 10 | Set-Content -Path $seedPath -Encoding UTF8
    $engineRoot = Join-Path $scenarioRoot "..\..\engine" | Resolve-Path
    $connection = & (Join-Path $engineRoot "Connect-GraphApp.ps1") -ConfigPath $configPath
    $global:AccessToken = $connection.AccessToken
    . (Join-Path $engineRoot "Invoke-SeedSharePoint.ps1") -ConfigPath $configPath -SharePointPath $seedPath
} finally {
    Remove-Item $seedPath -Force -ErrorAction SilentlyContinue
}
