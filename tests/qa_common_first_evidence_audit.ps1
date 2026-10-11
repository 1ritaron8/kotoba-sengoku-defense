param([switch]$RunHeadless)

$ErrorActionPreference = 'Stop'
$qaRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$qaOutput = Join-Path $PSScriptRoot ('profiles/qa-common-first-r1/run-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $qaOutput -Force | Out-Null

function Text-Hash([string]$Path) {
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($Path))
        return ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    } finally { $algorithm.Dispose() }
}

function File-Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Source-Snapshot {
    $result = [ordered]@{}
    # Include all native code/data, rather than just a verifier's direct imports.
    $paths = @(Get-ChildItem -LiteralPath (Join-Path $qaRoot 'native') -File -Recurse |
        Where-Object { $_.Extension -in @('.gd', '.json', '.gdshader', '.tscn', '.tres') })
    $paths += Get-Item -LiteralPath (Join-Path $qaRoot 'project.godot'), (Join-Path $qaRoot 'tools/run.ps1')
    foreach ($path in ($paths | Sort-Object FullName)) {
        $relative = $path.FullName.Substring($qaRoot.Length + 1).Replace('\', '/')
        $result[$relative] = File-Hash $path.FullName
    }
    return $result
}

function Snapshot-Delta($Before, $After) {
    $keys = @(@($Before.Keys) + @($After.Keys) | Sort-Object -Unique)
    return @($keys | Where-Object { $Before[$_] -ne $After[$_] })
}

$qaReports = @(
    @{ name='former-map-ui-cpu'; path='tests/profiles/ui-pilot-native-final/run-6f45def299d046b4912d0f1c8960bfbe/Godot/app_userdata/말의 전장/qa-ui-pilot.json'; kind='AUTOMATED_TEST'; bound='Retired map source only' },
    @{ name='former-map-ui-gpu'; path='tests/profiles/ui-pilot-gpu-final-v2/run-ca2198d52ccf4f3ebd74fe4d8fcec0ce/Godot/app_userdata/말의 전장/qa_ui_pilot_gpu.json'; kind='GPU_CAPTURE'; bound='Retired map; no new-world or full battle acceptance' },
    @{ name='empty-catalog-cpu'; path='tests/profiles/map-reset-native/run-7d0e15dde1e44c6493054069d8d539b4/Godot/app_userdata/말의 전장/qa-map-reset.json'; kind='AUTOMATED_TEST'; bound='Empty shell and isolated account fixtures only' },
    @{ name='functional-r2-cpu'; path='tests/profiles/unit-behavior-cpu-final/run-9a49ac2ce64e4ed894e1f00bc774d636/Godot/app_userdata/말의 전장/qa_unit_behavior_contracts.json'; kind='AUTOMATED_TEST'; bound='Synthetic geometry; no Troops3D/rendered world' },
    @{ name='functional-r2-gpu'; path='tests/profiles/unit-behavior-gpu-final/run-02b4a7f7e6d04534b4fff9b7248219b2/Godot/app_userdata/말의 전장/qa_unit_behavior_motion_gpu.json'; kind='GPU_CAPTURE'; bound='Game.actor_states into isolated SengokuActor3D; not actual Troops3D terrain/HUD integration' }
)
foreach ($recent in @(
    @{ profile='unit-behavior-qa-r1'; report='qa_unit_behavior_contracts.json'; name='qa-r1-cpu'; bound='Independent QA rerun; synthetic gameplay geometry only' },
    @{ profile='map-reset-qa-r1'; report='qa-map-reset.json'; name='empty-catalog-qa-r1'; bound='Independent QA rerun; actual empty Main and isolated account fixtures' }
)) {
    $recentDirectory = Join-Path $PSScriptRoot ('profiles/' + $recent.profile)
    if (-not (Test-Path -LiteralPath $recentDirectory)) { continue }
    foreach ($file in (Get-ChildItem -LiteralPath $recentDirectory -Filter $recent.report -File -Recurse)) {
        $qaReports += @{ name=$recent.name; path=$file.FullName.Substring($qaRoot.Length + 1).Replace('\','/'); kind='AUTOMATED_TEST'; bound=$recent.bound }
    }
}
# Audit the documented post-reset GPU report if it exists; do not invent a path.
$resetGpu = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'profiles') -Directory |
    Where-Object { $_.Name -like 'map-reset*gpu*' }
foreach ($folder in $resetGpu) {
    foreach ($file in (Get-ChildItem -LiteralPath $folder.FullName -Filter 'qa-map-reset.json' -File -Recurse)) {
        $qaReports += @{ name='empty-catalog-gpu'; path=$file.FullName.Substring($qaRoot.Length + 1).Replace('\','/'); kind='GPU_CAPTURE'; bound='Empty menus only; not new geometry' }
    }
}
$qaAudit = @()
foreach ($record in $qaReports) {
    # Resolve inside the exact run directory. Avoid locale-dependent non-ASCII
    # folder literals when Windows PowerShell reads an UTF-8 script without BOM.
    $segments = $record.path.Split('/')
    $runDirectory = Join-Path $qaRoot (($segments[0..3]) -join '/')
    $reportFile = Get-ChildItem -LiteralPath $runDirectory -Filter $segments[-1] -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    $reportPath = if ($null -ne $reportFile) { $reportFile.FullName } else { Join-Path $qaRoot $record.path }
    if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        $qaAudit += [ordered]@{ name=$record.name; path=$record.path; status='MISSING' }
        continue
    }
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $recorded = $report.sourceHashes
    if ($null -eq $recorded) { $recorded = $report.initialSourceHashes }
    $deltas = @()
    if ($null -ne $recorded) {
        foreach ($property in $recorded.PSObject.Properties) {
            $sourcePath = Join-Path $qaRoot $property.Name
            $current = if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
                if ($record.name -like 'empty-catalog-*') { Text-Hash $sourcePath } else { File-Hash $sourcePath }
            } else { $null }
            $deltas += [ordered]@{ path=$property.Name; recorded=$property.Value; current=$current; matches=($current -eq $property.Value) }
        }
    }
    $qaAudit += [ordered]@{
        name=$record.name; path=$reportPath; evidence_type=$record.kind; report_sha256=(File-Hash $reportPath)
        checks=$report.checks; failures=@($report.failures).Count; recorded_freeze=$report.sourceFreezeUnchanged
        source_frozen_during_harness=$report.sourceFrozenDuringHarness; scope=$report.scope; boundary=$record.bound
        source_hashes=$deltas; matching_sources=@($deltas | Where-Object { $_.matches }).Count
        changed_or_missing_sources=@($deltas | Where-Object { -not $_.matches }).Count
        current_acceptance='NOT_GRANTED: matching hashes do not expand the recorded test scope'
    }
}

$qaRuns = @()
if ($RunHeadless) {
    $cases = @(
        @{ script='tests/qa_unit_behavior_contracts.gd'; profile='unit-behavior-qa-r1'; report='qa_unit_behavior_contracts.json'; timeout=120 },
        @{ script='tests/qa_map_reset.gd'; profile='map-reset-qa-r1'; report='qa-map-reset.json'; timeout=120 }
    )
    foreach ($case in $cases) {
        $before = Source-Snapshot
        $testHash = File-Hash (Join-Path $qaRoot $case.script)
        $launcher = @(& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $qaRoot 'tools/run.ps1') -Mode Qa -Headless -Script $case.script -ProfileName $case.profile -TimeoutSeconds $case.timeout 2>&1)
        $exitCode = $LASTEXITCODE
        $after = Source-Snapshot
        $changed = @(Snapshot-Delta $before $after)
        if ($testHash -ne (File-Hash (Join-Path $qaRoot $case.script))) { $changed += $case.script }
        $receipt = $null
        foreach ($line in $launcher) {
            if ([string]$line -match '^\{"mode":') { $receipt = ([string]$line | ConvertFrom-Json) }
        }
        $data = $null; $resultPath = $null
        if ($null -ne $receipt) {
            $resultFile = Get-ChildItem -LiteralPath $receipt.profile -Filter $case.report -File -Recurse | Select-Object -First 1
            if ($null -ne $resultFile) { $resultPath=$resultFile.FullName; $data=Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json }
        }
        $status = if ($changed.Count -gt 0) { 'INVALIDATED_SOURCE_CHANGE' }
                  elseif ($exitCode -ne 0 -or $null -eq $data -or @($data.failures).Count -gt 0 -or $data.sourceFreezeUnchanged -ne $true) { 'FAIL' }
                  else { 'PASS' }
        $qaRuns += [ordered]@{ script=$case.script; status=$status; exit_code=$exitCode; receipt=$receipt
            report=$resultPath; checks=$data.checks; failures=$data.failures; scope=$data.scope
            source_hashes_before=$before; source_hashes_after=$after; test_hash=$testHash
            changed_sources=$changed; launcher_output=@($launcher | ForEach-Object { [string]$_ }) }
        Write-Output ([pscustomobject]$qaRuns[-1] | Select-Object script,status,exit_code,report,checks,changed_sources | ConvertTo-Json -Compress)
    }
}
$qaResult = [ordered]@{
    directive_id='JP_DF-HQ-20261008-COMMON-FIRST-R1'; task_id='QA-01'; owner='QA'; recorded_at_utc=[DateTime]::UtcNow.ToString('o')
    hash_method='Snapshots/raw reports: SHA256 file bytes (Godot get_sha256); empty-catalog reports: decoded UTF-8 text (Godot sha256_text). Snapshots include all native code/data.'
    status='REVIEW'; source_hashes=(Source-Snapshot); evidence=$qaAudit; automated_runs=$qaRuns
    blockers=@('Actual new-world/UI/Troops3D integration pending binding contract', 'GPU/performance require HQ slot and writer freeze', 'G1/G2/G3 and user art acceptance not granted by this audit')
    next_action='Use owner-approved adapter fixture; serialize GPU/performance and native natural-play verification after applicable gates'
}
$qaResultPath = Join-Path $qaOutput 'evidence-audit.json'
[IO.File]::WriteAllText($qaResultPath, ($qaResult | ConvertTo-Json -Depth 15), (New-Object Text.UTF8Encoding($false)))
Write-Output ('Evidence audit: ' + $qaResultPath)
foreach ($record in $qaAudit) { Write-Output ([pscustomobject]$record | Select-Object name,checks,failures,matching_sources,changed_or_missing_sources | ConvertTo-Json -Compress) }
