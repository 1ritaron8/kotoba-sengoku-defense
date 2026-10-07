param([switch]$SkipImport, [string]$ArtRevision = 'casual-v6')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskGodot = Join-Path $PSScriptRoot 'godot/Godot_v4.7.2-stable_win64_console.exe'
$taskOutput = Join-Path $taskRoot 'dist'
$taskProfile = Join-Path $taskRoot 'tests/profiles/casual-build'
New-Item -ItemType Directory -Path $taskOutput, $taskProfile -Force | Out-Null
$env:APPDATA = $taskProfile
$env:LOCALAPPDATA = $taskProfile
$taskMapsPath = Join-Path $taskRoot 'native/maps.json'
$taskArtPath = Join-Path $taskRoot 'assets/battlefields-rendered/manifest.json'
$taskMaps = @(Get-Content -LiteralPath $taskMapsPath -Raw | ConvertFrom-Json)
$taskArt = Get-Content -LiteralPath $taskArtPath -Raw | ConvertFrom-Json
$taskMapsSha = (Get-FileHash -LiteralPath $taskMapsPath -Algorithm SHA256).Hash.ToLowerInvariant()
if (-not $taskArt.complete -or $taskArt.expectedStageCount -ne 40 -or $taskMaps.Count -ne 40 -or $taskArt.stages.Count -ne 40 -or $taskArt.sourceMapsSha256 -ne $taskMapsSha) {
    throw 'Release requires forty complete battlefield images bound to the current maps.'
}
$taskImageHashes = @{}
for ($taskIndex = 0; $taskIndex -lt 40; $taskIndex++) {
    $taskMap = $taskMaps[$taskIndex]
    $taskEntry = $taskArt.stages[$taskIndex]
    $taskExpectedPath = 'res://assets/battlefields-rendered/stage-{0:D2}-{1}-{2}.png' -f ($taskIndex + 1), $taskMap.id, $ArtRevision
    if ($taskEntry.stageId -ne $taskMap.id -or $taskEntry.stageNumber -ne ($taskIndex + 1) -or $taskEntry.path -cne $taskExpectedPath -or -not $taskEntry.review.assetInspected -or -not $taskEntry.review.inGameReviewed) {
        throw "Battlefield $($taskIndex + 1) is missing its exact reviewed release image."
    }
    $taskImagePath = Join-Path $taskRoot $taskEntry.path.Substring(6)
    if (-not (Test-Path -LiteralPath $taskImagePath -PathType Leaf)) { throw "Missing battlefield image: $taskImagePath" }
    $taskImageSha = (Get-FileHash -LiteralPath $taskImagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($taskImageSha -ne $taskEntry.sha256 -or $taskImageHashes.ContainsKey($taskImageSha)) { throw "Unverified or reused battlefield image: $taskImagePath" }
    $taskImageHashes[$taskImageSha] = $true
    $taskImageBytes = [System.IO.File]::ReadAllBytes($taskImagePath)
    if ($taskImageBytes.Length -lt 24 -or [BitConverter]::ToString($taskImageBytes, 0, 8) -ne '89-50-4E-47-0D-0A-1A-0A') { throw "Invalid PNG: $taskImagePath" }
    $taskImageWidth = [uint32]$taskImageBytes[16] * 16777216 + [uint32]$taskImageBytes[17] * 65536 + [uint32]$taskImageBytes[18] * 256 + [uint32]$taskImageBytes[19]
    $taskImageHeight = [uint32]$taskImageBytes[20] * 16777216 + [uint32]$taskImageBytes[21] * 65536 + [uint32]$taskImageBytes[22] * 256 + [uint32]$taskImageBytes[23]
    if ($taskImageWidth -ne $taskEntry.width -or $taskImageHeight -ne $taskEntry.height -or $taskImageWidth -lt 1280 -or $taskImageHeight -lt 720 -or $taskImageWidth / $taskImageHeight -le 1.7 -or $taskImageWidth / $taskImageHeight -ge 1.85) { throw "Battlefield dimensions do not match the release record: $taskImagePath" }
}
if (-not $SkipImport) {
    & $taskGodot --headless --editor --path $taskRoot --quit
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
}
& $taskGodot --headless --path $taskRoot --export-release 'Windows Desktop' (Join-Path $taskOutput 'KotobaSengoku.exe')
if ($LASTEXITCODE -ne 0) { throw 'Godot export failed.' }
& $taskGodot --headless --path $taskRoot --script 'res://tools/license.gd'
if ($LASTEXITCODE -ne 0) { throw 'License generation failed.' }
$taskPayloadFiles = @(
    (Join-Path $taskOutput 'KotobaSengoku.exe'),
    (Join-Path $taskOutput 'ThirdParty.txt'),
    (Join-Path $taskOutput 'READ_ME.txt'),
    (Join-Path $taskRoot 'assets/fonts/OFL.txt'),
    (Join-Path $taskRoot 'assets/fonts/OFL-NotoSerifCJK.txt'),
    (Join-Path $taskRoot 'assets/fonts/OFL-NanumMyeongjo.txt'),
    (Join-Path $taskRoot 'assets/fonts/OFL-YujiSyuku.txt'),
    (Join-Path $taskRoot 'assets/fonts/OFL-KleeOne.txt')
)
Compress-Archive -LiteralPath $taskPayloadFiles -DestinationPath (Join-Path $taskOutput 'payload.zip') -Force
$taskCsc = 'C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $taskCsc /nologo /target:winexe /optimize+ '/reference:System.Windows.Forms.dll' '/reference:System.Drawing.dll' '/reference:System.IO.Compression.dll' '/reference:System.IO.Compression.FileSystem.dll' ('/resource:' + (Join-Path $taskOutput 'payload.zip') + ',payload.zip') ('/out:' + (Join-Path $taskOutput 'KotobaSengoku-Setup.exe')) (Join-Path $PSScriptRoot 'Installer.cs')
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed.' }
Get-ChildItem -LiteralPath (Join-Path $taskOutput 'KotobaSengoku.exe'), (Join-Path $taskOutput 'KotobaSengoku-Setup.exe') | Select-Object Name, Length
