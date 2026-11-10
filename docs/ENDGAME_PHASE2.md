# Endgame Phase 2 ("Goals and rewards"): stages 2A-2E (2026-11-05/06, Claude)

Plan: "Path of Dan Endgame Design: The Atlas of Ruin, Rot, Zone Mechanics and Pinnacle", section G, Phase 2.
Phase 2 is split into stages: **2A Layer Wardens + Ground Pigments**, 2B Fixative crafting + Rot-touched
implicits, 2C Commission Board + Restorers' Guild (ranks 1-4), 2D Collector's Wager + Pentimento Vaults, 2E bot tuning.

## Decisions (Dan, 2026-11-05)
- This session: **2A only**.
- Wardens are **summoned from Ground Shards** (not a fixed Warden hex): clears in a ring drop that layer's shards, and
  3 shards summon the ring's Warden at any cleared region of that ring.
- Until the pinnacle (Phase 3), **Ground Pigments are banked**, and the **first kill of each Warden gives +1 passive point**.
- 2B: Tempered/Runeforged already exist as req-15/31 bases, so Rot 4/5 will instead give drops a **Rot-touched implicit** from a small pool.

## Files
| File | What |
|---|---|
| `data/atlas.json` `wardens` | summon cost 3, shard cap 9, shard chance 45% + 10% per Rot, Hearts always drop one, pity after 2 dry clears; Ground Pigment chance 34% after the first kill, pity after 3 dry kills; pinnacle needs 4 of 6 layers; first-kill passive point; level +2; reward (legendary, 2 rares at +300 rarity, gold); the 3 Wardens. |
| `scripts/core/atlas_rules.gd` | `ward_cfg`, `warden_cfg`, `warden_rings`, `shards`, `add_shards`, `roll_shard`, `warden_at`, `summoned_hex`, `summon_refusal`, `summon`, `unsummon`, `apply_warden`, `warden_def`, `warden_victory`, `warden_kills`, `ground_count`, `ground_kinds`, `pinnacle_ready`, `_sanitize_wardens`. New state keys in `new_state`; `sanitize` cleans them. |
| `scripts/main.gd` | `enter_atlas`: a summoned hex runs `apply_warden` (after Rot, so Rot scaling still applies but no Heart). |
| `scripts/world/dungeon.gd` | `warden`, `warden_name`, `warden_result`, `shard_drop`; the Warden boss spawns at level +2; level name "- Warden"; objective names the Warden; `_roll_shard` on normal Atlas clears; `_on_warden_dead` (victory, Ground Pigment, first-kill point keyed `atlas_warden_<ring>` in `progress.bosses_killed`, loot). |
| `scripts/ui/atlas_panel.gd`, `components/atlas_map.gd` | Shard / Ground Pigment summary line; per-hex "Layer Warden" lines; "Boss: ... (summoned)"; **Summon Warden / Move Warden here** button (tooltip gives the refusal); gold crown on the summoned hex. |
| `scripts/core/dev_tools.gd`, `scripts/ui/dev_panel.gd` | Dungeon tab > Atlas Wardens: **Grant shards** (+3 each layer), **Summon at q,r** (uses the Atlas Rot q,r box; reveals, marks cleared, tops up shards). |
| `tests/test_atlas.gd` | +61 checks: `test_warden_rules`, `test_live_wardens`; `--shot` adds `atlas_warden.png`. |
| `tests/smartbot/smartbot.gd`, `run_atlas_p2a.ps1`, `p2a_summary.py` | `--warden=1` summons the target ring's Warden at the target hex each run; notes get `warden:N|ground`; the summary prints the Warden fight time (clear - time to boss). |

## Rules
- **State** (atlas, per character; ring numbers as string keys): `shards`, `shard_dry`, `summons` ({ring: hex}), `ground`,
  `ground_dry`, `warden_kills`. A 1E atlas loads with all empty. SAVE_VERSION stays 5.
- **Ground Shards:** after a normal (non-Warden) Atlas clear, roll once for a shard of the cleared ring's layer, seeded by
  (atlas seed, hex, clear count): 45% + 10% per Rot level; a Heart of Rot always drops one; after 2 dry clears in that ring
  the next is guaranteed. Cap 9 per ring. Shown as a message ("Varnish Shard found (2/3)").
- **Summon:** a cleared region of the ring with 3+ shards of its layer. One summon per ring; summoning elsewhere moves it.
  **Nothing is spent on summoning or on a death** - the 3 shards are spent only when the Warden dies.
- **Warden run:** the hex's normal run (layout, Rot scaling, Pigments, mechanics) with the ring's Warden instead of the hex
  boss and **no Heart** (no Restore/Harvest choice, no shard roll). The run still counts as a clear (reveal + Rot spread).
- **The Wardens** (existing bosses with new patterns from the existing library, a final phase, life x4.5, damage x1.3, level +2):

| Ring | Warden | New patterns | Final phase |
|---|---|---|---|
| 1 Varnish | Sir Morcant, the Varnish Warden | *Glaze Tide* (130-radius ring, phase 1, signature), *Lacquer Fan* (9 cold orbs, phase 2); charge cooldown 4 s | 30%: eruption + lacquer fan, +20% attack speed |
| 2 Craquelure | The Gravemaw, the Craquelure Warden | *Fault Lines* (7 eruptions, phase 1, signature), *Flaking* (10-shell mortar); burrow cooldown 4.5 s | 25%: flaking, +25% speed |
| 3 Pentimento | Archon Velis, the Pentimento Warden | *Underpainting* (3-wave void spiral, phase 1, signature), *Ghost Sigils* (5 eruptions, phase 2); teleport cooldown 3.5 s | 15%: +35% attack speed |

  The `signature` pattern is recorded for the Overpainter's phase 1 (Phase 3).
- **Victory:** spends 3 shards, ends the summon, drops a legendary, 2 rares (+300 rarity) and gold (level x 40).
  **Ground Pigment:** always on the first kill of that Warden, then 34%, guaranteed after 3 dry kills. Banked per layer;
  the panel shows "Ground Pigments: N of 6 layers (4 open the pinnacle)". `pinnacle_ready` = 4 distinct layers (needs Phase 3's rings 4-6).
- **First kill of each Warden: +1 passive point** (once per character, `progress.bosses_killed["atlas_warden_<ring>"]`).

## Results (Godot 4.0, Windows)
- `atlas_only` **382/0** (321 + 61 new). Full suite **47843/0**. Smartbot frozen baseline vs `baseline/tree_v4.csv`: **60/60 identical**.
- Smartbot Warden runs (`run_atlas_p2a.ps1`; atlas seed 1, `--warden=1`, Rot 0, no mechanic, Competent, balanced, seed 900,
  5 runs per class; hexes 1,0 (kit L41), 2,-1 (L45), 3,0 (L50); CSVs `tests/smartbot/out/atlas_p2a_r<N>_<tag>_rot0.csv`):

| Tuning | Ring 1 | Ring 2 | Ring 3 | Warden fight median |
|---|---|---|---|---|
| v1: life x1.6, damage x1.1 | 15/15 | 15/15 | 15/15 | 11 / 6 / 10 s (4-27 s) |
| **v2: life x4.5, damage x1.3** | **15/15** | **11/15** (mage 1/5) | **12/15** (mage 2/5) | **27 / 19 / 15 s** |

  v2 per class (fight median): warrior 37 / 17 / 11 s, ranger 17 / 19 / 13 s, mage 34 / 40 / 62 s. All 7 losses are the mage:
  Gravemaw's *Fault Lines* and *Quake* eruptions (4) and Velis's *Underpainting* / spiral (3).
- Reading: v1 Wardens died faster than normal zone bosses (5-15 s), so they were retuned. v2 is 84% overall, warrior and
  ranger never lose; the mage is again the weak class (see 1E). Rot 3+ Wardens were not bot-tested (they will be the
  "Master" tier in Phase 3).

## Open / next
- 2C Commission Board + Guild; 2D Wager + Vaults; 2E bot tuning.
- Mage balance (Warden eruptions and spirals, Rot Volatile deaths).
- Shards drop as a message, not a ground item; the Warden arena is the hex's normal boss room.
- Ground Pigments of rings 4-6 and the pinnacle wait for Phase 3 (radius 6). Duplicate Ground Pigments are banked (future Master/attempt costs).

---

# Stage 2B: Fixative crafting + Rot-touched implicits (2026-11-05, Claude)

## Decisions (Dan, 2026-11-05)
- Fixative: **-25 corruption per use, max 2 uses per item**; only below 100%, never on Abyssal-Brand corrupted items.
- Fixative is a **Blacksmith craft paid with Glaze Flakes + gold** (no new item).
- Rot-touched implicits: **Rot 4: 10%, Rot 5: 25%** of item drops.
- Pool: **a bonus with a drawback** (like the Varnishes).

## Files
| File | What |
|---|---|
| `data/atlas.json` `fixative` | reduce 25, max_uses 2, 60 Flakes, gold 20 + 3 x item level. |
| `data/atlas.json` `rot_touched` | chance {4: 0.10, 5: 0.25}, tier {4: 1, 5: 2}, colour, 6-entry pool (bonus stat, drawback stat, 2 tiers of [min, max, drawback]). |
| `data/corruption.json` | `fixative` added to `exempt_crafts` (never rolls corruption) + a craft note. |
| `scripts/core/atlas_craft_rules.gd` (new, pure) | Fixative: `fix_cost`, `fix_refusal`, `apply_fix`, `fix_preview`, `fix_tooltip`, `brand_corrupted`. Rot-touched: `chance`, `tier_for`, `roll`, `make_record`, `mods`, `normalize`, `name_of`. |
| `scripts/core/loot.gd` | `fixative` in `craft_ops` / name / cost / check / apply / preview; `item_mods` adds the Rot-touched mods; tooltip block `rot_implicit_text` (name in green, drawback in red) and the "Fixative applied: N of 2" line. |
| `scripts/core/character_data.gd` | `_fix_item` calls `AtlasCraft.normalize` (ints back to ints, malformed record dropped, unknown id kept inactive). |
| `scripts/world/level.gd`, `dungeon.gd` | `spawn_drop` calls the new `_on_item_drop` hook; the dungeon rolls Rot-touched implicits in Atlas runs with its own `rot_rng` (seed run_seed x 53 + 11) and counts `rot_touched`. |
| `scripts/core/dev_tools.gd`, `dev_panel.gd` | Items > corruption row: **Rot-touch bag items** (Rot 5 tier, cycles the pool, taints). |
| `tests/test_atlas.gd` | +40 checks: `test_fixative`, `test_rot_touched_rules`, `test_live_rot_touched`. |

## Rules
- **Fixative** (Blacksmith "Apply Fixative"): corruption -25 (never below 0), item field `fixative` counts uses (key absent at 0), max 2. Refused at 0% ("no crafting corruption to fix"), at 100% (the generic seal refuses first) and on Brand-corrupted items (`corruption_roll_version` > 0 or a corrupted/quarantined implicit). Exempt from the corruption roll. Cost 60 Glaze Flakes + 20 + 3 x ilvl gold. Two uses = 120 Flakes = one Glazed Pigment; a natural Rot 0 run gives ~46 Flakes, a Glazed-Pigment run ~90, so this is the Flake sink 1E asked for.
- **Rot-touched:** every item that drops on the floor in an Atlas run at Rot 4+ rolls once (own stream; the Loot, combat and global streams are untouched, so Rot 0-3 runs and the frozen baseline are unchanged). 10% at Rot 4 (tier 1), 25% at Rot 5 (tier 2). One per item, stored as `rot_implicit` {id, tier, mods}. It is an implicit, so reroll / remove / add / upgrade and Brand corruption leave it alone. Items from Harvest caches, Warden rewards and boss drops in the zone all count (they go through `spawn_drop`).

| Id | Name | Bonus T1 / T2 | Drawback T1 / T2 |
|---|---|---|---|
| festering_might | Festering Might | 12-18 / 18-25% increased Damage | 5 / 6% reduced Maximum Life |
| rotting_hide | Rotting Hide | +2-3 / 3-4% Damage Reduction | 5 / 6% reduced Movement Speed |
| spore_bloom | Spore Bloom | 20-30 / 30-40% increased Damage over Time | -10 / -12% Critical Multiplier |
| gnawing_hunger | Gnawing Hunger | +3-5 / 5-8 Life on Hit | 8 / 10% increased Mana Cost |
| blighted_fortune | Blighted Fortune | 15-22 / 22-30% increased Item Rarity | -10 / -12% Void Resistance |
| carrion_appetite | Carrion Appetite | 20-28 / 28-36% increased Damage vs Elites/Bosses | 15 / 20% reduced Life Regeneration |

## Results (Godot 4.0, Windows)
- `atlas_only` **422/0** (382 + 40 new). `items_crafting_only` **322/0**, `corruption_only` **127/0**. Full suite **47883/0**.
- Live check: 200 drops in a Rot 5 region -> within the 30-70 window (25% expected); 0 at Rot 0; the Loot stream state is unchanged by the rolls.
- Smartbot baseline vs `tree_v4.csv`: **60/60 identical** (`out/p2b_check.csv`).

## Open
- The smartbot does not craft, so Fixative has no bot data; the Rot-touched pool is tuned by hand against affix ranges (not bot-tested).
- **Decision (Dan, 2026-11-05): 2C gates Fixative behind Restorers' Guild rank 3.** Until 2C it stays open to anyone with Flakes.

## Follow-up (2026-11-05): loot filter rule for Rot-touched items
- `scripts/core/loot_filter.gd`: `describe()` adds `rot`; new conditions `rot_touched` (bool) and `rot_implicit_any` (id list). Editor fields in `loot_filter_panel.gd`; `tools/validate_loot_filters.py` updated.
- All 4 presets: a top "Rot-touched" rule (green beam + diamond minimap icon, continue) and a "Rot-touched below rare" green label rule (strict: below epic) before the hide/dim rules. Legendary/epic keep their own beam.
- Tests: `test_loot_filter.gd` engine tests 113 (new `_t_rot_touched`), `atlas_only` 423/0, full suite 47880/0 (the full-suite total moves by a few checks between runs; 0 failed). Presets validate OK.


---

# Stage 2C: Commission Board + Restorers' Guild, ranks 1-4 (2026-11-05, Claude)

## Decisions (Dan, 2026-11-05)
- Rank ladder: **R1** Commission Board + Seal caches, **R2** Pigment vendor (gold), **R3** Fixative at the Blacksmith (the 2B gate), **R4** 4th contract slot + caches offer 4 choices.
- Pace: **rank 3 after about 40-50 zones**.
- Location: a **new hub NPC**, Restorer Ottilie (shown once the Atlas is unlocked).
- Scope: contracts count **only in Atlas runs, only on completion** (credited when the zone boss dies; the Heart choice is credited when it is made). A death or an abandoned run credits nothing.

## Files
| File | What |
|---|---|
| `data/atlas.json` `guild` | NPC (name, sprite, hub cell 29,16), 3 slots (max 4), refresh every 5 zones, 1 free reroll per refresh, cache 10 Seals, 3 offers, Seal cap 99; 4 ranks; 12 contract templates; 6 caches; vendor (2 per refresh: Glazed 1500 gold, Unfinished 1000). |
| `scripts/core/guild_rules.gd` (new, pure) | State (`ensure`, `sanitize`), ranks (`rank`, `rank_for`, `next_rep`, `unlock_rank`, `has_unlock`, `fixative_refusal`), board (`slot_count`, `eligible`, `draw`, `fill_board`, `refresh`, `reroll`, `progress_of`, `credit`, `label`), caches (`cache_offers`, `open_cache`, `reward_level`), vendor (`buy_refusal`, `buy_pigment`). |
| `scripts/core/atlas_rules.gd` | `sanitize` keeps the `guild` block (runtime `load` to avoid a preload cycle). |
| `scripts/core/loot.gd` | `craft_check("fixative")` refuses below Guild rank 3 (`GuildRules.fixative_refusal(Game.ch)`); the Blacksmith shows the reason on the button. |
| `scripts/world/dungeon.gd` | `elite_kills`; `_credit_guild` builds the run report on boss death (`guild_report`, `guild_result`); `choose_heart` credits restore/harvest; `_announce_guild` messages (contract done, rep/Seals, rank up). |
| `scripts/world/hub.gd`, `scripts/gfx/art.gd` | Guild station (`kind` "guild") when the Atlas is unlocked; new sprite `npc_restorer`. |
| `scripts/ui/guild_panel.gd` (new), `ui_root.gd` | Guild panel (center group): rank/rep/Seals header, board with Reroll, rank list, Seal caches with Open, Pigment vendor. |
| `scripts/core/dev_tools.gd`, `dev_panel.gd` | Dungeon tab > Atlas Guild: **+100 rep**, **+10 Seals**, **Complete board**. |
| `tests/test_atlas.gd` | +49 checks: `test_guild_rules`, `test_guild_pace` (Monte Carlo), `test_live_guild`; `--shot` adds `guild_panel.png`. |

## Rules
- **State** (`atlas.guild`, per character): `rep`, `seals`, `board`, `draws`, `zones` (since refresh), `rerolls`, `bought`, `caches`, `done`. Created on first use; older atlases load without it. SAVE_VERSION stays 5.
- **Board:** 3 contracts (4 at rank 4), seeded by (atlas seed, draw count), never the same template twice. Templates need the atlas to support them (`req`: ring revealed, a visible Rot level, a Ground Shard / Warden kill, total clears, rank). A completed contract pays at once and shows "Done" until the refresh. **Refresh every 5 completed zones**: done contracts replaced, free reroll and vendor limit reset. Unfinished contracts stay.
- **Run report** (on zone boss death): zones 1, ring, Rot, hearts (Heart of Rot zone), glaze peels, sketches painted (colour or filled), elites killed before the boss, Pigment zone, Warden. The Heart choice sends a second report (`restore` or `harvest`, not a zone).
- **Rewards:** rep = round(rate x need), Seals = max(1, round(rate x need)).

| Contract | Need | Rep / Seals per unit | Needs |
|---|---|---|---|
| Complete N Atlas zones | 3-5 | 3 / 0.4 | - |
| Complete N zones in ring 2+ | 2-4 | 4 / 0.5 | ring 2 revealed |
| Complete N zones in ring 3 | 2-3 | 5 / 0.6 | ring 3 revealed |
| Complete N zones at Rot 2+ | 2-3 | 5 / 0.6 | a visible Rot 2 region |
| Slay N Hearts of Rot | 1-2 | 9 / 1.0 | visible Rot 2 |
| Restore 1 region | 1 | 10 / 1.0 | visible Rot 2 |
| Harvest 1 Heart | 1 | 10 / 1.5 | visible Rot 2 |
| Peel N glaze layers | 6-12 | 1 / 0.15 | - |
| Paint N sketches | 8-14 | 0.8 / 0.12 | - |
| Slay N elites | 10-18 | 0.6 / 0.1 | - |
| Complete N zones with a Pigment | 2-3 | 4 / 0.6 | 5 clears |
| Defeat 1 Layer Warden | 1 | 15 / 3 | a Ground Shard or Warden kill |

- **Ranks:** 1 Apprentice (0), 2 Journeyman (60 rep), 3 Restorer (195), 4 Master Restorer (400).
- **Seal caches** (10 Seals; 3 seeded distinct offers, 4 at rank 4; the offer re-rolls after each cache; reward level = deepest revealed ring's level + 1): Armoury (3 weapons/off-hands: 2 rares + one at +400 rarity), Wardrobe (3 armour), Jewel Case (3 rings/amulets/belts/charms), Restorer's Satchel (40 Glaze Flakes, 10 Dust, 6 materials), Gem Pouch (3 gems, 2 materials), Patron's Purse (120 gold x level). Item caches need free bag slots first.
- **Pigment vendor (rank 2):** Glazed 1500 gold, Unfinished 1000, random modifier (same as crafting), 2 per refresh, respects the Easel stock cap.
- **Fixative gate (rank 3):** existing characters below rank 3 lose access until they rank up; items keep the Fixative already applied. With no character (pure item tests/tools) the gate is open.

## Results (Godot 4.0, Windows)
- `atlas_only` **472/0** (423 + 49), `items_crafting_only` **322/0**, `corruption_only` **127/0**, full suite **47882/0**.
- Pace Monte Carlo (20 seeds, synthetic reports for a player moving ring 1 -> 3, no rerolls): rank 2 median **20 zones**, rank 3 median **48 zones** (range 35-54), ~28 Seals earned by then (~2-3 caches).
- Smartbot baseline vs `tree_v4.csv`: **60/60 identical** (`out/p2c_check.csv`).

## Open
- The pace is a synthetic sim (the smartbot does not visit the hub); check it in real play.
- Vendor prices and cache contents are hand-tuned. Guild ranks 5-8 (4th Pigment Well colour, pet cosmetic, hub restoration visuals) wait for Phase 3+.
- Next: 2D Collector's Wager + Pentimento Vaults (both can add contract templates: "win a wager", "open a vault").

---

# Stage 2D: Collector's Wager + Pentimento Vaults + new contracts (2026-11-05, Claude)

## Decisions (Dan, 2026-11-05)
- Wager stake: **gold at 1x / 2x / 3x**; a win pays the stake back with profit plus materials; a loss costs only the stake.
- Vault types: **Treasure + Trap + Riddle** (plaque shows the type before opening).
- **Natural spawn only** (no Wager / Vault Pigments in 2D).
- New contract families: **Wager & Vault, kill counts, boss kills, challenge runs**.

## Files
| File | What |
|---|---|
| `data/atlas.json` `mechanics.list` | `wager`, `vault` entries with `minor: true`, `chance` 0.2. |
| `data/atlas.json` `mechanics.wager` | offers 3, stake 20 gold x level x mult, mults [1,2,3], rot_bonus 0.1, materials/flakes/dust per mult 2/8/2, rare at 3x (+300 rarity), 9 bets. |
| `data/atlas.json` `mechanics.vault` | count 1 (+1 at ring 3 or Rot 3, max 2), wall life 90, pocket 5, mouth 2, types (45/35/20), cache, trap, riddle, shard 8% + 2%/Rot. |
| `data/atlas.json` `guild.contracts` | 13 new templates (below). |
| `scripts/core/wager_vault_rules.gd` (new, pure) | bets (`offers`, `bet_ok`, `limits`, `text`, `stake`, `payout`, `stake_refusal`, `ends_at_boss`), vaults (`vault_count`, `roll_type`, `riddle_order`, `sigil_name/color`, `shard_chance`, `cache`). |
| `scripts/core/atlas_rules.gd` | `natural_mechanic` skips minor mechanics; new `minor_mechanics`; `run_mechanics` appends them. |
| `scripts/core/guild_rules.gd` | `STATS` + kills, bosses, wagers_won, wager_3x, vaults, trap_vaults, riddle_vaults; `progress_of` filters `max_time`, `max_boss_time`, `min_pigments`; `on_death` (streak reset); singular labels. |
| `scripts/world/dungeon.gd` | `run_t`, `boss_t`/`boss_fight`, `zone_kills`; Collector (`_place_collector`, `accept_wager`, `_tick_wager`, win/lose, signals); vaults (`_carve_vaults` before the world is built, `_seal_vaults`, `_place_vault_walls`, `open_vault`, trap/riddle, `strike_sigil`, `_vault_done`); report fields; death loses the bet + streak reset; `cleanup` disconnects. All 2D rolls use `mech_rng`. |
| `scripts/world/vault_seal.gd` (new) | the shimmer over a sealed vault mouth. |
| `scripts/entities/enemy.gd`, `scripts/world/level.gd` | enemy def flag `object`: no AI/movement/attacks, plaque + life bar; no kill, XP, loot or on-kill passives. |
| `scripts/entities/player.gd` | `flasks_used` (Abstinence bet). |
| `scripts/ui/wager_panel.gd` (new), `ui_root.gd` | the Collector's panel (3 bets x 3 stakes; active/won/lost status). |
| `scripts/gfx/art.gd` | sprites `npc_collector`, `pentimento_wall`. |
| `scripts/ui/components/atlas_map.gd`, `atlas_panel.gd` | minor mechanics drawn as dots under the mechanic square; legend. |
| `scripts/core/dev_tools.gd`, `dev_panel.gd` | force Wager / Vaults; **Open vaults**. |
| `tests/test_atlas.gd` | +80 checks: `test_wager_vault_rules`, `test_contracts_2d`, `test_live_wager`, `test_live_vaults`, `test_live_contracts_2d`; pace sim gets the 2D report fields; the 1D "same layout" check now seeds the global RNG (see Open). |

## Rules
- **Minor mechanics:** the Wager and Vaults never take the main natural roll (still Glazed / Unfinished at 30%). Each rolls on its own at 20% (x the Blooming Varnish multiplier), seeded by (atlas seed, hex, clear count). So a zone can have Glazed + Wager + Vaults. `Game.atlas_force_mechanic` / Dev force works for them.
- **The Collector** stands in a mid-depth chamber (middle third by depth). Interact: 3 seeded bets the zone supports (mechanic bets need their mechanic, Unscathed needs a living elite). One bet per zone, stake paid on accepting.

| Bet | Condition | Odds | Settles |
|---|---|---|---|
| Unscathed | next elite killed without taking a hit | 1.2 | elite kill / hit |
| Against the Clock | zone boss dead within 45 s + 20 s per chamber link to the arena | 1.0 | boss / timeout |
| Economy of Means | at most 2 different skills until the boss dies | 1.0 | boss / 3rd skill |
| Frenzy | 25 kills within 45 s | 0.9 | count / timeout |
| Abstinence | no flask until the boss dies | 0.8 | boss / flask |
| Iron Will | never below 50% life until the boss dies | 1.3 | boss / low life |
| Flaking (Glazed) | peel 4 glaze layers | 0.9 | count |
| Colourist (Unfinished) | paint 5 sketches | 0.9 | count |
| Archaeology (Vaults) | open 1 vault | 0.8 | count |

  Count / "next elite" bets still running when the boss dies are lost; any bet is lost on a death.
  **Win:** gold = stake x (1 + odds) x (1 + 0.1 x Rot) (stake included), 2 random materials, 8 Glaze Flakes, 2 Pigment Dust per x; at 3x a rare at +300 rarity. Example L45, 1x: stake 900, win 1800 gold.
- **Pentimento Vaults:** at setup the zone looks for a straight chamber edge with 9 x 7 cells of solid rock behind it and carves a 2-wide, 2-deep mouth plus a 5 x 5 pocket (pocket cells join the chamber for flow fields). The mouth is sealed (wall cells + body + shimmer); an object "Pentimento Vault" stands in front with 90 base life (scaled like a monster: level and Rot). Breaking it opens the mouth. No site found = fewer vaults.
  - **Treasure:** cache = 2 rares (+1 per 2 Rot) at +300 rarity, 1 gem, 3 materials, 15 gold x level, 8% legendary.
  - **Trap:** 2 elites (2-3 mods, level +1) + 3-4 monsters inside, aggro, loot x2; the cache drops when the last one dies.
  - **Riddle:** 3 sigils (Crimson, Ochre, Verdigris) in the pocket; strike in the plaque's order; a wrong one resets and wakes 3 monsters; solved = cache + 1 rare.
  - Every opened vault: Ground Shard of the ring's layer at 8% + 2% per Rot.
- **Run report** (still only on zone completion) gains: `kills` (before the boss died, walls excluded), `bosses` 1, `time`, `boss_time`, `pigments`, `wagers_won`, `wager_3x`, `vaults`, `trap_vaults`, `riddle_vaults`. Vaults/bets finished after the boss dies pay out but do not count.

| New contract | Need | Rep / Seals per unit | Needs |
|---|---|---|---|
| Win N Collector's Wagers | 1-2 | 8 / 1.2 | 3 clears |
| Win a Wager at 3x | 1 | 14 / 2.5 | 8 clears |
| Open N Pentimento Vaults | 1-3 | 4 / 0.6 | 3 clears |
| Clear a Trap Vault | 1 | 8 / 1.2 | 5 clears |
| Solve a Riddle Vault | 1 | 9 / 1.3 | 5 clears |
| Slay N monsters | 250-450 | 0.02 / 0.003 | - |
| Slay N elites at Rot 2+ | 8-14 | 0.9 / 0.15 | visible Rot 2 |
| Defeat N zone bosses | 3-6 | 3 / 0.4 | - |
| Defeat N bosses within 20 s of waking them | 1-3 | 5 / 0.7 | - |
| N zones in a row without dying | 3-5 | 4.5 / 0.7 | - (a death in an Atlas zone resets it) |
| N zones in under 4 minutes | 2-3 | 4.5 / 0.7 | - |
| N zones with 2 Pigments slotted | 1-2 | 7 / 1.0 | ring 3 + 10 clears |
| N zones at Rot 4+ | 1-2 | 8 / 1.2 | visible Rot 4 |

## Results (Godot 4.0, Windows)
- `atlas_only` **552/0** (472 + 80), stable over repeated runs. Full suite **47884/0**.
- Smartbot baseline vs `tree_v4.csv`: **60/60 identical** (`out/p2d_check.csv`).
- Pace Monte Carlo with the 2D report fields (Wager 20% of zones, ~55% won; Vaults 20%): rank 2 median 20 zones, rank 3 median **47** (range 35-58) - unchanged by the 13 new contracts.
- Live checks: a Collector zone has the same layout, packs and main RNG state as the same seed without it; vault sites are deterministic per seed; vault walls give no kill/XP/loot; each bet's win/lose path; vault Treasure/Trap/Riddle; report fields credited to the board; a death breaks streaks.
- Screens (`--shot`): `wager_panel.png`, `vault_closed.png`, `vault_riddle.png`.

## Open
- The smartbot never talks to the Collector (no bot data on bet win rates); it does break vault walls when it walks past them. Odds/stakes are hand-tuned.
- Found while testing: `dungeon._populate` shuffles spawn lists with the **global** RNG (pre-existing), so pack anchors and the objective roll depend on global RNG state unless it is seeded (the smartbot seeds it). The 1D "same layout" test was flaky for this reason; it now seeds the global RNG.
- No site for a vault (no 9 x 7 block of rock behind a chamber edge) means fewer vaults; ring 3 test seeds found 2 of 2.
- Vault-exclusive legendaries (design C3) wait for the legendary expansion; vaults use the normal legendary pool (8%).
- Wager / Vault Pigments (and Guild vendor entries) can be added later if natural spawns feel too rare.

---

# Stage 2E: bot tuning (2026-11-06, Claude)

## Decisions (Dan, 2026-11-05)
- Scope: **Wager bot + odds**, **Vault tuning**, **Mage balance**. (Rot 3+ Wardens not in this stage.)
- Mage: **bot behaviour only** (no class changes).
- Wager target: **about 60% Competent wins per bet**, odds set so a win at that rate is mildly profitable (expected gold about +10-20%).

## Files
| File | What |
|---|---|
| `tests/smartbot/sb_endgame.gd` (new) | The bot's Wager and Vault play. Walks to the Collector, takes a bet (`--wager=<id>` forced, `auto` = best expected return from `EST_WIN`), obeys it (no flask under Abstinence, only the kept skill under Economy of Means, flasks at 68% under Iron Will, no loot detours against the clock), hunts the bet's prey (Frenzy: nearest pack; Unscathed: nearest elite; Flaking: glazed elite; Colourist: sketch), opens vaults (breaks revealed walls, fights the trap, strikes riddle sigils in the plaque's order). Row notes `wager:<bet>|x<mult>|<state>|why=|offers=|t=|gold=|hits=|kills=|limt=|minlife=|peels=|painted=` and `vaults:<type:state+...>|t=|sigils=|shards=`. |
| `tests/smartbot/sb_controller.gd` | Hooks for the module (goal before the boss room, flask / skill / loot rules). **Blink as a second dodge**: when walking and the roll cannot clear a perceived telegraph, a Blink on the bar teleports to the safest of 32 spots. `--hits` traces every hit (perceived? evaded? cost). Notes `blinks:N`. |
| `tests/smartbot/sb_threat.gd`, `sb_profiles.gd` | `group_perception` profile flag (**off by default**): telegraphs one source spawns together share one awareness roll. Tested, not adopted (see Results). |
| `tests/smartbot/smartbot.gd` | `--wager`, `--stake`, `--vaults=0`, `--vault_type=trap|riddle|treasure`; forced bets are put into the offer only if the zone could offer them; gold is topped up for the stake. |
| `tests/smartbot/run_atlas_p2e.ps1`, `p2e_summary.py`, `p2e_trap.py` | Runner (`-Bets <ids>|vault|warden|plain`, `-Set`, `-VaultType`) and summaries. |
| `scripts/main.gd` | `Game.atlas_force_mechanic` takes a comma list (bots/tests: `wager,glazed`). |
| `scripts/world/dungeon.gd` | Unscathed hit allowance; `wager_refusal` (Archaeology with no sealed vault left, Unscathed with no elite left); bets only count monsters/elites **ahead** of the Collector (rooms at least as deep); timed count bets (Archaeology, Colourist); "second skill" message. |
| `scripts/core/wager_vault_rules.gd` | `limits` gains `hits`; `{hits}` placeholder; `bet_ok`/`offers` take monsters ahead (`min_monsters`). |
| `scripts/ui/wager_panel.gd` | Bets that can no longer be won are greyed out with the reason; odds shown with 2 decimals. |
| `data/atlas.json` | Retuned bets (below); Trap Vault 3 elites (was 2). |
| `tests/test_atlas.gd` | Checks follow the data (no hard-coded odds/times); +7: Unscathed allowance, Frenzy `min_monsters`, Archaeology refusal, timed Colourist. |
| `tests/smartbot/baseline/tree_v4_bot2e.csv` | New frozen baseline (bot change, see Results). |

## Wager: what the bot measured and what changed
Runs: atlas seed 1, hexes 2,-1 (ring 2, L45) and 3,0 (ring 3, L50), Rot 0, Competent, balanced, seed 900, 5 runs per class per hex, the bet forced at 1x. A forced bet the zone could not offer (no elite / monsters ahead, vault already open) is skipped and listed as "-".

| Bet | First measure (2D numbers) | Problem | 2E rule | Final win rate | Odds |
|---|---|---|---|---|---|
| Unscathed | 17% | any hit lost it; the boss often died before an elite | **up to 5 hits** before the next elite dies; bot hunts the nearest elite | **59%** (w 40 / r 67 / m 70) | 1.2 -> **0.95** |
| Against the Clock | 97% | 45 s + 20 s/chamber was far too generous | **12 s + 8 s per chamber** | **67%** (w 70 / r 90 / m 40) | 1.0 -> **0.7** |
| Economy of Means | 100% (2 skills) | trivial | **1 skill** | **93%** (no further number to tune) | 1.0 -> **0.25** |
| Frenzy | 27-35% | zones with nothing left to kill; bot walked to the boss | offered only with **35+ monsters ahead**; 25 kills in **38 s**; bot hunts packs | **57%** (w 80 / r 60 / m 30) | 0.9 -> **1.0** |
| Abstinence | 87% | no number to tune | unchanged rule | 87% (deaths are the losses) | 0.8 -> **0.3** |
| Iron Will | 96% at 50% | trivial | **70% life** (from the min-life spread of 30 runs) | **60%** (w 40 / r 90 / m 50) | 1.3 -> **0.9** |
| Flaking | 7% | bot never sought glaze | bot hunts glazed elites; **7 layers** | **72%** | 0.9 -> **0.8** |
| Colourist | 80% (5) / 100% (12) | sketches everywhere | **10 sketches within 75 s** (timed) | COLOURIST_RESULT | 0.9 |
| Archaeology | 39% | vault opened before the bet | refused once no sealed vault is left; **timed: 40 s** | **61%** | 0.8 -> **0.9** |

- Expected gold per 1x bet at the measured rate is about +10-20% of the stake, plus the materials. The two "safe" bets (Abstinence, Economy of Means) have nothing left to tune, so they pay low odds instead of being forced to 60%.
- The mage is the slow class in timed bets (Against the Clock 40%, Frenzy 30%); the ranger is the best gambler.
- `EST_WIN` in `sb_endgame.gd` holds these per-class rates; `--wager=auto` picks the offered bet with the best `p x (1 + odds) - 1`.

## Vaults
- 60 runs with natural vault types (r2/r3, Rot 0/3): **69% of vaults opened** (the bot only detours for walls it has seen; the rest were off its route), breaking a wall takes 0-7 s, no death caused by a vault. 29 of 35 vaults were Treasure on these seeds, so Trap/Riddle were forced with `--vault_type`.
- Trap (forced, 2 elites): 60 runs, **no death while trap monsters were alive**; 5 deaths, all at Rot 3 to the Heart of Rot or a pack outside the vault; traps took 0-21 s. -> **3 elites** (same mods, loot x2): 60 runs, again no death inside a trap (4 Rot 3 deaths elsewhere). Traps stay a fairly safe extra fight; more danger can come with Rot-mutated vault bosses later (design C3).
- Riddle: always solved (the bot reads the plaque; a wrong strike is a player mistake the bot does not make).
- Wall life (90 base) left unchanged.

## Mage (bot behaviour only)
- Per-hit traces (`--hits`) of mage Warden deaths: **every damaging hit was a telegraph the bot never perceived** (Competent: awareness 75%, mistake 20%, so about 60% of telegraphs are acted on). The warrior misses the same share but each miss costs it 8-20% life; the mage loses 15-60% per miss (Gravemaw burrow up to 471), and its Warden fights last 3-6x longer (median 32-62 s vs 9-15 s; kit DPS 900-3200 vs warrior 2300-6300), so it meets more misses.
- **Blink as a dodge** (adopted): the mage always had Blink on the bar but never used it. Warden runs, rings 2/3, 5 runs per class: ring 2 mage 1/5 -> **2/5**, ring 3 unchanged 2/5 (Blink never fired: the hits were unperceived). Rot 4 ring 3, mage only: 0/5 (1E) -> **1/5**. Warrior and ranger unchanged.
- **Grouped perception** (tried, off): one roll per eruption/volley. Mage ring 3 2/5 -> 3/5 but ring 2 ranger 5/5 -> 4/5 (all-or-nothing misses hurt more). Left as `--set=group_perception:true` for later study.
- Reading: the remaining mage gap is fragility + low kit DPS, i.e. class balance, not bot play. A game-side fix (mage life/ES, Warden eruption damage, or kit DPS) is for Dan to decide.

## Results (Godot 4.0, Windows)
- `atlas_only` **ATLAS_RESULT**. Full suite **47883/0** (the total varies by 1-2 between runs, as in 2B-2D).
- Smartbot baseline vs `tree_v4.csv`: **55/60 identical**; the 5 changed rows are mage T6 runs where Blink fired (wins 6/10 -> 6/10: one won run lost, one lost run won). Warrior, ranger and all T3 rows identical. Frozen as **`baseline/tree_v4_bot2e.csv`**; compare against it from now on.
- Bot data: `tests/smartbot/out/atlas_p2e_<bet>_<r2|r3>_<tag>_rot0.csv` (v1 first measure, t1/t2/m1/m2 measurement, c1-c5 confirmation), vaults `atlas_p2e_vault_*_{v1,trap1,trap2}_rot{0,3}.csv`, Warden/Blink `atlas_p2e_warden_*_{e2,e3}_rot0.csv`, Rot `atlas_p2e_plain_r3_e3_rot4.csv`, baseline `out/p2e_check.csv`.

## Open
- Mage class balance (see above); Rot 3+ Wardens still not bot-tested.
- The bot still does not visit the hub between zones (Guild pace stays the synthetic sim) and does not craft Fixative.
- Flaking (72%) and Abstinence / Economy of Means (87-93%) sit above 60%; Colourist was confirmed on one batch only.
- Vault-exclusive legendaries, Wager/Vault Pigments: unchanged from 2D.
