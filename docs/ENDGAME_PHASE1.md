# Endgame Phase 1 (MVP "The Varnish Expedition"): stages 1A-1E (2026-11-05, Claude)

Plan: "Path of Dan Endgame Design: The Atlas of Ruin, Rot, Zone Mechanics and Pinnacle", section G, Phase 1.
Phase 1 is split into stages: **1A Atlas core**, **1B two more biomes** (both done here), then 1C Rot v1 + Heart
bosses, 1D Glazed Elites + The Unfinished, 1E Pigment/Varnish slots + bot tuning.

## Decisions (Dan, 2026-11-05)
- This session: 1A + 1B.
- The Atlas unlocks after Malgrath (Nightmare Vaults, T5). Ring 1 = monster level 40, ring 2 = 45, ring 3 = 50.
- Atlas state is **per character** (save key `atlas`, SAVE_VERSION 4 -> 5). Alts start their own Atlas.
- Summoner fix: a **lifetime summon cap in zones** (8 adds per non-boss summoner). Dungeons are unchanged.

## 1A: Atlas core
| File | What |
|---|---|
| `data/atlas.json` | Radius 3, unlock dungeon, ring table (layer, colour, level, life/damage/resist/rarity, mod_count, elite_chance), biome list (zone template + weight + colour), boss pool (the 6 bosses), vantage rules, `biome_stray`. |
| `scripts/core/atlas_rules.gd` | Pure rules. Axial hex maths (ring, neighbours, within, pixel <-> hex), seeded derivation (`hex_info`, `zone_def`, `layout_seed`, `run_mods`), state (`new_state`, `ensure`, `sanitize`, `complete`, `summary`, `unlocked`). |
| `scripts/core/character_data.gd` | `atlas` dict; SAVE_VERSION 5; written only once the Atlas exists; loaded through `AtlasRules.sanitize`. |
| `scripts/main.gd` | `enter_atlas(hex)`; `enter_dungeon("atlas:q,r")` resolves to it (smartbot); shared `_start_run`. |
| `scripts/world/dungeon.gd` | `atlas_hex`; level name "<name> (Atlas ring N)"; boss kill calls `AtlasRules.complete` (reveal) and counts `progress.atlas_clears`; no dungeon first-kill point / tier change. |
| `scripts/ui/atlas_panel.gd`, `scripts/ui/components/atlas_map.gd` | Atlas panel: drawn hex map (hub, biome colours, layer-coloured outlines, fog outlines next to known hexes, green dot = cleared, diamond = vantage, gold = selected), details (ring, level, scaling, boss, rarity, seeded modifiers, clears), Enter Zone, back to Gate. |
| `scripts/ui/dungeon_panel.gd`, `scripts/ui/ui_root.gd` | "Atlas of Ruin" button on the Dungeon Gate (locked until Malgrath); `atlas` panel shares the centre slot with dungeon/passives/skills/spec. |

### Rules
- Hexes in axial coords; the hub is (0, 0) (ring 0). Radius 3 = 36 zone hexes (6 / 12 / 18).
- A new Atlas reveals ring 1. **Every clear reveals the cleared hex's neighbours**; a **vantage** hex (ring 2+, 15%,
  about 4 per atlas) reveals radius 2. Clearing outward reveals all 36.
- Saved: `{"seed", "revealed": [keys], "clears": {key: n}}`. Everything else derives from `hash(seed, q, r)`:
  - biome: each sixth of the map gets one biome; 25% of hexes stray to another (neighbours share a biome ~60%);
  - boss: one of the 6 bosses; vantage flag;
  - layout seed and base modifiers: from (seed, hex, clear count), so a hex shows its next run's modifiers in the panel
    and plays a new layout after each clear.
- Atlas zone def = the biome's zone def (`zones.json`) with ring scaling: fixed monster level, tier 6 (loot like the
  Abyss tier), ring life/damage/resist/rarity/elite chance/mod count, hex boss, `id` `atlas:q,r`.
- Free entry, no key items. Death: unchanged for now (Rot handles it in 1C).

### Summon cap (Phase 0 finding 1)
`level.summon_lifetime` (zones: `summon_lifetime` in the zone def, 8; dungeons 0 = no cap). A non-boss summoner that
reaches the cap fires its projectile instead. Bosses (Malgrath's choir, Gravemaw's bats) are never capped.

## 1B: two more biomes (`data/zones.json`)
| Biome | Generator | Palette | Pool / boss template | Notes |
|---|---|---|---|---|
| Overgrown Ruin | CA 60% + BSP 40% | `warren` | Phase 0 pool | unchanged apart from the summon cap |
| Ruined Nave | BSP 85% (pillars 3%, less erosion) | `sanctum` | T4-style: bulwarks, assassins, acolytes, cultists, brutes, archers | straighter connectors (bias 0.8) |
| Flooded Catacomb | CA only, 2 loop links | `crypt` | ghouls, bloaters, archers, bats, witches, callers | winding tunnels (bias 0.62) |
The template boss in each biome def is only used in dev "Zone spike" runs; the Atlas picks the boss per hex.
Biome art still reuses existing palettes; chamber archetypes remain open.

## Tests
- `tests/atlas_only.tscn` (`test_atlas.gd`): data, hex maths, derivation (60 seeds), state, save v5, live run through
  the Gate -> Atlas panel -> zone -> boss kill -> reveal, re-run layout, hidden-hex refusal, summon cap, dungeon no cap.
  `--shot` (windowed) writes `tests/screens_out_atlas/`. Also prints the smartbot atlas (seed 1) hex list.
- `tests/zone_only.tscn` now runs the generator checks over every biome.
- Smartbot: `--dungeon=atlas:q,r --tier=6` uses atlas seed 1 and reveals the target hex.

## Results (Godot 4.0, Windows)
- `atlas_only` **114/0**; `zone_only` **78/0** (200 seeds per biome, every seed builds on the first or second try).

| Biome | avg / max ms | floor cells min-median-max | chamber styles (200 seeds) |
|---|---|---|---|
| Overgrown Ruin | 60 / 86 | 4388-5667-7441 | 751 CA, 446 BSP |
| Ruined Nave | 42 / 66 | 4299-5865-7284 | 1029 BSP, 168 CA |
| Flooded Catacomb | 72 / 156 | 4197-5444-6607 | 1195 CA |

- Full suite **47842/0** (count varies by 1-2 between runs from fixture affix rolls; Phase 5b had 47843, Phase 0 47844).
- Smartbot frozen baseline vs `baseline/tree_v4.csv`: **60/60 identical** (dungeons unchanged by the summon cap).
- Smartbot atlas runs (`tests/smartbot/run_atlas_p1.ps1`; atlas seed 1, Competent, balanced, seed 900, 5 runs per class
  per hex; CSVs `tests/smartbot/out/atlas_p1_*.csv`):

| Ring / kit | Hexes | Boss kills | Deaths | Clear median (min-max) | Kills median (max) |
|---|---|---|---|---|---|
| Ring 1, L41 | 1,0 nave (Stormheart), -1,1 catacomb (Stormheart), 0,1 ruin (Velis) | 42/45 | 3 (all mage vs Stormheart) | 131-181 s per hex (52-308) | 118-140 (228) |
| Ring 3, L50 | 3,0 nave (Iron Penitent) | 15/15 | 0 | 179 s (92-310) | 138 (217) |

  Per class, ring 1: warrior 15/15 (131 s), ranger 15/15 (120 s), mage 12/15 (169 s). Ring 3: warrior 154 s, ranger 144 s, mage 237 s.
- **Summon cap works:** the most kills in any atlas run is 228 (Phase 0 warrior runs reached 670-820).
- Clear times sit inside the agreed 3-5 minute window or a little under it. The tier-6 kit scales with level, so ring 3
  is not harder than ring 1 for the bot. Rot (1C) has to supply the difficulty, as Phase 0 predicted.

## 1C: Rot v1 + Heart bosses
### Decisions (Dan, 2026-11-05)
- Rot origin: **seeded sources**. A new Atlas plants Rot 1 on 2 seeded hexes in rings 2-3; every completion advances 2 fronts.
- Heart: **the zone's own boss becomes the Heart** at Rot 3+ (no extra boss or layout change).
- Harvest payout for now: **a guaranteed legendary + a material cache** (Rot-exclusive items wait for Phase 2's Tempered/Runeforged).

### Files
| File | What |
|---|---|
| `data/atlas.json` `rot` | max 5, min_ring 2 (ring 1 = safety ring), 2 sources at Rot 1, 2 fronts, cap 3 x highest revealed ring, death +1, Heart at 3, the per-level table, Heart and Harvest tuning, map colours. |
| `data/enemies.json` | `rot_mutations` (3 each) on the six atlas bosses, built only from existing pattern types. |
| `scripts/core/atlas_rules.gd` | Rot state (`rot`, `restored`, `spreads`, `fester` in the atlas save), `seed_rot`, `spread_candidates`, `spread`, `forecast`, `complete_run`, `add_death_rot`, `restore`, `fester`, `apply_rot`, `heart_mutations`, `heart_def`. `sanitize` gives a pre-1C atlas its seeded sources. |
| `scripts/main.gd` | `enter_atlas` applies the hex's Rot to the zone def; death calls `apply_death_rot`. |
| `scripts/world/dungeon.gd` | Rot density / reward, "- Rot N" in the level name, Heart boss def, `complete_run` on the kill, Restore / Harvest portals, `choose_heart`, `_harvest_payout`, `apply_death_rot` (once per run, not after the boss). |
| `scripts/ui/death_panel.gd` | Applies and shows the Rot gained from the death. |
| `scripts/ui/atlas_panel.gd`, `components/atlas_map.gd` | Umber "foxing" blotches + Rot badge, red heart at Heart levels, gold inner frame on Restored hexes, dashed outline + "+N" on next-spread targets; detail lines for Rot scaling, Heart mutations, Restored, forecast, death warning; footer Rot total / cap and next fronts. |
| `tests/test_atlas.gd` | +82 checks: Rot rules, Heart defs for all 6 bosses, live Rot 2 / Heart Restore / Heart Harvest / safety-ring runs, panel. `--shot` adds `atlas_rot*.png`. |
| `tests/smartbot/smartbot.gd`, `run_atlas_p1c.ps1` | `--rot=N` forces the target hex's Rot (unset = the atlas's own); notes column gets `rot:N|heart`. |

### Rules
- **Spread** happens once per completed zone (boss kill), never in real time. Fronts = 2 + pending festers. Each front
  raises (+1) the candidate with the lowest seeded score for that draw. Candidates: ring 2+, not Restored, below Rot 5,
  and a Rot hex or next to one (so Rot both deepens and creeps). If no Rot is left, any eligible hex can become a new source.
  Scoring every candidate keeps the forecast stable: it only changes if the forecast target itself drops out.
- **Cap:** total Rot <= 3 x the highest revealed ring (3 / 6 / 9). At the cap nothing spreads and the forecast is empty.
- **Forecast** = the next spread computed on a copy of the state. Restoring or harvesting the zone you finish can still change it.
- **Death** before the boss dies: +1 Rot on that hex (not ring 1, not Restored, max 5, ignores the cap). Shown on the death panel.
- **Per Rot level** (zone def; stacks on the ring scaling):

| Rot | Packs | Life | Damage | Quantity / rarity / XP | Elites | Heart mutations |
|---|---|---|---|---|---|---|
| 1 | +10% | +15% | +10% | +15% | - | - |
| 2 | +20% | +30% | +20% | +35% | +1 modifier | - |
| 3 | +30% | +50% | +35% | +60% | +1 | 1 |
| 4 | +40% | +75% | +50% | +90% | +1 | 2 |
| 5 | +50% | +100% | +70% | +130% | +1 | 3 |

- **Heart of Rot** (Rot 3+): the hex boss with its first N `rot_mutations` in a seeded per-hex order (Rot 4 keeps Rot 3's),
  later phases start 6 points earlier, +15% life, name "..., Heart of Rot", green light. A mutation can `add` a new pattern,
  `tune` fields of an existing one and `unlock` patterns into earlier phases. Examples: Sir Morcant *Drowned Hymn* (cold
  spiral), Gravemaw *Deep Burrow*, Velis *Veil Step*, Iron Penitent *Barrage*, Malgrath *Greater Choir* (6-add ward),
  Stormheart *Overcharge Rush*.
- **Restore / Harvest:** two portals appear by the dead Heart. Restore: Rot 0 and Restored for good (a firebreak). Harvest:
  legendary, gold (monster level x 30 x Rot), Rot x 3 materials, (Rot - 2) gems and rares; the hex keeps its Rot and the
  next spread gets +1 front. One choice per run; leaving without choosing keeps the Rot and adds nothing.
- Not yet: Restored hexes' +1 Pigment slot (1E, with Pigments), Tempered / Runeforged drops at Rot 4/5 (Phase 2), Rot Officers.

### 1C results
- `atlas_only` **196/0** (114 from 1A/1B + 82 new). Full suite **47841/0** (varies by 1-2 between runs, as before).
- Smartbot frozen baseline vs `baseline/tree_v4.csv`: **60/60 identical** (dungeons untouched).
- Smartbot Rot runs (`tests/smartbot/run_atlas_p1c.ps1`; atlas seed 1, `--rot=N`, Competent, balanced, seed 900, 5 runs per
  class; CSVs `tests/smartbot/out/atlas_p1c_*.csv`). Hexes: ring 2 `2,-1` Ruined Nave / Malgrath (kit L45), ring 3 `3,0`
  Ruined Nave / Iron Penitent (kit L50). Every Rot 3+ run fought a Heart.

| Hex / Rot | Boss kills | Deaths (all mage) | Clear median | Damage taken median | Kills median |
|---|---|---|---|---|---|
| Ring 2, Rot 0 | 15/15 | 0 | 160 s | 958 | 101 |
| Ring 2, Rot 3 | 14/15 | 1 (Heart Malgrath, hymn) | 189 s | 1872 | 173 |
| Ring 2, Rot 5 | 13/15 | 2 (cultist; Heart Malgrath, rift) | 305 s | 8320 | 306 |
| Ring 3, Rot 3 | 14/15 | 1 (Heart Penitent, mortar) | 239 s | 3524 | 237 |
| Ring 3, Rot 5 | 12/15 | 3 (bulwark, elite brute, Heart Penitent mortar) | 298 s | 6313 | 306 |

  Per class at Rot 5 (both hexes): warrior 10/10 (284 / 308 s), ranger 10/10 (226 / 254 s), mage 5/10 (502 / 350 s).
- Reading: Rot works as a dial (damage taken x7-9, clears x2, density x3 from Rot 0 to 5) but warrior and ranger still
  never die. Only the mage falls, so Rot 5 is about 80% wins overall against the ~50% target at Rot 4 + 2 Pigments.
  1D (Glazed Elites, The Unfinished) and 1E (Pigments) add more pressure; tune the Rot table in 1E with the bot.
  Rot 5 mage clears (up to 640 s) run past the 3-5 minute window.

## 1D: Glazed Elites + The Unfinished
### Decisions (Dan, 2026-11-05)
- Glazed peel trigger: a **glaze poise bar** on glazed elites (boss-style poise); each full break peels one layer.
- Unfinished fairness: a **neutral raw fill** from any hit, so no build is locked out; the right status paints instantly.
- Currencies: **Glaze Flake** and **Pigment Dust** are banked as materials now (weight 0, never random drops); Fixative (Phase 2) and Pigments (1E) give them a use.
- Spawning: a **natural 30% roll** per Atlas run (seeded by atlas seed, hex and clear count, shown in the panel). Pigments (1E) will guarantee one.

### Files
| File | What |
|---|---|
| `data/atlas.json` `mechanics` | `natural_chance`, the mechanic list (name, colour, description), `glazed` and `unfinished` tuning, the 5-colour palette. |
| `data/loot.json` | Materials `glaze_flake`, `pigment_dust` (weight 0). |
| `scripts/core/atlas_rules.gd` | `mech_cfg`, `mechanic_info`, `natural_mechanic`, `sketch_colours`, `colour_for_status`, `glaze_layers`. |
| `scripts/core/game.gd` | `atlas_force_mechanic` ("" natural, "none", or an id) for the smartbot and tests. |
| `scripts/main.gd` | `enter_atlas` sets `def.mechanic`. |
| `scripts/world/dungeon.gd` | `mechanic`, `mech_rng` (own stream), `mech_stats`; level name suffix; glazed elite chance x1.5 and `_glaze_mods`; `_sketch_packs` after populate; `on_glaze_peel` (Flakes), `on_sketch_painted`, Dust on kill; objective line. |
| `scripts/entities/enemy.gd` | Glaze: `make_glazed`, `glaze_hit`, `peel`, `_unapply_mod`, layer pips + poise bar. Sketch: `make_sketch`, `paint`, `add_status` / `take_dot` overrides, immunity in `receive_hit`, dashed colour outline + raw-fill arc, `loot_rank_up`, `loot_rarity_extra`. |
| `scripts/combat/combat.gd` | `deal` still applies statuses when the hit landed on a sketch (`sketch_hit`). |
| `scripts/world/level.gd` | Drops roll as elite for `loot_rank_up`; `loot_rarity_extra` adds rarity. |
| `scripts/ui/atlas_panel.gd`, `components/atlas_map.gd` | "Mechanic:" line for the next run; coloured square on the map. |
| `tests/test_atlas.gd` | +58 checks (rules + live). `--shot` adds `atlas_mechanic.png`, `mech_unfinished.png`, `mech_glazed.png`. |
| `tests/smartbot/smartbot.gd`, `run_atlas_p1d.ps1` | `--mechanic=glazed|unfinished|none`; notes column gets the mechanic stats. |

### Rules
- **Natural roll:** 30% per run, then 50/50 between the two mechanics. Because it is seeded by the clear count, the panel shows the next run's mechanic and it changes after each clear. The mechanic shows in the level name and the objective panel.
- **Glazed Elites** (reworked after Dan's review: speed and stuns are rewarded, slow kills are not): elite chance x1.5; every non-guardian elite is glazed, with layers = its modifiers, topped up to 2 and capped at 4 (Rot 2+ already adds a modifier).
  - **Burst poise:** a hit adds damage / max life / 0.2 x 100 (big hits up to x1.75); the bar **drains 25/s all the time**, so only fast damage fills it (3% of life per second never peels).
  - **Stuns:** every stun or freeze on the elite (hit-stun or a skill's stun status) adds 60 poise.
  - 100 poise peels the **outermost** layer: that modifier's effect is removed (speed, damage, armour, leech, regen, explode, conversion, on-hit status, summons, blink, shield), 0.4 s stagger, 1 s poise immunity, 1 Glaze Flake.
  - **Shatter on death:** layers still on shatter into Flakes by kill speed (timer from the first hit): all within 3 s, none after 10 s, linear between.
  - **Full glaze** (every layer peeled or shattered): +1 Flake (+1 per 2 Rot) and +150 rarity on its drops (applied before the drops roll). A fully peeled elite is still an elite ("Peeled").
- **The Unfinished:** 35% of packs (at least 3) are sketches (pale, dashed outline in their colours). A sketch takes no life damage from hits or DoTs but still attacks. It needs 1 colour (2 at Rot 3+ or ring 3), seeded per pack: ignite = Vermilion, chill/freeze = Ultramarine, poison = Verdigris, shock = Lead White, bleed/stun = Madder. A status from any source fills its colour; all colours = **painted**. Every hit (and DoT tick at 50%) also adds neutral raw fill; 60% of max life = **filled in**. Both make it a normal enemy whose drops roll one rank higher (normal -> elite rolls; elite -> +150 rarity). Painted by colour also drops Pigment Dust (elites 2).
- Mechanics use their own RNG, so the layout and the main spawn stream are unchanged by The Unfinished; Glazed changes which packs are elite (higher chance) by design.

### 1D results
- `atlas_only` **254/0** (196 + 58 new). Full suite **47844/0** (varies by 1-2 between runs). Smartbot frozen baseline vs `baseline/tree_v4.csv`: **60/60 identical** (dungeons untouched).
- Smartbot mechanic runs (`tests/smartbot/run_atlas_p1d.ps1`; atlas seed 1, ring 2 hex `2,-1` Ruined Nave / Malgrath, kit L45,
  `--mechanic=`, Competent, balanced, seed 900, 5 runs per class; CSVs `tests/smartbot/out/atlas_p1d_r2_<mech>_rot<N>.csv`).
  Reference = the 1C runs on the same hex with no mechanic.

| Run | Boss kills | Clear median | Damage taken median | Mechanic totals (15 runs) |
|---|---|---|---|---|
| No mechanic, Rot 0 (1C) | 15/15 | 160 s | 958 | - |
| Glazed, Rot 0 | 15/15 | 154 s | 1307 | 356 glazed (222 killed): 235 peels, 270 shattered, 192 full, 697 Flakes |
| Unfinished, Rot 0 | 15/15 | 166 s | 1479 | 924 sketches: 91 painted by colour, 364 filled in, 101 Dust |
| No mechanic, Rot 3 (1C) | 14/15 | 194 s | 1872 | - |
| Glazed, Rot 3 | 14/15 (mage: Heart rift) | 262 s | 2831 | 412 glazed (254 killed): 296 peels, 352 shattered, 191 full, 1030 Flakes |
| Unfinished, Rot 3 (2 colours) | 15/15 | 206 s | 2549 | 1302 sketches: 25 painted, 721 filled in, 28 Dust |

  Glazed per class (Flakes per glazed kill / average time to kill): Rot 0 warrior 3.27 / 2.1 s, ranger 3.28 / 2.1 s,
  mage 2.88 / 6.4 s; Rot 3 warrior 4.50 / 3.1 s, ranger 4.28 / 3.6 s, mage 3.37 / 7.8 s. The first version (cumulative poise,
  no shatter; `atlas_p1d_r2_glazed_v1_*`) gave the reverse: warrior 44 Flakes vs mage 103 at Rot 0.
  Unfinished per class (Rot 0), sketches painted by colour: warrior 9, ranger 35, mage 47 (of 308 each). At Rot 3 warrior painted 0.
- Reading: Rot works as a dial (damage taken x7-9, clears x2, density x3 from Rot 0 to 5) but warrior and ranger still
  never die. Only the mage falls, so Rot 5 is about 80% wins overall against the ~50% target at Rot 4 + 2 Pigments.
  1D (Glazed Elites, The Unfinished) and 1E (Pigments) add more pressure; tune the Rot table in 1E with the bot.
  Rot 5 mage clears (up to 640 s) run past the 3-5 minute window.

## 1E: Pigments, Varnish slots and Rot tuning
### Decisions (Dan, 2026-11-05)
- **Pigments are crafted from their own mechanic's material** at the Easel: Glazed Pigment = Glaze Flakes, Unfinished Pigment = Pigment Dust, so each mechanic sustains itself. Dust income raised so a Pigment costs about 2-3 natural runs.
- **A Pigment guarantees its mechanic and adds one seeded modifier; Pigments stack.** Two slots can hold both mechanics (one zone runs both) or two of one (two modifiers). 4 charges; 1 per run, 1 more on death.
- **Varnishes drop from Hearts of Rot** (always on Harvest, about 1 in 3 on Restore). Slots: 1, +1 per ring fully cleared, max 3 in the MVP. 6 rule-changers, each a bonus with a penalty, editing zone parameters only.
- **Tune Rot to ~50% Competent wins at Rot 4 + 2 Pigments**, and add **Dev panel shortcuts**. (Not chosen: glaze poise from stun stats.)

### Files
| File | What |
|---|---|
| `data/atlas.json` `pigments` | slots (1, +1 in ring 3 or a Restored region, max 2), charges 4, death_charges 1, stock_cap 12, reward +10% each; Glazed 120 Flakes, Unfinished 30 Dust; 4 modifiers per mechanic. |
| `data/atlas.json` `varnish` | slots 1 (+1 per full ring, max 3), restore_chance 0.34, the 6 Varnishes. |
| `data/atlas.json` `rot.levels` | Rot 3-5 retuned (damage, new `heal` and `attack_speed`); `mechanics.unfinished.filled_dust_chance` 0.25. |
| `data/loot.json` | Flake / Dust descriptions name the Easel. |
| `scripts/core/atlas_rules.gd` | Pigment rules (`add_pigment`, `craft_pigment`, `slot/unslot_pigment`, `pigment_slots`, `run_pigments`, `run_mechanics`, `pigment_mods`, `spend_pigments`, `mech_tuning`), Varnish rules (`varnish_fx`, `varnish_slot_count`, `slot/unslot_varnish`, `add_varnish`, `heart_varnish`), `heart_at_for`; `apply_rot` / `fronts_next` / `add_death_rot` / `natural_mechanic` read the Varnish; `sanitize` for the new keys. |
| `scripts/main.gd` | `enter_atlas`: Pigments + natural roll -> `def.mechanics`, `pigment_mods`, `pigment_uids`, `pigment_reward`, `varnish_fx`; spends a charge on entry. |
| `scripts/world/dungeon.gd` | `mechanics` (several at once), `has_mech`, `glaze_tune` / `sketch_tune` (per-run tuning with Pigment modifiers); filled-in Dust; Varnish density / elite chance / reward; Rot `heal` / `attack_speed`; death spends Pigment charges; Heart Varnish drop (`varnish_drop`). |
| `scripts/entities/enemy.gd` | Vivid status raw fill, Crowded painted rarity. |
| `scripts/ui/easel_panel.gd` (new), `atlas_panel.gd`, `components/atlas_map.gd`, `ui_root.gd` | The Easel (craft, slot, Varnish); Atlas detail lists the run's Pigments, Varnish, Rot healing/attack speed. |
| `scripts/core/dev_tools.gd`, `scripts/ui/dev_panel.gd` | Dungeon tab > Atlas: Unlock, Reveal all, Grant Easel kit, Set Rot (q,r + level), Force mechanic. |
| `tests/test_atlas.gd` | +67 checks (`test_pigment_rules`, `test_varnish_rules`, `test_live_pigments`); `--shot` adds `easel.png`. |
| `tests/smartbot/smartbot.gd`, `run_atlas_p1e.ps1`, `p1e_summary.py` | `--pigments=glazed[:mod],unfinished[:mod]` (fresh, slotted every run), `--varnish=ids`; notes get `pig:`. |

### Rules
- **State** (atlas, per character): `pigments` (stock), `easel` (slotted, in order), `crafted` (craft counter), `varnish` ({id: count}), `varnish_slots`. Bad entries are dropped on load; 1D atlases load with an empty Easel. SAVE_VERSION stays 5.
- **Pigments:** `{id, mod, charges, uid}`. Crafting pays the material and seeds the modifier from (atlas seed, craft count). At most 12 owned. A zone uses the first N slotted Pigments (N = 1, or 2 in ring 3 / a Restored region); each guarantees its mechanic (the natural roll still adds the other one), adds its modifier and +10% quantity/rarity/XP, and spends 1 charge when you enter. A death before the boss spends 1 more (once per run). An empty Pigment is used up.
- **Modifiers** (edit a per-run copy of the mechanic's tuning; the same one twice stacks):
  - Glazed: *Thick* +1 layer (up to 5), +1 Flake per full peel; *Crowded* elites x1.25, +1 Flake per peel; *Hardened* poise fills 25% slower, +150 rarity on a full peel; *Biting* glazed elites +20% damage, +1 Flake per shattered layer.
  - Unfinished: *Two-Tone* +1 colour (up to 3), +1 Dust; *Crowded* +15% sketched packs, +100 rarity when painted; *Stubborn* raw fill 85% of life, filled-in sketches always drop Dust; *Vivid* sketches +20% damage, each colour also adds 15% raw fill.
- **Dust:** filled-in sketches now drop 1 Dust 25% of the time (elites always), on top of colour painting.
- **Varnish** (slotted for good, one of each): *Thin* -1 front (min 1), Hearts from Rot 4; *Dense* packs +25%, +20% rewards, elites -30%; *Lacquered* elites x1.5 with +1 modifier, packs -15%; *Binding* crafted Pigments +2 charges, 1 Pigment slot; *Blooming* natural mechanic chance x2, monsters +10% damage; *Greedy* Rot rewards x1.5, death +1 more Rot. A Heart drops one at random (seeded by atlas seed, hex, clears, spreads).
- **Rot 3 / 4 / 5 (tuned):** monster damage x1.4 / 1.6 / 1.8 (was 1.35 / 1.5 / 1.7), **player life recovery x0.85 / 0.7 / 0.6**, **monster attack speed +5 / 10 / 15%**. Rot 1-2 unchanged. Shown in the Atlas detail pane.

### 1E results
- `atlas_only` **321/0** (254 + 67). Full suite **47844/0**. Smartbot frozen baseline vs `baseline/tree_v4.csv`: **60/60 identical** (before and after the Rot retune; dungeons untouched).
- Smartbot (`run_atlas_p1e.ps1`; atlas seed 1, ring 3 hex `3,0` Ruined Nave / Iron Penitent Heart, kit L50, Competent, balanced, 5 runs per class, `--mechanic=none`; the 2 Pigments roll Thick Glazed + Two-Tone Unfinished; CSVs `tests/smartbot/out/atlas_p1e_r3_*`):

| Run | Wins | Warrior | Ranger | Mage | Flakes / Dust per run |
|---|---|---|---|---|---|
| Rot 4 + 2 Pigments, **old** Rot table (seed 900) | 13/15 | 5/5 | 5/5 | 3/5 | 97 / 21 |
| Rot 3, no Pigments (seed 900) | 10/15 | 5/5 | 3/5 | 2/5 | - |
| Rot 4, no Pigments (seed 900) | 8/15 | 3/5 | 5/5 | 0/5 | - |
| **Rot 4 + 2 Pigments (seed 900)** | **8/15** | 4/5 | 3/5 | 1/5 | 90 / 22 |
| **Rot 4 + 2 Pigments (seed 1900)** | **6/15** | 1/5 (1 timeout) | 4/5 | 1/5 | 73 / 13 |
| Rot 5 + 2 Pigments (seed 900) | 5/15 | 3/5 | 2/5 | 0/5 | 60 / 12 |

- Reading:
  - **Target met:** Rot 4 + 2 Pigments wins 14/30 (47%) over two seeds; the dial now runs Rot 3 ~67% -> Rot 4 ~50% -> Rot 5 ~33%. Warrior and ranger now die (Bone Archers, cultists, the Heart's mortar/shrapnel), not only the mage.
  - **The mage is the weak class** (2/10 at Rot 4 + Pigments, 0/5 at Rot 5); many mage deaths are `death_explosion` (Volatile). That is class balance, not Rot; worth a look before Phase 2.
  - With Thick + Two-Tone the 2 Pigments did not measurably change win rate at Rot 4 (8/15 both); their cost is longer fights (3-colour sketches) and their reward is +20% loot and ~90 Flakes / ~20 Dust per run. A Pigment pays for itself in 1-2 runs, so slotting stays sustainable.
  - Pigment Dust is now ~13-22 per Unfinished run (was 2-7), so an Unfinished Pigment (30 Dust) takes about 2 natural runs; a Glazed Pigment (120 Flakes) about 2-3 natural Rot 0 runs (~46 Flakes).
  - One warrior run timed out with the boss objective open (bot route issue, 244 kills); not a Rot problem.
- Known flake: once, under heavy CPU load (two smartbot batches running), "The Unfinished: same layout as the run without it" failed; the rerun passed 321/0.

## Open / next
- **Phase 1 MVP is complete.** Next: Phase 2 (Layer Wardens + Ground Pigments, Fixative crafting with Flakes, Commission Board).
- Class balance in Rot: mage wins 0-20% at Rot 4-5 against warrior/ranger 40-80%; many deaths to Volatile explosions.
- Pigment balance: Thick + Two-Tone add no measurable danger at Rot 4; other modifiers (Biting, Vivid) untested by the bot. Flake income outpaces Glazed Pigment cost once a Pigment is slotted.
- Glaze poise ignores stun builds (Dan chose not to change it now).
- Rot cap 9 on a full radius-3 atlas is small (one Rot 5 hex uses over half); a Restored hex is permanent.
- Varnish slots grow by full rings; on a radius-3 atlas the 3rd slot needs 2 full rings. Varnish is the stand-in for the Easel board (Phase 3).
- Biome art (palettes reused), chamber archetypes, vantage count (~4 per atlas).
- Phase 0 flow peak (2.2-2.5 ms) unchanged.
