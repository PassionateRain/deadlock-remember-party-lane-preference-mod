# After a Deadlock update: checks whether the game files this mod overrides or depends on have changed.
#   1. Decompiles the game's current party popup + party bar layouts and diffs them against the vanilla
#      baseline in vanilla\ (the versions src\mod was built from).
#   2. Checks every ID / class / token / event the mod's scripts rely on still exists.
# Read-only on the game folder. Usage:
#   .\tools\check-game-update.ps1                  # check
#   .\tools\check-game-update.ps1 -SaveBaseline    # after updating src\mod: store current layouts as the new baseline
param(
    [string]$Game = 'C:\Program Files (x86)\Steam\steamapps\common\Deadlock\game\citadel',
    [switch]$SaveBaseline
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$s2v = Join-Path $PSScriptRoot 's2v\Source2Viewer-CLI.exe'
$vpk = Join-Path $Game 'pak01_dir.vpk'
$out = Join-Path $root 'build\check'
$baseline = Join-Path $root 'vanilla'

if (-not (Test-Path $s2v)) { throw "Source 2 Viewer CLI not found at $s2v (download cli-windows-x64.zip from github.com/ValveResourceFormat/ValveResourceFormat/releases)" }

$inf = Get-Content (Join-Path $Game 'steam.inf') -ErrorAction SilentlyContinue
Write-Host ("Game: " + (($inf | Where-Object { $_ -match '^(ClientVersion|VersionDate)=' }) -join ', '))

$layouts = @{
    'popup_join_or_create_party.xml' = 'panorama/layout/popups/popup_join_or_create_party.vxml_c'
    'citadel_party.xml'              = 'panorama/layout/citadel_party.vxml_c'
}

if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force $out | Out-Null
foreach ($name in $layouts.Keys) {
    & $s2v -i $vpk -o (Join-Path $out $name) -d -f $layouts[$name] | Out-Null
    if (-not (Test-Path (Join-Path $out $name))) { throw "Could not decompile $($layouts[$name]): file moved or renamed?" }
}

if ($SaveBaseline) {
    New-Item -ItemType Directory -Force $baseline | Out-Null
    Copy-Item (Join-Path $out '*.xml') $baseline -Force
    Write-Host "Baseline saved to $baseline"
    return
}

# 1. Layout diffs (ignoring the decompiler's header comment).
$changed = $false
foreach ($name in $layouts.Keys) {
    $base = Join-Path $baseline $name
    if (-not (Test-Path $base)) { Write-Host "[??] $name : no baseline in vanilla\ (run with -SaveBaseline on a known-good game version)"; continue }
    $a = Get-Content $base | Where-Object { $_ -notmatch '^<!-- xml reconstructed' }
    $b = Get-Content (Join-Path $out $name) | Where-Object { $_ -notmatch '^<!-- xml reconstructed' }
    $diff = Compare-Object $a $b
    if ($diff) {
        $changed = $true
        Write-Host "[CHANGED] $name : Valve changed this layout; merge their changes into src\mod (see MAINTENANCE.md)"
        $diff | ForEach-Object { '    ' + ($(if ($_.SideIndicator -eq '=>') { 'NEW ' } else { 'OLD ' })) + $_.InputObject.Trim() } | Write-Host
    } else {
        Write-Host "[ok] $name unchanged"
    }
}

# 2. Dependencies the scripts rely on.
$popup = Get-Content (Join-Path $out 'popup_join_or_create_party.xml') -Raw
$bar = Get-Content (Join-Path $out 'citadel_party.xml') -Raw
$css = [Text.Encoding]::UTF8.GetString((& {
    $tmp = Join-Path $out 'css'
    & (Join-Path $PSScriptRoot 'vpk.ps1') extract -Vpk $vpk -Filter '^panorama/styles/(citadel_party|citadel_base_styles)\.vcss_c$' -Out $tmp | Out-Null
    Get-ChildItem $tmp -Recurse -File | ForEach-Object { [IO.File]::ReadAllBytes($_.FullName) } | ForEach-Object { $_ }
}))
$loc = Get-Content (Join-Path $Game 'resource\localization\citadel_main\citadel_main_english.txt') -Raw -ErrorAction SilentlyContinue

$checks = @(
    @('popup: #LanePreferenceSelector dropdown', $popup, 'id="LanePreferenceSelector"'),
    @('popup: option lanepreference_0 (Balanced)', $popup, 'id="lanepreference_0"'),
    @('popup: option lanepreference_1 (With Party)', $popup, 'id="lanepreference_1"'),
    @('popup: #EscapeButton (auto-close)', $popup, 'id="EscapeButton"'),
    @('popup: root panel PopupJoinOrCreateParty', $popup, '<PopupJoinOrCreateParty'),
    @('bar: #JoinCreateParty button (auto-open)', $bar, 'id="JoinCreateParty"'),
    @('bar: #PartyMembersList', $bar, 'id="PartyMembersList"'),
    @('bar: PartyMember snippet', $bar, 'class="PartyMember"'),
    @('css: .PartyMember.Empty class', $css, '.PartyMember.Empty'),
    @('css: .PartyMember.Invited class', $css, '.PartyMember.Invited'),
    @('css: ShowEscapeMenu class', $css, '.ShowEscapeMenu'),
    @('css: ToggleButton base style', $css, 'ToggleButton'),
    @('loc: #Citadel_LanePreference_WithParty', $loc, 'Citadel_LanePreference_WithParty'),
    @('loc: #Citadel_LanePreference_BalancedLanes', $loc, 'Citadel_LanePreference_BalancedLanes'),
    @('loc: #Citadel_LanePreference_Title', $loc, 'Citadel_LanePreference_Title')
)
$missing = 0
foreach ($c in $checks) {
    if ($c[1] -and $c[1].Contains($c[2])) { Write-Host "[ok] $($c[0])" }
    else { Write-Host "[MISSING] $($c[0])  (looked for: $($c[2]))"; $missing++ }
}

Write-Host ''
if (-not $changed -and $missing -eq 0) { Write-Host 'Nothing the mod depends on changed. If it still misbehaves, see the symptom table in MAINTENANCE.md.' }
else { Write-Host "Action needed: $missing missing dependencies, layouts changed: $changed. See MAINTENANCE.md > Updating after a game patch." }
