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
$preflight.EmailsPath = Join-Path $root "emails.json"
$preflight.TeamsMessagesPath = Join-Path $root "teams-messages.json"
$preflight.FilesManifestPath = Join-Path $root "files-manifest.json"
& (Join-Path $engine "Invoke-SeedPreflight.ps1") @preflight
if ($PreflightOnly) { Write-Host "Read-only preflight complete."; return }
& (Join-Path $engine "Invoke-UploadFiles.ps1") -ConfigPath $configPath -FilesManifestPath (Join-Path $root "files-manifest.json") -StrictScenario
& (Join-Path $engine "Invoke-SeedEmails.ps1") -ConfigPath $configPath -EmailsPath (Join-Path $root "emails.json")
& (Join-Path $engine "Invoke-SeedTeamsChannel.ps1") -ConfigPath $configPath -TeamsMessagesPath (Join-Path $root "teams-messages.json")
Write-Host "Seeding phases completed. Verify tenant state read-only."
