# Endgame Phase 3: the Pinnacle

Plan: "Path of Dan Endgame Design: The Atlas of Ruin, Rot, Zone Mechanics and Pinnacle" (claude.ai project), section G, Phase 3.
Branch `endgame-phase3` (from `main` at `6120de6`). Status doc: `claude/endgame_phase3_status.md` (project).

## Decisions (Dan, 2026-11-10)

Yes to the proposed defaults, with these changes:

| # | Topic | Decision |
|---|---|---|
| 1 | Ring levels | 55 / 60 / 65 (Wardens +2 as before). **Gear for rings 4-6: a new affix tier 7 from item level 55** on the affixes whose top tier needs item level 42; tier 6 stays at 42. |
| 7 | Board name | **"The Atelier"**; the Easel stays the Pigment crafting / slotting panel. |
| 15 | Overpainter cost | **3 tries per set of 4 Ground Pigments.** Dying or **leaving the arena alive** uses a try; a win or the 3rd failed try spends the 4 Pigments. The set stays locked until then. |
| 16 | Overpainter reward | **3 uniques, one themed per class, all usable by any class and strong**, each changing how that class plays. Ideally in **a new equipment slot that only Overpainter uniques use**. Needs research (3D gate). |

Other defaults accepted: Wardens 4-6 = Iron Penitent / Malgrath / Stormheart; Rot reaches rings 4-6, max 5, D2 levels unchanged, cap 3 per revealed ring; 3 biomes with a layer tint; save v6; Atelier points per character (+1 per first ring 2+ clear up to 18, +2 per Warden first kill, max 30, free respec); Varnishes become 6 rule-changer nodes (owned Varnishes -> 2 Seals each; Hearts stop dropping them); Burning Canvas and Pigment Wells as in the proposal; Overpainter entry from the Atlas centre hex, level 68, no Rot; win-rate targets (rings 4-6 Rot 0 ~90/85/80%, Wardens 4-6 ~60% at Rot 3, Overpainter ~50% typical L60); leftovers deferred, Rot 5 + 2P left at 50-53%.

---

# Stage 3A: Atlas radius 6, rings 4-6, Wardens 4-6, affix tier 7 (2026-11-10, Claude)

## What was built

| File | What |
|---|---|
| `data/atlas.json` | `radius` 3 -> **6** (127 hexes, 126 regions). Rings 4-6 (below). Rot `reach_ring` 3. Wardens of rings 4-6. Contract "ring3" text now "ring 3 or deeper". |
| `data/affixes.json` | **Tier 7 at item level 55** on 46 affixes (see below). |
| `scripts/core/atlas_rules.gd` | `zone_def` blends a ring's `ambient_tint` into the biome light. `rot_reach` + `_rot_eligible`: Rot only reaches rings up to max(3, highest revealed ring). `_reveal_from` (shared by `complete` and the v6 load migration). |
| `scripts/entities/boss.gd` | Pattern options: eruption `line` / `cross` (`line_points`), mortar/eruption `pool` (`_spawn_pool`). |
| `scripts/entities/aoe.gd` | `on_trigger` callback when a blast lands (pools spawn only from blasts that land; an interrupted windup leaves none). |
| `scripts/entities/hazard.gd` | Kind `pool`: lifetime, tint, the boss's own hit packet (ring, Rot and Warden damage multipliers apply). |
| `scripts/ui/components/atlas_map.gd` | View fits the explored rings (highest revealed + 1, at least 3); mouse wheel zoom 1-3x, right/middle-drag pan; clipped. |
| `scripts/ui/atlas_panel.gd` | Legend mentions zoom and pan. |
| `scripts/core/character_data.gd` | `SAVE_VERSION` 5 -> **6**. |
| `tests/test_atlas.gd` | `test_phase3a` (rules) and `test_live_3a` (live Warden 4 run, pools, Atlas panel at radius 6); radius/ring/Warden checks updated. `tests/test_runner.gd`: SAVE_VERSION check. |
| `tests/smartbot/run_atlas_p3a.ps1` | Warden runs in rings 4-6 (smoke check now; tuning in 3E). |

## Rings

| Ring | Layer | Level | Life | Damage | Resist | Rarity | Mods | Elite | Light tint |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Varnish | 40 | 1.5 | 1.32 | 20 | 170 | 1 | 0.38 | - |
| 2 | Craquelure | 45 | 1.62 | 1.4 | 25 | 200 | 1-2 | 0.42 | - |
| 3 | Pentimento | 50 | 1.75 | 1.48 | 30 | 230 | 2 | 0.46 | - |
| **4** | **Underpainting** | **55** | 1.88 | 1.56 | 35 | 260 | 2-3 | 0.50 | umber, 35% |
| **5** | **Drawing** | **60** | 2.0 | 1.64 | 40 | 290 | 3 | 0.54 | graphite, 40% |
| **6** | **Bare Canvas** | **65** | 2.12 | 1.72 | 45 | 320 | 3 | 0.58 | linen, 40% |

Rings 1-3 are unchanged. Rings 4-6 continue the ring 1-3 steps; they are starting values for 3E. Monster level above the level cap (60) has no special rules in the game (no level-gap penalty), so rings 5-6 are simply stronger monsters.

## Keeping rings 1-3 (and D2) unchanged

- A hex's biome, boss, vantage flag and zone def depend only on (seed, hex), never on the radius. Tested: for 30 seeds every ring 1-3 hex is identical to the radius-3 atlas.
- **Rot reach:** Rot sources, fronts, death Rot and loaded Rot only use rings up to `rot_reach` = max(`reach_ring` 3, highest revealed ring). A new atlas plants its sources in rings 2-3 exactly as before, and while the player is in rings 1-3 Rot behaves exactly as on the radius-3 atlas. Once ring 4 is revealed, Rot can spread into it (only from a neighbouring Rot hex); the cap grows to 12, 15, 18 as rings 4-6 open. No extra Rot sources are planted in the new rings (not decided; see open items).
- The D2 Rot levels, Warden 1-3 multipliers, Wager numbers, Velis resist and Perfect Aim are untouched.
- Smartbot frozen baseline vs `d2_v1.csv`: see Results.

## Save v6

`SAVE_VERSION` 6. Loading runs `_reveal_from` for every cleared hex, so a radius-3 save whose ring 3 regions are cleared gets their ring 4 neighbours revealed (radius 2 for a vantage hex). Idempotent; old saves load. A v4 save re-saves as v6.

## Affix tier 7

46 affixes whose top tier needed item level 42 get a 7th tier from **item level 55** (Atlas ring 4+, Warden and Endless Abyss levels 55+). Rule: min = T6 max + 1, max = T6 max + round(0.8 x T6 width), about +17-21% over T6. Hand-set: Swift 28-32, of the Phoenix 14-16, of Penetration 16-18, Warding (charm) 5-6. **of Sorcery** (+2 spell skill levels) gets no tier 7. Affixes whose top tier is below 42 are unchanged. A tier 7 affix needs character level 55 to equip.

Examples: Brutal 105-129 -> **130-149**% increased physical damage; Hale 85-104 -> **105-120** life; of the Bear 34-42 -> **43-49** strength; Pyromancer's 58-72 -> **73-84**%; of Fortune 41-50 -> **51-58**% rarity.

Items below item level 55 roll exactly as before (same RNG use), so kits and drops for levels below 55 are unchanged.

## Layer Wardens 4-6

All built from existing pattern types plus the two new options. Each starts at 4.5x life and 1.0x damage (rings 1-3: 4.5x / 1.3, 0.4, 1.1); level = zone + 1 + 2.

| Ring | Warden | Signature | Second pattern | Final phase |
|---|---|---|---|---|
| 4 | The Iron Penitent, the Underpainting Warden | **Dead Colour**: 7 mortar blots, each leaves an umber pool for 4 s that chills (slows) | **Underwash**: a line of 8 blasts swept from the boss through you (from phase 2) | 30%: Underwash + Shockwave, faster |
| 5 | Malgrath, the Drawing Warden | **Contour Lines**: a line of 9 blasts swept through you | **Cross-Hatch**: the line plus a perpendicular line through you | 30%: Cross-Hatch + Hymn, faster |
| 6 | Stormheart Colossus, the Bare Canvas Warden | **Gesso**: 8 storm strikes (some on you) leave white void pools for 5 s | **Gesso Field**: 12 strikes, pools last 8 s | 25%: Gesso Field + Spiral (a 4th phase after Stormheart's own 30%) |

The arena-shrink idea for ring 6 was simplified to long-lasting void pools (no new arena tech). The six signatures (glaze_tide, fault_lines, underpainting, dead_colour, contour_lines, gesso) are distinct for the Overpainter's phase 1.

Ground Pigments of rings 4-6 count toward the pinnacle (4 of 6). Shards drop in rings 4-6 exactly as in rings 1-3.

## Results

- `atlas_only` **629/0** (559 + 70). `tree_only` **844/0**. Full suite (`test_runner`) **48015/0**.
- Windowed shot run: `tests/screens_out_atlas/atlas_radius6.png` (fully revealed atlas, ring 6 region selected).
- One flaky check found and fixed: "pools fade" counted pools after a fixed wait while the live boss kept casting; the test now freezes the boss and polls.
- **Smartbot smoke check** (`run_atlas_p3a.ps1`, Competent, balanced, tier-6 kit, Rot 0, seed 900, 4 runs per class; L56 ring 4, L60 rings 5-6). Not tuning, just "works and is in range":

| Warden | Warrior | Ranger | Mage | All | Warden fight (median) |
|---|---|---|---|---|---|
| 4 Iron Penitent | 4/4 | 3/4 | **0/4** | 7/12 | 10.5 s |
| 5 Malgrath | 4/4 | 4/4 | 4/4 | 12/12 | 31.8 s |
| 6 Stormheart | 1/4 | 3/4 | **0/4** | 4/12 | 14.6 s |

  Deaths: ring 4 mostly cannon / Dead Colour / mortar (mage); ring 6 Gesso pools, contact and spiral. The mage gap again (D6). Ring 5 is too easy and ring 6 too hard at 1.0x; 3E tunes all three to the ~60% at Rot 3 target.
- Frozen smartbot baseline (`run_baseline.ps1`, T3 + T6, 60 runs) vs `d2_v1.csv`: **60/60 identical**. No new baseline; keep comparing against `d2_v1.csv`.

## Open / for Dan

1. **Rot in rings 4-6** only arrives by spreading out of ring 3 (2 fronts per completion, shared with the inner rings). Plant one extra seeded Rot source when ring 4 (and 5, 6) is first revealed? Default suggestion: yes, 1 source per new ring.
2. Mage vs Wardens 4 and 6 (0/4 each at Rot 0) - class balance (D6) is out of Phase 3 scope, but 3E will report per class.
3. Contracts have no ring 4-6 specific entries (the ring 2 / ring 3 contracts count deeper rings). Add "Complete N zones in ring 5 or deeper"? Not needed for 3B.
4. Atelier, Burning Canvas, Pigment Wells and the Overpainter follow in 3B-3D.
