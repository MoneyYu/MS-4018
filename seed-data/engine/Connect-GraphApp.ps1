<#
.SYNOPSIS
    Connect to Microsoft Graph using Application Permissions (Client Credentials).
.DESCRIPTION
    Reads config.json from the scenario folder and connects using client credentials.
    Returns the access token for use with Invoke-MgGraphRequest.
.PARAMETER ConfigPath
    Path to the scenario config.json file.
#>
param(
    [Parameter(Mandatory)]
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

$tenantId    = $config.tenantId
$clientId    = $config.clientId
$clientSecret = $config.clientSecret

Write-Host "[Connect] Authenticating as App $clientId to tenant $tenantId ..." -ForegroundColor Cyan

# Get access token via client credentials flow
$body = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $clientSecret
    scope         = "https://graph.microsoft.com/.default"
}

$tokenResponse = Invoke-RestMethod -Method Post `
    -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
    -ContentType "application/x-www-form-urlencoded" `
    -Body $body

$global:AccessToken = $tokenResponse.access_token

# Also connect the MgGraph SDK with the access token for cmdlet usage
$secureToken = ConvertTo-SecureString $global:AccessToken -AsPlainText -Force
Connect-MgGraph -AccessToken $secureToken -NoWelcome

Write-Host "[Connect] Successfully connected." -ForegroundColor Green
Write-Host "[Connect] Token expires in $($tokenResponse.expires_in) seconds." -ForegroundColor Gray

# Return config and token for downstream scripts
return @{
    Config      = $config
    AccessToken = $global:AccessToken
}
