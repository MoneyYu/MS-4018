<#
.SYNOPSIS
    Seed calendar events via Microsoft Graph (Application Permissions).
.DESCRIPTION
    Reads calendar-events.json and creates events on the organizer's calendar
    with attendees. Supports past and future dates.
.PARAMETER ConfigPath
    Path to the scenario config.json.
.PARAMETER CalendarPath
    Path to the calendar-events.json data file.
#>
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [Parameter(Mandatory)][string]$CalendarPath
)

$ErrorActionPreference = "Stop"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$calData = Get-Content $CalendarPath -Raw -Encoding UTF8 | ConvertFrom-Json

# Build role→UPN lookup
$roleMap = @{}
foreach ($prop in $config.roles.PSObject.Properties) {
    $roleMap[$prop.Name] = $prop.Value.upn
}

function Get-Upn([string]$role) {
    if (-not $roleMap.ContainsKey($role)) { throw "Unknown role: $role" }
    return $roleMap[$role]
}

function Invoke-Graph {
    param([string]$Method, [string]$Uri, [object]$Body)
    $headers = @{ Authorization = "Bearer $($global:AccessToken)"; "Content-Type" = "application/json" }
    $bodyJson = if ($Body) { $Body | ConvertTo-Json -Depth 20 -Compress } else { $null }
    $params = @{ Method = $Method; Uri = $Uri; Headers = $headers }
    if ($bodyJson) { $params.Body = [System.Text.Encoding]::UTF8.GetBytes($bodyJson) }
    return Invoke-RestMethod @params
}

Write-Host "`n===== Seeding Calendar Events =====" -ForegroundColor Cyan

$today = (Get-Date).Date
Write-Host "  Base date (today): $($today.ToString('yyyy-MM-dd'))" -ForegroundColor Gray

foreach ($evt in $calData.events) {
    $organizerUpn = Get-Upn $evt.organizerRole
    $tz = if ($evt.timeZone) { $evt.timeZone } else { $config.timezone }

    # Support both fixed dates (startDateTime) and relative dates (dayOffset + startTime)
    if ($evt.dayOffset -ne $null -and $evt.startTime) {
        $eventDate = $today.AddDays($evt.dayOffset)
        $startDt = "$($eventDate.ToString('yyyy-MM-dd'))T$($evt.startTime):00"
        $endDt   = "$($eventDate.ToString('yyyy-MM-dd'))T$($evt.endTime):00"
    } else {
        $startDt = $evt.startDateTime
        $endDt   = $evt.endDateTime
    }

    Write-Host "  Creating: $($evt.subject) ($startDt)" -ForegroundColor White

    $attendees = @($evt.attendeeRoles | ForEach-Object {
        @{
            emailAddress = @{ address = (Get-Upn $_); name = $roleMap[$_] }
            type         = "required"
        }
    })

    $eventBody = @{
        subject = $evt.subject
        body    = @{ contentType = "HTML"; content = $evt.bodyHtml }
        start   = @{ dateTime = $startDt; timeZone = $tz }
        end     = @{ dateTime = $endDt;   timeZone = $tz }
        location = @{ displayName = $evt.location }
        attendees = $attendees
        isOnlineMeeting    = $evt.isOnlineMeeting
        onlineMeetingProvider = if ($evt.isOnlineMeeting) { "teamsForBusiness" } else { "unknown" }
    }

    try {
        $result = Invoke-Graph -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$organizerUpn/events" -Body $eventBody
        Write-Host "    -> Event ID: $($result.id)" -ForegroundColor Gray
    } catch {
        Write-Host "    -> ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }

    Start-Sleep -Seconds 2
}

Write-Host "`n===== Calendar Seeding Complete =====" -ForegroundColor Cyan
