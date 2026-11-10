# Endgame Phase 1D smartbot check: atlas zones with a forced zone mechanic (atlas seed 1), Competent, balanced, tier-6 kit.
#   powershell -File tests\smartbot\run_atlas_p1d.ps1 [-Jobs "2,-1|45|r2"] [-Mechs "glazed,unfinished"] [-Rots "0,3"] [-Classes "mage"] [-Runs 5]
# Each job is "hex|kit level|csv tag"; one CSV per tag, mechanic and Rot: tests/smartbot/out/atlas_p1d_<tag>_<mech>_rot<N>.csv.
# Compare with the 1C CSVs (atlas_p1c_<tag>_rot<N>.csv, no mechanic).
param(
  [string]$Jobs = "2,-1|45|r2",
  [string]$Mechs = "glazed,unfinished",
  [string]$Rots = "0,3",
  [string]$Classes = "warrior,ranger,mage",
  [int]$Runs = 5,
  [string]$Godot = "W:\AI game\Godot_v4.0-stable_win64_console.exe"
)
$proj = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach ($job in $Jobs.Split(";")) {
  $p = $job.Split("|")
  foreach ($m in $Mechs.Split(",")) {
    foreach ($rot in $Rots.Split(",")) {
      foreach ($c in $Classes.Split(",")) {
        & $Godot --headless --fixed-fps 60 --path $proj res://tests/smartbot/smartbot.tscn -- `
          --class=$c --tier=6 --level=$($p[1]) "--dungeon=atlas:$($p[0])" --rot=$rot --mechanic=$m --runs=$Runs --seed=900 --profile=Competent --build=balanced --jobs=$Runs "--out=res://tests/smartbot/out/atlas_p1d_$($p[2])_$($m)_rot$rot.csv" 2>&1 | Out-Null
      }
    }
  }
}
"done"
