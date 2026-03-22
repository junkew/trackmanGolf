# 1. Authentication
$Token = $env:bearertoken
if ([string]::IsNullOrWhiteSpace($Token)) {
    Write-Error "Environment variable 'bearertoken' is empty."
    return
}
if (-not $Token.StartsWith("Bearer ")) { $Token = "Bearer $Token" }

# 2. Configuration
$Endpoint = "https://api.trackmangolf.com/graphql/"
$Headers = @{ "Authorization" = $Token; "Content-Type" = "application/json" }
$AllResults = [System.Collections.Generic.List[PSObject]]::new()

# Unit Conversion Settings
$UseYards = $false
$UseKMH   = $true

function Send-TrackmanRequest ($Query) {
    $Body = @{ query = $Query } | ConvertTo-Json
    try {
        return (Invoke-RestMethod -Uri $Endpoint -Method Post -Body $Body -Headers $Headers -ErrorAction Stop).data
    } catch {
        if ($_.Exception.Response) {
            $streamReader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            Write-Host "API Error: $($streamReader.ReadToEnd())" -ForegroundColor Red
        }
        return $null
    }
}

# --- STEP 1: Get Total Count & Initial Progress ---
Write-Host "Connecting and calculating total history..." -ForegroundColor Cyan
$InitData = Send-TrackmanRequest "{ me { activities(take: 1) { totalCount } } }"
$TotalActivities = $InitData.me.activities.totalCount
Write-Host "Found $TotalActivities total activities. Starting full download..." -ForegroundColor Green

# --- STEP 2: Pagination Loop ---
$PageSize = 50 # Amount of sessions per request
$Skip = 0

while ($Skip -lt $TotalActivities) {
    Write-Host "Fetching sessions $Skip to $($Skip + $PageSize) of $TotalActivities..." -ForegroundColor Gray
    
    $ListQuery = "{ me { activities(take: $PageSize, skip: $Skip) { items { id kind time } } } }"
    $Data = Send-TrackmanRequest $ListQuery
    $Activities = $Data.me.activities.items
    
    if (-not $Activities) { break }

    foreach ($act in $Activities) {
        # Skip non-data activities
        if ($act.kind -in @("VIDEO", "EVENT_REPORT", "PDF_REPORT", "SCREENCAST", "NOTE")) { continue }

        $DetailQuery = @"
        {
          node(id: "$($act.id)") {
            ... on RangeActivityInterface {
              rangeStrokes: strokes {
                time club
                measurement(measurementType: SITE_MEASUREMENT) {
                  ballSpeed carry total maxHeight ballSpin distanceFromPin
                }
              }
            }
            ... on SessionActivityInterface {
              sessionStrokes: strokes {
                time club
                measurement {
                  ballSpeed carry total maxHeight spinRate
                }
              }
            }
          }
        }
"@
        $Details = Send-TrackmanRequest $DetailQuery
        $Strokes = if ($Details.node.rangeStrokes) { $Details.node.rangeStrokes } else { $Details.node.sessionStrokes }

        if ($Strokes) {
            $sDate = [DateTime]$act.time
            foreach ($s in $Strokes) {
                $m = $s.measurement
                $spin = if ($m.ballSpin) { $m.ballSpin } else { $m.spinRate }
                $distFact = if ($UseYards) { 1.09361 } else { 1.0 }
                $spdFact  = if ($UseKMH) { 3.6 } else { 2.23694 }

                $AllResults.Add([PSCustomObject]@{
                    Year         = $sDate.Year
                    Month        = $sDate.Month
                    Day          = $sDate.Day
                    SessionTime  = $sDate.ToString("HH:mm:ss")
                    ActivityType = $act.kind
                    Club         = $s.club
                    BallSpeed    = if ($m.ballSpeed) { [Math]::Round($m.ballSpeed * $spdFact, 1) } else { 0 }
                    Carry        = if ($m.carry)     { [Math]::Round($m.carry * $distFact, 1) } else { 0 }
                    Total        = if ($m.total)     { [Math]::Round($m.total * $distFact, 1) } else { 0 }
                    Spin         = if ($spin)        { [Math]::Round($spin, 0) } else { 0 }
                    DistPin      = if ($m.distanceFromPin) { [Math]::Round($m.distanceFromPin * $distFact, 1) } else { "-" }
                    UnitDist     = if($UseYards){"Yds"}else{"M"}
                })
            }
        }
    }
    $Skip += $PageSize
}

# --- FINAL STEP ---
if ($AllResults.Count -gt 0) {
    Write-Host "`nFinished! Total shots retrieved: $($AllResults.Count)" -ForegroundColor Green
    $AllResults | Out-GridView -Title "Trackman Full History Export"
    
    # Optional: Auto-save to CSV
    $AllResults | Export-Csv -Path "Trackman_All_History.csv" -NoTypeInformation -Delimiter ";" -Encoding utf8
}
