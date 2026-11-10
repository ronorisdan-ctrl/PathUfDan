# Smartbot gear and passive tree audit (Phase A)

2026-11-06 · Claude (Cowork) for Dan · brief: "Path of Dan: Smartbot Gear and Passive Tree Audit"

Read-only audit. **No project file was changed except this report.** Phase B has not started; the decisions at the end are for Dan.

## 1. Five-minute summary

**The tree layers are confirmed missing, but they are not the big gap. Item quality is.** The bot takes no keystones, masteries or tree gem sockets, and in the Atlas it is 2-6 points short of a real player. In the static model each of these layers is worth about 0-15% DPS, with one cell at +39%. Replacing the kit's "natural drop" items with sensible rares is worth 1.5-5x DPS for warrior and ranger, and 1.7-3x effective HP for every class.

**Better gear makes the mage gap wider, not smaller.** Rare gear lifts warrior and ranger single-target DPS 1.5-5.2x but the mage only 1.2-2.1x. Gear has flat added damage for attacks (weapon, gloves, rings, quiver) and only % increases for spells. Mage-to-warrior single-target DPS against the stage's boss profile:

| Stage | Legacy kit | Rare gear, best of 5 ("typical") | Rare gear, best of 20 ("geared") |
|---|---|---|---|
| T3 L20 | 0.94 | 0.63 | 0.59 |
| T6 L46 (T6 boss) | 0.39 | 0.32 | 0.18 |
| Atlas ring 1 L40 (ring-1 Warden) | 0.40 | 0.27 | 0.30 |
| Atlas ring 3 L50 (ring-3 Warden) | 0.34 | 0.28 | 0.25 |

The mage's effective HP stays at 0.4-0.6x the warrior's and about 0.85-1.05x the ranger's in every profile.

**Two mage-specific bot faults are worth fixing first:**

- **Element vs resistance.** The bot ranks skills by raw damage and ignores what the target resists. The ring-3 Warden (Archon Velis) has 70% fire and 60% lightning resistance but only 30% cold, and the T6 boss has 90% lightning resistance (75 base + 25 tier bonus, capped at 90). The mage's two main skills are one fire and one lightning skill in 26 of 35 kits (T3 to ring 3), and Warden resistances cut its single-target DPS to 0.40x of its no-defence value at ring 3. The warrior keeps 0.80x.
- **Element mismatch.** The specialisation, tree spend and main skill disagree. At T6 and in the Atlas, 15 of 20 mage kits have a spec that does not match their lead skill (at ring 1 all 5 are Stormcaller, lightning, but lead with fireball). Their tree points are spread over Tempest (lightning), Frostweaver (cold), Embers (fire) and Legion (minions).

**Verdict so far:** most of the mage's DPS gap is not explained by the bot's gear or tree. In this static model it comes from game itemisation (spells have no flat-damage or +skill-level affixes, and spell base damage stops scaling at skill level 20) and from Warden resistances. Real runs in Phase C still have to confirm this. The model leaves out ailments, minions, curses and conditional keystones.

### H1-H6 verdicts

| # | Hypothesis | Verdict | One-line evidence |
|---|---|---|---|
| H1 | Kit predates itemisation | **Refuted as stated, but quality is the biggest gap** | The kit uses the live drop code (`Loot.roll_item`), so it does get Tempered and Runeforged bases, sockets with top-grade gems, charms, implicits and the odd legendary. But only 12-37% of slots are rare or better, 15-36% are commons with no affixes, and affix tiers sit at 61-84% of the maximum for the item level. There are no Rot-touched implicits and no corruption. |
| H2 | Bot misses boss / Abyss / Warden points | **Refuted for T2-T6, confirmed for the Atlas** | T stages: the bot has levels plus earlier boss kills, which matches the reference player, with 0 unspent. Atlas: the bot has 44/49/54 points vs about 46/53/60 for the reference (no T6 first kill, no Abyss milestones, no Warden kills). Worth about +0-7% DPS. |
| H3 | Generic "balanced" spread, no archetype | **Confirmed** | 0 keystones, 0 masteries and 0 tree gems in all 120 kits. The planner excludes those node types (`sb_planner.gd` line 37). At the Atlas stages only 6-14 of 44-54 points sit in archetype spurs, split across 2-4 archetypes. |
| H4 | Mage hurt most | **Confirmed, but mostly not by gear or tree** | At ring 3 the mage has 846 life (warrior 1,499), 20 armour (warrior 531) and 0 block. Energy shield does not exist in the game. Single-target DPS vs the ring-3 Warden is 299 (warrior 878, ranger 1,173). Gear lifts the mage least (see the table above). |
| H5 | Kit not scaled to Atlas level | **Partly confirmed** | Item level is fine: L-4 to L, so 36-50 against monster levels 40-50, and affix tiers can reach the top tier. Below a player's: points (-2/-4/-6), rarity (the kit uses half the T6 rarity bonus, 85, while Atlas rings drop at 170-230), and no Atlas-only item layers. |
| H6 | Runes, spec and flasks not matched to the build | **Confirmed for runes and spec, not applicable to flasks** | Runes come from a generic role table. The mage spec follows the main skill's element when it is first chosen and is never revisited, so 15 of 20 T6-and-Atlas mage kits have a spec that does not match their lead skill. The game has no flask choice: two fixed flasks (life and mana), and only `flask_effect` affixes. |

The seventh question (Blink and skill bar uptime) is deferred, as the brief asks, until gear is fixed.

## 2. Method

- **The same kits the bot uses.** A small audit scene subclasses `smartbot.gd` and overrides only its `--kit_only` dump. It calls the unchanged `kit.make` with the bot's own seeding (`seed_all(mix([seed, chain, "kit"]))`). I checked it against the stock `smartbot.tscn --kit_only=1` for 5 mage R3 kits: allocation, items, `dps_est` and life were identical.
- **Stages** (5 kits each, 120 characters in total): T2 L12, T3 L20, T4 L28, T5 L37, T6 L46 with seed 700 (`--tier=N --level=L`). Atlas ring 1/2/3 use the tier-6 kit at L40/45/50 with seed 900, which is how `run_atlas_p2e.ps1` builds them. The Layer Warden fight uses the same ring kit; the runners give the Warden no separate kit.
- **Machine.** Godot 4.0-stable, Linux headless, in the cloud workspace. Smartbot README section 5 records that Linux and Windows produce identical entry kits. Only dungeon runs diverge between them, and Phase A runs no dungeons.
- **"Kit DPS" is a static estimate, not a Training Grounds run.** The smartbot has no Training Grounds driver. For each hotbar skill, `Combat.player_packet` gives the average hit with crits. It is mitigated with `TrainingRules.profile_defence` + `TrainingRules.mitigate`, the same maths the dummies use, then divided by use time or cooldown. AoE uses the bot's own `targets_factor`. Profiles are T3 normal, T6 boss, and three Layer Warden profiles: ring boss resistance + ring `resist_bonus`, armour scaled to ring level + 2. **Not counted:** DoTs (ignite, bleed, poison), minions, turrets, traps, curses, shock/chill/frailty and keystone flags. These matter for all classes, the mage most (Army of the Damned, ignite). Phase C must measure DPS on real dummies.
- **What-ifs** (section 6) rebuild the same kit and change one thing: missing points, masteries plus a socket, a keystone, or rare gear. Masteries and keystones each have a control that spends the same points with the legacy planner. Re-running the town visit alone moves numbers by up to ±7%, and up to -20% for the mage when its hotbar flips from fireball to lightning bolt against a lightning-resistant boss. Treat differences under 10% as noise.

## 3. Where the bot makes each choice (code map)

| Choice | Where | How |
|---|---|---|
| Entry kit (gear) | `sb_kit.gd` `make()` lines 36-94 | For each of 11 slots: best of `KIT_CHOICES = 3` natural drops (`Loot.roll_item(ilvl L-4..L, rarity_bonus = tier bonus x 0.5)`), scored by `hub.score + item_extra` |
| Points | `sb_kit.gd` line 44-47 | `bonus_passive_points += 1` per dungeon with tier < kit tier. No Abyss depth, no Warden kills, no T6 boss for Atlas kits |
| Currencies, gems, runes | `sb_kit.gd` lines 84-91 | gold `25+30L`, `L/3` random gems, `L/6` random runes, materials by level |
| Town visit | `sb_hub.gd` `town_visit()` line 642 | hotbar → passives → spec → equip → sell → shop → craft → gems → equip → hotbar → runes → flasks |
| Passive tree | `sb_planner.gd` `spend()` | `balanced` has no targets (lines 14/19/24). The frontier skips `keystone`, `mastery`, `socket` (line 43, look-ahead line 93). Picks are by `hub.score` gain per point |
| Power score | `sb_hub.gd` `power()` line 98 | log(DPS of the 2 main skills) + log(EHP) + move speed. Weights by `--build` |
| Hotbar | `sb_hub.gd` `choose_hotbar()` line 470 | Role order per class. Damage is ranked by raw `skill_dps`, with **no target resistance** |
| Runes | `sb_hub.gd` `rune_value()` line 542, `runes()` line 583 | Fixed value table by role and slot |
| Specialisation | `sb_hub.gd` `spec()` line 607 | Fixed per class and build. Mage = element of `main_skills[0]` **at the moment it is first chosen**, never changed after (`if ch.spec_id == ""`) |
| Crafting | `sb_hub.gd` `craft()` line 297 | socket, upgrade base, raise rarity, add affix, reroll the weakest affix, with half the gold. Calls `Loot.craft_check/apply` directly (no corruption) |
| Gems | `sb_hub.gd` `gems()` line 373, `socket_all()` | Combine, buy, socket by score. **Tree sockets (`ch.tree_gems`) are never used** |
| Flasks | `sb_hub.gd` line 655 | Refills charges `[3, 3]`. The game has only the fixed life and mana flasks |
| Atlas setup | `smartbot.gd` `_one_run()` lines 492-531 | Sets up Atlas state only; the character is the tier-6 kit at `--level` |

## 4. Dumps: what the bot actually has

Means over 5 kits per cell. Full per-item dumps (slot, base, rarity, ilvl, implicit, affixes with tiers, sockets and gems, corruption fields, nodes by cluster, tag and archetype, every skill row) are in `*_audit.json` (section 9).

### 4a. Points, gear quality and tree layers

| Stage | Class | Points total/spent/unspent | Rare+ slots | Common slots | Affixes per item | Affix tier vs max for ilvl | Sockets filled/total | Legendaries (5 kits) | Keystones / masteries / tree gems | Archetype-spur nodes per kit |
|---|---|---|---|---|---|---|---|---|---|---|
| T2 L12 | warrior | 12/12/0 | 12% | 36% | 1.3 | 0.84 | 3.6/4.6 | 0 | 0/0/0 | 0.8 |
| T2 L12 | ranger | 12/12/0 | 33% | 21% | 2.0 | 0.75 | 3.2/4.0 | 0 | 0/0/0 | 0.4 |
| T2 L12 | mage | 12/12/0 | 19% | 26% | 1.6 | 0.79 | 2.4/3.2 | 0 | 0/0/0 | 6.6 |
| T3 L20 | warrior | 21/21/0 | 23% | 31% | 1.6 | 0.67 | 4.0/4.0 | 1 | 0/0/0 | 1.0 |
| T3 L20 | ranger | 21/21/0 | 22% | 33% | 1.4 | 0.72 | 5.6/5.8 | 2 | 0/0/0 | 0.8 |
| T3 L20 | mage | 21/21/0 | 37% | 23% | 2.0 | 0.73 | 3.4/3.4 | 1 | 0/0/0 | 9.4 |
| T4 L28 | warrior | 30/30/0 | 18% | 22% | 1.7 | 0.72 | 6.2/6.2 | 1 | 0/0/0 | 1.8 |
| T4 L28 | ranger | 30/30/0 | 25% | 26% | 1.4 | 0.67 | 5.6/6.0 | 2 | 0/0/0 | 2.6 |
| T4 L28 | mage | 30/30/0 | 28% | 34% | 1.5 | 0.67 | 7.4/7.6 | 0 | 0/0/0 | 11.2 |
| T5 L37 | warrior | 40/40/0 | 25% | 20% | 1.8 | 0.66 | 7.6/7.6 | 0 | 0/0/0 | 4.6 |
| T5 L37 | ranger | 40/40/0 | 15% | 28% | 1.5 | 0.65 | 8.2/8.2 | 0 | 0/0/0 | 9.4 |
| T5 L37 | mage | 40/40/0 | 22% | 22% | 1.7 | 0.70 | 8.4/8.8 | 1 | 0/0/0 | 6.2 |
| T6 L46 | warrior | 50/50/0 | 28% | 23% | 1.8 | 0.63 | 8.8/8.8 | 1 | 0/0/0 | 7.6 |
| T6 L46 | ranger | 50/50/0 | 27% | 27% | 1.6 | 0.69 | 8.6/8.6 | 1 | 0/0/0 | 10.0 |
| T6 L46 | mage | 50/50/0 | 29% | 22% | 1.8 | 0.65 | 9.4/9.8 | 0 | 0/0/0 | 8.6 |
| R1 L40 | warrior | 44/44/0 | 35% | 20% | 2.1 | 0.65 | 8.2/8.2 | 0 | 0/0/0 | 6.4 |
| R1 L40 | ranger | 44/44/0 | 19% | 26% | 1.6 | 0.66 | 9.0/10.2 | 0 | 0/0/0 | 10.2 |
| R1 L40 | mage | 44/44/0 | 21% | 26% | 1.6 | 0.63 | 9.0/9.8 | 0 | 0/0/0 | 6.6 |
| R2 L45 | warrior | 49/49/0 | 24% | 24% | 1.8 | 0.64 | 8.4/8.4 | 0 | 0/0/0 | 7.6 |
| R2 L45 | ranger | 49/49/0 | 29% | 15% | 2.0 | 0.69 | 9.4/9.4 | 0 | 0/0/0 | 5.6 |
| R2 L45 | mage | 49/49/0 | 27% | 25% | 1.9 | 0.66 | 8.4/8.6 | 0 | 0/0/0 | 10.6 |
| R3 L50 | warrior | 54/54/0 | 29% | 23% | 1.9 | 0.61 | 8.2/8.6 | 0 | 0/0/0 | 9.2 |
| R3 L50 | ranger | 54/54/0 | 27% | 21% | 1.8 | 0.70 | 9.4/9.4 | 0 | 0/0/0 | 6.0 |
| R3 L50 | mage | 54/54/0 | 23% | 32% | 1.6 | 0.66 | 8.0/8.0 | 0 | 0/0/0 | 14.2 |

Every kit has a charm (11th slot, usually common or uncommon). Base tiers: Tempered from T3, mostly Runeforged from T5. Mean item level is L-2. No item has a Rot-touched implicit or a corrupted affix. Gems are mostly the top grade usable at the level.

### 4b. Defence

| Stage | Warrior life / armour / evasion / block / res F/C/L/V | Ranger | Mage |
|---|---|---|---|
| T2 L12 | 432 / 109 / 13 / 0 / 21/23/29/19 | 299 / 28 / 132 / 0 / 5/15/16/10 | 258 / 0 / 86 / 0 / 29/9/14/5 |
| T3 L20 | 634 / 260 / 25 / 8 / 40/26/30/21 | 400 / 34 / 199 / 0 / 33/31/26/3 | 408 / 10 / 127 / 0 / 42/24/41/4 |
| T4 L28 | 908 / 250 / 24 / 4 / 41/47/29/28 | 536 / 32 / 268 / 0 / 21/36/28/8 | 455 / 23 / 150 / 0 / 14/32/22/23 |
| T5 L37 | 1,157 / 425 / 52 / 5 / 55/55/42/41 | 704 / 55 / 406 / 0 / 25/67/35/34 | 688 / 23 / 267 / 0 / 54/63/69/15 |
| T6 L46 | 1,390 / 665 / 59 / 17 / 59/66/62/38 | 849 / 40 / 479 / 0 / 61/45/61/29 | 888 / 20 / 294 / 0 / 52/72/68/40 |
| R1 L40 | 1,296 / 525 / 8 / 6 / 56/36/62/28 | 689 / 58 / 405 / 0 / 51/55/46/45 | 682 / 16 / 289 / 0 / 48/62/70/26 |
| R2 L45 | 1,371 / 442 / 28 / 6 / 37/64/69/47 | 742 / 98 / 511 / 0 / 61/69/62/22 | 800 / 22 / 300 / 0 / 58/74/55/42 |
| R3 L50 | 1,499 / 531 / 27 / 12 / 37/67/66/65 | 782 / 88 / 580 / 0 / 60/73/54/26 | 846 / 20 / 296 / 0 / 59/69/64/29 |

No class reaches the 75% resistance cap on all three elements at any stage. The mage's life is 53-64% of the warrior's from T5 on, with almost no armour and no block. Energy shield is not a stat in this game (`character_data.resolve` has none).

### 4c. Kit DPS (static, single target unless noted)

The "main" skill is the better of the bot's two main hotbar skills. The vs-Warden column uses the stage's ring Warden.

| Stage | Class | No defences | T3 normal | T3 normal AoE | T6 boss | vs Warden | `dps_est` (bot's score) |
|---|---|---|---|---|---|---|---|
| T3 L20 | warrior / ranger / mage | 166 / 205 / 168 | 160 / 192 / 150 | 295 / 394 / 424 | 109 / 138 / 118 | | 310 / 408 / 375 |
| T6 L46 | warrior / ranger / mage | 1,214 / 1,777 / 543 | 1,161 / 1,587 / 477 | 2,074 / 3,309 / 1,591 | 1,079 / 980 / 419 | | 2,181 / 3,555 / 1,666 |
| R1 L40 | warrior / ranger / mage | 988 / 915 / 407 | 939 / 845 / 355 | 1,725 / 2,007 / 1,064 | 770 / 569 / 289 | 824 / 696 / 326 | 1,824 / 1,616 / 1,222 |
| R2 L45 | warrior / ranger / mage | 1,224 / 1,380 / 570 | 1,161 / 1,279 / 496 | 2,042 / 3,070 / 1,513 | 1,019 / 956 / 309 | 1,088 / 1,161 / 428 | 2,170 / 3,078 / 1,719 |
| R3 L50 | warrior / ranger / mage | 1,099 / 1,566 / 748 | 1,028 / 1,474 / 651 | 1,865 / 3,010 / 1,953 | 751 / 1,178 / 253 | 878 / 1,173 / 299 | 2,012 / 2,938 / 1,633 |

The mage is level with the others up to T3/T4 (mage/warrior ratio 0.94-1.04 at T2-T3, 0.70-0.75 at T4). It falls to 0.30-0.47 against the boss and Warden profiles from T5 on. That is where Runeforged weapon bases arrive for attackers, and where the mage's main spells near the skill-level cap of 20 (`MAX_SKILL_LEVEL`; spell base damage only scales with skill level). The mage holds its own in AoE against T3 packs (ratio 0.62-1.44).

### 4d. Skill bar, runes, specialisation (chain 0, ring 3)

| Class | Hotbar | Runes | Spec |
|---|---|---|---|
| warrior | quick_slash, cleave, avatar_of_war, last_stand, battle_leap, war_cry, adrenaline_surge | quick_slash: haste, concussive; avatar_of_war: recharge | Weapon Master 1-4 + 6 (all 40 warrior kits) |
| ranger | sniper_round, piercing_arrow, deadeye, frost_turret, smoke_bomb, lightning_trap, marked_prey | sniper_round: haste, chaining, piercing; deadeye: recharge; frost_turret: horde | Deadeye 1-4 + 6 (all 40 ranger kits) |
| mage | fireball, lightning_bolt, army_of_the_damned, archmage_ascension, blink, mark_of_ruin, static_field | fireball: piercing, concentrated; army: bone_frenzy | Stormcaller 1-4 + 6 |

Mage spec vs lead skill across the 5 kits per stage:

| Stage | Matched kits | Kits as spec / lead skill |
|---|---|---|
| T2 | 5 of 5 | |
| T3 | 3 of 5 | |
| T4 | 4 of 5 | |
| T5 | 4 of 5 | |
| T6 | 2 of 5 | arcanist / fireball, Stormcaller / fireball x2, Stormcaller / lightning, Pyromancer / fireball |
| R1 | 0 of 5 | Stormcaller / fireball x5 |
| R2 | 0 of 5 | Stormcaller / fireball x3, Pyromancer / lightning, Stormcaller / ice lance |
| R3 | 3 of 5 | |

Matched means a Pyromancer leading with a fire skill, a Stormcaller with a lightning skill, and so on.

## 5. Reference player

**Points** come from the code (`CharacterData.total_passive_points` = levels - 1 + `bonus_passive_points` + Abyss milestones). Bonus points come only from the first kill of each dungeon boss (`dungeon.gd` line 849) and of each Layer Warden (line 1010). Atlas hex bosses give none. Abyss milestones are depths 10, 20 ... 70 (7, not 4). The budget is 59 + 6 + 7 = 72. I found **no "side content" points in the code**, so the brief's "about 3 side content" and "4 Abyss" look out of date.

| Stage | Levels | Boss first kills | Abyss (assumed depth) | Warden kills | Reference | Bot | Gap |
|---|---|---|---|---|---|---|---|
| T2 L12 | 11 | 1 | 0 | 0 | 12 | 12 | 0 |
| T3 L20 | 19 | 2 | 0 | 0 | 21 | 21 | 0 |
| T4 L28 | 27 | 3 | 0 | 0 | 30 | 30 | 0 |
| T5 L37 | 36 | 4 | 0 | 0 | 40 | 40 | 0 |
| T6 L46 | 45 | 5 | 0-1 | 0 | 50-51 | 50 | 0-1 |
| Ring 1 L40 | 39 | 6 | 1 (depth 10) | 0 | 46 | 44 | 2 |
| Ring 2 L45 | 44 | 6 | 2 (depth 20) | 1 | 53 | 49 | 4 |
| Ring 3 L50 | 49 | 6 | 3 (depth 30) | 2 | 60 | 54 | 6 |
| Warden fight | as the ring | | | | as the ring | as the ring | as the ring |

The Atlas unlocks after the T5 boss (`atlas.json` `unlock_dungeon`), so the T6 first kill (+1) is likely but not certain at ring 1. The Abyss depths are assumptions for a player who visits the Abyss now and then.

**Items.** A sensible rare set is every slot rare (20% epic) on a class-usable base at ilvl = level, best of N by the bot's own score, with sockets filled. "Typical" uses N = 5 and "geared" uses N = 20. From T6 on, the lowest elemental resistance then reaches 67-75% (from 28-53%). These are proposals for the Phase B stage table, measured in section 6.

## 6. Gaps, ranked by estimated impact

What-if results: means over 5 kits. The multiplier is relative to the legacy kit. Single-target DPS is against the stage's boss profile (T3 normal, T6 boss, Warden ring 1 or ring 3). EHP is the bot's own `ehp_est`. Full tables are in `whatif.md`.

| Class, stage | Missing points | Masteries + class socket (control) | Static keystone pick (control) | Rare gear N=5 | Rare gear N=20 | All together |
|---|---|---|---|---|---|---|
| Warrior T6 | 0 pts | DPS 1.09 (0.95), EHP 1.09 | 0.94 (0.96) | DPS 1.53, EHP 1.82 | DPS 2.56, EHP 2.81 | DPS 2.94, EHP 2.19 |
| Warrior R3 | +6: DPS 1.07, EHP 1.06 | 1.13 (1.04), 1.08 | 1.07 (1.09) | 2.07, 1.70 | 2.83, 2.72 | 3.47, 2.72 |
| Ranger T6 | 0 pts | 1.10 (1.00), 1.03 | 1.06 (1.03) | 2.80, 1.97 | 4.30, 2.68 | 4.06, 2.52 |
| Ranger R3 | +6: 1.04, 1.04 | 1.12 (1.02), 1.06 | 1.12 (1.03) | 2.80, 2.12 | 3.57, 2.42 | 5.23, 2.47 |
| Mage T6 | 0 pts | 0.94 (0.83), 1.07 | 0.93 (0.81) | 1.28, 1.85 | 1.18, 2.26 | 1.05, 2.21 |
| Mage R3 | +6: 1.00, 1.03 | 1.08 (0.98), 1.06 | 1.07 (0.94) | 1.72, 1.92 | 2.11, 2.68 | 2.70, 2.60 |

**Warrior**

1. Item quality: DPS x2.1-2.8 and EHP x1.7-2.7 at ring 3. Lowest resistance goes from 30 to 67-72.
2. Masteries + class socket: +9-25% DPS, +8% EHP, about +10% better than spending the same points as today.
3. Missing Atlas points: +4-7%.
4. Keystone: the static model gains only +3-7%, but the right keystone is conditional. Earthbreaker gives 35% more damage to slams, and heavy_strike and battle_leap are already slams. Its value needs real runs.
5. No runes or spec issue found.

**Ranger**

1. Item quality: DPS x2.8-5.2, EHP x2.0-2.7.
2. Masteries + socket: +10-39% DPS (ring 1 is the high end).
3. Keystone: Perfect Aim or Prismatic Soul raise the lowest resistance from about 42 to 50-63, but the DPS effect is unmeasured statically.
4. Missing points: +4-14%.

**Mage**

1. Item quality, mainly for defence: EHP x1.8-2.7 and ring-3 life 846 → 1,330-1,600. DPS only x1.2-2.1.
2. **Element vs target resistance (bot fault).** The ring-3 Warden takes 2.3x more from cold than from fire and 1.75x more than from lightning. The ring-2 Warden (Gravemaw) has 5% cold vs 50% fire resistance. The bot already unlocks ice_lance, glacial_eruption, blizzard, frostbolt and frost_nova. Not measured as a what-if; the upper bound on the main hit is about x1.75-2.3 against those Wardens.
3. **Spec, tree and skill element mismatch (bot fault).** Up to 4 archetypes per kit, and the spec is locked from an earlier skill choice. A committed cold build (Frostweaver plus Glacial Heart, 40% more damage vs frozen enemies) would also suit the ring-3 Warden. Unmeasured statically.
4. Masteries + socket: about 10% more DPS than the same points spent by today's planner, +5-8% EHP.
5. Missing points: about +0%.

**Game-side observations (out of scope; for Dan, Phase D):**

- **Caster gear has no flat damage.** Attack weapons, gloves, rings and quivers roll flat added damage (`emberforged`, `rimecut`, `stormcharged`, `jagged`). Caster gear rolls only % increases (`arcane`, `pyromancers`, `glacial`, `voltaic`, `of_haste`). No affix adds flat spell damage or + skill level. This is why gear widens the mage gap.
- **Spell scaling stops at skill level 20.** Spell base damage scales only with skill level (`1 + 0.12 x (lvl - 1)`, capped at 20). Fireball reaches the cap at character level 44, while attacks keep scaling with weapon base tiers.
- **Boss resistances against the mage's main elements:** T6 boss (Stormheart) 90% lightning; ring-3 Warden 70% fire and 60% lightning.

## 7. What the brief assumed that the code says otherwise

- **Start levels.** The frozen baseline runs at the kit default `min_level + 3` (T3 L18, T6 L41), not `min_level + tier + 2`. The study levels (12/20/28/37/46) come in through `--level`.
- **Abyss milestones** are 7 (depths 10-70), and no side-content points exist in the code (section 5).
- **Kit features.** The kit is not "pre-itemisation": it draws from today's drop tables. What it lacks is drop quality, not features (H1).
- **Flasks.** There are no flask items to choose (H6).

## 8. Decisions for Dan (before Phase B)

The six decisions from the brief, updated with the audit numbers, and two new ones.

| # | Decision | Recommendation after the audit |
|---|---|---|
| 1 | Default profile for Atlas and Wager bots: `typical` or `geared`? | `typical` for tuning, `geared` as the upper-bound check. Proposed item bar: typical = rare (20% epic) best of 5 at ilvl = level, geared = best of 20. These two already differ by x1.2-1.6 DPS. |
| 2 | Flag-less default stays `legacy`? | Yes. |
| 3 | Keystones: may bots take them, and which? | Yes, one per class, taken from hand-written POD1 archetype builds, not from the static score. The score cannot value conditional keystones and picks scattered ones (Iron Riposte, Prismatic Soul, Tailwind). Suggested starting set: warrior Earthbreaker (slam bar), ranger Perfect Aim or Barrage-spur build, mage Glacial Heart with a cold bar. |
| 4 | Generate items directly or simulate drops? | Generate directly, best of N (as measured here). |
| 5 | Corruption rolls? | No; keep today's behaviour. |
| 6 | Retune if Rot and Wager get too easy? | Decide after Phase D. All classes gain 2-4x DPS and 2-3x EHP from gear, so Rot and Wager targets will very likely move. |
| 7 (new) | May `typical` and `geared` bots choose skills and spec by the target's resistances, and re-pick the spec when the main skill changes? | Yes for `typical` and `geared` (a player would); `legacy` unchanged. This is the largest bot-side mage fix found. |
| 8 (new) | Caster itemisation and spell scaling cap (section 6 game-side observations) | Not for Phase B. Flagged so the Phase C mage verdict can name the cause if the gap persists. |

### Dan's answers (2026-11-06)

- **#7.** Re-pick the specialisation when the main skill changes: **yes**. Choosing skills by the target's resistances: **no**. Players don't do it, and the warrior isn't asked to.
- **#8.** Caster itemisation is now the main work. The proposal and its measurements are in `docs/CASTER_ITEMISATION.md`.
- **#1-6 (answered 2026-11-06, Phase B done, see `docs/BOT_GEAR_PROFILES.md`).**
  - #1: `typical` for tuning and `geared` for upper-bound checks. Typical gear must be fairly decent, because a player crafts with the in-game systems.
  - #2: yes, the flag-less default stays `legacy`.
  - #3: bots play keystone builds, chosen by a build analysis system (library + analyser of real runs).
  - #4: generate directly, using maths over the game's drop and crafting systems for typical vs geared. Geared = 3x the farming.
  - #5: no Abyssal Brand corruption. Normal crafts follow the crafting-corruption meter like a player's.
  - #6: retune Rot/Wager after Phase D.
  - Follow-up: Atlas Rot-touched implicits and Fixative are for `geared` only.

## 9. Files and how to reproduce

Project files changed: **only `docs/BOT_GEAR_AUDIT.md`**.

Audit tooling and raw data are kept outside the project, in `W:\AI game\PathofDan\_claude_xfer\bot_gear_audit\`:

- `sb_audit.gd`, `sb_audit.tscn`: the dump and what-if scene (extends `smartbot.gd`; copy to `tests/smartbot/audit/` to run).
- `audit_summary.py`, `whatif_summary.py`: build the tables in this report.
- `summary.md`, `whatif.md`: the full tables.
- `audit_data.tgz`: the 24 stage dumps (`*_audit.json`, 120 characters), the 12 what-if dumps (`wi_*_audit.json`), `summary.json` and `whatif_summary.json`.
- `pod_src.tgz` and `pod_src2.tgz`: project snapshots used for the cloud run (the first one is an oversized duplicate and can be deleted).

```
godot --headless --fixed-fps 60 --path . res://tests/smartbot/audit/sb_audit.tscn -- --class=mage --tier=6 --level=50 --runs=5 --seed=900 --kit_only=1 --stage=R3 [--whatif=pts,gear5,gear,mast,mast_ctrl,ks,ks_ctrl,all --ref_extra=6] --out=res://tests/smartbot/out/audit/mage_R3.csv
python3 tests/smartbot/audit/audit_summary.py tests/smartbot/out/audit .
python3 tests/smartbot/audit/whatif_summary.py tests/smartbot/out/audit
```

**Gate:** Phase A stops here. Phase B starts after Dan answers section 8.
