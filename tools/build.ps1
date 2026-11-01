# Compiles a panorama mod source tree with the CS2 Workshop Tools and packs it into a VPK.
# Usage:
#   .\tools\build.ps1 -Src src\probe -Name party_lane_probe
#
# Install the resulting VPK through Deadlock Mod Manager (it owns the addons folder and pak numbering).
#
# Source layout mirrors the game: <Src>\panorama\layout\*.xml, <Src>\panorama\scripts\*.js,
# <Src>\panorama\styles\*.css. Output: build\<Name>\ (compiled files) and build\<Name>.vpk.
param(
    [Parameter(Mandatory)] [string]$Src,
    [Parameter(Mandatory)] [string]$Name,
    [string]$Cs2 = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent

function Find-Cs2 {
    $vdf = 'C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf'
    $libs = Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' |
        ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
    foreach ($l in $libs) {
        $p = Join-Path $l 'steamapps\common\Counter-Strike Global Offensive'
        if (Test-Path (Join-Path $p 'game\bin\win64\resourcecompiler.exe')) { return $p }
    }
    throw 'CS2 Workshop Tools not found (no resourcecompiler.exe). Install CS2 + its Workshop Tools DLC.'
}

if (-not $Cs2) { $Cs2 = Find-Cs2 }
$bin = Join-Path $Cs2 'game\bin\win64'
$rc = Join-Path $bin 'resourcecompiler.exe'

$srcDir = (Resolve-Path (Join-Path $root $Src)).Path
$contentDir = Join-Path $Cs2 "content\csgo_addons\$Name"
$gameDir = Join-Path $Cs2 "game\csgo_addons\$Name"
$outDir = Join-Path $root "build\$Name"

# 1. Mirror source into the CS2 addon content folder (clean so removed files don't linger).
if (Test-Path $contentDir) { Remove-Item -Recurse -Force $contentDir }
if (Test-Path $gameDir) { Remove-Item -Recurse -Force $gameDir }
New-Item -ItemType Directory -Force $contentDir | Out-Null
Copy-Item -Recurse (Join-Path $srcDir '*') $contentDir

# 2. Compile every source file. Layouts reference our scripts as .vjs_c, so compile scripts first.
$files = Get-ChildItem $contentDir -Recurse -File -Include *.js, *.css, *.xml |
    Sort-Object { switch ($_.Extension) { '.js' { 0 } '.css' { 1 } default { 2 } } }
foreach ($f in $files) {
    Write-Host "compile $($f.FullName.Substring($contentDir.Length + 1))"
    & $rc -game (Join-Path $Cs2 'game\csgo') -i $f.FullName
    if ($LASTEXITCODE -ne 0) { throw "resourcecompiler failed on $($f.Name) (exit $LASTEXITCODE)" }
}

# 3. Collect compiled output. resourcecompiler names layouts .vxml_c, scripts .vjs_c, styles .vcss_c.
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
New-Item -ItemType Directory -Force $outDir | Out-Null
Get-ChildItem $gameDir -Recurse -File -Include *.vxml_c, *.vjs_c, *.vcss_c | ForEach-Object {
    $rel = $_.FullName.Substring($gameDir.Length + 1)
    $dest = Join-Path $outDir $rel
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    Copy-Item $_.FullName $dest
    Write-Host "  -> $rel"
}

# 4. Pack. CS2 doesn't ship vpk.exe, so use our own single-file VPK v2 packer.
$vpkOut = "$outDir.vpk"
if (Test-Path $vpkOut) { Remove-Item $vpkOut }
& (Join-Path $PSScriptRoot 'vpkpack.ps1') -Dir $outDir -Out $vpkOut
if (-not (Test-Path $vpkOut)) { throw 'vpk.exe did not produce a package' }
Write-Host "built $vpkOut (add it in Deadlock Mod Manager)"
