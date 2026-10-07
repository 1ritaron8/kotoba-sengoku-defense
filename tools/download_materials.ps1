$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskMaterialRoot = Join-Path $taskRoot 'assets/materials'
$taskMetadataRoot = Join-Path $PSScriptRoot 'art-research'
New-Item -ItemType Directory -Path $taskMaterialRoot, $taskMetadataRoot -Force | Out-Null
$taskMaterials = @()
foreach ($taskId in @('metal_plate_02', 'denim_fabric', 'brown_leather')) {
    $taskFiles = Get-Content -LiteralPath (Join-Path $taskMetadataRoot ($taskId + '-files.json')) -Raw | ConvertFrom-Json
    $taskDirectory = Join-Path $taskMaterialRoot $taskId
    New-Item -ItemType Directory -Path $taskDirectory -Force | Out-Null
    $taskDownloads = @()
    foreach ($taskChannel in @('nor_gl', 'rough', 'diff')) {
        $taskSourceChannel = if ($taskChannel -eq 'diff') { 'Diffuse' } else { $taskChannel }
        $taskEntry = $taskFiles.$taskSourceChannel.'1k'.jpg
        if ($null -eq $taskEntry) { throw ('Missing texture channel: ' + $taskId + '/' + $taskChannel) }
        $taskOutput = Join-Path $taskDirectory ($taskChannel + '.jpg')
        if (-not (Test-Path -LiteralPath $taskOutput)) {
            Invoke-WebRequest -Uri $taskEntry.url -OutFile $taskOutput -Headers @{ 'User-Agent'='KotobaSengokuAssetResearch/1.0' }
        }
        $taskHash = (Get-FileHash -LiteralPath $taskOutput -Algorithm MD5).Hash.ToLowerInvariant()
        if ($taskHash -ne $taskEntry.md5) { throw ('Download checksum mismatch: ' + $taskOutput) }
        $taskDownloads += @{ channel=$taskChannel; path=('res://assets/materials/' + $taskId + '/' + $taskChannel + '.jpg'); url=$taskEntry.url; md5=$taskHash; bytes=(Get-Item -LiteralPath $taskOutput).Length }
    }
    $taskMaterials += @{ id=$taskId; source=('https://polyhaven.com/a/' + $taskId); license='CC0-1.0'; licenseUrl='https://polyhaven.com/license'; files=$taskDownloads; use='Surface colour, normal and roughness maps with game-authored colour tint and UV scale.' }
}
@{ materials=$taskMaterials } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $taskRoot 'native/material_sources.json') -Encoding utf8
$taskMaterials | ForEach-Object { [PSCustomObject]@{ id=$_.id; files=$_.files.Count; bytes=($_.files | Measure-Object -Property bytes -Sum).Sum } }
