# Smartbot Phase C: real-run measurements with typical and geared gear

2026-11-07 · Claude (Cowork) for Dan · follows `docs/BOT_GEAR_AUDIT.md` (Phase A) and `docs/BOT_GEAR_PROFILES.md` (Phase B)

All runs were on Dan's PC (Godot 4.0 win64 console, headless, `--fixed-fps 60`, ts 1). 72 matrix batches + 6 side batches + 9 ranger-analyser batches, 870 runs, **0 script errors**. Only `tests/smartbot/` and `docs/` changed. No game file changed. Nothing is committed.

## 1. Summary

- **Ranger rework first (Dan's choice).** I added three ranger builds. Two change how the bot plays the keystone: `r_far_aim` holds a 190-290 range band for Perfect Aim, and `r_wind_roll` rolls in combat to keep Wind Dance up. The third, `r_glass`, takes Glass Cannon, 6 points from the start. **None beats having no keystone** (best: Glass Cannon 1.07x, Perfect Aim 1.08x). How the bot plays the keystones doesn't explain the loss. The ranger keystones look weak compared with what the same points buy elsewhere on the tree (Phase D, game side). Phase C runs the ranger with `--plan=none`.
- **Typical and geared bots win everything.** 10/10 boss and Warden kills in every typical and geared cell, with one exception: a no-keystone mage side cell lost 1 run to the Gravemaw. The only deaths in the main matrix are in legacy W2 (ranger 1, mage 2).
- **Typical gear cuts clear time by 10-60% and damage taken by 50-90% against legacy.** Warrior and mage gain the most. Geared is another 10-25% faster. Rot, Wager and Warden targets measured with legacy bots will be too easy for players (Phase D).
- **Mage verdict.** With typical gear and Avatar of Embers, the mage is level with the warrior against the T6 boss (0.93x boss-fight time; legacy 5.4x) and the ring 1-2 Wardens (0.76-1.27x). It is **1.6x slower against the ring-3 Warden** (Archon Velis, 70% fire). Embers converts everything to fire, so that is its worst match. A no-keystone (lightning) or Glacial Heart (cold) mage fights Velis in 16-17 s, against 23 s for Embers and 15 s for the warrior. **So the remaining mage gap is the Warden's fire resistance against an all-fire build, not gear or the tree.** Everywhere else, caster itemisation closed the gap seen in Phase A.
- **The mage still finishes Atlas stages 10-30% later than the warrior** (clear time 1.04-1.33x at T6 and rings 1-3, all profiles). That gap is walking and pack clear, not the boss fight.

## 2. Ranger rework (analyser rerun)

New builds in `sb_builds.gd`, with two new optional build fields: `standoff` sets the ranged kiting band, and `buff_roll` rolls in combat whenever that buff is down and the roll is ready. The controller reads them in `sb_controller.gd` (ranged spacing and `tick`). Builds without these fields play exactly as before, so the earlier ranger cells were reused. 10 runs per cell, typical, T3 / T6 / R3.

| Build | Mean relative clear (1.00 = no keystone) | T3 / T6 / R3 | Damage taken R3 (none 699) |
|---|---|---|---|
| r_glass (new) | 1.07 | 1.06 / 1.10 / 1.04 | 405 |
| r_perfect_aim | 1.08 | 1.16 / 1.02 / 1.05 | 420 |
| r_far_aim (new) | 1.09 | 1.08 / 1.06 / 1.11 | 542 |
| r_wind | 1.13 | 1.27 / 1.15 / 0.99 | 451 |
| r_wind_roll (new) | 1.17 | 1.09 / 1.23 / 1.21 | 564 |
| r_machinist | 1.30 | 1.04 / 1.16 / 1.69 | 865 |
| r_trapper | 1.30 | 1.06 / 1.35 / 1.50 | 1,082 |

- Holding range helps Perfect Aim at T3 (1.16 -> 1.08) but costs time at ring 3, where rooms and line of sight make the far band hard to hold.
- Rolling for Wind Dance costs more attack time than the 40% more damage gives back.
- Every keystone build takes less damage than `none` at ring 3, so the ranger keystones buy safety, not speed.
- `build_picks.json` now names `r_glass` as the ranger pick, because the analyser always picks a keystone build. **Use `--plan=none` for the ranger** until the keystones are retuned. The analyser report for this rerun is `out/builds/analyser_typical_ranger_phaseC.md`. `analyser_typical.md` is the full 10-run pass from Phase B, restored.

## 3. Method

- `tests/smartbot/phaseC_runner.py`: 3 classes x 3 gear profiles x 8 stages, 10 runs per cell, Competent, `--build=balanced`, `--jobs=10`.
  - Stages: T3 L20 and T6 L46 (seed 700), and Atlas rings 1/2/3 at L40/45/50 (`atlas:1,0`, `atlas:2,-1`, `atlas:3,0`, seed 900). Each ring is run plain (W = no) and with its Layer Warden summoned (`--warden=1`), Rot 0, `--mechanic=none`, `--wager=none`.
  - Plans: legacy `none` (the frozen-baseline bot), and for typical and geared: warrior `w_earthbreaker`, mage `m_embers`, ranger `none`.
- Side cells: typical mage at W1-W3 with `m_glacial` and with `none` (tags `_glacial`, `_none`).
- `tests/smartbot/phaseC_summary.py` builds the tables (`out/phaseC/phaseC_summary.md` / `.json`).
- "Boss fight" = clear time - time to boss, over wins only. These fights are short and have outliers, so the median is shown too. Differences under about 15% in one cell are within noise.

## 4. Results

### 4a. All cells

| Stage | Class | Gear | Boss kills | Deaths | Clear s | To boss s | Boss fight s (median) | Damage taken | Life | Keystone |
|---|---|---|---|---|---|---|---|---|---|---|
| T3 | warrior | legacy | 10/10 | 0 | 171 | 158 | 13 (13) | 2694 | 642 | - |
| T3 | warrior | typical | 10/10 | 0 | 69 | 65 | 4 (4) | 581 | 685 | Earthbreaker |
| T3 | warrior | geared | 10/10 | 0 | 66 | 62 | 4 (4) | 305 | 782 | Earthbreaker |
| T3 | ranger | legacy | 10/10 | 0 | 144 | 127 | 16 (15) | 473 | 415 | - |
| T3 | ranger | typical | 10/10 | 0 | 109 | 99 | 10 (10) | 236 | 505 | - |
| T3 | ranger | geared | 10/10 | 0 | 96 | 87 | 9 (9) | 174 | 646 | - |
| T3 | mage | legacy | 10/10 | 0 | 108 | 96 | 13 (12) | 181 | 405 | - |
| T3 | mage | typical | 10/10 | 0 | 88 | 78 | 10 (10) | 160 | 508 | Embers |
| T3 | mage | geared | 10/10 | 0 | 73 | 67 | 6 (6) | 77 | 673 | Embers |
| T6 | warrior | legacy | 10/10 | 0 | 87 | 80 | 7 (6) | 3476 | 1500 | - |
| T6 | warrior | typical | 10/10 | 0 | 49 | 46 | 4 (4) | 868 | 1700 | Earthbreaker |
| T6 | warrior | geared | 10/10 | 0 | 50 | 47 | 3 (2) | 653 | 2039 | Earthbreaker |
| T6 | ranger | legacy | 10/10 | 0 | 78 | 72 | 6 (5) | 394 | 833 | - |
| T6 | ranger | typical | 10/10 | 0 | 51 | 49 | 1 (1) | 174 | 1118 | - |
| T6 | ranger | geared | 10/10 | 0 | 45 | 44 | 1 (1) | 116 | 1378 | - |
| T6 | mage | legacy | 10/10 | 0 | 115 | 77 | 38 (38) | 1024 | 816 | - |
| T6 | mage | typical | 10/10 | 0 | 66 | 62 | 4 (3) | 122 | 1100 | Embers |
| T6 | mage | geared | 10/10 | 0 | 58 | 55 | 3 (3) | 148 | 1438 | Embers |
| R1 | warrior | legacy | 10/10 | 0 | 173 | 160 | 13 (10) | 4172 | 1320 | - |
| R1 | warrior | typical | 10/10 | 0 | 140 | 134 | 6 (5) | 1487 | 1595 | Earthbreaker |
| R1 | warrior | geared | 10/10 | 0 | 119 | 115 | 4 (4) | 976 | 1945 | Earthbreaker |
| R1 | ranger | legacy | 10/10 | 0 | 153 | 145 | 8 (7) | 472 | 788 | - |
| R1 | ranger | typical | 10/10 | 0 | 173 | 165 | 7 (6) | 676 | 1007 | - |
| R1 | ranger | geared | 10/10 | 0 | 113 | 110 | 3 (2) | 146 | 1309 | - |
| R1 | mage | legacy | 10/10 | 0 | 220 | 170 | 50 (44) | 1430 | 784 | - |
| R1 | mage | typical | 10/10 | 0 | 165 | 159 | 6 (5) | 408 | 992 | Embers |
| R1 | mage | geared | 10/10 | 0 | 131 | 128 | 3 (3) | 205 | 1316 | Embers |
| R2 | warrior | legacy | 10/10 | 0 | 153 | 148 | 6 (4) | 4094 | 1527 | - |
| R2 | warrior | typical | 10/10 | 0 | 120 | 115 | 5 (4) | 1635 | 1746 | Earthbreaker |
| R2 | warrior | geared | 10/10 | 0 | 101 | 98 | 2 (2) | 797 | 2149 | Earthbreaker |
| R2 | ranger | legacy | 10/10 | 0 | 136 | 131 | 5 (4) | 657 | 849 | - |
| R2 | ranger | typical | 10/10 | 0 | 129 | 125 | 4 (2) | 606 | 1182 | - |
| R2 | ranger | geared | 10/10 | 0 | 108 | 106 | 2 (1) | 308 | 1548 | - |
| R2 | mage | legacy | 10/10 | 0 | 158 | 147 | 11 (7) | 561 | 872 | - |
| R2 | mage | typical | 10/10 | 0 | 134 | 129 | 5 (5) | 535 | 1169 | Embers |
| R2 | mage | geared | 10/10 | 0 | 120 | 116 | 4 (4) | 342 | 1536 | Embers |
| R3 | warrior | legacy | 10/10 | 0 | 151 | 145 | 5 (6) | 7465 | 1645 | - |
| R3 | warrior | typical | 10/10 | 0 | 130 | 125 | 5 (4) | 3287 | 1899 | Earthbreaker |
| R3 | warrior | geared | 10/10 | 0 | 114 | 110 | 3 (2) | 2428 | 2313 | Earthbreaker |
| R3 | ranger | legacy | 10/10 | 0 | 150 | 144 | 6 (5) | 704 | 924 | - |
| R3 | ranger | typical | 10/10 | 0 | 120 | 117 | 3 (2) | 699 | 1302 | - |
| R3 | ranger | geared | 10/10 | 0 | 107 | 106 | 1 (0) | 383 | 1559 | - |
| R3 | mage | legacy | 10/10 | 0 | 171 | 165 | 7 (5) | 830 | 936 | - |
| R3 | mage | typical | 10/10 | 0 | 152 | 146 | 7 (6) | 780 | 1336 | Embers |
| R3 | mage | geared | 10/10 | 0 | 131 | 127 | 4 (3) | 428 | 1633 | Embers |
| W1 | warrior | legacy | 10/10 | 0 | 188 | 156 | 32 (26) | 4720 | 1314 | - |
| W1 | warrior | typical | 10/10 | 0 | 144 | 129 | 15 (13) | 1504 | 1548 | Earthbreaker |
| W1 | warrior | geared | 10/10 | 0 | 129 | 119 | 10 (9) | 1205 | 1940 | Earthbreaker |
| W1 | ranger | legacy | 10/10 | 0 | 165 | 148 | 18 (15) | 569 | 796 | - |
| W1 | ranger | typical | 10/10 | 0 | 177 | 160 | 16 (7) | 627 | 974 | - |
| W1 | ranger | geared | 10/10 | 0 | 119 | 115 | 4 (4) | 169 | 1309 | - |
| W1 | mage | legacy | 10/10 | 0 | 213 | 172 | 41 (35) | 1253 | 830 | - |
| W1 | mage | typical | 10/10 | 0 | 182 | 163 | 19 (16) | 636 | 996 | Embers |
| W1 | mage | geared | 10/10 | 0 | 143 | 133 | 10 (10) | 312 | 1318 | Embers |
| W2 | warrior | legacy | 10/10 | 0 | 159 | 136 | 24 (24) | 4976 | 1452 | - |
| W2 | warrior | typical | 10/10 | 0 | 143 | 115 | 28 (13) | 2616 | 1749 | Earthbreaker |
| W2 | warrior | geared | 10/10 | 0 | 108 | 94 | 14 (9) | 1395 | 2191 | Earthbreaker |
| W2 | ranger | legacy | 9/10 | 1 | 143 | 126 | 16 (13) | 1143 | 844 | - |
| W2 | ranger | typical | 10/10 | 0 | 138 | 128 | 10 (9) | 658 | 1164 | - |
| W2 | ranger | geared | 10/10 | 0 | 112 | 107 | 5 (4) | 235 | 1530 | - |
| W2 | mage | legacy | 8/10 | 2 | 176 | 140 | 35 (33) | 1708 | 860 | - |
| W2 | mage | typical | 10/10 | 0 | 149 | 127 | 21 (18) | 609 | 1172 | Embers |
| W2 | mage | geared | 10/10 | 0 | 132 | 116 | 15 (16) | 552 | 1536 | Embers |
| W3 | warrior | legacy | 10/10 | 0 | 157 | 139 | 18 (17) | 6142 | 1590 | - |
| W3 | warrior | typical | 10/10 | 0 | 135 | 121 | 15 (11) | 2177 | 1970 | Earthbreaker |
| W3 | warrior | geared | 10/10 | 0 | 114 | 105 | 9 (6) | 1398 | 2248 | Earthbreaker |
| W3 | ranger | legacy | 10/10 | 0 | 159 | 147 | 13 (9) | 811 | 927 | - |
| W3 | ranger | typical | 10/10 | 0 | 133 | 127 | 6 (3) | 514 | 1232 | - |
| W3 | ranger | geared | 10/10 | 0 | 110 | 106 | 4 (2) | 331 | 1559 | - |
| W3 | mage | legacy | 10/10 | 0 | 200 | 165 | 35 (34) | 1368 | 903 | - |
| W3 | mage | typical | 10/10 | 0 | 173 | 150 | 23 (16) | 1068 | 1321 | Embers |
| W3 | mage | geared | 10/10 | 0 | 146 | 132 | 14 (12) | 512 | 1625 | Embers |

Deaths: legacy W2 ranger 1 (Gravemaw fault lines) and mage 2 (flaking, quake). The Gravemaw is the deadliest fight for low-life legacy characters.

### 4b. Gear against legacy (mean clear time and damage taken, ratio to legacy)

| Stage | Class | Typical clear | Geared clear | Typical taken | Geared taken |
|---|---|---|---|---|---|
| T3 | warrior / ranger / mage | 0.41 / 0.76 / 0.81 | 0.39 / 0.67 / 0.67 | 0.22 / 0.50 / 0.88 | 0.11 / 0.37 / 0.42 |
| T6 | warrior / ranger / mage | 0.57 / 0.65 / 0.58 | 0.57 / 0.58 / 0.51 | 0.25 / 0.44 / 0.12 | 0.19 / 0.29 / 0.14 |
| R1 | warrior / ranger / mage | 0.81 / 1.13 / 0.75 | 0.69 / 0.74 / 0.60 | 0.36 / 1.43 / 0.29 | 0.23 / 0.31 / 0.14 |
| R2 | warrior / ranger / mage | 0.78 / 0.95 / 0.85 | 0.66 / 0.80 / 0.76 | 0.40 / 0.92 / 0.95 | 0.19 / 0.47 / 0.61 |
| R3 | warrior / ranger / mage | 0.86 / 0.80 / 0.89 | 0.76 / 0.71 / 0.77 | 0.44 / 0.99 / 0.94 | 0.33 / 0.54 / 0.52 |
| W1 | warrior / ranger / mage | 0.76 / 1.07 / 0.86 | 0.69 / 0.72 / 0.67 | 0.32 / 1.10 / 0.51 | 0.26 / 0.30 / 0.25 |
| W2 | warrior / ranger / mage | 0.90 / 0.97 / 0.85 | 0.68 / 0.78 / 0.75 | 0.53 / 0.58 / 0.36 | 0.28 / 0.21 / 0.32 |
| W3 | warrior / ranger / mage | 0.86 / 0.84 / 0.86 | 0.73 / 0.69 / 0.73 | 0.35 / 0.63 / 0.78 | 0.23 / 0.41 / 0.37 |

- In the Atlas most of a run is walking and packs, so gear saves less time there (10-25%) than in dungeons (20-60%).
- **Ring 1 typical ranger is the one regression** (clear 1.13x, damage 1.43x legacy). At ring 1 the typical ranger has seen only about 2.9 runs of drops, and this seed's typical kits are weak (W1 typical median fight 7 s, mean 16 s: a few slow runs). Geared fixes it. It is worth a look in Phase D, but not a blocker.

### 4c. Class balance (boss-fight time, class / warrior, same gear)

| Stage | Gear | Ranger / warrior | Mage / warrior | Mage clear / warrior clear |
|---|---|---|---|---|
| T6 | legacy | 0.86 | **5.41** | 1.31 |
| T6 | typical | 0.30 | 0.93 | 1.33 |
| T6 | geared | 0.41 | 1.05 | 1.17 |
| W1 | legacy | 0.56 | 1.29 | 1.13 |
| W1 | typical | 1.12 | 1.27 | 1.27 |
| W1 | geared | 0.44 | 1.02 | 1.11 |
| W2 | legacy | 0.69 | 1.49 | 1.10 |
| W2 | typical | 0.35 | 0.76 | 1.04 |
| W2 | geared | 0.32 | 1.07 | 1.22 |
| W3 | legacy | 0.70 | **1.93** | 1.27 |
| W3 | typical | 0.40 | **1.59** | 1.28 |
| W3 | geared | 0.47 | **1.58** | 1.28 |

The plain-ring hex bosses (R1-R3) die in 1-7 s for every typical and geared class, so their ratios are noise and are left out (`out/phaseC/phaseC_summary.md` has them).

## 5. Mage against Warden resistances

Warden resistances, with the ring's `resist_bonus` (+20/+25/+30) added:

| Warden | Fire | Cold | Lightning |
|---|---|---|---|
| W1 Sir Morcant | 35 | 50 | 20 |
| W2 The Gravemaw | 50 | 5 | 25 |
| W3 Archon Velis | 70 | 30 | 60 |

Side cells: typical mage, 10 runs each.

| Warden | Embers (all fire) | No keystone (Stormcaller, lightning_bolt lead) | Glacial Heart (Cryomancer, ice_lance lead) | Warrior (Earthbreaker) |
|---|---|---|---|---|
| W1 fight s (median) | 19 (16) | 19 | 27 | 15 (13) |
| W2 fight s (median) | 21 (18) | 17, 1 death | 27 | 28 (13) |
| W3 fight s (median) | **23 (16)** | **17** | **16** | 15 (11) |
| W3 damage taken | 1,068 | 865 | 732 | 2,177 |

- Against Velis, Embers is the slowest mage: 23 s mean against 16-17 s for a cold or lightning lead. A mage that doesn't convert to fire fights Velis at about the warrior's speed (1.1x).
- Glacial Heart only wins at W3. At W1 and W2 it is the slowest, even against the Gravemaw's 5% cold. The 20% less damage against unchilled targets costs more than the cold resistance saves. That fits its 1.07 analyser score.
- The bot still doesn't pick skills by target resistance (Dan's #7). These cells force the build, as a player who respecs for Velis would.

**Verdict:** gear and the tree no longer explain the mage gap. Caster itemisation plus Embers brought the mage level with the warrior at T6 and the ring 1-2 Wardens. What remains:
- Archon Velis's 70% fire is a hard counter to the analyser's mage pick. Either accept it as a respec moment or soften it in Phase D.
- The mage clears Atlas stages 10-30% slower, in walking and packs.
- The mage has the least life (0.6-0.7x the warrior's), but takes far less damage than the warrior (0.1-0.5x in typical cells) and about as much as the ranger.

## 6. What this means for Phase D

- **Every typical and geared cell went 10/10**, Wardens included, with no deaths. At Rot 0, no tuning target can be "harder than typical" yet. Phase D should re-measure Rot 3-5, the Wager bets and the Wardens with typical bots, and tune to a target win rate below 100% (Dan's #6).
- **Ranger keystones** (Perfect Aim, Wind Dancer, Automaton, Master Trapper, Glass Cannon on the ranger) don't beat the no-keystone tree. They are a candidate game-side retune.
- **Archon Velis against Embers** (section 5).
- **Ring 1 typical ranger** kit quality (section 4b).

## 7. Verification

- 0 `SCRIPT ERROR` in all 87 batch logs. Every cell has 10 rows. All 270 Warden runs carry a `warden:N` note.
- The new `standoff` and `buff_roll` fields are read only when a build sets them, so the earlier Phase B cells (all builds without them) were reused unchanged.
- Smoke test before the rerun: 2 runs each of the three new builds at T3. The keystone was allocated, the spec picked, and `r_wind_roll` rolled 16-25 times per run (others 0-3).
- Backups of the pre-Phase-C `sb_builds.gd`, `sb_controller.gd`, `build_picks.json` and `analyser_typical.md`: `W:\AI game\PathofDan\_claude_xfer\phaseC\backup\`.

## 8. Files and commands

New: `tests/smartbot/phaseC_runner.py`, `tests/smartbot/phaseC_summary.py`, `docs/PHASE_C_MEASUREMENTS.md`, `out/phaseC/` (CSV, logs, `phaseC_summary.md/.json`), `out/builds/analyser_typical_ranger_phaseC.md`. Changed: `sb_builds.gd` (3 ranger builds, `standoff`, `buff_roll`), `sb_controller.gd` (range band and buff roll), `build_picks.json` (ranger evidence and pick).

```
python tests/smartbot/build_analyser.py --godot "W:\AI game\Godot_v4.0-stable_win64_console.exe" --runs 10 --stages T3,T6,R3 --classes ranger
python tests/smartbot/phaseC_runner.py --godot "W:\AI game\Godot_v4.0-stable_win64_console.exe" --runs 10 --plan-ranger none
python tests/smartbot/phaseC_runner.py --godot ... --runs 10 --classes mage --gears typical --stages W1,W2,W3 --plan-mage m_glacial --tag glacial
python tests/smartbot/phaseC_summary.py
```
