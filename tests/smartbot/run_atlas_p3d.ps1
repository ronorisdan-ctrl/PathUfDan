# Endgame Phase 3D smartbot runs: the Overpainter, Apprentice (docs/ENDGAME_PHASE3.md, Stage 3D).
# Level 60 (the cap), Competent, balanced, typical gear with ring-6 bases (Phase C plans: warrior
# w_earthbreaker, ranger none, mage m_embers), no brush equipped. Each run is one fight; the Ground
# Pigment set is granted. The list order is also the Warden first-kill order (the phase 1 studies).
#   powershell -File tests\smartbot\run_atlas_p3d.ps1 [-Sets "1,2,3,4;3,4,5,6;1,3,5,6"] [-Runs 10] [-Tag v1] [-Tune "pinnacle.life_mult=10"]
#   -Sets   ;-separated Ground Pigment sets: early (1,2,3,4), late (3,4,5,6), mixed (1,3,5,6)
#   -Tune   --tune passed through (e.g. pinnacle.life_mult=10;pinnacle.damage_mult=1.5)
# One CSV per set and class: tests/smartbot/out/p3d/typical_<class>_set<abcd>_<Tag>.csv.
# Summary: python tests/smartbot/p3d_summary.py [--tag v1]
param(
  [string]$Sets = "1,2,3,4;3,4,5,6;1,3,5,6",
  [string]$Classes = "warrior,ranger,mage",
  [int]$Runs = 10,
  [int]$Seed = 900,
  [string]$Tag = "v1",
  [string]$Tune = "",
  [int]$Timeout = 600,
  [string]$Godot = "W:\AI game\Godot_v4.0-stable_win64_console.exe"
)
$proj = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$plans = @{ "warrior" = "w_earthbreaker"; "ranger" = "none"; "mage" = "m_embers" }
$outdir = Join-Path $proj "tests\smartbot\out\p3d"
New-Item -ItemType Directory -Force -Path $outdir | Out-Null
foreach ($set in $Sets.Split(";")) {
  $sname = "set" + ($set -replace ",", "")
  foreach ($c in $Classes.Split(",")) {
    $name = "typical_$($c)_$($sname)_$Tag"
    $csv = Join-Path $outdir "$name.csv"
    if (Test-Path $csv) {
      $n = (Import-Csv $csv | Measure-Object).Count
      if ($n -ge $Runs) { "skip $name ($n rows)"; continue }
      Remove-Item $csv -Force
    }
    foreach ($d in @("$outdir\$($name)_rows", "$outdir\$($name)_ckpt")) { if (Test-Path $d) { Remove-Item $d -Recurse -Force } }
    $extra = @()
    if ($Tune -ne "") { $extra += "--tune=$Tune" }
    & $Godot --headless --fixed-fps 60 --path $proj res://tests/smartbot/smartbot.tscn -- `
      --class=$c --tier=6 --level=60 "--pinnacle=$set" --mechanic=none --wager=none --runs=$Runs --seed=$Seed --timeout=$Timeout `
      --profile=Competent --build=balanced --gear=typical "--plan=$($plans[$c])" --jobs=$Runs @extra "--out=res://tests/smartbot/out/p3d/$name.csv" 2>&1 | Out-File "$outdir\$name.log"
    $rows = 0; if (Test-Path $csv) { $rows = (Import-Csv $csv | Measure-Object).Count }
    $err = Select-String -Path "$outdir\$name.log" -Pattern "SCRIPT ERROR" -Quiet
    "$name rows=$rows $(if ($err) { 'SCRIPT ERROR' })"
  }
}
"done"
