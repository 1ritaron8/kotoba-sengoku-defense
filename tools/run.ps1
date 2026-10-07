param(
    [ValidateSet('Play', 'Edit', 'Import', 'Check', 'Qa')]
    [string]$Mode = 'Play',
    [string]$Script = '',
    [string]$ProfileName = '',
    [string]$GodotPath = '',
    [switch]$Headless,
    [ValidateRange(0, 3600)]
    [int]$TimeoutSeconds = 0,
    [ValidateRange(0, 100000)]
    [int]$QuitAfter = 0,
    [string[]]$UserArguments = @()
)

$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$taskTestsRoot = Join-Path $taskRoot 'tests'
$taskProfilesRoot = Join-Path $taskTestsRoot 'profiles'
$taskLocalRoot = Join-Path $taskRoot '.local'

function ConvertTo-NativeArgument([string]$Value) {
    if ($Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $quoted = [regex]::Replace($Value, '(\\*)"', '${1}${1}\"')
    $quoted = [regex]::Replace($quoted, '(\\+)$', '${1}${1}')
    return '"' + $quoted + '"'
}

if (-not (Test-Path -LiteralPath (Join-Path $taskRoot 'project.godot') -PathType Leaf)) {
    throw 'The launcher must be inside the project tools directory.'
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $GodotPath = Join-Path $PSScriptRoot 'godot/Godot_v4.7.2-stable_win64.exe'
}
$GodotPath = [IO.Path]::GetFullPath($GodotPath)
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Put the official Godot 4.7.2 Windows engine in tools/godot, or pass -GodotPath. No engine is downloaded automatically.'
}

if ($Mode -in @('Play', 'Edit') -and
    (-not (Test-Path -LiteralPath (Join-Path $taskRoot '.godot/global_script_class_cache.cfg')) -or
     -not (Test-Path -LiteralPath (Join-Path $taskRoot '.godot/imported') -PathType Container))) {
    Write-Output 'Preparing source assets for the first launch.'
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Mode Import -Headless -GodotPath $GodotPath
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$taskArguments = @('--path', $taskRoot, '--accessibility', 'disabled')
if ($Headless -or $Mode -in @('Import', 'Check', 'Qa')) {
    if ($Headless -or $Mode -in @('Import', 'Check')) { $taskArguments += '--headless' }
}
if ($Mode -eq 'Edit') { $taskArguments += '--editor' }
if ($Mode -eq 'Import') { $taskArguments += @('--editor', '--import') }
if ($Mode -in @('Check', 'Qa')) {
    if ([string]::IsNullOrWhiteSpace($Script)) { throw "$Mode requires -Script." }
    $taskScriptRelative = $Script -replace '^res://', ''
    $taskScriptPath = [IO.Path]::GetFullPath((Join-Path $taskRoot $taskScriptRelative))
    $taskScriptBoundary = $taskRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $taskScriptPath.StartsWith($taskScriptBoundary, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetExtension($taskScriptPath) -ne '.gd' -or
        -not (Test-Path -LiteralPath $taskScriptPath -PathType Leaf)) {
        throw 'Script must be an existing GDScript inside this checkout.'
    }
    if ($Mode -eq 'Qa' -and -not $taskScriptPath.StartsWith($taskTestsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'QA can only run scripts inside this checkout tests directory.'
    }
    $taskArguments += @('--script', $taskScriptPath)
    if ($Mode -eq 'Check') { $taskArguments += '--check-only' }
}
if (-not $Headless -and $Mode -in @('Play', 'Edit', 'Qa')) {
    $taskArguments += @('--rendering-method', 'gl_compatibility', '--rendering-driver', 'opengl3')
}
if ($QuitAfter -gt 0) { $taskArguments += @('--quit-after', [string]$QuitAfter) }

if ($Mode -in @('Import', 'Check', 'Qa') -or $Headless -or $QuitAfter -gt 0) {
    if ([string]::IsNullOrWhiteSpace($ProfileName)) {
        $ProfileName = if ($Script) { [IO.Path]::GetFileNameWithoutExtension($Script).Replace('_', '-') } else { $Mode.ToLowerInvariant() }
    }
    if ($ProfileName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]*$') { throw 'ProfileName must be a plain directory name.' }
    $taskProfile = Join-Path (Join-Path $taskProfilesRoot $ProfileName) ('run-' + [Guid]::NewGuid().ToString('N'))
    if ($TimeoutSeconds -eq 0) { $TimeoutSeconds = if ($Mode -eq 'Import') { 600 } else { 180 } }
} else {
    $taskProfile = Join-Path $taskLocalRoot $(if ($Mode -eq 'Edit') { 'editor' } else { 'player' })
}
$taskTemp = Join-Path $taskProfile 'temp'
New-Item -ItemType Directory -Path $taskProfile, $taskTemp, $taskLocalRoot, $taskProfilesRoot -Force | Out-Null
# Prevent the editor from importing local saves, logs or temporary QA scripts.
foreach ($taskIgnoredDirectory in @($taskLocalRoot, $taskProfilesRoot)) {
    $taskIgnoreFile = Join-Path $taskIgnoredDirectory '.gdignore'
    if (-not (Test-Path -LiteralPath $taskIgnoreFile)) { [IO.File]::WriteAllText($taskIgnoreFile, '') }
}
$taskLog = Join-Path $taskProfile 'godot.log'
$taskArguments += @('--log-file', $taskLog)
if ($UserArguments.Count -gt 0) { $taskArguments += @('--') + $UserArguments }

$taskStart = New-Object System.Diagnostics.ProcessStartInfo
$taskStart.FileName = $GodotPath
$taskStart.WorkingDirectory = $taskRoot
$taskStart.Arguments = ($taskArguments | ForEach-Object { ConvertTo-NativeArgument ([string]$_) }) -join ' '
$taskStart.UseShellExecute = $false
$taskStart.CreateNoWindow = $true
$taskStart.RedirectStandardOutput = $true
$taskStart.RedirectStandardError = $true
# Changes apply only to the child process. Real AppData and the calling shell stay intact.
$taskStart.EnvironmentVariables['APPDATA'] = $taskProfile
$taskStart.EnvironmentVariables['LOCALAPPDATA'] = $taskProfile
$taskStart.EnvironmentVariables['TEMP'] = $taskTemp
$taskStart.EnvironmentVariables['TMP'] = $taskTemp
$taskProcess = New-Object System.Diagnostics.Process
$taskProcess.StartInfo = $taskStart
$taskTimedOut = $false
$taskTerminationFailed = $false
try {
    if (-not $taskProcess.Start()) { throw 'Godot could not start.' }
    $taskStdout = $taskProcess.StandardOutput.ReadToEndAsync()
    $taskStderr = $taskProcess.StandardError.ReadToEndAsync()
    if ($TimeoutSeconds -gt 0) {
        if (-not $taskProcess.WaitForExit($TimeoutSeconds * 1000)) {
            $taskTimedOut = $true
            & (Join-Path $env:WINDIR 'System32/taskkill.exe') /PID $taskProcess.Id /T /F | Out-Null
            if (-not $taskProcess.WaitForExit(2000)) {
                try { $taskProcess.Kill() } catch { Write-Warning ('Could not stop this timed-out process: ' + $_.Exception.Message) }
                $taskTerminationFailed = -not $taskProcess.WaitForExit(2000)
            }
        }
    } else {
        $taskProcess.WaitForExit()
    }
    if ($taskTerminationFailed) {
        $taskOut = ''
        $taskErr = 'The run timed out, but Windows denied termination of the owned Godot process. PID: ' + $taskProcess.Id
    } else {
        $taskOut = $taskStdout.GetAwaiter().GetResult()
        $taskErr = $taskStderr.GetAwaiter().GetResult()
    }
    [IO.File]::WriteAllText((Join-Path $taskProfile 'stdout.log'), $taskOut)
    [IO.File]::WriteAllText((Join-Path $taskProfile 'stderr.log'), $taskErr)
    $taskExit = if ($taskTimedOut) { 124 } else { $taskProcess.ExitCode }
    # GDScript exceptions can otherwise leave a successful native exit status.
    if ($taskExit -eq 0 -and ($taskOut + $taskErr) -match 'SCRIPT ERROR:|Parse Error:|Failed to load script|Failed loading resource') {
        $taskExit = 1
    }
    $taskReceipt = [ordered]@{mode=$Mode; script=$Script; profile=$taskProfile; log=$taskLog; exitCode=$taskExit; timedOut=$taskTimedOut; processId=$taskProcess.Id; terminationFailed=$taskTerminationFailed}
    [IO.File]::WriteAllText((Join-Path $taskProfile 'run.json'), ($taskReceipt | ConvertTo-Json))
    Write-Output ($taskReceipt | ConvertTo-Json -Compress)
    if ($taskExit -ne 0) {
        if ($taskErr) { Write-Output $taskErr.Trim() }
        if ($taskOut) { Write-Output (($taskOut -split '\r?\n' | Select-Object -Last 20) -join [Environment]::NewLine) }
    }
    exit $taskExit
} finally {
    $taskProcess.Dispose()
}
