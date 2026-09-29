<#
.SYNOPSIS
    Update user profiles (JobTitle, Department) via Microsoft Graph.
.DESCRIPTION
    Reads user-profiles.json and applies industry profiles to tenant users.
    Only modifies JobTitle and Department — does NOT change DisplayName.
    Use -Industry to apply one, or -All to apply all industries at once.
.PARAMETER ConfigPath
    Path to the scenario config.json.
.PARAMETER ProfilesPath
    Path to the user-profiles.json data file.
.PARAMETER Industry
    The industry key to apply: manufacturing, financial, technology, telecom, cathay-financial.
.PARAMETER All
    Apply ALL industry profiles simultaneously (each uses different users).
#>
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$ProfilesPath,
    [ValidateSet("manufacturing","financial","technology","telecom","cathay-financial")]
    [string]$Industry,
    [switch]$All
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\Seed-Idempotency.ps1"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$profileData = Get-Content $ProfilesPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Determine which industries to apply
if ($All) {
    $industriesToApply = $profileData.industries.PSObject.Properties | ForEach-Object { $_.Name }
} elseif ($Industry) {
    $industriesToApply = @($Industry)
} else {
    throw "Specify -Industry <name> or -All"
}

function Invoke-Graph {
    param([string]$Method, [string]$Uri, [object]$Body)
    $headers = @{ Authorization = "Bearer $($global:AccessToken)"; "Content-Type" = "application/json" }
    $bodyJson = if ($Body) { $Body | ConvertTo-Json -Depth 10 -Compress } else { $null }
    $params = @{ Method = $Method; Uri = $Uri; Headers = $headers }
    if ($bodyJson) { $params.Body = [System.Text.Encoding]::UTF8.GetBytes($bodyJson) }
    return Invoke-RestMethod @params
}

Write-Host "`n===== Updating User Profiles =====" -ForegroundColor Cyan
Write-Host "  Industries: $($industriesToApply -join ', ')" -ForegroundColor Gray

foreach ($industryKey in $industriesToApply) {
    $industryData = $profileData.industries.$industryKey
    Write-Host "`n--- $($industryData.name) ($industryKey) — $($industryData.example) ---" -ForegroundColor Yellow

    foreach ($prop in $industryData.profiles.PSObject.Properties) {
        $roleName = $prop.Name
        $profile = $prop.Value
        $upn = $profile.upn

        Write-Host "  [$roleName] $upn → $($profile.jobTitle) | $($profile.department)" -ForegroundColor White

        $updateBody = @{
            jobTitle   = $profile.jobTitle
            department = $profile.department
        }

        try {
            Invoke-Graph -Method PATCH -Uri "https://graph.microsoft.com/v1.0/users/$upn" -Body $updateBody | Out-Null
            Write-Host "    -> Updated" -ForegroundColor Green
        } catch {
            throw "Failed to update the profile of '$upn' ($roleName): $(Get-SeedGraphErrorText -ErrorObject $_)"
        }

        Start-Sleep -Seconds 1
    }
}

Write-Host "`n===== User Profile Update Complete =====" -ForegroundColor Cyan
