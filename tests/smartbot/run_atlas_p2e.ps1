# Endgame Phase 2E smartbot runs: the Collector's Wager (one bet forced per batch) and Pentimento Vaults.
# Atlas seed 1, Competent, balanced, tier-6 kit, Rot -Rot, no Pigments.
#   powershell -File tests\smartbot\run_atlas_p2e.ps1 [-Bets "boss_rush,frenzy"] [-Jobs "2,-1|45|r2;3,0|50|r3"] [-Stake 1] [-Tag v1] [-Classes "mage"] [-Runs 5]
#   -Bets vault   = no bet, Vaults forced (vault tuning)
#   -Bets warden  = no bet, no mechanic, the ring's Layer Warden summoned (mage / dodge checks)
#   -Bets plain   = no bet, no mechanic (Rot checks)
#   -Set "group_perception:false"  profile override (smartbot --set)
# One CSV per bet, job and Rot: tests/smartbot/out/atlas_p2e_<bet>_<job>_<Tag>_rot<N>.csv.
param(
  [string]$Bets = "unscathed,boss_rush,few_skills,frenzy,abstinence,iron_will,flaking,colourist,archaeology",
  [string]$Jobs = "2,-1|45|r2;3,0|50|r3",
  [string]$Rots = "0",
  [int]$Stake = 1,
  [string]$Tag = "v1",
  [string]$Classes = "warrior,ranger,mage",
  [int]$Runs = 5,
  [int]$Seed = 900,
  [int]$Par = 6,
  [string]$Set = "",
  [string]$VaultType = "",
  [string]$Godot = "W:\AI game\Godot_v4.0-stable_win64_console.exe"
)
$proj = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$mech = @{ "flaking" = "wager,glazed"; "colourist" = "wager,unfinished"; "archaeology" = "wager,vault"; "vault" = "vault"; "warden" = "none"; "plain" = "none" }
foreach ($bet in $Bets.Split(",")) {
  $m = $mech[$bet]; if (-not $m) { $m = "wager" }
  $w = $bet; if ($bet -in @("vault", "warden", "plain")) { $w = "none" }
  $extra = @(); if ($bet -eq "warden") { $extra += "--warden=1" }; if ($Set -ne "") { $extra += "--set=$Set" }; if ($VaultType -ne "") { $extra += "--vault_type=$VaultType" }; if ($bet -eq "archaeology") { $extra += "--vaults=0" }   # measure Archaeology with the vault still sealed at the Collector
  foreach ($job in $Jobs.Split(";")) {
    $p = $job.Split("|")
    foreach ($rot in $Rots.Split(",")) {
      foreach ($c in $Classes.Split(",")) {
        & $Godot --headless --fixed-fps 60 --path $proj res://tests/smartbot/smartbot.tscn -- `
          --class=$c --tier=6 --level=$($p[1]) "--dungeon=atlas:$($p[0])" --rot=$rot "--mechanic=$m" --wager=$w --stake=$Stake --runs=$Runs --seed=$Seed --profile=Competent --build=balanced --jobs=$Par @extra "--out=res://tests/smartbot/out/atlas_p2e_$($bet)_$($p[2])_$($Tag)_rot$rot.csv" 2>&1 | Out-Null
      }
    }
  }
  "bet $bet done"
}
"done"
