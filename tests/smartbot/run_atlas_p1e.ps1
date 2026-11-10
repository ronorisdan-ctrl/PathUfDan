# Endgame Phase 1E smartbot check: atlas zones with forced Rot and slotted Pigments (atlas seed 1), Competent, balanced, tier-6 kit.
#   powershell -File tests\smartbot\run_atlas_p1e.ps1 [-Jobs "3,0|50|r3"] [-Rots "4"] [-Pigments "glazed,unfinished"] [-Mech none] [-Varnish ""] [-Tag v1] [-Classes "mage"] [-Runs 5]
# -Pigments: comma list of mechanic[:modifier] (no modifier = seeded); -Mech: the natural mechanic ("none" = only the Pigments).
# One CSV per job tag and Rot: tests/smartbot/out/atlas_p1e_<tag>_<Tag>_rot<N>.csv.
param(
  [string]$Jobs = "3,0|50|r3",
  [string]$Rots = "4",
  [string]$Pigments = "glazed,unfinished",
  [string]$Mech = "none",
  [string]$Varnish = "",
  [string]$Tag = "p2",
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
      $extra = @()
      if ($Pigments -ne "") { $extra += "--pigments=$Pigments" }
      if ($Varnish -ne "") { $extra += "--varnish=$Varnish" }
      & $Godot --headless --fixed-fps 60 --path $proj res://tests/smartbot/smartbot.tscn -- `
        --class=$c --tier=6 --level=$($p[1]) "--dungeon=atlas:$($p[0])" --rot=$rot --mechanic=$Mech @extra --runs=$Runs --seed=$Seed --profile=Competent --build=balanced --jobs=$Runs "--out=res://tests/smartbot/out/atlas_p1e_$($p[2])_$($Tag)_rot$rot.csv" 2>&1 | Out-Null
    }
  }
}
"done"
