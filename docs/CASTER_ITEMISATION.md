# Caster itemisation

2026-11-06 · Claude (Cowork) for Dan · follows `docs/BOT_GEAR_AUDIT.md`

**Status: applied to the project, not committed.** Backups of every changed file are in `_claude_xfer\caster_backup\`. Tests and the new smartbot baseline: section 6.

## 1. Decisions

| # | Question | Dan's answer |
|---|---|---|
| Audit #7 | Bot skill choice and spec | Re-pick the specialisation when the main skill changes (a bot change, Phase B). **No** skill choice by target resistance: players don't do it, and the warrior isn't asked to. |
| Audit #8 | Caster itemisation | This is the main work, and it is what this document covers. |
| 1 | Apply the proposal? | Yes, as proposed. |
| 2 | Gloves | Gloves get **cast speed and % spell damage instead of** the flat spell-damage prefixes. |
| 3 | Boss resistance gap | Add a **spell penetration** affix. |

Audit decisions 1-6 (bot profiles) are still open and wait for Phase B.

## 2. The problem

An attack's base hit is the weapon's damage plus flat "Adds X Damage to Attacks" affixes, and Tempered and Runeforged bases roughly double and then triple the weapon's damage. A spell's base hit was only its own base damage times its skill level (`1 + 0.12 x (lvl - 1)`, capped at skill level 20), and caster gear gave only % increases. From about level 20, a better wand barely changed spell damage while a better axe multiplied attack damage. In the audit the mage fell to 0.3-0.45 of the warrior's single-target DPS from T5 on, and rare gear made the gap worse.

## 3. What changed in the game

| Part | Content |
|---|---|
| Flat spell damage | New prefixes **Searing / Frigid / Crackling**: "Adds {v} Fire / Cold / Lightning Damage to Spells". Caster weapons and caster off-hands only. Weight 80; tiers copied from Emberforged / Rimecut / Stormcharged (top 31-38, 31-38, 36-44). |
| Caster base tiers | Implicit "+N Added Spell Damage" (the spell's own type). Apprentice Wand line: Tempered 2, Runeforged 11. Bone Wand line: 3, 12. Gnarled Staff line: 4, 18. Tier 1 bases get none. |
| Effectiveness | Flat spell damage rolls `value x 0.7` to `value x 1.3`, times the spell's base-damage average / 16 (clamped to 0.4-1.5, overridable with `"added_eff"` in `skills.json`), times `1 + 4%` per skill level. So every spell gains about the same percentage. Spells only; traps, turrets and minions are unchanged. |
| Spell levels | New suffix **of Sorcery**: "+1 / +2 to Level of all Spell Skills" (ilvl 24 / 42; caster weapons and amulets; weight 30). **Skill levels from items may exceed the cap of 20 by up to 5** (`loot.json` `caster.overcap`); this includes the existing "+1 to Level of all Skills" sources. Levels from character level and corruption still stop at 20. |
| Gloves | New prefix **Sorcerous**: "{v}% increased Spell Damage" (gloves only, Mighty's tiers, top 47-58, weight 70). **of Haste** (cast speed) can now roll on gloves. |
| Penetration | New suffix **of Penetration**: "Spells Penetrate {v}% Elemental Resistances" (caster weapons, caster off-hands, amulets; weight 50; tiers ilvl 14: 4-6, 24: 7-9, 32: 10-12, 42: 13-15). Applies to fire, cold and lightning from spell hits, before the 90% cap. Enemies, bosses and Training Grounds dummies all use it. DoTs are unaffected. |

## 4. Results

These are static DPS estimates (main skill, single target) from the audit tooling, 5 characters per cell, with today's bot kit ("kit") and rare gear at the character's level, best of 5 rolls per slot ("gear5"). Expect ±15% noise per cell. The fair target is between the warrior and the ranger, which are themselves far apart, so the ratio shown is the mage against their midpoint (geometric mean).

**Without enemy defences:**

| Stage | Gear | Warrior | Ranger | Mage before | Mage after | Mage / midpoint, before → after |
|---|---|---|---|---|---|---|
| T2 L12 | kit | 78 | 102 | 82 | 94 | 0.91 → 1.05 |
| T2 L12 | gear5 | 188 | 251 | – | 184 | – → 0.84 |
| T3 L20 | kit | 191 | 187 | 168 | 171 | 0.91 → 0.91 |
| T3 L20 | gear5 | 310 | 486 | 237 | 436 | 0.59 → 1.12 |
| T4 L28 | kit | 388 | 334 | 298 | 315 | 0.81 → 0.87 |
| T4 L28 | gear5 | 720 | 981 | – | 624 | – → 0.74 |
| T5 L37 | kit | 1,048 | 913 | 387 | 786 | 0.41 → 0.80 |
| T5 L37 | gear5 | 1,914 | 2,238 | – | 1,687 | – → 0.82 |
| T6 L46 | kit | 1,243 | 2,034 | 543 | 1,238 | 0.37 → 0.78 |
| T6 L46 | gear5 | 2,183 | 4,876 | 933 | 2,991 | 0.29 → 0.92 |
| Ring 1 L40 | kit | 1,021 | 943 | 407 | 1,007 | 0.43 → 1.03 |
| Ring 1 L40 | gear5 | 2,319 | 3,469 | 654 | 2,167 | 0.23 → 0.76 |
| Ring 2 L45 | kit | 1,227 | 1,257 | 570 | 1,015 | 0.44 → 0.82 |
| Ring 2 L45 | gear5 | 2,296 | 4,337 | – | 2,839 | – → 0.90 |
| Ring 3 L50 | kit | 1,121 | 1,431 | 748 | 1,243 | 0.57 → 0.98 |
| Ring 3 L50 | gear5 | 2,582 | 5,756 | 1,274 | 3,145 | 0.33 → 0.82 |

The mage now sits at 0.74-1.12 of the midpoint at every stage, against 0.23-0.91 before. Rare gear lifts the mage about as much as the warrior.

Moving the flat prefixes off gloves (your answer 2) lowers the mage by about 0.1 compared with the version measured before. The glove Sorcerous and cast-speed affixes give part of that back.

**Against bosses and Wardens, with spell penetration** (same characters; penetration fixed at 0, 15 or 30):

| Target | Warrior / ranger (gear5) | Mage, no penetration | Mage, 15% (one top roll) | Mage, 30% (two top rolls) |
|---|---|---|---|---|
| T6 boss (Stormheart, 90% lightning) | 1,585 / 2,574 | 0.52 | 0.62 | 0.79 |
| Ring 1 Warden | 1,890 / 2,602 | 0.84 | 0.90 | |
| Ring 2 Warden | 1,924 / 3,437 | 0.81 | 0.95 | |
| Ring 3 Warden (70% fire, 60% lightning) | 1,815 / 3,196 | 0.57 | 0.73 | 0.93 |

The mage values in the last three columns are relative to the warrior/ranger midpoint. With two top penetration rolls (staff plus amulet), the mage reaches 0.8-0.93 of the midpoint against the most resistant bosses.

The bot's gear score ignores enemy resistances, so bot-generated gear rarely picks penetration (a Phase B bot fix). The table therefore fixes penetration at a value instead of using what the bot happened to roll.

Mage life and effective HP are unchanged within noise.

## 5. Not changed

- Bosses, Rot, Wagers and Warden numbers (Phase D).
- Existing affix values.
- Traps, turrets and minions. They have a similar flat-damage gap, at a smaller scale.
- Bot behaviour: the spec re-pick and the resistance-aware gear score belong to Phase B.

## 6. Files and verification

**Changed:**

- `data/affixes.json`: +6 affixes; `of_haste` also rolls on gloves.
- `data/item_bases.json`: 6 implicits.
- `data/stats.json`: +6 stat names.
- `data/loot.json`: `caster` block.
- `scripts/combat/combat.gd`: `spell_added_eff`, `_caster_added`, packet key `ele_pen`.
- `scripts/core/character_data.gd`: `skill_level`.
- `scripts/entities/enemy.gd`, `scripts/core/training_rules.gd`, `scripts/entities/training_dummy.gd`: penetration.
- `tests/test_runner.gd`: hook for the new tests.
- `README.md`, `CHANGELOG.md`, `CODEX_HANDOFF.md`.

**New:**

- `tests/test_caster_itemisation.gd`: 56 checks covering data, legal slots, packet maths, effectiveness, the cap rule, penetration on a live enemy, and tooltip text.
- `tests/caster_only.tscn` and `tests/caster_only.gd`: the quick run.

**Results:**

| Run | Where | Result |
|---|---|---|
| `caster_only` | your PC | 56 / 0 |
| `caster_only`, items/crafting, training, corruption, tree, atlas | cloud Linux copy | 56/0, 322/0, 93/0, 127/0, 843/0, 559/0 |
| `test_runner` | cloud Linux copy | 47,924 / 9. The 9 are art placeholder-sheet checks that fail identically on unchanged code there. |
| `test_runner` | your PC | see section 7 |
| Smartbot baseline set (T3 and T6 x 3 classes x 10 runs, seed 1000) | your PC | `tests/smartbot/out/caster_v1.csv`; see section 7 |

The launcher job list `tests/smartbot/jobs.txt` was replaced for this check run. The original is in `_claude_xfer\caster_backup\jobs.txt`.

## 7. Results on your PC (Godot 4.0, Windows)

- **Full suite `test_runner`: 47,965 passed, 0 failed**, including the 56 caster checks. `caster_only`: 56 / 0.
- **Smartbot baseline set** (T3 and T6, 3 classes, 10 runs each, Competent, balanced, seed 1000) in `tests/smartbot/out/caster_v1.csv`, compared with `baseline/tree_v4_bot2e.csv`:

| Class, tier | Before: wins, clear time, damage taken, `dps_est`, life | After |
|---|---|---|
| Mage T3 | 10/10, 115 s, 147, 438, 351 | 10/10, 104 s, 172, 492, 376 |
| **Mage T6** | **6/10, 179 s, 2,224, 1,353, 766** | **8/10, 114 s, 942, 3,358, 657** |
| Ranger T3 | 10/10, 127 s, 395, 627, 372 | 10/10, 133 s, 543, 539, 381 |
| Ranger T6 | 10/10, 89 s, 570, 4,650, 732 | 10/10, 92 s, 420, 5,254, 752 |
| Warrior T3 | 10/10, 138 s, 2,085, 525, 652 | 10/10, 140 s, 2,106, 467, 679 |
| Warrior T6 | 10/10, 113 s, 3,464, 3,072, 1,213 | 10/10, 111 s, 3,361, 2,903, 1,201 |

The T6 mage now clears faster than before (114 s, against 179 s before; the warrior takes 111 s) and takes less than half the damage. Warrior and ranger stay within run-to-run noise. Their rows differ from the old baseline only because the larger affix pool changes the item rolls.

**Frozen (Dan, 2026-11-06):** `tests/smartbot/baseline/caster_v1.csv` is the new smartbot baseline, with a row in `baseline/BASELINES.md`. `compare_baseline.py` against the source run: 60/60 identical. `tests/smartbot/jobs.txt` has been restored to its original content.
