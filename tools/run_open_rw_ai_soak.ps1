param(
    [string]$ProbeRoot = 'C:\Users\Administrator\Documents\Codex\open-rw-probe',
    [string]$GodotExecutable = 'C:\Users\Administrator\Documents\Godot\Godot_v4.7.2-stable_win64.exe',
    [string]$MapName = '[p6]Valley Pass (6p).tmx',
    [int]$AiCount = 4,
    [int]$Port = 5125,
    [int]$DurationSeconds = 120,
    [switch]$Rebuild
)

$ErrorActionPreference = 'Stop'
function Get-ListeningProcessId {
    param([int]$TargetPort)

    foreach ($line in (& netstat.exe -ano -p tcp)) {
        if ($line -match "^\s*TCP\s+\S+:$TargetPort\s+\S+\s+LISTENING\s+(\d+)\s*$") {
            return [int]$Matches[1]
        }
    }
    return 0
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$probeRunner = Join-Path $ProbeRoot 'run_probe.ps1'
$mapFile = Join-Path $projectRoot "assets\rwx\maps\skirmish\$MapName"
if (-not (Test-Path -LiteralPath $probeRunner)) {
    throw "OPEN-RW probe runner not found: $probeRunner"
}
if (-not (Test-Path -LiteralPath $GodotExecutable)) {
    throw "Godot executable not found: $GodotExecutable"
}
if (-not (Test-Path -LiteralPath $mapFile)) {
    throw "Map is not imported into Godot: $mapFile"
}
if ($AiCount -lt 1 -or $AiCount -gt 8) {
    throw 'AiCount must be between 1 and 8'
}
if ($MapName.Contains('"') -or $ProbeRoot.Contains('"')) {
    throw 'MapName and ProbeRoot cannot contain quote characters'
}
if ((Get-ListeningProcessId -TargetPort $Port) -gt 0) {
    throw "Port $Port is already listening"
}

$runId = Get-Date -Format 'yyyyMMdd-HHmmss'
$outputDirectory = Join-Path $ProbeRoot "probe-output\ai-soak-$runId"
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$referenceTrace = Join-Path $outputDirectory 'open-rw.tsv'
$godotReport = Join-Path $outputDirectory 'godot.jsonl'
$godotTrace = Join-Path $outputDirectory 'godot.tsv'
$hostOutput = Join-Path $outputDirectory 'host.stdout.log'
$hostError = Join-Path $outputDirectory 'host.stderr.log'
$godotOutput = Join-Path $outputDirectory 'godot.console.log'
$godotError = Join-Path $outputDirectory 'godot.stderr.log'
$hostArguments = @(
    '-NoProfile',
    '-File', "`"$probeRunner`"",
    '-AutoHost',
    '-HostPort', $Port,
    '-HostAi', $AiCount,
    '-HostMap', "`"$MapName`"",
    '-MaxFrame', [Math]::Ceiling($DurationSeconds * 60 + 1800),
    '-Interval', 10,
    '-OutputPath', "`"$referenceTrace`""
)
if ($Rebuild) {
    $hostArguments += '-Rebuild'
}

$hostProcess = $null
$hostJavaPid = 0
try {
    $hostProcess = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') `
        -ArgumentList ($hostArguments -join ' ') `
        -WorkingDirectory $ProbeRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput $hostOutput `
        -RedirectStandardError $hostError `
        -PassThru
    $ready = $false
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        Start-Sleep -Seconds 1
        $hostProcess.Refresh()
        if ($hostProcess.HasExited) {
            throw "OPEN-RW host exited before opening port $Port; see $hostError"
        }
        $hostJavaPid = Get-ListeningProcessId -TargetPort $Port
        if ($hostJavaPid -gt 0) {
            $ready = $true
            break
        }
    }
    if (-not $ready) {
        throw "OPEN-RW host did not open port $Port within 90 seconds"
    }
    Write-Output "OPEN-RW room: 127.0.0.1:$Port, map=$MapName, AI=$AiCount"

    $env:RW_SOAK_ADDRESS = "127.0.0.1:$Port"
    $env:RW_SOAK_EXPECT_MAP = ($MapName -replace '^.*\]', '' -replace '\s*\(.*$', '').Trim()
    $env:RW_SOAK_MIN_PLAYERS = [string]($AiCount + 2)
    $env:RW_SOAK_DURATION = [string]$DurationSeconds
    $env:RW_SOAK_START_TIMEOUT = '90'
    $env:RW_SOAK_REPORT_PATH = $godotReport
    $env:RW_PROBE_CHECKSUMS = '1'
    $env:RW_PROBE_PATH = $godotTrace
    $env:RW_PROBE_INTERVAL = '10'
    $godotArguments = @('--headless', '--path', "`"$projectRoot`"", '--scene', 'res://tests/rw_multiplayer_soak.tscn')
    $godotProcess = Start-Process -FilePath $GodotExecutable `
        -ArgumentList ($godotArguments -join ' ') `
        -WorkingDirectory $projectRoot `
        -WindowStyle Hidden `
        -RedirectStandardOutput $godotOutput `
        -RedirectStandardError $godotError `
        -Wait `
        -PassThru
    $godotExitCode = $godotProcess.ExitCode
    if (-not (Test-Path -LiteralPath $godotReport)) {
        throw "Godot did not write a report; see $godotOutput"
    }
    $events = @(Get-Content -LiteralPath $godotReport | ForEach-Object { $_ | ConvertFrom-Json })
    $completed = @($events | Where-Object event -eq 'transport_completed')
    $matches = @($events | Where-Object event -eq 'checksum_unit_match')
    $mismatches = @($events | Where-Object event -eq 'checksum_unit_mismatch')
    $unverified = @($events | Where-Object event -eq 'checksum_unverified')
    $firstMismatch = $mismatches | Select-Object -First 1
    Write-Output "Godot exit=$godotExitCode; checksum matches=$($matches.Count), mismatches=$($mismatches.Count), unverified=$($unverified.Count)"
    if ($firstMismatch) {
        Write-Output "First mismatch: frame=$($firstMismatch.frame), fields=$(($firstMismatch.differences.PSObject.Properties.Name -join ','))"
    }
    Write-Output "Report: $godotReport"
    Write-Output "OPEN-RW trace: $referenceTrace"
    Write-Output "Godot trace: $godotTrace"
    if ((Get-Command py -ErrorAction SilentlyContinue) -and
        (Test-Path -LiteralPath $referenceTrace) -and
        (Test-Path -LiteralPath $godotTrace)) {
        $comparator = Join-Path $PSScriptRoot 'compare_rw_state_traces.py'
        $trajectoryResult = & py -3 $comparator $referenceTrace $godotTrace `
            --exclude-type tree `
            --fields x,y,rot,order,order_x,order_y,path_x,path_y `
            --position-tolerance 0.1 `
            --angle-tolerance 0.1
        Write-Output 'Trajectory comparison:'
        $trajectoryResult | ForEach-Object { Write-Output $_ }
    }
    if ($godotExitCode -ne 0 -or $completed.Count -eq 0) {
        throw 'AI soak did not complete; inspect the report and console logs'
    }
}
finally {
    if ($hostJavaPid -gt 0) {
        Stop-Process -Id $hostJavaPid -Force -ErrorAction SilentlyContinue
    }
    if ($hostProcess -and -not $hostProcess.HasExited) {
        Stop-Process -Id $hostProcess.Id -Force -ErrorAction SilentlyContinue
    }
}
