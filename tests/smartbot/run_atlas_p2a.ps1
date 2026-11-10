# Endgame Phase 2A smartbot check: Layer Warden runs (atlas seed 1, --warden=1 summons the ring's Warden
# at the target hex every run), Competent, balanced, tier-6 kit, no mechanic, no Pigments.
#   powershell -File tests\smartbot\run_atlas_p2a.ps1 [-Jobs "1,0|41|r1;2,-1|45|r2;3,0|50|r3"] [-Rots "0"] [-Tag v1] [-Classes "mage"] [-Runs 5]
# One CSV per job tag and Rot: tests/smartbot/out/atlas_p2a_<tag>_<Tag>_rot<N>.csv.
param(
  [string]$Jobs = "1,0|41|r1;2,-1|45|r2;3,0|50|r3",
  [string]$Rots = "0",
  [string]$Tag = "v1",
  [string]$Classes = "warrior,ranger,mage",
  [int]$Runs = 5,
  [int]$Seed = 900,
  [string]$Godot = "W:\AI game\Godot_v4.0-stable_win64_console.exe"
)
$proj = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach ($job in $Jobs.Split(";")) {
  $p = $job.Split("|")
  foreach ($rot in $Rots.Split(",")) {
    foreach ($c in $Classes.Split(",")) {
      & $Godot --headless --fixed-fps 60 --path $proj res://tests/smartbot/smartbot.tscn -- `
        --class=$c --tier=6 --level=$($p[1]) "--dungeon=atlas:$($p[0])" --rot=$rot --mechanic=none --warden=1 --runs=$Runs --seed=$Seed --profile=Competent --build=balanced --jobs=$Runs "--out=res://tests/smartbot/out/atlas_p2a_$($p[2])_$($Tag)_rot$rot.csv" 2>&1 | Out-Null
    }
  }
}
"done"
