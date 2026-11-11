# Endgame Phase 3C smartbot runs: the Burning Canvas and the Pigment Wells (docs/ENDGAME_PHASE3.md, Stage 3C).
# Atlas seed 1, ring 3 hex 3,0 (level 50), Competent, balanced, typical gear (Phase C plans: warrior w_earthbreaker,
# ranger none, mage m_embers), no Pigments, no Collector.
#   powershell -File tests\smartbot\run_atlas_p3c.ps1 [-Cells "plain,burn,wells"] [-Rots "0,3"] [-Runs 10] [-Tag v1]
#   -Cells   plain = no mechanic (the reference), burn = Burning Canvas forced, wells = Pigment Wells forced,
#            sweep = Burning Canvas at each -ArenaTimes value (front speed sweep; Rot from -Rots)
#   -ArenaTimes "140,170,230"   mechanics.burning.arena_time values for the sweep (--tune=mech.burning.arena_time=N)
# One CSV per cell, Rot and class: tests/smartbot/out/p3c/typical_<class>_<cell>_rot<N>_<Tag>.csv.
# Summary: python tests/smartbot/p3c_summary.py [--tag v1]
param(
  [string]$Cells = "plain,burn,wells",
  [string]$Rots = "0,3",
  [string]$Classes = "warrior,ranger,mage",
  [int]$Runs = 10,
  [int]$Seed = 900,
  [string]$Tag = "v1",
  [string]$ArenaTimes = "140,170,230",
  [string]$Godot = "W:\AI game\Godot_v4.0-stable_win64_console.exe"
)
$proj = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$plans = @{ "warrior" = "w_earthbreaker"; "ranger" = "none"; "mage" = "m_embers" }
$outdir = Join-Path $proj "tests\smartbot\out\p3c"
New-Item -ItemType Directory -Force -Path $outdir | Out-Null
foreach ($cell in $Cells.Split(",")) {
  $variants = @(@{ name = $cell; tune = "" })
  if ($cell -eq "sweep") {
    $variants = @()
    foreach ($at in $ArenaTimes.Split(",")) { $variants += @{ name = "sweep$at"; tune = "mech.burning.arena_time=$at" } }
  }
  $mech = @{ "plain" = "none"; "burn" = "burning"; "wells" = "wells"; "sweep" = "burning" }[$cell]
  foreach ($v in $variants) {
    foreach ($rot in $Rots.Split(",")) {
      foreach ($c in $Classes.Split(",")) {
        $name = "typical_$($c)_$($v.name)_rot$($rot)_$Tag"
        $csv = Join-Path $outdir "$name.csv"
        if (Test-Path $csv) {
          $n = (Import-Csv $csv | Measure-Object).Count
          if ($n -ge $Runs) { "skip $name ($n rows)"; continue }
          Remove-Item $csv -Force
        }
        foreach ($d in @("$outdir\$($name)_rows", "$outdir\$($name)_ckpt")) { if (Test-Path $d) { Remove-Item $d -Recurse -Force } }
        $extra = @()
        if ($v.tune -ne "") { $extra += "--tune=$($v.tune)" }
        & $Godot --headless --fixed-fps 60 --path $proj res://tests/smartbot/smartbot.tscn -- `
          --class=$c --tier=6 --level=50 "--dungeon=atlas:3,0" --rot=$rot "--mechanic=$mech" --wager=none --runs=$Runs --seed=$Seed `
          --profile=Competent --build=balanced --gear=typical "--plan=$($plans[$c])" --jobs=$Runs @extra "--out=res://tests/smartbot/out/p3c/$name.csv" 2>&1 | Out-File "$outdir\$name.log"
        $rows = 0; if (Test-Path $csv) { $rows = (Import-Csv $csv | Measure-Object).Count }
        $err = Select-String -Path "$outdir\$name.log" -Pattern "SCRIPT ERROR" -Quiet
        "$name rows=$rows $(if ($err) { 'SCRIPT ERROR' })"
      }
    }
  }
}
"done"
