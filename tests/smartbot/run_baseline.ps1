# Frozen smartbot baseline for the passive tree plan (Phase 1).
# 3 classes x tiers 3 and 6 x 10 runs, Competent, balanced build, seed 1000.
#   powershell -File tests\smartbot\run_baseline.ps1 [-Out res://tests/smartbot/out/check.csv] [-Godot <exe>]
# Then: python tests\smartbot\compare_baseline.py tests\smartbot\baseline\caster_v1.csv tests\smartbot\out\check.csv
param(
  [string]$Out = "res://tests/smartbot/out/baseline_check.csv",
  [string]$Godot = "W:\AI game\Godot_v4.0-stable_win64_console.exe"
)
$proj = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach ($tier in 3, 6) {
  foreach ($c in "warrior", "ranger", "mage") {
    & $Godot --headless --fixed-fps 60 --path $proj res://tests/smartbot/smartbot.tscn -- `
      --class=$c --tier=$tier --runs=10 --seed=1000 --profile=Competent --build=balanced --jobs=10 --out=$Out | Out-Null
  }
}
"done: $Out"
