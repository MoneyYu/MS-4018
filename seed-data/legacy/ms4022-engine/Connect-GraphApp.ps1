param(
    [Parameter(Mandatory)][string]$ConfigPath
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
foreach ($property in "tenantId", "clientId", "clientSecret") {
    if (-not $config.$property -or $config.$property -like "<*") {
        throw "Set '$property' in $ConfigPath before running the seeder."
    }
}

$tokenResponse = Invoke-RestMethod -Method Post `
    -Uri "https://login.microsoftonline.com/$($config.tenantId)/oauth2/v2.0/token" `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{
        grant_type    = "client_credentials"
        client_id     = $config.clientId
        client_secret = $config.clientSecret
        scope         = "https://graph.microsoft.com/.default"
    }

$global:AccessToken = $tokenResponse.access_token
return @{ Config = $config; AccessToken = $global:AccessToken }