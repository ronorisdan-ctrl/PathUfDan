# Smartbot Phase D2: Rot dial, Wardens, Wager, Velis and the ranger keystone dummy pass

2026-11-10 · Claude (Cowork) for Dan · follows `docs/PHASE_D_MEASUREMENTS.md` (D1)

## Dan's decisions (gate before D2)

| # | Decision | What was done |
|---|---|---|
| D1 | Rot target | Dial with typical bots: ~85% Rot 3, ~65% Rot 4 + 2 Pigments, ~45% Rot 5 + 2 Pigments, plus a lever that reaches the ranger |
| D2 | Wardens at Rot 3+ | ~60% typical wins at Rot 5 (ring 2 and 3; ring 1 never has Rot) |
| D3 | Wager numbers | Numbers measured and solved for ~60% wins, odds for about +15% expected gold. Archaeology bot fixed first |
| D4 | Velis | Base fire resistance 40 -> 30 (60% in ring 3) |
| D5 | Ranger keystones | Training Grounds dummy test built and run (section 6). Then Dan (2026-11-10): **Perfect Aim penalty 30% within 100 units -> 25% within 70**; Wind Dancer left as is (players can chain a movement skill and the roll to keep Wind Dance up) |

All runs on Dan's PC (Godot 4.0 win64 console, headless, `--fixed-fps 60`). There were 215 batch logs and 0 `SCRIPT ERROR`s. Nothing is committed. Backups of every changed file are in `_claude_xfer\phaseD2\backup\`.

## 1. Summary

- **Rot is a dial again.** With typical bots: Rot 3 **87%** (target 85), Rot 4 + 2 Pigments **68%** over 60 runs (target 65), Rot 5 + 2 Pigments **53%** (target 45). Rot 5 sits inside the ±9-point noise of 30 runs. Pooled over the four Rot 5 settings between 4.5x and 5.0x damage, it is 60/120 = 50%. D1 had 100 / 100 / 97%.
- **The ranger is reachable now.** Two new Rot levers (monster movement and projectile speed) take the ranger from 30/30 to 6/10 wins at Rot 5. Its damage taken at Rot 4 + 2P roughly doubles (801 -> ~1,440).
- **Wardens at Rot 5: 63% (ring 2) and 63% (ring 3)**, from 87% and 100%. The ring-2 Warden needed its damage multiplier cut from 1.3 to 0.4, because Rot 5 alone made it 17%.
- **Wager: all 7 tunable bets land at 57-67%** after one calculated step: margins from each run were measured, and the threshold that gives 60% was read off. Odds were then set for +15% expected gold.
- **Velis vs Embers fixed.** At the new Rot 4, Embers needs 18.4 s on Velis. That is level with Glacial Heart (18.1 s) and the lightning mage (20.0 s); in D1 it was 32.9 vs 22.8 / 24.4. Velis is also the Tier 3 dungeon boss, so fire builds find T3 slightly easier too.
- **Ranger keystones (dummy test).** Glass Cannon and Perfect Aim at range work as maths (x1.17-1.46); Perfect Aim inside 100 units was x0.68, so its drawback is now 25% within 70 units (Dan). Wind Dancer is left as is. Details in section 6.
- **Game bug found and fixed (not part of the brief):** loading a save checked the passive tree before `progress` was read, so Abyss milestone points counted as 0. Any tree that spent them was **fully refunded on every load**. This also hit about 1% of bot runs in Phases C and D1 (19 rows), which fought with no tree.

## 2. Final numbers (data/atlas.json)

| Rot | Damage | Life recovery | Monster attack speed | **Monster move speed (new)** | **Monster projectile speed (new)** |
|---|---|---|---|---|---|
| 3 | 1.4 -> **3.0** | 0.85 -> **0.65** | 1.05 -> **1.15** | **1.10** | **1.25** |
| 4 | 1.6 -> **4.3** | 0.7 -> **0.45** | 1.1 -> **1.22** | **1.18** | **1.40** |
| 5 | 1.8 -> **4.8** | 0.6 -> **0.38** | 1.15 -> **1.25** | **1.20** | **1.45** |

Density, life, reward, elite mods and Heart mutations are unchanged. The Atlas panel's "The Rot saps you" line now also names the move and projectile speed.

Wardens: ring 2 (Gravemaw) `damage_mult` 1.3 -> **0.4**, ring 3 (Velis) 1.3 -> **1.1**, ring 1 unchanged.

Velis: base resist fire 40 -> **30** (lightning 30, void 30 unchanged; +30 in ring 3).

## 3. Rot (ring 3 hex 3,0, L50, typical, 10 runs per class per cell)

| Setting (Rot 3 / 4 / 5 damage) | Rot 3 | Rot 4 + 2P (s900) | Rot 4 + 2P (s1900) | Rot 5 + 2P |
|---|---|---|---|---|
| D1 (1.4 / 1.6 / 1.8) | 30/30 | 30/30 | 30/30 | 29/30 |
| A (2.0 / 2.6 / 3.2) | 28/30 | 26/30 | - | 21/30 |
| B (2.6 / 3.4 / 4.2) | 28/30 | 26/30 | - | 14/30 |
| C (2.8 / 4.0 / 4.3) | 27/30 | 23/30 | 23/30 | 15/30 |
| F (3.0 / 4.3 / 4.5) | 26/30 | 21/30 | 20/30 | 16/30 |
| G (Rot 5 4.7) | | | | 17/30 |
| H (Rot 5 5.0, heal 0.35) | | | | 11/30 |
| **Final (3.0 / 4.3 / 4.8)** | **26/30 (87%)** | **21/30** | **20/30** (68% together) | **16/30 (53%)** |

(Each setting also moves heal, attack, move and projectile speed; see the `--tune` strings in `_claude_xfer\phaseD2\r*.ps1`.)

- The final Rot 3 and Rot 4 rows equal the F rows run for run. That is expected, because the numbers are the same, and it confirms the bot is deterministic.
- Win rate responds slowly to damage at Rot 3 (93 -> 87% for 2.0 -> 3.0x): deaths come in spikes (Heart mortar, death explosions), not from wear. At Rot 5 the cause of death is split between the Heart of Rot and Volatile death explosions.
- Final per class, Rot 4 + 2P: warrior 14/20, ranger 19/20, mage 8/20. Rot 5 + 2P: 4 / 6 / 6 of 10. **The mage is the weakest class at Rot 4** (the D6 class-balance flag).
- **Not measured: legacy (under-geared) bots.** D1 showed legacy at 67-83% under the old Rot 4. With 2.7x more Rot 4 damage, under-geared characters will mostly die at Rot 4-5. That is the intended cost of the dial, but worth a playtest.

## 4. Wardens at Rot 5 (typical, 10 runs per class)

| Warden (damage_mult) | Rot 5 damage | All | W / R / M |
|---|---|---|---|
| W2 Gravemaw, D1 (1.3) | 1.8 | 26/30 | 10 / 10 / 6 |
| W2 (1.3), C | 4.3 | 5/30 | 0 / 5 / 0 |
| W2 (1.0) / (0.8) / (0.65), F | 4.5 | 7 / 12 / 15 of 30 | |
| W2 (0.5), G | 4.7 | 14/30 | 2 / 10 / 2 |
| W2 (0.4), H | 5.0 | 16/30 | 4 / 10 / 2 |
| **W2 (0.4), final** | 4.8 | **19/30 (63%)** | 5 / 10 / 4 |
| W3 Velis (1.3), C / F / G (1.2) / H (1.1) | | 19 / 18 / 18 / 18 of 30 | |
| **W3 (1.1), final** | 4.8 | **19/30 (63%)** | 7 / 8 / 4 |

- Below a ring-2 multiplier of about 0.65 the win rate stops climbing (47-63%). About 4-5 of 30 runs die in the Rot 5 zone before the Warden, and the warrior and mage lose to the Gravemaw's own mechanics. This is the same class gap D1 flagged (D6), not a number problem.
- A ring-2 Warden that deals 0.4x the base Gravemaw's damage looks odd on paper, but at Rot 5 it hits 0.4 x 4.8 = 1.9x the base boss. At Rot 3 it hits 0.4 x 3.0 = 1.2x, so W2 at Rot 3-4 is now easier than before. The test "warden: more life and damage" was changed to "more life, damage x ring damage_mult".

## 5. Collector's Wager (typical, rings 2 + 3, Rot 0, stake 1x, 30 runs per bet)

Method: run 1 applied the D1 proposals (`w1`). Each run's margin was read from the row (finish time, kills, peels, sketches, hits taken, lowest life). For each bet, the limit at which 18 of 30 runs would have won was read off, and run 2 (`w2`) re-measured with it.

| Bet | D1 rule -> D2 rule | D1 win | w1 win | **w2 win** | Odds (D1 -> D2) | Net gold per stake at w2 |
|---|---|---|---|---|---|---|
| Unscathed | max 5 hits -> **2** | 67% | 72% | **66%** | 0.95 -> **0.75** | +0.16 |
| Against the Clock | 12 + 8 s/chamber -> **12 + 3.7** | 77% | 80% (6.5 s) | **67%** | 0.7 -> **0.72** | +0.15 |
| Economy of Means | 1 skill (no number) | 90% | 93% | - | 0.25 (kept) | +0.16 |
| Frenzy | 25 kills / 38 s -> **30 / 30 s** | 73% | 77% (30 / 38) | **60%** | 1.0 -> **0.92** | +0.15 |
| Abstinence | no flask (no number) | 100% | 100% | - | 0.3 -> **0.15** | +0.15 |
| Iron Will | never below 70% -> **97%** | 90% | 90% (85%) | **57%** | 0.9 -> **1.0** | +0.14 |
| Flaking | 7 layers -> **4** | 43% | 53% (5) | **63%** | 0.6 -> **0.83** | +0.16 |
| Colourist | 10 sketches / 75 s -> **12 / 58 s** | 80% | 73% (12 / 75) | **60%** | 0.65 -> **0.92** | +0.15 |
| Archaeology | 1 vault / 40 s -> **15 s** | 81% | 75% (30 s) | **62%** (24 bets) | 0.9 -> **0.84** | +0.14 |

- **Why the D1 proposals barely moved the win rates:** the binding limit was usually not the one being changed. Frenzy, Colourist and Unscathed losses are mostly "the zone boss fell first", and finish times sat well inside the old timers. So the timers had to come down a long way: Frenzy 38 -> 30 s, Colourist 75 -> 58 s, Archaeology 40 -> 15 s, Against the Clock 8 -> 3.7 s per chamber.
- **Iron Will at 97%** is close to "take no damage". The warrior wins it 20% of the time and the ranger 90%; the warrior also has the worst Unscathed (33%). Class spread on these two bets is large.
- **Archaeology bot fix:** with an Archaeology plan the bot now leaves vault walls alone until it has taken the bet (`sb_endgame.hold_wall`). The 14/30 "vault opened before the Collector" runs from D1 are down to 6/30. The bot never targets the wall in those 6 (vault time 0); the ring-2 vault breaks from splash damage while the bot fights next to it. A player could avoid that, so it is left as a bot limit.
- Odds = (1.15 - p) / p at the w2 win rate p. The w2 numbers carry about ±9 points of noise; the odds follow the measured rate, so the expected gold stays near +15% whichever way the noise fell.

## 6. Ranger keystones: Training Grounds dummy pass (D5)

New smartbot mode `--dummy=<dist>[:<secs>]` (`tests/smartbot/sb_dummy.gd`). It uses the bot's own skill choice and aim (sb_controller `_pick_skill`) on a Training Grounds dummy in the hub, with the T6 boss defence profile. The player is pinned at a fixed distance, nothing attacks, and the TrainingLog measures a 30 s window. `--dummy-roll=2.5` dodge-rolls every 2.5 s, which is how a player keeps Wind Dance up. Typical gear, L50, 5 kits per cell. "x none" is paired by kit seed against the no-keystone ranger.

| Build | Keystone | Life | DPS @ 60 units | DPS @ 140 | DPS @ 220 |
|---|---|---|---|---|---|
| none | - | 1,132 | 38,632 (x1.00) | 14,578 (x1.00) | 14,130 (x1.00) |
| Glass Cannon | ks_glass | 740 | 47,866 (**x1.31**) | 21,222 (**x1.46**) | 16,034 (**x1.17**) |
| Perfect Aim | ks_perfect_aim | 1,129 | 26,134 (**x0.68**) | 17,130 (x1.16) | 16,927 (x1.18) |
| Wind Dancer, no rolls | xw_ks | 1,105 | 12,955 (**x0.43**) | 6,650 (**x0.48**) | 8,795 (**x0.62**) |
| Wind Dancer, roll every 2.5 s | xw_ks | 1,105 | 21,438 (x0.70) | 11,840 (x0.84) | 11,367 (x0.81) |

(Perfect Aim and "Perfect Aim at range" are the same tree, so on a fixed dummy they give identical numbers.)

**Verdict.**
- **Glass Cannon: the maths is fine.** +17-46% DPS for 35% less life is a fair glass trade. On Velis in D1 it was slower than no keystone (5.2 vs 4.3 s). That comes from bot play with 740 life, not from the keystone. **No change needed.**
- **Perfect Aim: the close-range penalty decides it.** Out of 100 units it gains 16-18%. Inside 100 units it loses 32%. Close range is where the ranger does most damage (none: 38.6k at 60 units vs 14.6k at 140), and Velis teleports next to you every 3.5 s. **Change recommended:** the D1 proposal of a 15% close penalty, or a 60-unit radius.
- **Wind Dancer: the build loses even with perfect upkeep (x0.70-0.84).** The 40% more for 3 s only covers part of what its route and the Wraith Hunter spec give up against the Deadeye route. **Change recommended**, e.g. drop the "10% less without Wind Dance" and raise Wind Dance to 60% more or 4 s. Because the spec differs, a clean keystone-only number would need the same spec on both builds. That is a further dummy run if you want it before choosing.
- The ranger is still the fastest boss killer (Velis at Rot 4: 4.8 s vs warrior 13.5 s, mage 18-20 s), so neither fix should add raw power. Both are sidegrades.

**Applied (Dan, 2026-11-10): Perfect Aim's drawback is now 25% less damage within 70 units** (was 30% within 100). `combat.gd`, tree text in `hand_nodes.json` / `passive_tree.json` (generator `--check` byte-identical), `passive_flags.json`, test updated. Re-measured:

| Perfect Aim | @ 60 units | @ 140 | @ 220 | Velis at Rot 4 (fight s) |
|---|---|---|---|---|
| before (30% within 100) | x0.68 | x1.16 | x1.18 | 6.5 (Perfect Aim at range 6.4) |
| **after (25% within 70)** | **x0.73** | x1.17 | x1.18 | **5.5** (at range 6.5) |

Ranger with no keystone on Velis at the new Rot 4: 4.8 s. The Velis rows before and after are at different Rot (D1 old Rot 4 vs D2 new Rot 4).

**Wind Dancer: left as is** (Dan): a player can use a movement skill and get the roll back, keeping the 4 s buff up more often than the bot's fixed 2.5 s roll.

## 7. Velis vs Embers (D4)

Velis at the new Rot 4 (W3 damage_mult 1.1), typical, 10 runs each:

| Build | D1 fight s (fire 40) | **D2 fight s (fire 30)** | D2 wins |
|---|---|---|---|
| mage, Embers | 32.9 | **18.4** | 8/10 |
| mage, no keystone (lightning) | 22.8 | 20.0 | 9/10 |
| mage, Glacial Heart | 24.4 | 18.1 | 8/10 |
| warrior, Earthbreaker | 14.5 | 13.5 | 9/10 |
| ranger | 4.3 | 4.8 | 9/10 |

Embers is now level with the other mage builds. Part of the overall speed-up also comes from the passive-tree load fix (section 8).

## 8. Bug fix: passive tree refunded on load when it spends Abyss points

- `character_data.gd` `from_dict` calls `_load_passives` before `progress` is loaded. `total_passive_points()` therefore saw `abyss_best = 0`. A tree that spent any Abyss milestone point read as "N points spent but only N-k available" and was **fully refunded on every load** (with the one-time refund notice).
- Fix: `_load_passives` takes the Abyss points from the save's own `progress.abyss_best`. Regression test "abyss points: a tree spending them is kept on load" is in `tests/test_passive_tree.gd`.
- Bot impact: the smartbot's checkpoint round trip is a save and load. The Phase B reference player has Abyss points, so 19 rows in Phases C and D1 (about 1%) fought with an empty tree. D1's conclusions do not change at that rate.

## 9. Files changed

Game:
- `data/atlas.json`: Rot levels 3-5, Wager bet numbers and odds, Warden ring 2/3 damage_mult, docs.
- `data/enemies.json`: Archon Velis fire 40 -> 30.
- `scripts/entities/enemy.gd`, `scripts/entities/boss.gd`: `proj_speed_mult`.
- `scripts/world/dungeon.gd`, `scripts/core/atlas_rules.gd`: Rot `move_speed` and `proj_speed` into the zone's enemy scaling.
- `scripts/ui/atlas_panel.gd`: Rot tooltip line.
- `scripts/core/character_data.gd`: load fix.

Tests:
- `tests/test_passive_tree.gd`: new regression check.
- `tests/test_atlas.gd`: Warden damage check and boss-rush time rounding updated for the new numbers.

Smartbot:
- `smartbot.gd`: `--tune=` in-memory overrides for sweeps, `--dummy` row.
- `sb_dummy.gd` (new).
- `sb_controller.gd` + `sb_endgame.gd`: Archaeology `hold_wall`.
- `phaseD_runner.py`: groups `d2rot`, `d2warden`, `dummy`, `--tune`, `--outdir`.
- `phaseD2_summary.py` (new).

Output: `tests/smartbot/out/phaseD2/` (CSVs, logs, `phaseD2_summary.md/.json`). Sweep scripts and logs: `_claude_xfer\phaseD2\`.

```
python tests/smartbot/phaseD_runner.py --godot "W:\AI game\Godot_v4.0-stable_win64_console.exe" --groups d2rot,d2warden --outdir phaseD2 --tag final
python tests/smartbot/phaseD_runner.py --godot "..." --groups wager --outdir phaseD2 --tag w2
python tests/smartbot/phaseD_runner.py --godot "..." --groups dummy --classes ranger --outdir phaseD2
python tests/smartbot/phaseD2_summary.py --md tests/smartbot/out/phaseD2/phaseD2_summary.md
```

## 10. Verification

- atlas_only 559/0; tree_only 844/0 (with the new check, and again after the Perfect Aim change).
- Smartbot frozen baseline (`run_baseline.ps1` vs `caster_v1.csv`): **52/60 identical**. The 8 changed rows are all T3 mage and ranger runs. **Archon Velis is also the Tier 3 dungeon boss** (`abyssal_warrens`), so her fire 40 -> 30 changes those fights. Wins are identical (all six class/tier cells), T3 mean clear time mage 104.4 -> 103.8 s and ranger 132.7 -> 133.6 s, and T6 and every warrior row are byte-identical. **Frozen as `tests/smartbot/baseline/d2_v1.csv`** (Dan, 2026-11-10). After the Perfect Aim change the baseline was re-run: 60/60 identical to d2_v1 (baseline bots take no keystones).
- Full suite (test_runner): **47969 passed, 0 failed**.

## 11. Open / for Dan

1. Class balance (D6): mage weakest at Rot 4 (8/20) and on the Gravemaw; warrior weak at Iron Will and Unscathed; ranger 3-4x faster on Wardens.
2. Under-geared (legacy) players at the new Rot 4-5: Dan will playtest.
3. Rot 5 + 2P lands at 50-53% vs the 45% target. It is inside the noise; one more step (damage 5.0, heal 0.35 gave 37%) is available if you want it lower.
