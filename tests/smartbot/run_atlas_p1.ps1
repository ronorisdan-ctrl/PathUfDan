# Endgame Phase 1A/1B smartbot check: atlas zones (atlas seed 1), Competent, balanced, tier-6 kit.
#   powershell -File tests\smartbot\run_atlas_p1.ps1 [-Jobs "1,0|41|r1;3,0|50|r3"] [-Classes "mage"] [-Runs 5]
# Each job is "hex|kit level|csv tag" (jobs separated by ';'); one CSV per tag: tests/smartbot/out/atlas_p1_<tag>.csv.
param(
  [string]$Jobs = "1,0|41|r1;-1,1|41|r1;0,1|41|r1;3,0|50|r3",
  [string]$Classes = "warrior,ranger,mage",
  [int]$Runs = 5,
  [string]$Godot = "W:\AI game\Godot_v4.0-stable_win64_console.exe"
)
$proj = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach ($job in $Jobs.Split(";")) {
  $p = $job.Split("|")
  foreach ($c in $Classes.Split(",")) {
    & $Godot --headless --fixed-fps 60 --path $proj res://tests/smartbot/smartbot.tscn -- `
      --class=$c --tier=6 --level=$($p[1]) "--dungeon=atlas:$($p[0])" --runs=$Runs --seed=900 --profile=Competent --build=balanced --jobs=$Runs "--out=res://tests/smartbot/out/atlas_p1_$($p[2]).csv" 2>&1 | Out-Null
  }
}
"done"
