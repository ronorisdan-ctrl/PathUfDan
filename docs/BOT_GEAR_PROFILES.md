# Smartbot gear profiles and keystone builds (Phase B)

2026-11-06 · Claude (Cowork) for Dan · follows `docs/BOT_GEAR_AUDIT.md` (Phase A)

Phase B changes **only the smartbot** (`tests/smartbot/`). No game file, data file or test changed. Without the new flags the bot is unchanged: legacy entry kits and a legacy dungeon run are byte-identical to before (section 7).

## 1. Summary

- **New flag `--gear=legacy|typical|geared`** (default `legacy`). `typical` is what a player owns after the runs it takes to level to that point. Every item those runs dropped is rolled with the game's own drop code, the best one per slot is equipped, the rest is salvaged or sold, and the gear is crafted with the materials and gold those runs gave. Crafting follows the crafting-corruption meter, so items lock at 100%. `geared` is the same player after 3x the farming. In the Atlas, `geared` also gets Rot-touched drops (ring 2+) and the Fixative craft. No profile ever uses the Abyssal Brand "Corrupt Item".
- **Typical gear is decent, as Dan asked.** About 9 of 11 slots are rare or better (legacy: about 3). The lowest elemental resistance is 57-73 from T6 on (legacy: 25-59), and life is 1.3-1.5x higher. Warrior and ranger get 2-3.4x the legacy static DPS without a keystone. The mage gets 1.05-2.4x. EHP rises 1.4-2.2x for every class.
- **Keystone builds.** There are 12 hand-written builds (4 per class), each with a keystone, a mastery, a tree gem socket, a specialisation and preferred skill tags. The new **build analyser** plays each build in real dungeon and Atlas runs and picks one build per class. The picks (10 runs per cell, on Dan's PC): **warrior Earthbreaker** (0.83x the no-keystone clear time), **mage Avatar of Embers** (0.91x) and **ranger Perfect Aim** (1.08x, so slower than no keystone; no ranger build beats `none`). The 4-run cloud pass picked the same three builds. `--plan=auto` (the default for typical and geared) uses these picks.
- **Other bot changes for typical and geared:**
  - The Atlas reference points (+2/+4/+6 at rings 1/2/3).
  - Masteries and the tree gem socket.
  - The spec is re-picked when the main skill or the build changes (Dan's #7).
  - The gear score values spell penetration and armour against the stage's generic enemy defence. This is one resistance for all three elements, so no element is favoured (Dan: no skill choice by target resistance).
- **Expect Rot, Wager and Warden targets to move (Phase D).** With typical gear and keystones, every class killed the boss in 10 of 10 runs at T3, T6 and ring 3 in every build (10-run analyser). Clear times are about half of the frozen baseline's.

## 2. Dan's decisions (2026-11-06) and how they are applied

| # | Decision | Applied as |
|---|---|---|
| 1 | `typical` for tuning, `geared` for upper-bound checks; typical gear "fairly decent" because a player crafts | `--gear=typical` / `--gear=geared`. Typical includes the crafting a player would do with the materials of those runs. |
| 2 | Flag-less default stays `legacy` (recommendation accepted) | Without `--gear` the bot is unchanged, so `caster_v1.csv` and the old runner scripts still reproduce. |
| 3 | Bots use keystone builds; build a system to analyse and pick them | `sb_builds.gd` (library) + `build_analyser.py` (real runs, writes `build_picks.json`) + `--plan=auto`. |
| 4 | Generate directly, use maths for typical vs geared, realistic to the game | Run counts from the XP curve and drop maths over game data. Items rolled with `Loot.roll_item` at the right monster level and rarity bonus. Crafting with `Loot.craft_*` and the corruption meter (section 3). |
| 5 | No Abyssal Brand corruption (confirmed: decision 5 meant the Brand "Corrupt Item" action) | Never used. Normal crafts **do** follow the crafting meter: 60% chance of +25% per add / reroll / raise rarity, sealed at 100% (Dan's follow-up answer). |
| 6 | Retune Rot/Wager after Phase D | Not done here. The section 6 results show why it will be needed. |
| 7 | Re-pick the spec when the main skill changes (earlier answer) | Done for typical and geared. Legacy keeps the first choice. |
| Follow-ups | Geared = 3x the farming; Atlas Rot-touched implicits and Fixative for geared only; builds from a library plus analyser | As stated. |

## 3. The economy model (how "typical" and "geared" are measured)

All of this is in `tests/smartbot/sb_gear.gd`.

**Runs per level.** A player runs the highest tier whose `min_level` is at or below its level. From the level the stage starts, it runs the stage's Atlas ring. One run's XP is `kills x mean pool XP x (1 + 0.18 (ml - 1)) + boss XP (60 x ml x tier)`, the same formulas as `enemy.gd` and `dungeon.gd`. The monster level `ml` is clamped to the dungeon's range, and the Atlas ring level is used in the Atlas. The runs at level `l` are `xp_for_level(l)` divided by that. The only measured input is **kills per run**: 98 at T3 and 148 at T6 (all classes, frozen baselines). T1/T2/T4/T5 are scaled from those by `packs_per_room x pack_size` (84/95/126/150).

**The candidate pool.** These are the drops of the runs in the last 6 levels. Older drops have lower base and affix tiers, and gems come from the last 10 levels. Per run, using the `data/loot.json` chances:

- normal kills: 16% item chance at the dungeon or ring rarity bonus
- elites: 2 rolls at 16%, +150 rarity
- the boss: 4 items at +400 rarity, the first forced rare (80%) or epic (20%)
- materials: 12% per kill, 3 rolls per elite, 6 from the boss, split by material weight
- gold: as `roll_drops`
- gems and runes: 3% / 2% per kill, 18% / 12% per elite, plus the boss

Every drop is rolled with `Loot.roll_item`, so class bias, base tiers, legendaries and sockets come from the real code.

| Stage | Runs to reach it | Runs in the last 6 levels (typical) | Drops (typical / geared) | Rarity bonus | Materials | of which catalysts / essences / arcane dust | Gold |
|---|---|---|---|---|---|---|---|
| T3 L20 | 10 | 3.8 | 77 / 228 | 60 | 72 | 2.4 / 4.8 / 10.8 | 10k |
| T4 L28 | 14 | 3.0 | 77 / 231 | 100 | 70 | 2.3 / 4.7 / 10.5 | 16k |
| T5 L37 | 19 | 3.2 | 96 / 288 | 150 | 86 | 2.9 / 5.7 / 12.9 | 27k |
| T6 L46 | 24 | 3.4 | 100 / 298 | 170 | 89 | 3.0 / 6.0 / 13.4 | 36k |
| Ring 1 L40 | 20 | 2.9 | 84 / 253 | 170 | 75 | 2.5 / 5.0 / 11.3 | 28k |
| Ring 2 L45 | 23 | 3.1 | 92 / 276 | 200 | 82 | 2.7 / 5.5 / 12.3 | 35k |
| Ring 3 L50 | 26 | 3.3 | 99 / 296 | 230 | 89 | 3.0 / 5.9 / 13.4 | 42k |

Geared multiplies the window runs, drops and materials by 3. Leveling is fast in this game (1.5-1.9 levels per run), so a typical character has seen only about 3-4 runs' worth of drops at its level.

**Selection and disposal.** For each slot (weapon first) the best candidate is equipped by the bot's own score, in two passes so that two-handers and off-hands settle. Leftover commons are sold and the rest salvaged (`Loot.salvage_yield`). That is where most of the arcane dust and monster cores come from. Half of the window's gold counts as already spent.

**Crafting, as a player does it with the meter** (`craft_gear`):

1. Upgrades come first, since they are exempt from the meter: up to +5, weapon first, with up to 70% of the gold.
2. Then the rolling crafts: raise rarity, add affix, reroll the weakest affix, and remove-weakest-plus-add. They are ranked by expected score gain (two trial rolls on a copy, then the real craft is rolled afresh, so the bot never sees the result before paying) per material value. Material value is about the inverse of its drop weight, so a catalyst counts 9x as much as an arcane dust.
3. Each rolling craft rolls the meter (`CorruptionRules.roll`). A sealed item gets no more crafts.
4. A geared Atlas character applies Fixative (up to 2 uses on 4 items) when one more hit would seal an item.

The town visit's own crafting (`sb_hub.craft`) also rolls the meter for typical and geared bots.

Catalysts are the bottleneck: a typical character has about 3, so it makes 1-3 add-affix crafts and 6-10 rerolls per kit, and 0-1.6 items end up sealed. Typical crafting is limited by materials, not by the meter. That matches the drop tables.

**Gems and runes.** Gems drop in the last 10 levels at those monster levels (35-40 at T6). Runes come from the whole game at 2.5 per run, capped at 36.

**Points (reference player, BOT_GEAR_AUDIT.md section 5).** The dungeon stages already match. The Atlas adds the T6 first kill, Abyss depth 10 per ring (milestones through `abyss_best`) and the Layer Wardens of the lower rings, which gives +2/+4/+6 at rings 1/2/3.

## 4. Keystone builds and the analyser

`tests/smartbot/sb_builds.gd` holds the builds. Each build gives the planner targets:

- the tree gem socket and first mastery from level 1
- the keystone from `ks_at`, walked node by node on the game's shortest route
- the other masteries after that

Mastery effects and the capstone (`_5` or `_6`) are chosen by the power score, and the socket gets the best pouch gem. Skills with the build's tags are ranked 1.6x higher (3x for Glacial Heart, which punishes hits on targets that are not chilled). The turret, trap and minion builds also set their own hotbar role order.

| Class | Build | Keystone | Masteries / socket | Spec |
|---|---|---|---|---|
| warrior | w_earthbreaker | Earthbreaker | Melee / Warrior socket | Earthbreaker |
| warrior | w_momentum | Overwhelming Momentum | Melee, Bulwark / Warrior | Weapon Master |
| warrior | w_riposte | Iron Riposte | Bulwark, Melee / Warrior | Juggernaut |
| warrior | w_executioner | Executioner's Creed | Melee / Warrior | Berserker |
| ranger | r_perfect_aim | Perfect Aim | Projectile / Ranger | Deadeye |
| ranger | r_machinist | Automaton Doctrine | Deployable / Ranger | Machinist |
| ranger | r_trapper | Master Trapper | Deployable / Ranger | Trapper |
| ranger | r_wind | Wind Dancer | Projectile / Ranger | Wraith Hunter |
| mage | m_glacial | Glacial Heart | Elemental / Mage | Cryomancer |
| mage | m_embers | Avatar of Embers | Elemental / Mage | Pyromancer |
| mage | m_convergence | Elemental Convergence | Elemental / Mage | element of the main skill |
| mage | m_legion | Legion of Bone | Minion / Mage | Summoner |

**Why real runs rather than Training Grounds dummies.** I had proposed dummies, but the analyser uses real runs. Several keystones only work in real combat: Earthbreaker's stun, Perfect Aim's distance, Wind Dancer's dodge rolls, Iron Riposte's blocks and Glacial Heart's chill. The smartbot also has no Training Grounds driver. Real dungeon and Atlas runs test all of that with packs and the boss included.

**Method.** `build_analyser.py` runs every build plus `none` (the planner with no keystone) as a full smartbot batch:

- typical gear, Competent profile, **10 runs per cell** (first pass: 4 runs, in the cloud)
- stages T3 L20, T6 L46 and ring 3 L50 (`atlas:3,0`)
- the same kit seeds for every build, so the comparison is paired

A player commits to one build, so the pick is per class: the build with the lowest mean relative clear time against `none` over the three stages. A lower boss-kill rate than `none` adds a penalty (the win-rate gap, i.e. 0.25 per kill fewer in 4 runs).

**10-run results (2026-11-06, run natively on Dan's Windows PC, Godot 4.0 win64, 45 batches of 10).** The 4-run cloud numbers are in the last column for comparison.

| Class | Build | Mean relative clear (1.00 = no keystone) | T3 / T6 / R3 | 4-run mean |
|---|---|---|---|---|
| warrior | **w_earthbreaker** | **0.83** | 0.74 / 0.92 / 0.83 | 0.89 |
| warrior | w_executioner | 0.94 | 0.86 / 0.97 / 1.01 | 1.05 |
| warrior | w_momentum | 1.03 | 0.99 / 1.07 / 1.01 | 0.99 |
| warrior | w_riposte | 1.05 | 0.88 / 1.04 / 1.24 | 0.98 |
| ranger | **r_perfect_aim** | **1.08** | 1.16 / 1.02 / 1.05 | 1.01 |
| ranger | r_wind | 1.13 | 1.27 / 1.15 / 0.99 | 1.08 |
| ranger | r_machinist | 1.30 | 1.04 / 1.16 / 1.69 | 1.25 |
| ranger | r_trapper | 1.30 | 1.06 / 1.35 / 1.50 | 1.30 |
| mage | **m_embers** | **0.91** | 0.85 / 0.88 / 1.00 | 0.88 |
| mage | m_convergence | 1.01 | 0.98 / 1.03 / 1.02 | 1.04 |
| mage | m_glacial | 1.07 | 1.23 / 0.97 / 1.02 | 1.02 |
| mage | m_legion | 1.24 | 1.17 / 1.29 / 1.26 | 1.27 |

Every build, including `none`, killed the boss in all 10 runs at every stage, with no deaths, so the ranking is on clear time alone. Damage taken still favours the warrior and mage picks: the Earthbreaker warrior took 3,287 at ring 3 vs 5,065 with no keystone, and the Embers mage took 122 at T6 vs 533. The full per-stage table (boss kills, deaths, clear time, damage taken, keystones, spec) is in `tests/smartbot/out/builds/analyser_typical.md`, and the evidence is in `build_picks.json`.

**Reading it.** The three class picks are the same as in the 4-run pass:

- **Earthbreaker** is now clearly ahead: 17% faster than no keystone, and fastest at all three stages. Executioner's Creed moved up to second (0.94). Iron Riposte dropped to last, because it is slow at ring 3 (1.24).
- **Avatar of Embers** stays the mage pick: 9% faster, and the stage best at all three stages, though it only ties `none` at ring 3. Legion of Bone is still the slowest. Its gear score values only the main hit, not minions (a known limit).
- **Ranger: no keystone build beats `none`.** Perfect Aim is the least bad (1.08, so 8% slower). It ties `none` at T6 and is behind at T3 (1.16). Wind Dancer is the only build at or under 1.00 at any stage (ring 3, 0.99). Both take less damage than `none` at ring 3 (420 / 451 vs 699). Turrets and traps are still clearly worse at T6 and ring 3. The 4-run "level with none" result was noise in the ranger's favour.

With 10 runs the stage-by-stage bests are steadier for warrior and mage. For the ranger, a new or reworked build is needed before a keystone pick can be frozen. Until then, `--plan=none` is the honest ranger choice for tuning (section 10).

## 5. Gear profile results (entry kits, static)

Means over 5 kits per cell, seeds 700 (T) / 900 (R), `--kit_only=1`. "DPS raw" is the bot's static DPS of the better main skill with no defences, and "vs stage" is the same after the stage's generic enemy defence (section 1). Both are computed the same way for every profile. Multipliers are DPS raw / DPS vs stage / EHP against legacy. "Typical, no keystone" is typical gear with `--plan=none`.

| Stage | Class | Profile | Life | Lowest res | DPS raw | DPS vs stage | EHP | Rare+ slots | Points | Crafts add / reroll / rarity / swap, sealed |
|---|---|---|---|---|---|---|---|---|---|---|
| T3 L20 | warrior | legacy | 661 | 20 | 302 | 285 | 1,120 | 2.8 | 21 | - |
| | | typical, no keystone (x2.41 / x2.39 / x1.40) | 804 | 30 | 729 | 682 | 1,567 | 6.6 | 21 | 1.6 / 5.0 / 2.6 / 0.2, 0.0 |
| | | typical, Earthbreaker (x3.43 / x3.44 / x1.06) | 668 | 21 | 1,036 | 979 | 1,192 | 7.0 | 21 | 1.4 / 4.8 / 2.8 / 0.2, 0.0 |
| | | geared, Earthbreaker (x4.89 / x4.84 / x1.90) | 782 | 50 | 1,476 | 1,379 | 2,133 | 10.4 | 21 | 2.6 / 7.6 / 3.8 / 0.8, 0.4 |
| T3 L20 | ranger | legacy | 429 | 14 | 372 | 351 | 608 | 3.4 | 21 | - |
| | | typical, no keystone (x3.22 / x3.10 / x1.35) | 513 | 12 | 1,196 | 1,089 | 822 | 8.2 | 21 | 1.6 / 5.4 / 3.6 / 0.6, 0.2 |
| | | typical, Perfect Aim (x2.83 / x2.75 / x1.36) | 517 | 10 | 1,051 | 967 | 826 | 7.4 | 21 | 1.6 / 7.0 / 3.0 / 0.4, 0.4 |
| | | geared, Perfect Aim (x2.73 / x2.69 / x2.25) | 649 | 38 | 1,015 | 945 | 1,366 | 10.2 | 21 | 2.0 / 9.2 / 3.2 / 0.4, 0.4 |
| T3 L20 | mage | legacy | 419 | 10 | 437 | 374 | 547 | 2.4 | 21 | - |
| | | typical, no keystone (x1.19 / x1.22 / x1.60) | 558 | 25 | 518 | 457 | 874 | 7.6 | 21 | 1.6 / 5.4 / 3.8 / 0.0, 0.2 |
| | | typical, Embers (x1.78 / x1.82 / x1.47) | 531 | 25 | 778 | 682 | 804 | 7.4 | 21 | 1.4 / 3.6 / 4.0 / 0.2, 0.2 |
| | | geared, Embers (x2.38 / x2.43 / x2.48) | 717 | 43 | 1,037 | 911 | 1,356 | 10.2 | 21 | 1.6 / 9.6 / 1.8 / 1.0, 0.4 |
| T6 L46 | warrior | legacy | 1,386 | 47 | 2,254 | 1,933 | 3,303 | 3.4 | 50 | - |
| | | typical, no keystone (x2.07 / x2.14 / x2.04) | 1,848 | 73 | 4,671 | 4,128 | 6,748 | 9.6 | 50 | 1.8 / 10.2 / 4.0 / 0.4, 0.6 |
| | | typical, Earthbreaker (x3.15 / x3.27 / x1.97) | 1,831 | 73 | 7,088 | 6,322 | 6,513 | 9.6 | 50 | 1.8 / 10.2 / 4.0 / 0.4, 0.6 |
| | | geared, Earthbreaker (x4.46 / x4.60 / x2.69) | 2,224 | 75 | 10,059 | 8,886 | 8,882 | 10.6 | 50 | 0.6 / 8.6 / 1.8 / 1.0, 0.0 |
| T6 L46 | ranger | legacy | 836 | 40 | 4,173 | 3,312 | 1,459 | 3.0 | 50 | - |
| | | typical, no keystone (x2.02 / x2.14 / x2.11) | 1,121 | 71 | 8,414 | 7,085 | 3,084 | 8.8 | 50 | 1.8 / 9.0 / 4.0 / 1.0, 0.2 |
| | | typical, Perfect Aim (x2.51 / x2.66 / x2.08) | 1,118 | 71 | 10,465 | 8,824 | 3,030 | 8.8 | 50 | 1.8 / 9.0 / 4.0 / 1.0, 0.2 |
| | | geared, Perfect Aim (x3.97 / x4.27 / x2.73) | 1,387 | 74 | 16,548 | 14,141 | 3,991 | 11.0 | 50 | 3.0 / 11.2 / 3.6 / 2.2, 1.0 |
| T6 L46 | mage | legacy | 761 | 59 | 3,195 | 2,289 | 1,358 | 2.6 | 50 | - |
| | | typical, no keystone (x1.10 / x1.16 / x1.98) | 1,190 | 69 | 3,526 | 2,654 | 2,690 | 8.8 | 50 | 2.2 / 8.2 / 4.6 / 0.8, 0.4 |
| | | typical, Embers (x1.82 / x1.86 / x1.84) | 1,089 | 74 | 5,809 | 4,269 | 2,501 | 8.6 | 50 | 2.8 / 10.4 / 4.2 / 0.6, 0.4 |
| | | geared, Embers (x3.78 / x4.44 / x2.73) | 1,630 | 74 | 12,088 | 10,165 | 3,709 | 10.4 | 50 | 2.8 / 9.6 / 4.8 / 1.0, 0.4 |
| Ring 1 L40 | warrior | legacy | 1,313 | 32 | 1,739 | 1,591 | 2,451 | 3.4 | 44 | - |
| | | typical, no keystone (x2.30 / x2.17 / x2.25) | 1,626 | 63 | 3,996 | 3,456 | 5,504 | 8.6 | 46 | 1.0 / 8.8 / 3.0 / 0.6, 0.4 |
| | | typical, Earthbreaker (x2.78 / x2.63 / x2.27) | 1,637 | 63 | 4,834 | 4,184 | 5,566 | 8.6 | 46 | 1.0 / 8.8 / 3.0 / 0.6, 0.4 |
| | | geared, Earthbreaker (x4.33 / x4.19 / x3.06) | 1,911 | 74 | 7,525 | 6,668 | 7,508 | 10.2 | 46 | 3.2 / 10.2 / 3.2 / 0.6, 1.4 |
| Ring 1 L40 | ranger | legacy | 671 | 32 | 1,720 | 1,520 | 1,165 | 2.2 | 44 | - |
| | | typical, no keystone (x3.26 / x3.24 / x1.85) | 941 | 61 | 5,602 | 4,923 | 2,153 | 8.4 | 46 | 2.0 / 7.4 / 3.6 / 0.0, 0.4 |
| | | typical, Perfect Aim (x3.37 / x3.34 / x1.83) | 937 | 61 | 5,803 | 5,083 | 2,138 | 8.4 | 46 | 2.0 / 7.4 / 3.6 / 0.0, 0.4 |
| | | geared, Perfect Aim (x6.56 / x6.33 / x3.12) | 1,234 | 73 | 11,276 | 9,626 | 3,633 | 10.8 | 46 | 4.2 / 11.6 / 3.2 / 0.4, 0.2 |
| Ring 1 L40 | mage | legacy | 726 | 47 | 2,710 | 2,078 | 1,150 | 2.2 | 44 | - |
| | | typical, no keystone (x1.05 / x1.05 / x1.67) | 981 | 57 | 2,854 | 2,188 | 1,916 | 8.2 | 46 | 1.4 / 7.6 / 3.4 / 0.6, 0.2 |
| | | typical, Embers (x1.38 / x1.38 / x1.72) | 993 | 58 | 3,732 | 2,861 | 1,980 | 8.6 | 46 | 1.6 / 5.6 / 3.8 / 0.4, 0.0 |
| | | geared, Embers (x3.05 / x3.21 / x2.75) | 1,269 | 74 | 8,255 | 6,668 | 3,167 | 10.6 | 46 | 2.0 / 7.6 / 2.0 / 1.8, 0.4 |
| Ring 3 L50 | warrior | legacy | 1,504 | 25 | 2,052 | 1,734 | 3,068 | 3.0 | 54 | - |
| | | typical, no keystone (x2.53 / x2.72 / x2.23) | 1,998 | 73 | 5,185 | 4,713 | 6,842 | 9.6 | 60 | 1.2 / 6.4 / 2.8 / 1.2, 0.2 |
| | | typical, Earthbreaker (x3.08 / x3.30 / x2.15) | 2,015 | 73 | 6,326 | 5,718 | 6,586 | 9.6 | 60 | 1.2 / 6.4 / 2.8 / 1.2, 0.2 |
| | | geared, Earthbreaker (x5.04 / x5.15 / x2.97) | 2,381 | 75 | 10,351 | 8,921 | 9,127 | 10.4 | 60 | 3.8 / 7.8 / 3.8 / 0.4, 0.4 |
| Ring 3 L50 | ranger | legacy | 782 | 45 | 2,651 | 2,289 | 1,518 | 2.8 | 54 | - |
| | | typical, no keystone (x3.37 / x3.12 / x2.04) | 1,132 | 67 | 8,920 | 7,135 | 3,090 | 9.2 | 60 | 2.6 / 10.2 / 4.6 / 0.8, 1.0 |
| | | typical, Perfect Aim (x4.43 / x4.15 / x2.03) | 1,129 | 67 | 11,742 | 9,490 | 3,081 | 9.2 | 60 | 2.6 / 10.2 / 4.6 / 0.8, 1.0 |
| | | geared, Perfect Aim (x6.18 / x5.74 / x2.82) | 1,520 | 73 | 16,376 | 13,139 | 4,283 | 10.8 | 60 | 3.2 / 11.2 / 3.6 / 2.0, 0.2 |
| Ring 3 L50 | mage | legacy | 865 | 44 | 3,192 | 2,128 | 1,388 | 2.4 | 54 | - |
| | | typical, no keystone (x2.42 / x2.67 / x2.11) | 1,263 | 68 | 7,733 | 5,671 | 2,928 | 8.2 | 60 | 2.0 / 8.6 / 4.6 / 0.2, 0.0 |
| | | typical, Embers (x3.41 / x4.00 / x2.00) | 1,258 | 67 | 10,884 | 8,520 | 2,775 | 9.0 | 60 | 2.4 / 8.2 / 4.2 / 0.8, 0.6 |
| | | geared, Embers (x4.49 / x4.78 / x2.79) | 1,638 | 75 | 14,322 | 10,175 | 3,870 | 10.2 | 60 | 1.6 / 6.0 / 3.0 / 0.0, 0.2 |

Notes:

- The static DPS counts the keystone only where `Combat.player_packet` sees it. Avatar of Embers' conversion counts. Earthbreaker's 35% more for slams is static but also changes the hotbar. The conditional ones (Perfect Aim's distance, Glacial Heart's chill) are not counted, so the real runs in section 4 decide.
- Typical mage DPS without a keystone is noisy at T6 and ring 1 (x1.05-1.16). The mage's DPS hangs on one caster weapon with flat spell damage, and only a few such weapons drop in 3 runs. Geared has 3x the chances.
- The mage's EHP stays at 0.38-0.45x the warrior's in every profile. Gear raises everyone's defence about equally.
- Ring-3 static mage DPS is now above the warrior's: about 1.7x raw and 1.5x vs the stage defence for typical Embers. That comes from caster itemisation plus the Embers conversion. Phase C should check it in real Warden fights, which have high fire resistance (BOT_GEAR_AUDIT.md section 1).

## 6. Real runs so far (a preview for Phase C)

T6 L46, seed 700, 4 runs per cell, Competent. Typical uses each class's pick, and "none" is typical gear with no keystone (from the analyser).

| Class | Profile | Boss kills | Deaths | Clear s (wins) | Damage taken | ehp_est | Keystone |
|---|---|---|---|---|---|---|---|
| warrior | legacy | 4/4 | 0 | 90 | 1923 | 3898 | - |
| warrior | typical, no keystone | 4/4 | 0 | 53 | 622 | 6659 | - |
| warrior | typical, w_earthbreaker | 4/4 | 0 | 59 | 487 | 6016 | p3b_eb_cap |
| warrior | geared, w_earthbreaker | 4/4 | 0 | 57 | 513 | 7656 | p3b_eb_cap |
| ranger | legacy | 4/4 | 0 | 77 | 192 | 1439 | - |
| ranger | typical, no keystone | 4/4 | 0 | 55 | 93 | 2862 | - |
| ranger | typical, r_perfect_aim | 4/4 | 0 | 61 | 78 | 2737 | ks_perfect_aim |
| ranger | geared, r_perfect_aim | 4/4 | 0 | 46 | 64 | 3626 | ks_perfect_aim |
| mage | legacy | 4/4 | 0 | 99 | 875 | 1340 | - |
| mage | typical, no keystone | 4/4 | 0 | 100 | 814 | 2514 | - |
| mage | typical, m_embers | 4/4 | 0 | 69 | 55 | 2177 | p2_ks_embers |
| mage | geared, m_embers | 4/4 | 0 | 66 | 63 | 3092 | p2_ks_embers |

Typical gear alone cuts the warrior's and ranger's clear time by about 30-40% and their damage taken by 50-70% against legacy. The mage needs the Embers build to gain (100 s -> 69 s, damage taken 814 -> 55). Geared is only a little faster than typical at T6: the boss kill is no longer the limit there, and ring 3 is where the gap shows (section 5). The bot's `dps_est` column is left out because typical and geared rows score DPS after the stage defence, so it is not comparable with legacy.

Frozen baseline `caster_v1.csv` (legacy, T6 L41, 10 runs) for scale: warrior 10/10 boss kills, 111 s; ranger 10/10, 92 s; mage 8/10, 114 s.

## 7. Verification

- **Legacy unchanged.** The full `CharacterData.to_dict()` and the original summary fields of 18 legacy kits (3 classes x T3 L20 / T6 L46 x 3 seeds) are identical before and after Phase B. A legacy T6 mage dungeon run (seed 1000) gives an identical CSV row.
- **No game files touched.** Only `tests/smartbot/` and `docs/` changed. No game test loads the smartbot scripts (`test_runner.gd` and `test_atlas.gd` only mention it in comments), so the game test suite is unaffected.
- **Smoke tests.** All 12 builds allocate their keystone, mastery and socket, pick their spec and fill the hotbar (T3 L20 kits). 180 analyser runs and the section 6 runs finished with no script errors. Kit generation for typical and geared takes about 2-5 s per character (legacy about 1 s).
- Machine: cloud workspace, Godot 4.0-stable Linux headless (Phase A showed Linux and Windows produce identical entry kits). The section 4 analyser numbers were rerun with 10 runs on Dan's PC (Godot 4.0 win64), with 0 script errors in 450 runs. The section 6 preview runs are still cloud runs.
- **Windows fixes for that rerun (smartbot only).** `smartbot.gd`: run IDs with a plan contain `|`, which Windows forbids in file names, so every keystone-build run failed to write its row file (`store_string` on null, line 493). `_row_path` and `_ckpt_path` now pass the ID through `_safe_fn`, which replaces `| : * ? " < > \` with `_`. The run ID inside the CSV is unchanged. `build_analyser.py`: `--force` now deletes the cell's CSV, `_perf.csv`, `_kits.json`, `_errors.txt`, `_rows/` and `_ckpt/` first, because smartbot otherwise resumes from them and replays nothing. The boss-kill penalty and the gain/worse note now compare win rates, so cells with different run counts compare fairly. With equal run counts the result is the same as before.

## 8. Known limits

- **Kills per run** come from bot runs (all classes). A player who clears every pack sees more drops, so typical is a little conservative.
- **Dungeon modifiers** (`reward_bonus`, Pigments) and the player's own `item_rarity` beyond what the starting gear has are ignored. So are vendor purchases inside the window. The town visit still shops.
- **The gear score values minions, turrets and traps only through their own hit** (as before). That is why the summoner, turret and trap builds lose the analyser, and why the bot plays them poorly.
- **The analyser uses 10 runs per cell** (since the rerun on Dan's PC). Differences under about 5% at a single stage are still within noise.
- **The spec re-pick** costs `spec_reset_cost` gold and only happens when the bot can pay. A bot whose main skill flips between two elements will pay that more than once, as a player would.
- **The penetration value** uses a generic stage defence on purpose (Dan: no skill choice by target resistance). So the bot does not swap to cold against a fire-resistant Warden.

## 9. Files and commands

New: `tests/smartbot/sb_gear.gd`, `sb_builds.gd`, `build_analyser.py`, `gear_compare.py`, `build_picks.json`, `docs/BOT_GEAR_PROFILES.md`. Changed: `smartbot.gd` (`--gear`, `--plan`, Atlas ring for the kit, kit-dump fields), `sb_kit.gd` (profile branch, reference points, stage defence), `sb_hub.gd` (meter-aware crafting, stage-defence DPS, build tags and roles, spec re-pick, best capstone, tree gems), `sb_planner.gd` (build-plan targets, mastery effects), `README.md` (arguments, files).

```
# entry kits for a profile
godot --headless --fixed-fps 60 --path . res://tests/smartbot/smartbot.tscn -- --class=mage --tier=6 --level=46 --runs=5 --seed=700 --kit_only=1 --gear=typical --out=res://tests/smartbot/out/k_typical/mage_T6.csv
python tests/smartbot/gear_compare.py tests/smartbot/out legacy typical geared
# a tuning batch with typical gear and the analyser's build (Atlas ring 3)
godot ... smartbot.tscn -- --class=warrior --tier=6 --level=50 --dungeon=atlas:3,0 --runs=10 --seed=900 --gear=typical --jobs=10 --out=res://tests/smartbot/out/p_typ_r3.csv
# re-run the build analyser (writes build_picks.json and out/builds/analyser_typical.md)
python tests/smartbot/build_analyser.py --godot "W:\AI game\Godot_v4.0-stable_win64_console.exe" --runs 10 --stages T3,T6,R3
```

## 10. Next

- **Phase C: done (2026-11-07), see `docs/PHASE_C_MEASUREMENTS.md`.** Three reworked ranger builds were tried (`r_far_aim`, `r_wind_roll`, `r_glass`) and none beats no keystone, so Phase C ran the ranger with `--plan=none`.
- **Ranger build:** none of the four ranger keystone builds beats no keystone (best: Perfect Aim 1.08x). `--plan=auto` still gives the ranger Perfect Aim, because the analyser always picks a keystone build. Either use `--plan=none` for the ranger in Phase C tuning, or write a new or reworked ranger build (for example Wind Dancer with a later `ks_at`, since it is level at ring 3) and rerun with `--classes ranger`.
- **Phase D:** re-measure Rot, the Wager and the Wardens with typical bots, then retune (Dan's #6).
- **Open:** whether the bot needs better minion, turret and trap play before those builds can be judged fairly.
