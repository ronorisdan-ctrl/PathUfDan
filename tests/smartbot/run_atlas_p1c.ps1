# Endgame Phase 1C smartbot check: atlas zones with forced Rot (atlas seed 1), Competent, balanced, tier-6 kit.
#   powershell -File tests\smartbot\run_atlas_p1c.ps1 [-Jobs "2,-1|45|r2;3,0|50|r3"] [-Rots "0,3,5"] [-Classes "mage"] [-Runs 5]
# Each job is "hex|kit level|csv tag"; one CSV per tag and Rot: tests/smartbot/out/atlas_p1c_<tag>_rot<N>.csv.
param(
  [string]$Jobs = "2,-1|45|r2;3,0|50|r3",
  [string]$Rots = "0,3,5",
  [string]$Classes = "warrior,ranger,mage",
  [int]$Runs = 5,
  [string]$Godot = "W:\AI game\Godot_v4.0-stable_win64_console.exe"
)
$proj = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach ($job in $Jobs.Split(";")) {
  $p = $job.Split("|")
  foreach ($rot in $Rots.Split(",")) {
    foreach ($c in $Classes.Split(",")) {
      & $Godot --headless --fixed-fps 60 --path $proj res://tests/smartbot/smartbot.tscn -- `
        --class=$c --tier=6 --level=$($p[1]) "--dungeon=atlas:$($p[0])" --rot=$rot --runs=$Runs --seed=900 --profile=Competent --build=balanced --jobs=$Runs "--out=res://tests/smartbot/out/atlas_p1c_$($p[2])_rot$rot.csv" 2>&1 | Out-Null
    }
  }
}
"done"
