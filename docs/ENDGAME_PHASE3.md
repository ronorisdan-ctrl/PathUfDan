# Endgame Phase 3: the Pinnacle

Stages: 3A (below), 3B the Atelier, 3C Burning Canvas + Pigment Wells, **3D the Overpainter** (end of file).

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

1. **Rot in rings 4-6** only arrives by spreading out of ring 3 (2 fronts per completion, shared with the inner rings). Plant one extra seeded Rot source when ring 4 (and 5, 6) is first revealed? Default suggestion: yes, 1 source per new ring. **Approved and built in 3B.**
2. Mage vs Wardens 4 and 6 (0/4 each at Rot 0) - class balance (D6) is out of Phase 3 scope, but 3E will report per class.
3. Contracts have no ring 4-6 specific entries (the ring 2 / ring 3 contracts count deeper rings). Add "Complete N zones in ring 5 or deeper"? Not needed for 3B.
4. Atelier, Burning Canvas, Pigment Wells and the Overpainter follow in 3B-3D.

---

# Stage 3B: The Atelier (2026-11-11, Claude)

The Atelier replaces the Varnish slots: a per-character board of 36 zone-rule nodes in 6 wedges. Node list: `claude/atelier_node_draft.md` (approved as written). The rules the draft left open were decided by Dan on 2026-11-11 (`claude/atelier_3b_questions.md`): the proposed defaults 1-16, and for **Last Light** the expanded rules with cost B (Lantern-bearers +1 more modifier).

## What was built

| File | What |
|---|---|
| `data/atlas.json` | New `atelier` block (`_doc`, `fx_doc`): points, costs, path rule, 6 wedges x 6 nodes with bonus / cost text and `fx`, `last_light`, `varnish_map`, `varnish_seals`, `pigment_danger`, `preview_pool`. The `varnish` block is gone. `pigments`: `max_slots` 2 -> 3 (the 3rd slot only from The Third Colour), new `easel_slots` 2. `rot.ring_sources` 1. |
| `scripts/core/atlas_rules.gd` | `atelier_fx(st)` (replaces `varnish_fx`; single source of zone-rule effects), `fx_of`, `atelier_nodes` / `atelier_node` / `atelier_option`, `_clean_atelier`. Rot: `spread(st, from)` + `_local_candidates`, `forecast(st, from)`, `forecast_depends_on_hex`, `restore` lowers neighbours, death Rot with the Atelier, `rot_reward_mult`, Heart life. `plant_ring_sources` (ring 4-6 Rot sources). `next_mechanics` (natural roll: chance add, force, second roll, major mult; minor: per-mechanic mults, one-of). `elite_preview`. Pigments: `pigment_slots`, `easel_slots`, `pigment_cost`, charges and danger roll. Wardens: `summon_cost(st)`, `shard_cap(st)`, `shard_cap_max`, chance bonus, pity, `warden_victory(st, ring, rot)` with Rot shards. Save v7: `_migrate_varnish`, `varnish_message` / `ack_varnish_message`. Varnish functions removed. |
| `scripts/core/atelier_rules.gd` (new) | Points (computed from the atlas, never stored), paths, `take` / `refund` / `respec`, `set_nodes` (smartbot / dev, old Varnish ids map), `fix` (load), `node_status`. |
| `scripts/main.gd` | Puts `atelier_fx` on the zone def; damage / life / Pigment reward and damage / elite mods / elite pool / base mods; marks Last Light zones. |
| `scripts/world/dungeon.gd` | All in-zone node effects (below), Last Light waves, Hearts no longer drop Varnishes. |
| `scripts/core/wager_vault_rules.gd` | `mults(max_mult)` (4x), `offers(..., exclude)`, `cache(..., treasure_extra)`. |
| `scripts/core/guild_rules.gd` | `boss_times` (one fight time per Lantern-bearer) for the "within 20 s" contract; vendor +1 with Guild Supplier. |
| `scripts/ui/atelier_panel.gd` (new) | The Atelier: wedge columns, node status colours, plain tooltips, a detail column with the bonus in green and the cost in red, Take / Refund / pick buttons, points line, Respec all. |
| `scripts/ui/atlas_panel.gd`, `easel_panel.gd`, `components/atlas_map.gd`, `ui_root.gd`, `wager_panel.gd` | Atelier button on the Atlas panel; the Easel's Varnish column became an Atelier summary + button; Atelier-aware lines (mechanic chance, Pigment slots / reward / death charge, death Rot, forecast per region, elite preview, Last Light boss line); map shows up to 2 natural mechanics; the Wager panel offers 4x with High Stakes; one-time Varnish message. |
| `scripts/core/character_data.gd` | `SAVE_VERSION` 6 -> **7**. |
| `scripts/core/dev_tools.gd`, `scripts/ui/dev_panel.gd` | Atelier row: +5 points (dev bonus), Take all nodes, Respec. The Easel kit no longer grants Varnishes. |
| `tests/smartbot/smartbot.gd` | `--atelier=<ids>` (choice picks as `id:b`); `--varnish=` still works (old ids map to their nodes). |
| `tests/test_atlas.gd` | `test_atelier_rules`, `test_atelier_nodes`, `test_atelier_save`, `test_live_atelier` (Last Light live run, Heart zone unchanged, the panel, the Easel); Varnish tests replaced. `tests/test_runner.gd`: SAVE_VERSION 7. |

## Board and points

- 6 wedges (Varnish/Rot, Craquelure/packs, Pentimento/Vaults+Wager, Underpainting/Pigments, Drawing/natural mechanics, Bare Canvas/Wardens) x 6 nodes: 3 small (1 point), choice (1, pick 1 of 3), notable (2), tip rule-changer (3). 9 points per wedge, 54 for the board (51 without the two 3C nodes).
- **Path:** smalls open from the hub in any order; the choice needs 2 smalls; the notable the choice; the tip the notable. Cheapest route to a tip: 8 points.
- **Points** are counted from the atlas each time: +1 per cleared ring 2+ region (max 18) + 2 per Layer Warden first kill (12) = **30**; Master's Lesson (Bare Canvas choice b) makes it +3 per Warden (up to 36, retroactive). Existing characters get what their saves earned on load.
- **Respec:** free "Respec all"; a single node can be refunded when nothing taken needs it and the points still cover the rest (so Master's Lesson can't leave you over budget). A choice pick changes only through a refund or respec. On load, nodes whose path broke are dropped; an overspent board is refunded with a message.
- **Stacking:** % effects multiply; "+N" effects add; Rot reward bonuses add (+40 and +50 = +90%).
- The Warden first-kill +1 passive point is unchanged.

## The 36 nodes (as built; numbers are first guesses for 3E)

| Wedge | Small 1 | Small 2 | Small 3 | Choice (a / b / c) | Notable (2) | Tip (3) |
|---|---|---|---|---|---|---|
| **Varnish** (Rot) | Contained Bloom: Rot spreads only into revealed regions next to the one you completed (else any revealed region); Rot rewards -10% | Ripened Hearts: +1 material roll per Rot level (Harvest 4 instead of 3, Restore 1); Hearts +15% life | Gilded Firebreak: Restore clears 1 Rot from each neighbour; Restored regions give no extra Pigment slot | Harvest gold +50% / Harvest +1 gem / Restore drops a Ground Shard 50% | Fermentation: Rot rewards +40%, +1 front per spread | **Thin Varnish**: 1 fewer front (min 1); Hearts from Rot 4 |
| **Craquelure** (packs) | Swollen Packs: packs +10%, elites 10% rarer | Fine Cracks: elites +15%, packs -5% | Connoisseur's Eye: a run's elite modifiers (a seeded pool of 4) shown on the Atlas; monsters +5% damage | Crowned Bosses (zone bosses and Hearts: +1 elite modifier, +1 rare) / Crowded Finale (+2 elite packs in the deepest chamber) / First Blood (first elite drops a rare) | **Dense Varnish**: packs +25%, +20% items, elites 30% rarer | **Lacquered Varnish**: elites +50% with +1 modifier, packs -15% |
| **Pentimento** (Vaults, Collector) | Hidden Rooms: Vaults x1.5, Wager x0.75 | The Collector's Favour: Wager x1.5, Vaults x0.75 | Thin Plaster: vault walls -30% life; Trap Vaults +1 elite | Treasure +1 rare / Riddles allow 1 mistake / stakes up to 4x | Always Something Beneath: every zone has a Vault or the Collector (never both); Glazed / Unfinished roll 30% less | **Greedy Varnish**: Rot rewards +50%, +1 more Rot on death |
| **Underpainting** (Pigments) | Generous Grind: +1 charge; crafting +20% material | Bold Mixing: +5% reward per slotted Pigment; modifiers roll twice and keep the more dangerous | Steady Hand: no extra Pigment charge on death; +1 more Rot on death at Rot 1+ | Glazed Pigments -25% / Unfinished -25% / vendor +1 per refresh | The Third Colour: +1 Pigment slot everywhere (3rd slot, a 3rd Easel slot); +5% monster damage per slotted Pigment | **Binding Varnish**: +2 charges, 1 Pigment per zone |
| **Drawing** (natural mechanics) | Thick Glaze: +1 Flake per peeled / shattered layer; Glazed Elites +1 layer | Loose Sketching: sketches need 1 fewer colour (min 1); Dust x0.8 | Busy Canvas: natural chance +10 points; +1 base modifier | always Glazed / always Unfinished / always Burning Canvas or Wells (**3C**) | Double Study: a second natural roll; monsters +10% life | **Blooming Varnish**: natural mechanics x2, monsters +10% damage |
| **Bare Canvas** (Wardens) | Shard Seeker: shard chance +10 points; Wardens +10% life | Warden's Tithe: Warden fights +1 rare; summons cost +1 Shard | Rot-Fed Wardens: a Warden killed at Rot 3+ gives +1 Shard of its ring | Ground Pigment pity after 2 dry kills / Master's Lesson / Shard cap 12 | **Umber Well** (**3C**: Pigment Wells' 4th well) | **Last Light** (below) |

Danger order for Bold Mixing: Biting > Hardened > Thick > Crowded; Vivid > Stubborn > Two-Tone > Crowded.

## Last Light (Bare Canvas tip; Dan, 2026-11-11)

Ordinary zones (not Hearts of Rot, not Warden runs) have no boss. Entering the arena wakes the Last Light: **3 waves** (+2 with Crowded Finale), each **2 elites + 3-5 normals**; the next wave comes when 1 monster or fewer is left. The first elite of each wave is a **Lantern-bearer**: x2.5 life, **+2 elite modifiers** (one boss-like, one as the node's cost), level +1, drops 1 rare. The last kill of the last wave is the zone's "boss death": clear, Rot spread, shard roll, Guild credit, XP, tier loot (from the last kill) and the exit portal. Each Lantern-bearer counts as a boss for contracts; "within 20 s of waking" times each one from its wave start. The Wager does not offer its four boss bets there. Numbers in `atelier.last_light` for 3E.

## Save v7 and the Varnish migration

- Slotted and owned Varnishes become **2 Guild Seals each** (Seal cap respected); a one-time message on the Atlas panel says how many (and if the cap kept some). Hearts no longer drop Varnishes (Harvest keeps the legendary + cache). New saves have no `varnish` / `varnish_slots`; v4, v5 and v6 saves load.
- Old `--varnish=` smartbot runs map to the same effects: Thin -> `var_tip`, Dense -> `craq_notable`, Lacquered -> `craq_tip`, Binding -> `under_tip`, Blooming -> `draw_tip`, Greedy -> `pent_tip`.

## Rot in rings 4-6 (Dan, 2026-11-11)

When ring 4, 5 or 6 is first revealed it gets **1 extra Rot source** at `source_level`, seeded by atlas seed + ring and recorded in `atlas.ring_sources`. Nothing changes while only rings 1-3 are revealed. Saves that revealed ring 4+ before 3B get theirs once on load.

## Results

`atlas_only` **704/0** (+75), `tree_only` **844/0**, full suite **48016/0**. Smartbot with no Atelier nodes: frozen baseline vs `d2_v1.csv` **60/60 identical**; the D2 Rot cell (ring 3 hex 3,0, Rot 4 + 2 Pigments, typical, seed 900) **21/30, identical run for run** to D2. A flaky 3A check ("pools fade") was rewritten to check each pool's lifetime instead of a frame budget. Screenshot: `tests/screens_out_atlas/atelier.png`. (Filled in during 3C: the 3B commit left this placeholder.)

## Open items / for 3C-3E

1. **3C nodes:** Study in Fire (Drawing choice c) and Umber Well (Bare Canvas notable) are in the data, shown, and locked until 3C. (Done in 3C.)
2. **Smartbot and Last Light:** the bot fights the waves like any pack, but its runners have no Last Light cells yet; 3E measures it (target: a win rate close to a boss run, shorter time) and the 3x boss-contract pace.
3. All node numbers are first guesses; 3E checks the specialisers with the bot (zone outcomes only, no build retests).
4. Contracts: no Atelier-specific contracts; boss contracts go ~3x faster with Last Light.

# Stage 3C: Burning Canvas + Pigment Wells (2026-11-12, Claude)

Two new main natural mechanics and the two Atelier nodes that waited for them. Dan's decisions (2026-11-12): fire speed to be tested; no pause at the boss (data flag); Rot adds a cistern; the Ash Pigment hard to get (4-5 runs of Ash); wells fill from kills + time, 2-3 per zone; then **"yes to defaults"** for everything else (`claude/endgame_phase3c_questions.md`, 26 items).

## What was built

| File | What |
|---|---|
| `data/atlas.json` | `mechanics.list`: `burning` (Burning Canvas, fire orange `#ff8a3a`) and `wells` (Pigment Wells, `#4ab8a0`), both main, weight 1. New tuning blocks `mechanics.burning` and `mechanics.wells` (with `_doc`). `pigments.list`: **Ash Pigment** (`burning`, 240 Ash) and **Wells Pigment** (`wells`, a `materials` block: 120 Flakes + 30 Dust + 120 Ash); 4 modifiers each. Atelier: Study in Fire (`natural_force: "burning|wells"`) and Umber Well unlocked (`needs_3c` removed); `pigment_danger` for both. Guild: contracts `cisterns` and `wells_full` (`req.seen`). |
| `data/loot.json` | New material **Ash** (weight 0: only from the Burning Canvas and ochre chests). |
| `scripts/core/burning_rules.gd` (new) | Pure rules: the 4-way distance field from the entrance, kill speed-up, base speed, burn damage, cistern count / depth fractions, push-back, what burns, Ash per kill. |
| `scripts/core/wells_rules.gd` (new) | Pure rules: well count / colours, fill per kill / second, danger per colour, **the mix** (pure / mixed / balanced, draws, legendary and unique chances) and the chest tables (`roll_draw`). |
| `scripts/world/zone_fire.gd` (new) | The live fire: front, scorched overlay (one pixel per cell, glowing edge, embers), minimap, burn, loot burning, Ash, cisterns (channel, interrupt, push, hold, greyed out). |
| `scripts/world/zone_wells.gd`, `well_visual.gd` (new) | The live wells: placement, fill, danger on monsters, the easel and the mix; the well drawing (basin, fill ring, label). |
| `scripts/world/dungeon.gd` | Creates `burn` / `wells` from the mechanics (tuning with Pigment modifiers), ticks them, kill hooks, easel after the boss, cistern / easel interactions, one exit-portal warning, burnt cells on the minimap, Parched rarity, Guild report `cisterns` / `wells_full`, `minimap_marks()`, cleanup. |
| `scripts/core/atlas_rules.gd` | `natural_mechanic` force `a|b` (seeded pick); `pigment_costs` (several materials), `pigment_cost` = their sum, `cost_text`, `pigment_materials`; `_MECH_MULT` multipliers for the new modifiers; `mark_seen` / `has_seen`; `atlas.seen` in the state and `sanitize`. |
| `scripts/core/guild_rules.gd` | `req.seen`; stats `cisterns`, `wells_full`. |
| `scripts/main.gd` | Marks a run's mechanics as seen. |
| `scripts/entities/enemy.gd`, `scripts/combat/combat.gd` | `extra_status` (a well's ignite / poison) rides on monster hits. |
| `scripts/ui/hud.gd` | Minimap markers for cisterns (dry = grey), wells and the easel. |
| `scripts/ui/easel_panel.gd` | Ash next to Flakes and Dust; multi-material costs. |
| `scripts/core/character_data.gd` | `SAVE_VERSION` 7 -> **8** (`atlas.seen`). |
| `tests/test_atlas.gd` | `test_phase3c` (rules) and `test_live_burning`, `test_live_wells`; 3B tests that expected the nodes locked now expect them open; save v8. `tests/test_runner.gd`: SAVE_VERSION 8. |
| `tests/smartbot/sb_endgame.gd`, `sb_controller.gd`, `smartbot.gd` | Bot behaviour for both mechanics, run notes, `--tune=mech.<id>.<key>`. |
| `tests/smartbot/run_atlas_p3c.ps1`, `p3c_summary.py` (new) | The 3C runner and its summary. |

## The Burning Canvas (as built)

- **The front** is a distance along the floor from the entrance (4-way flood fill over the zone, the arena seal ignored), so it follows corridors and never jumps chambers. It starts after **15 s** and moves at *arena distance / `arena_time`* cells per second (**`arena_time` 250**, from the sweep below), **+0.5% per kill, up to +50%**. `pause_at_boss` (off) can stop it while the boss is awake. It stops when the boss dies (Last Light: the last wave).
- **Burnt floor:** a scorched tint with a glowing edge and embers; burnt cells show on the minimap. Normal and magic items and gold on the ground burn; rares and better, gems and materials are safe. Standing there deals fire damage of **3% of a reference life (30 x zone level) per second**, less fire resistance (45/s at level 50 before resistance). Monsters are unharmed.
- **Ash:** a normal kill drops 1 at 25%, an elite 1 (+1 at 25%), the boss 3; kills within 6 cells ahead of the front drop double.
- **Cisterns:** 2 per zone (+1 in a Rot zone), in the normal chambers nearest 1/3 and 2/3 of the arena distance (the Rot one at 1/2). Interact: a 1 s channel (a hit of 10% of max life or stepping 40 px away cancels it); the front goes back 25% of the arena distance (never behind the entrance) and holds for 8 s. One use each; a dry cistern is grey on the map and minimap.
- **Ash Pigment (240 Ash, about 4.5 typical runs):** Kindled (fire 5 s sooner; +25% Ash), Roaring (20% faster; triple Ash ahead of it), Parched (1 fewer cistern; +100 rarity), Searing (burn +50%; elites +1 Ash). Danger order: Kindled < Parched < Roaring < Searing.

## The Pigment Wells (as built)

- **2 or 3 wells** (50/50, seeded), each in a different normal chamber spread by depth (never the entrance or the arena), colours crimson / ochre / verdigris without repeats. The Atelier's **Umber Well** adds a 4th, umber well.
- **Fill:** a kill in the well's chamber (or within 6 cells) adds 4%, an elite or miniboss 15%; standing within 4 cells adds 1% per second. No fill after the boss. (Monsters have no "magic" rank in Path of Dan, so the proposed 6% magic step does not exist.)
- **Danger** (monsters in the well's chamber, x fill): crimson +25% of their damage as added fire and a 50% ignite chance; ochre +60% armour; verdigris a 60% poison chance. Bonuses are replaced every 0.5 s, never stacked.
- **The mix:** after the boss an easel stands in the arena. Draws = the colour fills summed and rounded (at least 1 if anything filled) + 1 per 2 Rot. **Balanced** (3 wells: no share over 45%; 2 wells: shares within 15 points): the draws cycle through the colours + a legendary at 25% (+10% per fill over 1, max 60%). **Pure** (a share of 50%+): every draw from that colour. **Mixed** (otherwise): the dominant colour's draws + 1 of the second. Umber's fill = the chance of a unique usable at the zone level.
- **Tables:** crimson a rare weapon / off-hand with at least one offensive affix (the first at +400 rarity); ochre 120 gold x zone level, 3 crafting materials, 20 Flakes, 5 Dust, 3 Ash; verdigris a rare ring / amulet / belt / charm or a gem (2:1).
- Leaving without mixing forfeits the chest; the exit portal warns once.
- **Wells Pigment (120 Flakes + 30 Dust + 120 Ash):** Patient (time fill x2, kills -20%), Deep (fill -25%, +1 draw), Triptych (always 3 wells, kills +10%), Bright (danger +50%, chest items +150 rarity). Danger order: Patient < Deep < Triptych < Bright.

## Hooks

- Natural roll: the four main mechanics at weight 1 (`natural_chance` 0.3 unchanged), so each is about 7.5% of runs; Glazed and The Unfinished each went from 1 in 2 to 1 in 4 of the natural rolls (as intended).
- **Study in Fire** (Drawing choice c): the natural mechanic is the Burning Canvas or the Wells, 50/50 seeded on the same roll. **Umber Well** (Bare Canvas notable): unlocked.
- Atelier Pigment nodes apply to the new Pigments (charges, +20% craft cost, danger roll, slots, damage); the -25% choices stay Glazed / Unfinished. The Guild vendor does not sell the new Pigments.
- **Contracts:** "Douse N cisterns in the Burning Canvas" and "Fill N Pigment Wells" (2-4, rep 1.5, Seals 0.25 per unit, weight 1). They are offered only after the mechanic has been met (`atlas.seen`).
- Any pair of natural mechanics can share a zone (Double Study / Blooming Varnish); Warden and Heart runs handle them like Glazed / Unfinished. No new Wager bets.
- Atlas panel and map: the new mechanics in their colours with their one-line descriptions (the panel and map read the mechanic list).

## Save v8

`atlas.seen` lists the zone mechanics the character has met (written when a run starts). Older atlases load with an empty list (sanitize drops unknown ids). v4-v7 saves load (the save tests cover v4 and the v7 Atelier round trip).

## Smartbot

- **Burning Canvas:** with the front within 8 cells the bot stops for loot, leaves packs behind it and heads for the arena; with the front within 14 cells and an unused cistern ahead of the front within 320 px it pumps the cistern (standing still while it fights). Knobs: `--fire_flee`, `--fire_cistern`. Deaths on burnt floor are `burning_canvas`.
- **Wells:** the bot stands by each revealed, unfilled well it passes for up to 12 s (`--wells_linger`) and fights there; after the boss it mixes at the easel before looting (the run waits for it).
- Run notes: `burn:ash=..|ahead_ash|cist=used/total|fire_t|burn_t|ahead_pct|caught|burnt_items|burnt_gold|dmg|arena_d|reach_arena|front_end|kills|flee_t|min_gap|speed` and `wells:<colour>=fill+..|full|kind|dom|draws|drops|value|leg|uniq|kill_fill|time_fill|near_t`.
- `--pigments=burning,wells` (Pigment ids) works through the existing Pigment list; `--mechanic=burning|wells` forces the mechanic; `--tune=mech.burning.arena_time=200` overrides tuning.

## Results

Tests: `atlas_only` **790/0** (+86), `tree_only` **844/0**, full suite **48015/0**. Screenshots: `tests/screens_out_atlas/burning_zone.png` (front, scorched floor, minimap, cistern messages), `wells_well.png` (a full well), `wells_easel.png` (the easel after the boss), updated `easel.png` (Ash and the new Pigments) and `atelier.png` (the 3C nodes unlocked).

**Unchanged checks.** Frozen baseline (`run_baseline.ps1` vs `baseline/d2_v1.csv`, dungeon tiers): **60/60 identical**. D2 Rot cell (ring 3 hex 3,0, Rot 4 + 2 Pigments, typical, seed 900): **21/30, identical run for run** to 3B. No run rolled a new mechanic: that cell uses `--mechanic=none`, which replaces the natural roll, so the new weights cannot reach it.

**Burning Canvas** (`run_atlas_p3c.ps1`, ring 3 hex 3,0, level 50, typical gear, 10 runs per class, seed 900; summary `tests/smartbot/out/p3c/p3c_summary_v1.md`). "Never caught" = runs in which the bot never stood on burnt floor before the boss died. "Time ahead" = share of the burning time spent ahead of the front.

| | Rot 0: wins | clear s | never caught | time ahead | Rot 3: wins | clear s | never caught | time ahead |
|---|---|---|---|---|---|---|---|---|
| no mechanic (reference) | 30/30 | 103 | - | - | 26/30 | 114 | - | - |
| arena_time 140 | 30/30 | 101 | 16/30 | 91% | 24/30 | 106 | 14/30 | 87% |
| arena_time 170 | 30/30 | 105 | 19/30 | 95% | 25/30 | 113 | 17/30 | 92% |
| arena_time 205 | 30/30 | 107 | 21/30 | 98% | 26/30 | 118 | 18/30 | 94% |
| **arena_time 250 (set)** | 30/30 | 108 | **24/30** | 99% | 24/30 | 113 | **22/30** | 96% |

- The fire changed no win rate beyond noise and killed nobody (240 runs, 0 deaths on burnt floor; all Rot 3 losses are mage / ranger deaths to monsters, as without the mechanic). Mean burn damage per run: 2-410 (mage highest, ranger and warrior often under 100).
- **`arena_time` 250** meets the default target (a typical bot never caught in ~80% of runs: 80% at Rot 0, 73% at Rot 3). With kills the front still runs up to 1.5x faster; it reached the arena at about 115 / 135 / 160 / 190 s for 140 / 170 / 205 / 250.
- **Ash per run:** 44.5 at Rot 0 and 60.6 at Rot 3 (mean 52.6, about the same at every speed; about 2% of it from kills ahead of the front). Ash Pigment = 4.5 x 52.6 = **240** (about 5.4 runs at Rot 0, 4 at Rot 3); Wells Pigment Ash = half, **120**.
- Cisterns: 0.1-0.4 used per run (the bot is usually past them when the front comes close).

**Pigment Wells** (same hex, Rot 0, 6 runs per class, seed 900): 18/18 wins. Mean fill crimson 0.67, ochre 0.49, verdigris 0.80; 1.6 full wells per run. Chests: 9 balanced, 9 pure (no mixed); 1.7 draws per run; mean value about 2,700 (gold + item sell values; an ochre draw alone is 6,000 gold at level 50); 6 legendaries in 18 runs (all from balanced chests). Fills were 0 or 1 in 17 of 18 runs: a well in a chamber the bot fights through fills completely from kills.

## Open items / for 3D-3E

1. **The fire is gentle.** Over 240 typical runs the burn never killed anyone; the mean burn damage per run was 2-410 (mage highest). If Dan wants the fire to bite, raise `dot_pct` (e.g. 6-8%) and/or use `arena_time` 205 or 170; the sweep shows the "caught" share for each.
2. **Wells fill fast.** Wells in chambers the bot fights through reach 100% (fills were 0 or 1 in 17 of 18 runs), so the chest depends on the route more than on feeding one well. 3E could halve `kill_fill` / `elite_fill` so feeding a well is a choice.
3. The bot rarely uses cisterns (0-0.4 per run): by the time the front is close it is usually past them. Players may use them more; the contract needs 2-4.
4. Not built (as agreed): Cinder items, the front revealing Pentimento Vaults, Wager bets for the new mechanics, vendor Pigments.
5. All numbers are first values for 3E (`mechanics.burning`, `mechanics.wells`, Pigment costs and modifiers).

---

# Stage 3D: the Overpainter, Apprentice (2026-11-19, Claude)

Dan's decisions (2026-11-10 and 2026-11-18) and "yes to defaults" on the 3D question list (`claude/endgame_phase3d_questions.md` in the claude.ai project).

## What was built

- **The Bare Ground** on the Atlas centre hex. Clicking the hub hex opens the pinnacle panel: the owned Ground Pigments (one toggle per layer with its count), a pick of exactly 4, the study order of the picked set, tries left, rewards and Enter. It opens with Ground Pigments of any 4 of the 6 layers (`PinnacleRules.is_ready`).
- **The lock and tries** (`scripts/core/pinnacle_rules.gd`, pure). Entering locks the set (`atlas.pinnacle.set`) with 3 tries; **a try is used on entry**, so dying, leaving through the portal ("Leave (the try is used)") and closing the game mid-fight all count. A win, or the end of the last try, spends 1 Ground Pigment of each layer in the set and unlocks it. A locked set cannot be changed. `in_fight` is saved at entry: a save loaded with it set counts the try as used and, on the last try, spends the set (`PinnacleRules.sanitize`).
- **The arena** (`scripts/world/pinnacle_gen.gd`, `scripts/world/pinnacle_arena.gd`). A fixed round studio, radius 12 tiles, no packs or chambers, monster level 68. The dungeon builds it (`def.generator = "pinnacle"`) but the run is not an Atlas zone. `enter_pinnacle` (main.gd) never calls the Rot, Pigment, mechanic, Atelier or run-modifier code, and the def has no `atlas` flag, so `dungeon.atlas_hex` stays "". Everything hex-keyed (reveal, clears, Rot spread and death Rot, contract credit, `mark_seen`) is skipped. Live tests check that the atlas state (minus the pinnacle block) is byte-identical after a leave, a death and a win. The boss wakes 1.5 s after you arrive. Fight rolls use the arena's own RNG (seeded from the run seed); the main run stream is not touched.
- **The Overpainter** (`data/enemies.json` `overpainter`, built by `PinnacleRules.boss_def`).
  - Phase 1, **Studies** (100-70%): the signature pattern of each Warden whose Ground Pigment you brought (`wardens.rings[].add[signature]`, at the Warden's numbers x `study_mult`), in the order of your first kills, on a loop, with a void fan (`study_fan`) between them. Boss phases can now carry a `sequence` (boss.gd `_choose`).
  - Phase 2, **Erasure** (70-35%): ring wash, blots and erase strokes. Every 9 s one of 8 pie sections is painted over after a 2 s white warning (at most 6 painted; the centre disc, radius 3 tiles, is never painted). Painted floor hits for 0.15 x the boss hit as void every 0.5 s and chills. **A poise break restores the painted section nearest you** (boss.gd calls `level.on_boss_stagger`).
  - Phase 3, **Bare Canvas** (35-0%): void spirals, teleport (vanish, then a 5-orb volley), primer mortars that leave void pools on you, erase strokes. No new sections are painted. **The poise bar drains fast**: a phase can override `data/stun.json` poise (`regen_delay` 1.0 s instead of 3.0, `regen_per_sec` 30 instead of 15, `immunity_after_stagger` 5 s instead of 8), so you stun him on a rhythm. The shared stun config is untouched.
- **First-kill order** (save v9): `atlas.warden_order` records each Warden's first kill from now on (`AtlasRules.warden_victory`). Older kills without an entry follow in ring order, then the rings never beaten (`PinnacleRules.kill_order`).
- **Rewards** (`_on_pinnacle_dead`): +1 passive point on the first kill; one of the Overpainter's brushes (the first kill gives your class's brush; later wins give one you don't own yet, weighted 60/20/20 to your class, then any brush 60/20/20); a legendary, 2 rares (+320 rarity) and 50 gold per monster level, like a ring-6 Warden. `progress.bosses_killed.pinnacle_overpainter` counts kills.
- **The Brush slot and the three brushes** (below).
- **Hooks:** the Atlas map draws the centre hex by state (locked: grey; ready: a pulsing pale fill; set locked: 4 layer-colour pips and "N tries left"; beaten: a gold mark). The Atlas panel's first line explains it. The Guild offers "Defeat the Overpainter" (weight 0.25, 25 rep, 5 Seals) only after the first kill; a win credits it. No Wager, no Atelier nodes. Dev panel row "Overpainter": 4 Ground Pigments, reset the lock, give the 3 brushes.
- **Smartbot:** `--pinnacle=a,b,c,d` (grants the set; the list is also the first-kill order), `pinnacle.<key>` in `--tune`, run notes `pin:...`, the bot steps off painted floor (`sb_endgame.paint_goal`). Runner `tests/smartbot/run_atlas_p3d.ps1`, summary `p3d_summary.py`.

## Research: dedicated endgame slots and pinnacle-exclusive uniques

| Game | System | What works | What players complain about | What fits Path of Dan |
|---|---|---|---|---|
| Path of Exile 1 | Jewels in passive-tree sockets, free to swap; cluster jewels extend the tree. Each pinnacle boss (Shaper, Elder, Uber Elder, Maven, Sirus, the Ubers) has its own unique list; GGG designed the Elder uniques as a themed cycle split by damage type; Uber Elder can drop the 3-mod Watcher's Eye; Shaper / Elder drop the fragments of the next fight. | A themed set per boss; key chains (boss A drops boss B's key), like our Ground Pigments. | Chase drops are rare on purpose (the 3-mod Watcher's Eye); the Uber tier is for few players. | The themed cycle (3 brushes, one per class). Not the rarity: we have one boss. |
| Path of Exile 2 | Charms in belt charm slots; a belt has 1-3 slots, random by item level; charms are normal / magic / unique only. | Automatic triggers, no flask juggling. | A belt with 3 charm slots is luck; it became a meme. | Never gate the slot on a roll: the Brush slot is always there. |
| Grim Dawn | One relic slot; relics are crafted at the Blacksmith from blueprints in 3 tiers (Mythical from level 60, blueprints from bosses), each craft adds a random bonus. | A slot that never competes with gear; the craft chain is a long goal. | A character uses about 3 relics in its life; relic icons have little character; weak relics are never used because the slot is so valuable. | One slot, but three items that are all worth using (a real choice) with their own art. |
| Last Epoch | The idol grid (20 cells, Tetris-style), fixed non-modifiable idols. Timeline bosses drop from a pool of 4 uniques, one very rare and only in Empowered timelines; Uber Aberroth has its own items. | Fixed items are easy to read and balance. | Boss-only uniques with low drop rates behind harder content; aspirational loot should feel optional. | No grid (3 items). Guaranteed drops. Strong, but not needed for the rest of the game. |
| Diablo IV | Lord of Hatred's Talisman: its own tab, a Seal in the centre and up to 6 Charms, not competing with gear. Uber uniques (e.g. the Harlequin Crest) dropped about 2% from Uber Duriel. | Endgame power on top of gear, in its own space. | Uber uniques were "a carrot no one can reach"; Blizzard raised the rates and ran double-drop events. | A guaranteed brush per win, no duplicate until you own all 3. |

Sources: [PoE wiki: The Uber Elder](https://www.poewiki.net/wiki/The_Uber_Elder), [Maxroll: Uber Elder](https://maxroll.gg/poe/bosses/the-uber-elder-boss-guide), [Maxroll: The Elder](https://maxroll.gg/poe/bosses/the-elder-boss-guide), [GameBanshee: Designing the Elder Uniques](https://gamebanshee.com/k4934), [PoE wiki: Passive skill (jewel sockets)](https://www.poewiki.net/wiki/Passive), [PoE: Cluster Jewels announcement](https://pathofexile.com/forum/view-thread/2783927), [PoE2 wiki: Charm](https://poe2wiki.net/wiki/Charm), [Mein-MMO: PoE 2 belt charm slots](https://mein-mmo.de/en/players-of-path-of-exile-2-demand-changes-to-loot-especially-one-type-of-item-annoys-them,1210743), [Grim Dawn: Relics](https://www.grimdawn.com/guide/items/relics), [Crate forum: Relics of the Past](https://forums.crateentertainment.com/t/grim-misadventure-40-relics-of-the-past/28485), [Crate forum: What do you think of Relics? (p13)](https://forums.crateentertainment.com/t/what-do-you-think-of-relics/28534?page=13), [(p9)](https://forums.crateentertainment.com/t/what-do-you-think-of-relics/28534?page=9), [Icy Veins: Last Epoch idols](https://www.icy-veins.com/last-epoch/unlocking-idols), [GINX: Last Epoch idols](https://www.ginx.tv/en/?p=61147), [LE forum: the case against boss-specific drops](https://forum.lastepoch.com/t/the-case-against-boss-specific-unique-set-item-drops/35936), [LE forum: aspirational content should feel optional](https://forum.lastepoch.com/t/aspirational-content-should-always-feel-100-optional-uber-abby-does-not-feel-that-way/76416?page=5), [d4guides: Talisman](https://d4guides.gg/guides/miscellaneous/talisman-lord-of-hatred), [DiabloBytes: Talismans](https://www.diablobytes.com/diablo-iv/lord-of-hatred/talismans/), [PC Gamer: Uber Unique drop rate doubled](https://pcgamer.com/blizzard-just-doubled-the-drop-rate-of-diablo-4s-rarest-loot-so-nows-your-chance-to-grab-those-uber-uniques), [Mein-MMO: "a carrot that no one can reach"](https://mein-mmo.de/en/diablo-4-players-do-not-understand-a-decision-from-blizzard-a-carrot-that-no-one-can-reach,1040802), [Icy Veins: Uber unique drop chance](https://wp-prod.icy-veins.com/uber-unique-drop-chance-buffed-in-patch-1-3-2/).

## The Brush slot

- `CharacterData.EQUIP_SLOTS` gains `brush` (save v9; older saves load with it empty). Paper doll: the empty cell between Ring 1 and Ring 2, under the belt, with a brush placeholder icon (`art.gd` ICONS `brush`).
- Only items whose slot is `brush` go there, and a brush goes nowhere else (`equip_from_bag`). Any class can wear one; only one at a time.
- Brushes are uniques with fixed rolled mods (`data/uniques.json`, `pinnacle: true`) on three brush bases (`data/item_bases.json`, `pinnacle: true`, level 60). `Data` keeps them out of `unique_list` and `item_base_list`, so no random drop, Guild cache, Wells chest, dev "all bases" list or corruption pool can roll one. Items carry `pinnacle: true`: `Loot.craft_check` and `corruption_refusal` refuse them, salvage is off (sell, stash and drop work), the tooltip says so, and the loot filter always shows them with a pale beam.
- Touched: `character_data.gd`, `data.gd`, `loot.gd`, `loot_filter.gd` (slot `brush`), `inventory_panel.gd`, `art.gd`, `combat.gd`, `player.gd`, `guild_rules.gd` (contract and stat), `dev_tools.gd`, `dev_panel.gd`, `data/art/sprites.json` (manifest entry for the boss). The smartbot gear code needed no change (it never rolls brushes and does not equip them; brushes stay off for the 3E baseline).

## The three brushes (numbers in `data/uniques.json` `effect_params`)

| Brush | Theme | Mods | Effect |
|---|---|---|---|
| **The Broad Stroke** (Flat Brush: +40 life) | warrior | +60-80 life, +20-30% armour, +10-15% area, +15-25 Str | Every 4th melee hit paints a stroke along the swing (180 x 50) for 120% of the hit. The wet paint lasts 3 s: enemies in it are chilled; you take 15% less damage while you stand in it. |
| **The Rigger** (Liner Brush: +10% projectile speed) | ranger | +15-25 Dex, +15-25% projectile speed, +25-40% crit chance, +40-55 life | Projectile hits paint the target for 4 s. Hitting a painted enemy draws lines to up to 3 other painted enemies within 240; each line deals 60% of the hit to every enemy it crosses (0.5 s per target). |
| **The Glazier** (Glazing Brush: +30 mana) | mage | +15-25 Int, +10-15% cast speed, +40-60 mana, +40-55 life | Each spell adds a Glaze layer (max 5, 6 s, +4% spell damage each). A spell cast at 5 layers spends them and casts again 0.2 s later at 70% damage. |

Brush hits carry `brush_extra` so they never trigger a brush again (`scripts/combat/brush_fx.gd`, `scripts/entities/wet_paint.gd`).

## Numbers (data/atlas.json `pinnacle`; starting values for 3E)

need 4, tries 3, level 68, life_mult **80** (x the boss's 825 base), damage_mult **1.2** (x 16-26), resist +45, phases at 70% / 35%, study_mult 1.0, filler `study_fan`, arena 12 tiles / safe disc 3 / 8 sections, paint every 9 s (the first after 4.5 s), warning 2 s, max 6 painted, tick 0.5 s at 0.15 x the boss hit (void, chill), phase 3 poise regen_delay 1.0 / regen_per_sec 30 / immunity 5 s, reward 1 legendary + 2 rares (+320) + 50 gold/level, brushes warrior / ranger / mage, weights 60 / 20.

**Life and damage were tuned in 3D** from the 12 / 1.7 of the question list: at 12 the warrior killed the boss in 13 s. Sweep (set 1,2,3,4, 5 runs per class, timeout 600 s): life 100 / damage 1.7: 5/15 wins (warrior 1, ranger 4, mage 0); 60 / 1.7: 7/15 (3, 4, 0); 60 / 1.2: 10/15 (4, 4, 2); **80 / 1.2: 8/15 (2, 4, 2)**. Damage 1.2 keeps the mage above 0%.

## Save v9

`atlas.warden_order: [ring...]`, `atlas.pinnacle: {set, tries, attempts, wins, in_fight, first, owned}` and `equipment.brush`. v4-v8 saves load: an empty pinnacle block, `warden_order` empty (studies fall back to ring order), an empty Brush slot. `new_state` writes the same empty block as `PinnacleRules.new_pin()` (a test checks they match).

## Results

Tests: `atlas_only` **874/0** (+84: `test_phase3d` rules / data / save / slot, `test_live_3d` the fight, panel and tries, `test_live_brushes` the three effects), `tree_only` **844/0**, full suite **48022/0** (+7; two existing checks extended: the loot filter's slot list and the art manifest now include the brush and the Overpainter). Screenshots in `tests/screens_out_atlas/`: `pinnacle_panel.png` (the pick), `pinnacle_locked.png` (the locked set and tries), `pinnacle_phase1.png`, `pinnacle_phase2.png` (painted sections and a warning), `pinnacle_phase3.png`, `brush_slot.png` (the inventory with a brush).

**Unchanged checks.** Frozen baseline (`run_baseline.ps1` vs `baseline/d2_v1.csv`, dungeon tiers): **60/60 identical**. D2 Rot cell (`phaseD_runner.py --groups d2rot --only rot4p --gears typical --tag p3d`): **21/30, identical run for run** to 3C (outcome, clear time, damage taken, kills and boss life of all 30 runs). The pinnacle is not reachable from either: brushes never drop at random and the bot never equips one.

**Smartbot: the Overpainter** (`run_atlas_p3d.ps1 -Runs 10 -Tag v1 -Timeout 600`; level 60, Competent, balanced, typical gear for ring 6, no brush, seed 900; one fight per run; summary `tests/smartbot/out/p3d/p3d_summary_v1.txt`). "In 3" = the chance a set is beaten within its 3 tries at that win rate (1 - (1-p)^3); "tries" = expected tries used per set.

| Set (study order) | Warrior | Ranger | Mage | All |
|---|---|---|---|---|
| early 1,2,3,4 (glaze tide, fault lines, underpainting, dead colour) | 5/10 | 9/10 | 2/10 | 16/30 |
| late 3,4,5,6 (underpainting, dead colour, contour lines, gesso) | 6/10 | 9/10 | 0/10 | 15/30 |
| mixed 1,3,5,6 (glaze tide, underpainting, contour lines, gesso) | 8/10 | 9/10 | 3/10 | 20/30 |
| **all** | **19/30 (63%)** | **27/30 (90%)** | **5/30 (17%)** | **51/90 (57%)** |

- **Fight time:** median win 82 s; mean win time warrior 136-198 s, ranger 35-39 s, mage 207-248 s. 3 timeouts in 90 (all warrior, 600 s).
- **Which phase kills the bot:** of 36 deaths, phase 1: 5, phase 2: 10, phase 3: 21 (the mage's 25 deaths are spread over all three phases; all 11 warrior and ranger deaths are in phase 3). Killing blows: blot 9, erase stroke 8, primer 8, contact 5, vanish 2, spiral 2, gesso 1, fan 1.
- **Erasure:** 1.5-5.1 sections painted per fight (more in longer fights), 0.9-1.5 restored, 2.1-2.5 poise breaks per fight; the bot stood on painted floor for 7-40 ticks (warriors most: melee follows the boss onto the paint).
- **Try use** (from the win rate, each run being one fight): a set is beaten within its 3 tries 88-99% of the time for the warrior, 100% for the ranger and 0-66% for the mage; expected tries per set 1.1 (ranger), 1.2-1.8 (warrior), 2.2-3.0 (mage).
- **The class spread is the main finding.** The bot's DPS estimate at level 60 (p10-p90 over the 30 runs; median) is 10-39k (median 15k) for the ranger, 8-18k (10k) for the warrior and 2-14k (6k) for the mage, and its EHP is 4.7k, 8.6k and 3.6k. So the ranger wins in about 35 s, the warrior outlasts a 2-3 minute fight, and the mage, with the lowest of both, dies to the accumulated damage in phase 2-3. The pinnacle numbers cannot fix that alone: lowering damage helps the mage (life 60 / damage 1.2: mage 2/5) but pushes the ranger and warrior toward 100%.

## Open items / for 3E

1. **Win rate 57% (51/90)** at life 80 / damage 1.2, near the ~50% target. 3E can move it with `pinnacle.life_mult` / `damage_mult` (`--tune=pinnacle.<key>=`).
2. **Class balance:** ranger 90%, warrior 63%, mage 17% (0/10 on the late set). This is the D2 class gap (mage DPS / EHP) at its widest in a long single-target fight. Options for Dan: accept it for Apprentice; tune per class elsewhere (D6); or make the Erasure / primer pressure scale with fight time.
3. The bot does not play the poise rhythm on purpose: it attacks whenever it can, like against Glazed elites and Wardens. Poise breaks (2-2.5 per fight) come from that. A player who saves big hits for the poise window will restore more sections.
4. The brushes are unmeasured (the bot never equips one, to keep the 3E baseline clean). A `--brush=` option for the bot is a small 3E add.
5. Master, Masterpiece and the Overpaint ladder are Phase 4. Nothing blocks them: `pinnacle` can gain tiers, the boss def is built per fight, and the lock state has room for a tier field.
6. The boss uses the brute body with a pale tint (art manifest entry `overpainter`, fallback `brute`) until it has its own sheets.
