# Changelog

## Caster itemisation (2026-11-06)

- **Spells now scale with caster gear the way attacks scale with weapons.** Before this, a better wand or staff added only % increases, so from about level 20 the mage fell further behind with every gear upgrade.
  - New prefixes **Searing / Frigid / Crackling**: "Adds X Fire / Cold / Lightning Damage to Spells" on caster weapons and off-hands. Same tiers as the attack versions (up to 31-38 / 31-38 / 36-44).
  - **Tempered and Runeforged wands and staves** gain an implicit "+N Added Spell Damage" (the spell's own type): wands 2-3 (Tempered) and 11-12 (Runeforged), staves 4 and 18.
  - Flat spell damage is scaled by each spell's **effectiveness** (its base damage relative to Fireball, +4% per skill level), so every spell gains about the same percentage.
  - New suffix **of Sorcery**: "+1 / +2 to Level of all Spell Skills" (caster weapons, amulets). **Skill levels from items may now exceed the level cap of 20 by up to 5.** This also applies to the existing "+1 to Level of all Skills" sources. Levels from character level and corruption still stop at 20.
  - **Gloves** can roll **Sorcerous** ("X% increased Spell Damage", same tiers as Mighty) and **of Haste** (cast speed).
  - New suffix **of Penetration**: "Spells Penetrate X% Elemental Resistances" (caster weapons, off-hands, amulets; up to 13-15%). Applies to fire, cold and lightning hits from spells, before the 90% resistance cap. Training Grounds dummies use the same rule.
- Measured with the bot gear audit tooling (static DPS, 5 characters per stage): the mage's single-target damage, without enemy defences, goes from 0.22-0.91 to about 0.75-1.1 of the warrior/ranger midpoint at every stage, and rare gear now lifts the mage as much as the warrior. Details: `docs/CASTER_ITEMISATION.md`.
- Tests: new `tests/test_caster_itemisation.gd` (quick run `tests/caster_only.tscn`). New smartbot frozen baseline `tests/smartbot/baseline/caster_v1.csv` (mage T6 6/10 -> 8/10 wins; warrior and ranger unchanged within noise).

## Endgame Phase 2E: Wager and Vault tuning from bot runs (2026-11-06)

- **Collector's Wager retuned** so a competent player wins about 60% of most bets, and a win is worth about +15% of the stake on average (plus materials):
  - Unscathed: "Slay the next elite taking no more than 5 hits" (was: no hit at all), odds 0.95.
  - Against the Clock: 12 s + 8 s per chamber to the arena (was 45 + 20), odds 0.7.
  - Economy of Means: a single skill (was 2), odds 0.25. Abstinence: odds 0.3 (both are safe bets, so they pay little).
  - Frenzy: 25 kills in 38 s (was 45 s), odds 1.0, and only offered when 35+ monsters are still ahead of the Collector.
  - Iron Will: never below 70% life (was 50%), odds 0.9. Flaking: 7 glaze layers (was 4), odds 0.6.
  - Colourist: 10 sketches within 75 s (was 5, untimed), odds 0.65. Archaeology: open a vault within 40 s, odds 0.9.
  - Unscathed and Frenzy now only count elites / monsters in the chambers from the Collector onward. A bet that can no longer be won (no sealed vault left, every elite dead) is greyed out in the Collector's panel with the reason.
- **Trap Vaults** spawn 3 elites (was 2).
- Smartbot: plays the Collector (takes, obeys and hunts for its bets) and Pentimento Vaults; the mage uses Blink to escape telegraphs it cannot walk or roll out of. New smartbot baseline `tests/smartbot/baseline/tree_v4_bot2e.csv`. Details: `docs/ENDGAME_PHASE2.md` (2E).

## Endgame Phase 2D: Collector's Wager, Pentimento Vaults, new contracts (2026-11-05)

- **The Collector's Wager** (natural, ~20% of Atlas zones): a gaunt collector waits mid-zone with 3 bets, e.g. "Slay the zone boss within 85 seconds", "Slay 25 monsters within 45 seconds", "Slay the next elite without taking a hit", "Use no more than 2 different skills", "No flasks", "Never drop below 50% life", plus bets on Glazed / Unfinished / Vaults when the zone has them. Stake gold at 1x, 2x or 3x (20 gold x zone level per x). A win pays the stake back with profit (stake x (1 + odds), +10% per Rot) plus materials, Glaze Flakes and Pigment Dust; 3x also gives a rare at +300 rarity. A loss (or a death) costs only the stake.
- **Pentimento Vaults** (natural, ~20% of zones; 1 vault, 2 in ring 3 or at Rot 3+): a shimmering painted-over wall hides a room carved into the rock. Break the wall (it has a life bar and never fights back); the plaque tells you first what is inside: **Treasure** (cache: 2+ rares, gem, materials, gold, small legendary chance), **Trap** (elite ambush with double loot, cache when cleared) or **Riddle** (strike 3 sigils in the plaque's order; a wrong sigil resets it and wakes guardians; richer cache). Every vault has an 8% (+2% per Rot) chance at a Ground Shard.
- **13 new Commission Board contracts:** win Wagers, win a Wager at 3x, open Vaults, clear a Trap Vault, solve a Riddle Vault, slay N monsters, slay elites at Rot 2+, defeat N zone bosses, defeat bosses within 20 s of waking them, N zones in a row without dying (a death resets it), zones in under 4 minutes, zones with 2 Pigments, zones at Rot 4+.
- The Atlas map shows Wager / Vault zones as small dots under the mechanic square. Dev panel > Dungeon > Atlas: force "Collector's Wager" / "Pentimento Vaults", **Open vaults**. Details: `docs/ENDGAME_PHASE2.md`.

## Endgame Phase 2C: Commission Board and Restorers' Guild (2026-11-05)

- **Restorer Ottilie** now stands in Ashfall Sanctuary once the Atlas is open. Her **Commission Board** holds 3 contracts (e.g. "Complete 4 Atlas zones", "Slay 2 Hearts of Rot", "Peel 10 glaze layers", "Defeat a Layer Warden") that progress as you complete Atlas zones. Finished contracts pay Guild reputation and Seals at once. The board refreshes every 5 completed zones, with one free reroll per refresh.
- **Seals:** 10 open a cache of your choice from 3 on offer (weapons, armour, jewellery, crafting materials incl. Glaze Flakes, gems, or gold).
- **Guild ranks:** 2 Journeyman (Pigment vendor: buy Glazed/Unfinished Pigments for gold, 2 per refresh), 3 Restorer (**Apply Fixative at the Blacksmith now needs rank 3**, about 40-50 zones), 4 Master Restorer (4th contract slot, 4 cache choices).
- Dev panel > Dungeon > Atlas Guild: +100 rep, +10 Seals, Complete board. Details: `docs/ENDGAME_PHASE2.md`.

## Endgame Phase 2B: Fixative and Rot-touched items (2026-11-05)

- **Apply Fixative** (new Blacksmith craft): spend 60 Glaze Flakes + gold (20 + 3 x item level) to lower an item's crafting corruption by 25%. At most twice per item (the tooltip shows "Fixative applied: N of 2"). It never rolls corruption itself, and it cannot touch a 100% sealed item or an Abyssal-Brand corrupted one.
- **Rot-touched items:** item drops in a Rot 4 region have a 10% chance (Rot 5: 25%, stronger tier) to carry a Rot-touched implicit: a bonus with a drawback, shown in green/red under the base implicits. Six kinds: Festering Might (damage / less life), Rotting Hide (damage reduction / slower), Spore Bloom (damage over time / crit multiplier), Gnawing Hunger (life on hit / mana cost), Blighted Fortune (rarity / void resistance), Carrion Appetite (damage vs elites / life regeneration). Crafting keeps it.
- Loot filter: new conditions "Is Rot-touched" and "Rot-touched kind ids". Every preset gives Rot-touched drops a green beam and minimap icon and never hides or dims them.
- Dev panel > Items: "Rot-touch bag items". Details: `docs/ENDGAME_PHASE2.md`.

## Endgame Phase 2A: Layer Wardens (2026-11-05)

- **Ground Shards:** clearing an Atlas region can drop a shard of its layer (Varnish, Craquelure, Pentimento): 45% + 10% per Rot, always from a Heart of Rot, guaranteed after 2 dry clears.
- **Layer Wardens:** with 3 shards, summon the ring's Warden at any cleared region of that ring (Atlas panel button; a gold crown marks it). The next run there fights Sir Morcant, the Gravemaw or Archon Velis as a Warden: new patterns, a final phase, much more life. Shards are spent only on victory; dying costs none.
- **Ground Pigments:** a Warden drops its layer's Ground Pigment (always on the first kill, then 1 in 3 with pity). Banked for the pinnacle (4 of 6 layers). The first kill of each Warden gives +1 passive point.
- Dev panel: Grant shards, Summon at q,r. Smartbot `--warden=1`. Details: `docs/ENDGAME_PHASE2.md`.

## Endgame Phase 1E: Pigments, Varnish and Rot tuning (2026-11-05)

- **The Easel** (button on the Atlas panel): craft Pigments from Glaze Flakes (Glazed, 120) or Pigment Dust (Unfinished, 30). Each has 4 charges and a random modifier (4 per mechanic). Slot up to 2; zones use 1 (2 in ring 3 or a Restored region). A slotted Pigment guarantees its mechanic, adds its modifier and +10% rewards; entering spends a charge, dying spends one more. Two Pigments can run both mechanics in one zone.
- **Varnish:** 6 rule-changers (a bonus with a penalty) dropped by Hearts of Rot (always on Harvest, sometimes on Restore). 1 slot, +1 per fully cleared ring (max 3).
- Filled-in sketches drop Pigment Dust 25% of the time.
- Rot 3-5 are harder: more monster damage, less life recovery for you (-15/30/40%) and faster monster attacks (+5/10/15%). The smartbot now wins about half its runs at Rot 4 with 2 Pigments.
- Dev panel > Dungeon > Atlas: unlock, reveal all, grant an Easel kit, set a region's Rot, force a mechanic.
- Tests: `atlas_only` 321/0, full suite 47844/0, smartbot baseline 60/60 identical. Details: `docs/ENDGAME_PHASE1.md`.

## Endgame Phase 1D: Glazed Elites and The Unfinished (2026-11-05)

- Two zone mechanics. Each Atlas run rolls one at 30% (seeded per region and clear, shown on the Atlas map as a coloured square and in the detail pane).
- **Glazed Elites:** more elites (x1.5), each wearing 2-4 glaze layers, one per modifier. A draining glaze-poise bar fills from burst damage and stuns/freezes; each break peels the outer layer, removing that modifier and dropping a Glaze Flake. Layers left on a fast kill shatter into Flakes (all within 3 s, none after 10 s). Removing every layer gives bonus Flakes and rarity.
- **The Unfinished:** 35% of packs (at least 3) are sketches: they attack but take no damage until painted with the status colours on their outline (ignite, chill/freeze, poison, shock, bleed/stun; 2 colours at Rot 3+ or ring 3) or filled in by enough hits. Painted sketches drop loot one rank higher; painting by colour also drops Pigment Dust.
- New materials Glaze Flake and Pigment Dust (banked for Fixative and Pigments in later updates; they never drop at random).
- Tests: `atlas_only` 254/0, full suite 47844/0, smartbot baseline 60/60 identical. Details: `docs/ENDGAME_PHASE1.md`.

## Endgame Phase 1C: Rot v1 and Heart bosses (2026-11-05)

- Rot, a per-region decay level 0-5 on the Atlas. A new Atlas plants Rot 1 on 2 seeded regions in rings 2-3; every completed zone spreads 2 fronts (+1 per harvested Heart) to Rot regions or their neighbours. Ring 1 is a safety ring; Restored regions never take Rot; total Rot is capped at 3 x the highest revealed ring. Dying in a zone adds +1 Rot there.
- Rot scales zones: up to +50% packs, +100% life, +70% damage, +130% quantity/rarity/XP, and elites gain a modifier from Rot 2.
- At Rot 3+ the zone boss is a Heart of Rot with 1-3 seeded mutations from new `rot_mutations` in `data/enemies.json` (3 per atlas boss), earlier phases and more life. After it dies choose Restore (Rot 0, region Restored for good) or Harvest (a legendary, gold, materials, gems and rares; the Rot stays and spreads faster).
- The Atlas map shows Rot blotches and level, Heart marks, Restored frames and the next spread; the detail pane lists the Rot scaling and the Heart's mutations. Existing atlases get their Rot sources on load (no save version change).
- Tests: `atlas_only` 196/0, full suite 47841/0, smartbot baseline 60/60 identical; smartbot Rot runs 68/75 boss kills (mage 5/10 at Rot 5, warrior and ranger 20/20). Details: `docs/ENDGAME_PHASE1.md`.

## Endgame Phase 1A + 1B: Atlas of Ruin core and two biomes (2026-11-05)

- The Atlas of Ruin opens from the Dungeon Gate after Malgrath (T5): a radius-3 hex map (36 regions; ring 1 Varnish L40, ring 2 Craquelure L45, ring 3 Pentimento L50). Clearing a region (boss kill) reveals its neighbours; vantage regions reveal radius 2. Biome, boss, base modifiers and layout derive from the atlas seed, so the panel shows the next run's modifiers. Free entry; no first-kill point or tier change from atlas bosses.
- Atlas state is per character: save version 5 adds an optional `atlas` key (`{seed, revealed, clears}`); v4 saves load unchanged.
- Two new zone biomes: Ruined Nave (BSP halls, sanctum palette) and Flooded Catacomb (cellular-automata grottoes, crypt palette), beside Overgrown Ruin.
- Zones cap each non-boss summoner at 8 adds in total (dungeons unchanged).
- Tests: `tests/atlas_only.tscn` 114/0, `tests/zone_only.tscn` 78/0 (3 biomes x 200 seeds), full suite 47842/0, smartbot baseline vs tree_v4 60/60 identical, smartbot atlas 57/60 boss kills. Details: `docs/ENDGAME_PHASE1.md`.

## Endgame Phase 0: zone technical spike (2026-11-05)

- New chamber-stitched zone generator (`scripts/world/zone_gen.gd`, `data/zones.json`): 5-7 cellular-automata / BSP chambers of 30-40 cells, an authored boss arena, wide drunkard's-walk connectors and a flood-fill pass. Dev-only "Zone spike: Overgrown Ruin" (Dev panel > Dungeon > Start run; smartbot `--dungeon=zone_overgrown_ruin`). No first-kill point or tier unlock.
- Zones: the flow field covers only the player's chamber and the chambers linked to it, and far packs sleep (no AI, no physics body). Flow BFS rewritten with integer indices (same distances). Chunked tile drawing in zones.
- Tests: `tests/zone_only.tscn` 48/0 (200 seeds); bench `tests/zone_bench.tscn` (windowed: about 156-174 fps with 180 enemies, p99 under 17 ms with 315). Smartbot 30/30 zone boss kills (T3), full suite 47844/0, smartbot baseline vs tree_v4 60/60 identical. Details: `docs/ENDGAME_PHASE0.md`.

## Passive tree Phase 5a: tree navigation and readability (2026-11-04)

- UI only; tree content, `tree_version` (6) and saves unchanged. Phase 5 split (Dan): 5a navigation/readability, 5b presets, planner and build codes.
- Three zoom levels of detail: far (cluster labels, class starts, keystones, allocated nodes), mid (+ notables, greater, masteries, sockets; minors as dots), near (all nodes and labels). Hidden nodes are not clickable.
- Filter row: 12 tag chips (fire, cold, lightning, physical, void, crit, ailment, melee, projectile, spell, minion, trap), a "More tags..." list of every other used tag, a "Behaviour only" toggle (keystones, masteries, sockets, flagged nodes) and Clear. Non-matching nodes are dimmed.
- Minimap (top right, click to jump, toggle button), "Jump to my start", and search-hit stepping (< / > / Enter, hit counter).
- Tooltips show the drawback in red and the node's tags. "Summary" side panel: what my tree does (keystones with drawbacks, behaviour nodes, masteries, socketed gems, every allocated stat summed and grouped by theme, top tags).
- Codex V5 contract: `docs/TREE_UI_CONTRACT.md` (node-state enum locked / available / unavailable / allocated / planned / migrated_refunded, overlays, LOD, art_id, cluster ids). A full tree refund now records the refunded node ids (`tree_refund.ids`), shown as "refunded" until the next load.
- Tests: tree_only 818/0, full suite 47818/0 (Godot 4.0, Windows). Screenshots: `tests/screens_tree_p5a.tscn`. `tests/run_timeout.ps1` runs a Godot scene with a timeout.

## Corruption system spec v1 (2026-11-04)

- Blacksmith Corrupt Item: one Abyssal Brand, 15/25/56/4 outcomes, permanent 100% seal, independent prefix/suffix implicits and explicit warning/result UI. Legendary properties and existing gem recovery preserved.
- Exact 82-family registry, category/family/tier weights, base-tag restrictions and compatibility checks. All ordinary, Signature and individually gated exceptional mechanics implemented and tested.
- Persisted action receipts, legacy/current item normalization, source-tagged effects and failed-save rollback. No save-version bump or retroactive implicit roll.
- Rare Brand drops use an isolated seeded stream. Existing craft corruption gain and non-corruption combat behavior retained; compatibility decisions and benchmark limits recorded in `docs/CORRUPTION_SYSTEM.md`.

## Passive tree Phase 4b: tree gem sockets (2026-11-04)

- Tree 328 -> 337 nodes, `tree_version` 6 (full free refund for older saves). 9 gem sockets (ids `p4_s_*`, `rev` 6): 2 per class (inner + archetype spur) and 1 in the middle of each bridge.
- A socket holds one gem from the pouch; socketing, swapping and removing are free, refunding the socket returns the gem. The gem gives a tree-only stat table (`tree` in `data/gems.json`, scaled by grade) and boosts allocated minor/greater/notable nodes within 240 units that share its `tree_tags` by 15/25/35/50% (Chipped..Flawless); overlapping rings take the larger boost.
- Saves keep `tree_gems`; a gem whose socket is gone returns to the pouch (never lost). Validator: socket schema, `tree_sockets` config, no routing through sockets. UI: socket node with gem colour, ring on hover, boosted-node outline, gem menu, tooltip. Bots skip sockets.
- The "25% behaviour nodes" check now counts fixed nodes only (masteries and sockets are a separate choice layer): 84/316.
- Tests: tree_only 782/0, full suite 47728/0 (Godot 4.0, Windows; includes the corruption acceptance batch). Smartbot baseline check: 60/60 runs identical to `tree_v4.csv` (no re-baseline).

## Passive tree Phase 4a: mastery choice nodes (2026-11-04)

- Tree 316 -> 328 nodes, `tree_version` 5 (full free refund for older saves). 12 mastery nodes (ids `p4_m_*`, `rev` 5) over 9 groups: Melee, Bulwark, Bloodletting x2, Projectile x2, Deployable, Affliction, Elemental x2, Minion, Mind. Each offers 4 effects; pick one when allocating.
- An effect can be chosen once across the tree (matters for the 3 doubled groups). Changing an effect costs one node's refund price. Saves keep `mastery_choices`; a bad choice in a save is an illegal allocation (full refund).
- Validator: mastery schema, option registry (unique ids, flat/inc only), no routing through masteries. UI: hexagon nodes, effect menu, tooltip with taken/current effects. Bots skip masteries.
- Tests: tree_only 736/0, full suite 3088/0 (Godot 4.0, Windows). Smartbot baseline check: 60/60 runs identical to `tree_v4.csv` (no re-baseline; bots take no masteries).

## Passive tree Phase 3b: six archetype spurs (2026-11-04)

- Tree 232 -> 316 nodes (+84), `tree_version` 4 (full free refund for older saves). Behaviour-changing nodes 66 -> 84 (27%); keystones 23 -> 26.
- Six 14-node "wheel" spurs, two per class (ids `p3b_*`, `rev` 4): Earthbreaker (Tremor Lines, Shockwave, keystone Earthbreaker) and Duelist (Feint, Single Combat, Blade Dance) for the warrior; Trapper (Barbed Snares, Noxious Payload, keystone Master Trapper) and Barrage (Volley Fire, Arrowstorm, Endless Quiver) for the ranger; Tempest (Conductive Web, Thunderhead, Static Cascade) and Frostweaver (Cold Snap, Brittle, keystone Glacial Heart) for the mage.
- Exclusive pairs: Master Trapper ⟂ Clockwork Mind; Glacial Heart ⟂ Avatar of Embers and Prismatic Soul.
- Status coverage: chill 8 -> 12, freeze 6 -> 9, shock 6 -> 10, stun 4 -> 7, snare 6 -> 9, poison 3 -> 5, agony 3 -> 4.
- Tests: tree_only 680/0, full suite 3017/0 (Godot 4.0, Windows). Smartbot re-baselined: `tests/smartbot/baseline/tree_v4.csv`.

## Passive tree Phase 3a: bridges, conversions, cuts, Abyss points (2026-11-04)

- Tree 227 -> 232 nodes (+19 new, -14 cut), `tree_version` 3 (full free refund for older saves). Behaviour-changing nodes 39 -> 66 (28%); keystones 20 -> 23.
- Bridges on the three class roads: centres became behaviour notables (Hunter-Knight, Hexshot, Spellblade), each with a spur of 2 notables and a bridge keystone: Pinning Shot, Run Them Down, Twin Disciplines | Charged Quiver, Overload, Spell Archer | Rime Edge, Shatter, Battlemage's Covenant.
- Phase 0 conversions: Brutal Force, Second Wind, Deadeye Mastery, Engineer's Doctrine, Killer Instinct, Pyroclasm, Commander Mastery, Rift Step, Festering Wounds, Elemental Warding, Tailwind, Deathblow, Arcane Shell, Abyssal Gaze; Prismatic Soul got a rule (elemental ailment immunity, cannot inflict them; exclusive with Avatar of Embers).
- Phase 0 cuts: 12 Wanderer's Road minors (arcs now 4 nodes of +6) and xp_p13/xp_p14. Generator supports explicit ids and hand -> generated links.
- Endless Abyss bonus points: +1 at depths 10/20/30/40/50/60/70 (derived from abyss_best, retroactive). L60 total 72.
- Status coverage: freeze 0 -> 6, shock 0 -> 6, chill 1 -> 8, marked 1 -> 5, snare 1 -> 6.
- Tests: tree_only 524/0, full suite 2762/0 (Godot 4.0, Windows). Smartbot re-baselined: `tests/smartbot/baseline/tree_v3.csv`.

## Passive tree Phase 2: 24 behaviour nodes (2026-11-04)

- Tree 203 -> 227 nodes, `tree_version` 2 (full free refund for every older save, per Dan's policy; v3/tree-1 saves get a `.tree1.bak`). Behaviour-changing nodes 15 -> 39; keystones 14 -> 20.
- 6 keystones: Blood Frenzy, Iron Riposte (mutually exclusive), Clockwork Mind, Venom Pact, Avatar of Embers, Legion of Bone. 18 notables, 2 per archetype (Opened Veins, Blood Scent, Counterweight, Staggering Guard, Rallying Cry, Herald's Voice, Volatile Mechanisms, Overclock, Agonising Toxins, Virulence, Marked for Death, Shadowstep, Funeral Pyre, Searing Insight, Marrow Feast, Necrotic Orders, Frailty Bloom, Hexblight). All 5 audit examples are in. Each archetype is a 2-3 node spur off its class cluster (ids `p2_*`, `rev` 2).
- New combat hooks (Dan accepted 2 [H]): poison stacking (`actor.add_status` with `max_stacks`, `poison_stacks()`; normal poison unchanged) and Avatar of Embers conversion (`Combat.player_packet` + `apply_status`). Other hooks: `Combat._on_hit_passives`, `player._kill_passives` (on_kill now gets the killer), `player._on_block(source)`, `turret/mine.retire()`, `turret.overclocked()`, minion death burst, War Herald in the buff behaviour.
- Mind over Matter now has a drawback (30% less mana regeneration); `pending_rework` is empty.
- 24 new flags registered (39 total), each with a behavioural test; v3 save fixtures now expect a full refund to tree 2.
- Tests: tree_only 333/0, full suite 2538/0 (Godot 4.0, Windows).
- Smartbot re-baselined once: `tests/smartbot/baseline/tree_v2.csv` (T6 wins: warrior 10/10, ranger 10 -> 9/10, mage 7 -> 8/10). The bots take no keystones.

## Passive tree Phase 1: schema, migration, validator (2026-11-04)

- Schema: all 203 nodes carry `tags` (from the Phase 0 audit), the 14 keystones carry `drawback`; optional `exclusive_with`, `rev`, `art_id`. Sources stay in `data/tree_src/`; `tools/gen_clusters.py` copies the new keys through and `--check` is still byte-for-byte. No node, link, cost or effect changed.
- `data/passive_flags.json`: registry of the 15 tree flags (12 behaviour, 3 marker), tag vocabulary, statuses, point budget 72. `data/passive_migrations.json`: `tree_version` 1 and an empty id history.
- `scripts/core/tree_rules.gd`: validator (ids, keys, types, costs, tags, flags, `more` only on keystones, drawbacks, links, exclusivity, reachability, keystone cost within budget per class, migration history) and allocation rules used on load.
- SAVE_VERSION 4: saves store `tree_version`. Full free refund (Dan's policy) when the tree version is older or the allocation is illegal; one-time message on the next level load; the original file is kept as `<slot>.tree<N>.bak`. Version 3 saves load unchanged.
- `exclusive_with` is enforced by `can_allocate` and `path_to` (no pairs exist yet).
- Tests: `tests/test_passive_tree.gd` (also in the full suite) and `tests/tree_only.tscn`: validator on the real tree plus 15 broken-tree cases, generator check, v3 saves in all 10 slots and the autosave, refund cases, and a behavioural test for every flag on a live character in a dungeon. Two old checks that hard-coded SAVE_VERSION 3 now expect 4.
- Smartbot: frozen baseline `tests/smartbot/baseline/tree_v1.csv` (3 classes x T3/T6 x 10 runs), `run_baseline.ps1`, `compare_baseline.py`.
- Docs: `docs/PASSIVE_TREE_DATA.md`.

## Visual overhaul Phase V0: art pipeline (2026-10-29)

- Art scale decision (`docs/adr/0001-art-scale.md`): 32 px art per 16-unit cell at node scale 0.5 with the existing camera zoom 2, so 1 art pixel = 1 screen pixel and no gameplay number changes. Values in `data/render.json` (`Art.ART_SCALE`, `Art.camera_zoom()`; `player.gd` reads the zoom from it).
- Master palette `assets/palette/dying_canvas.hex` (48 pigment colours from the Art Bible).
- Sprite manifest `data/art/sprites.json`: 31 entries (3 classes, 15 monsters, 6 bosses, 7 minions) with frame size, pivot, directions, mirroring and animations, following the Art Bible (64x64 canvas, feet at y=58, 10 fps; player 8 directions, enemies and bosses 4).
- `scripts/gfx/sprite_anim.gd` (AnimatedSprite2D built at runtime) and `scripts/gfx/anim_rules.gd` (pure rules). Hooked into `actor.gd`: player, enemies, bosses and minions use sheets when present, otherwise the old sprite exactly as before. Hit flash, dodge fade and visibility carry over; the fake bob and tilt are skipped for animated actors.
- Visual-only bookkeeping so animations land on the hit: `player.swing_skill_kind` and `player.swing_impact` (set in `skill_exec.gd` for melee arcs and self-centred ground AoEs). Enemy health bars use `visual_height()`.
- Tools (Pillow): `tools/art_ingest.py`, `tools/validate_art.py`, `tools/make_placeholder_sheets.py`, `tools/make_asset_list.py`, `tools/make_style_images.py`, shared `tools/art_common.py`.
- Placeholder sheets for warrior, ranger, mage and ghoul in `assets/placeholders/` (off in game by default).
- `tests/art_gallery.tscn`, `tests/screens_art.tscn`, `tests/art_only.tscn`, and `tests/test_art.gd` (about 100 checks, also run by the full suite): manifest integrity, fallback with missing files, 8-way picking with hysteresis, mirroring, impact-frame sync for a fast and a slow melee attack and for an enemy wind-up, RNG isolation, texture import settings, gallery.
- Docs: `docs/ART_STYLE_GUIDE.md`, `docs/ART_ASSET_LIST.md` (generated), `docs/img/`, `assets/CREDITS.md`.
- Fix: Drillmaster Rook showed the fallback ghoul sprite because `data/training.json` named a sprite id that doesn't exist (`drillmaster`); now `npc_drillmaster`. Found by `validate_art.py`.
- Verification: 2158 passed, 0 failed (2058 before plus the new art checks). Smartbot (Linux, warrior T1, ranger T2 L12 Expert, mage T2 L12 Competent, 4 runs each) byte-identical to the pre-V0 baseline with art off and with placeholder sheets on.

## Crafting corruption (branch `feature/crafting-corruption`, not merged)

- Phase 1: `data/corruption.json`, pure rules in `scripts/core/corruption_rules.gd`, `Data.corruption_cfg`, rules tests. Add Affix, Reroll Affix and Raise Rarity roll (50% for +20% corruption); Upgrade Base, Remove Affix and Add Socket are exempt.
- Phase 2: the Blacksmith applies the craft in full, then rolls once with its own RNG (`apply_craft`). At 100% add / reroll / raise rarity are refused before any cost. The value is saved as an integer `corruption` on the item (no save version change) and survives the personal and shared stash.
- Phase 3: "Corruption: N%" line and a 10-block bar on every item tooltip (grey, amber, red; red "Corrupted: cannot be crafted" at 100%), a wide bar with tick marks and "N more corruption events before lock" in the Blacksmith, a risk line on each rolling craft button, disabled add / reroll / raise rarity buttons with the refusal as tooltip at 100%, a warning in the confirm dialog above 60%, a red corner marker on 100% item slots, and Set / Clear corruption buttons in the F1 Items tab (dev-used save flag). Tests: `test_corruption_ui()`, `tests/items_crafting_only.tscn`, screenshots via `tests/screens_corruption.tscn`.
- Tuning (Dan, 2026-10-29): chance 0.6 and step 25 in `data/corruption.json` (minimum 4 rolling crafts, about 6.7 on average). The corruption tests now read the numbers from the data file instead of hard-coding 50% / +20%.
- Phase 4: README section (Crafting corruption, test commands, limitations), this entry and a status note in the project docs.

## 2026-10-28 — Dying Canvas inventory preview

- Added a standalone inventory/character UI study with tarnished cabinet frames, forty bag cells, eleven equipment cells, hover/pinned/focus states, comparison gains/losses, ring target switching, local sample swaps, sorting, filtering and reset.
- Added a one-click launcher, JSON sample fixtures, focused interaction checks and five repeatable screenshot states. Existing procedural icons and fonts remain provisional; the illustrated concept is a visual reference, not a flattened in-game panel.
- The preview does not create or save a character; live gameplay and UI are unchanged.

## Training Grounds (branch `feature/training-grounds`, not merged)

Added
- **Drillmaster Rook** (hub NPC) and a Training panel with Setup, Result and History tabs.
- Single-target and three-dummy AoE DPS tests: 10 s or 30 s, All sources or Player only, defence profile (none, Tier 3 normal enemy, Tier 6 boss with poise), cluster spacing Tight or Spread.
- Result above the dummy's head (average DPS, peak second, settings, top three sources; in AoE a total line above dummy 1 and each dummy's own DPS and share), and a full Result tab with a per-skill breakdown, per-dummy table and average targets hit per cast.
- History of the last 5 tests per character (session only), with the change against the previous comparable test, a build snapshot (character, level, specialisation, main/off hand, hotbar, passives) and "what changed since last time". Clear history asks for confirmation.
- `data/training.json` (all tuning and wording), `scripts/core/training_rules.gd` (pure rules), `scripts/core/training_log.gd` (new autoload `TrainingLog`, listed last, after `Dev`), `scripts/entities/training_dummy.gd`, `scripts/ui/training_panel.gd`.
- Tests: `test_training()` and `test_training_world()` in `tests/test_runner.gd` (about 160 checks), `tests/train_only.tscn` for a quick run, `tests/screens_training.tscn` for screenshots.

Changed
- The old fixed hub dummy (an enemy entry in the hub) is replaced by the spawnable training dummy.
- Summon, deploy and buff skills are allowed in the hub, but only while training dummies exist (`player.gd`, one condition).
- Player damage packets carry a cast number (`Combat.cast_serial`); statuses record the skill that applied them (`src_skill`, `src_kind`); minions know which skill summoned them. These are bookkeeping only: smartbot results are byte-identical to the baseline (warrior/ranger/mage, tier 2 Competent and tier 3 Expert, seed 700).

Not changed
- Gameplay, balance, the save format (no `SAVE_VERSION` change) and the existing autoload order (`TrainingLog` is appended).
- The Training Grounds are off under `Game.testing` unless `Game.training_in_tests` is set.
