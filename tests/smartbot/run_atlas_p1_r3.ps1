# Endgame Phase 1A/1B smartbot check: atlas zones (atlas seed 1), Competent, balanced, tier-6 kit.
#   powershell -File tests\smartbot\run_atlas_p1.ps1
param([string]$Godot = "W:\AI game\Godot_v4.0-stable_win64_console.exe")
$proj = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$jobs = @(
  @("3,0", 50, "r3")
)
foreach ($j in $jobs) {
  foreach ($c in "warrior", "ranger", "mage") {
    $out = "res://tests/smartbot/out/atlas_p1_$($j[2]).csv"
    & $Godot --headless --fixed-fps 60 --path $proj res://tests/smartbot/smartbot.tscn -- `
      --class=$c --tier=6 --level=$($j[1]) --dungeon=atlas:$($j[0]) --runs=5 --seed=900 --profile=Competent --build=balanced --jobs=5 --out=$out 2>&1 | Out-Null
  }
}
"done"
