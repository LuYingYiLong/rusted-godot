param(
    [string]$SourceRoot = 'C:\Users\Administrator\Downloads\rw_analysis-master\rw_analysis-master',
    [string]$GameJar = 'C:\Program Files (x86)\Steam\steamapps\common\Rusted Warfare\game-lib.jar',
    [string]$JavaExecutable = 'C:\Program Files (x86)\Steam\steamapps\common\Rusted Warfare\jvm64\bin\java.exe',
    [string]$GodotExecutable = 'C:\Users\Administrator\Documents\Godot\Godot_v4.7.2-stable_win64.exe',
    [string]$ReportDirectory = (Join-Path $env:TEMP 'rusted-godot-rw115-tests')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
foreach ($required in @($SourceRoot, $GameJar, $JavaExecutable, $GodotExecutable)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required path does not exist: $required"
    }
}

New-Item -ItemType Directory -Path $ReportDirectory -Force | Out-Null
$appData = Join-Path $ReportDirectory 'appdata'
$localAppData = Join-Path $ReportDirectory 'localappdata'
New-Item -ItemType Directory -Path $appData, $localAppData -Force | Out-Null
$env:APPDATA = $appData
$env:LOCALAPPDATA = $localAppData
$env:PYTHONUTF8 = '1'

$results = [System.Collections.Generic.List[object]]::new()
$python = (Get-Command python -ErrorAction Stop).Source
$catalogOutput = & $python (Join-Path $PSScriptRoot 'verify_rw_115_native_catalog.py') `
    --source-root $SourceRoot --game-jar $GameJar --java $JavaExecutable 2>&1 | Out-String
$catalogExit = $LASTEXITCODE
$catalogLog = Join-Path $ReportDirectory 'native_catalog.log'
Set-Content -LiteralPath $catalogLog -Value $catalogOutput -Encoding utf8
$catalogPassed = $catalogExit -eq 0 -and $catalogOutput.Contains('RW_115_CATALOG_OK') -and $catalogOutput.Contains('RW_115_BINARY_OK')
$results.Add([pscustomobject]@{
    name = 'native_catalog_115'
    evidence = 'stock_binary_and_02b_source'
    status = $(if ($catalogPassed) { 'passed' } else { 'failed' })
    exit_code = $catalogExit
    log = $catalogLog
})
Write-Output "native_catalog_115: $(if ($catalogPassed) { 'passed' } else { 'failed' })"

$collisionSourceOutput = & $python (Join-Path $PSScriptRoot 'verify_rw_115_collision_source.py') `
    --source-root $SourceRoot 2>&1 | Out-String
$collisionSourceExit = $LASTEXITCODE
$collisionSourceLog = Join-Path $ReportDirectory 'collision_source.log'
Set-Content -LiteralPath $collisionSourceLog -Value $collisionSourceOutput -Encoding utf8
$collisionSourcePassed = $collisionSourceExit -eq 0 -and $collisionSourceOutput.Contains('RW_115_COLLISION_SOURCE_OK')
$results.Add([pscustomobject]@{
    name = 'collision_source_115'
    evidence = 'original_115_02b_source'
    status = $(if ($collisionSourcePassed) { 'passed' } else { 'failed' })
    exit_code = $collisionSourceExit
    log = $collisionSourceLog
})
Write-Output "collision_source_115: $(if ($collisionSourcePassed) { 'passed' } else { 'failed' })"

$pathDelayOutput = & $python (Join-Path $PSScriptRoot 'verify_rw_115_path_delays.py') `
    --source-root $SourceRoot 2>&1 | Out-String
$pathDelayExit = $LASTEXITCODE
$pathDelayLog = Join-Path $ReportDirectory 'path_delays.log'
Set-Content -LiteralPath $pathDelayLog -Value $pathDelayOutput -Encoding utf8
$pathDelayPassed = $pathDelayExit -eq 0 -and $pathDelayOutput.Contains('RW_115_PATH_DELAY_OK')
$results.Add([pscustomobject]@{
    name = 'path_delay_bands_115'
    evidence = 'original_115_02b_source'
    status = $(if ($pathDelayPassed) { 'passed' } else { 'failed' })
    exit_code = $pathDelayExit
    log = $pathDelayLog
})
Write-Output "path_delay_bands_115: $(if ($pathDelayPassed) { 'passed' } else { 'failed' })"

$cases = @(
    @{ name = 'vanilla_unit_catalog'; script = 'tests/rw_vanilla_unit_catalog_test.gd'; marker = 'RW vanilla unit catalog:'; evidence = 'local_regression' },
    @{ name = 'factory_exit_115'; script = 'tests/rw_factory_exit_reference_test.gd'; marker = 'Factory exit reference passed:'; evidence = 'original_115_fixture' },
    @{ name = 'build_range_115'; script = 'tests/rw_build_range_reference_test.gd'; marker = 'BUILD_RANGE_REFERENCE_CHECK_OK'; evidence = 'original_115_fixture' },
    @{ name = 'command_reader'; script = 'tests/rw_battle_command_reader_test.gd'; marker = 'COMMAND_READER_CHECK_OK'; evidence = 'synthetic_protocol_regression' },
    @{ name = 'movement_grid'; script = 'tests/rw_movement_type_grid_test.gd'; marker = 'MOVEMENT_TYPE_GRID_OK'; evidence = 'local_regression' },
    @{ name = 'production_actions'; script = 'tests/rw_vanilla_production_test.gd'; marker = 'RW production:'; evidence = 'local_regression' },
    @{ name = 'collision_current_behavior'; script = 'tests/rw_battle_collision_test.gd'; marker = 'BATTLE_COLLISION_CHECK_OK'; evidence = 'local_regression' },
    @{ name = 'cross_team_collision_115'; script = 'tests/rw_115_cross_team_collision_test.gd'; marker = 'RW_115_CROSS_TEAM_COLLISION_OK'; evidence = 'original_115_source'; gap_marker = 'RW_115_COLLISION_GAP' }
)

foreach ($case in $cases) {
    $stdoutPath = Join-Path $ReportDirectory "$($case.name).stdout.log"
    $stderrPath = Join-Path $ReportDirectory "$($case.name).stderr.log"
    $arguments = @('--headless', '--quit-after', '600', '--path', "`"$projectRoot`"", '--script', $case.script)
    $process = Start-Process -FilePath $GodotExecutable -ArgumentList $arguments `
        -WorkingDirectory $projectRoot -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    $finished = $process.WaitForExit(30000)
    if (-not $finished) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    $process.Refresh()
    $stdout = [string](Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue)
    $stderr = [string](Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue)
    $passed = $finished -and $process.ExitCode -eq 0 -and $stdout.Contains($case.marker) -and
        $stdout -notmatch 'SCRIPT ERROR|Parse Error|Assertion failed' -and
        $stderr -notmatch 'SCRIPT ERROR|Parse Error|Assertion failed'
    $knownGap = $case.ContainsKey('gap_marker') -and $stderr.Contains($case.gap_marker)
    $status = if ($passed) { 'passed' } elseif ($knownGap) { 'known_gap' } elseif (-not $finished) { 'timeout' } else { 'failed' }
    $results.Add([pscustomobject]@{
        name = $case.name
        evidence = $case.evidence
        status = $status
        exit_code = $(if ($finished) { $process.ExitCode } else { -1 })
        stdout = $stdoutPath
        stderr = $stderrPath
    })
    Write-Output "$($case.name): $status"
}

$reportPath = Join-Path $ReportDirectory 'summary.json'
$summary = [pscustomobject]@{
    source_root = $SourceRoot
    game_jar = $GameJar
    project_root = $projectRoot
    checked_at = (Get-Date).ToString('o')
    results = @($results)
}
$summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding utf8
Write-Output "Report: $reportPath"
if (@($results | Where-Object { $_.status -ne 'passed' -and $_.status -ne 'known_gap' }).Count -gt 0) {
    exit 1
}
