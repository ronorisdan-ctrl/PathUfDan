# Path of Dan

A 2D pixel-art dark-fantasy action RPG built in **Godot 4.0** (GDScript).
Stage 2 adds the full **dungeon progression**: six tiers (including the endless
Abyss), run modifiers, objectives, hazards, minibosses, five new bosses and
endgame item tiers - on top of the stage 1 slice (three classes, passive tree,
random loot with legendaries, crafting, hub town).

## Running

1. Open Godot 4.0+ and import `project.godot` from this folder (or run it from the Godot MCP).
2. Press **F5**. The main scene is `res://scenes/main.tscn`.

No assets need importing: all pixel art is generated from palette grids in
`scripts/gfx/art.gd`, and all content is loaded from `data/*.json`.

> Exporting: add `*.json` to *Export > Resources > Filters to export non-resource files* so the data folder is packed.

## Controls

| Input | Action |
|---|---|
| WASD | Move |
| Mouse | Aim |
| LMB / RMB / Q / E / R / T / G | Skills 1-7 (hold to repeat) |
| Space | Dodge roll (brief invulnerability) |
| 1 / 2 | Life / mana flask |
| F | Interact / pick up. With the cursor on (or within 40 px of) an item label: pick it up if it is within reach, otherwise send your pet to fetch it. LMB on an item label also picks it up |
| I (or B) | Inventory |
| C | Character sheet |
| P | Passive skill tree |
| K | Skills / hotbar loadout / skill runes |
| J | Class specialisation |
| Tab | Large map |
| Z | Cycle loot filter |
| Esc | Close panels / pause menu |

## Game loop

Ashfall Sanctuary (hub) -> Dungeon Gate -> pick a tier (see its modifiers first) ->
complete the objectives to break the seal on the boss arena -> defeat the boss ->
Exit Portal (or Descend, in the Abyss) -> sell / salvage / craft / stash / respec.
Beating a tier's boss unlocks the next tier. Death returns you to town
(lose 10% of the current level's experience).

| Tier | Dungeon | Levels | Objectives | Boss |
|---|---|---|---|---|
| 1 | The Forgotten Depths | 1-10 | Boss | Sir Morcant, the Drowned Warden |
| 2 | Corrupted Catacombs | 8-18 | Elite guardian, boss | The Gravemaw (burrows, spits, erupts) |
| 3 | Abyssal Warrens | 15-26 | 3 ancient mechanisms, boss | Archon Velis (teleports, fire fans, void spirals, meteors) |
| 4 | Dread Sanctums | 22-34 | 3 relic fragments, Blood Altar waves, boss | The Iron Penitent (mortars, cannon; overheats = vulnerable) |
| 5 | Nightmare Vaults | 30-42 | Guardian, 3 seals, boss | Malgrath the Choirmaster (minion ward, hymn spirals) |
| 6 | The Endless Abyss | 38+ | Random objective per depth, elite waves every 3rd depth | Random tyrant per depth; Stormheart Colossus at depth 1 |

Each tier raises monster life, damage and resistances and the item rarity bonus.
From Tier 2, every run rolls **modifiers** (13 types, e.g. Hastened Horde,
Burning Blood, Volatile Dead, Tempest, Grim Healing, Glass Pact) shown at the
Dungeon Gate before you enter; each adds item quantity, rarity and experience.
Rooms can contain **hazards** (spike traps, fire vents, miasma pools).

### Pets

Buy pets with gold from the **Pet Keeper** in town (16 pets: dog, cat, frog, slime,
robot, goblin, fox, bunny, hedgehog, baby dragon, axolotl, tiny ghost, owl,
mushroom buddy, bat, mimic). The active pet follows you, collects gold and
crafting materials on its own, and fetches a far item when you press F on its
label. Each pet has its own upgrade tier (0-5, paid in crafting materials): every
tier unlocks one more rarity for F plus a capability (speed, shorter cooldown,
blink, wall-pass and magnet, full camera range). Switching pets is free at any
time (pause menu > Pets) and each pet keeps its upgrades. Pets are cosmetic only:
no collision, no health, never targeted, and their quirks use their own RNG.
All numbers are in `data/pets.json`. Every pickup (yours and the pet's) goes
through `level.pickup()`, which re-checks the loot filter, the pet's rarity cap,
bag space and the single-claim rule at the moment of collection. Pets are off
under `Game.testing` (tests and bots) unless `Game.pets_in_tests` is set.

## Architecture

```
data/                 All content (JSON). Add skills, items, affixes, passives,
                      enemies and dungeons here without touching code.
scripts/core/         Autoloads and state
  data.gd             Loads data/*.json                         (autoload Data)
  events.gd           Global signal bus                         (autoload Events)
  game.gd             Character, settings, input map, save/load (autoload Game)
  loot.gd             Item generation, affixes, drops, crafting (autoload Loot)
  stat_block.gd       Modifier aggregation: flat / increased / more, with sources
  character_data.gd   Level, passives, inventory, equipment, stat resolution, save format
scripts/combat/
  combat.gd           Damage packets, hit resolution, mitigation, statuses (autoload Combat)
  skill_exec.gd       Data-driven skill behaviours (melee_arc, projectile, ground_aoe,
                      nova, chain, dash, blink, summon, deploy, buff)
scripts/entities/     Player, enemy, boss (data-driven attack patterns + phases), minion, turret,
                      mine, projectile, AoE, hazard, loot drop
scripts/world/        Level base (grid, flow-field pathing, LoS, loot), hub, dungeon, generator
scripts/ui/           HUD, panels (inventory, character, passives, skills, vendor,
                      blacksmith, stash, dungeon gate, pause, death), menus, tooltips
scripts/gfx/art.gd    Original pixel art as palette grids, tiles, light textures (autoload Art)
tests/                Headless acceptance tests, screenshot capture, balance bot
```

### Damage rules (applied everywhere)

`final = (base + flat) x (1 + sum of increased%) x product(1 + more%)`

* *Increased* modifiers add together; *more* modifiers multiply.
* Attacks use weapon damage x skill effectiveness plus "added" elemental damage; spells use the skill's base damage. Skill level scales both.
* Defender: evasion (attacks only, capped 60%) -> block (spells at half chance, cap 75%) -> armour vs physical (`armour / (armour + 12 x hit)`, cap 80%) and resistances (cap 75%) -> damage reduction (cap 60%, 75% with temporary effects).

## Tests

```
godot --headless --path . res://tests/test_runner.tscn        # ~1400 acceptance checks (every skill is cast in a real dungeon)
godot --headless --path . res://tests/bot.tscn -- mage 3                          # autoplay from level 1
godot --headless --path . res://tests/bot.tscn -- ranger 1 dread_sanctums 28      # geared level-28 run of tier 4
xvfb-run godot --rendering-driver opengl3 --path . res://tests/screens_tiers.tscn -- /tmp/tiers
xvfb-run godot --rendering-driver opengl3 --path . res://tests/screens.tscn -- ranger /tmp/shots
xvfb-run godot --rendering-driver opengl3 --path . res://tests/screens_s3.tscn   # skills, runes, specialisations
xvfb-run godot --rendering-driver opengl3 --path . res://tests/screens_s4.tscn   # passive web, jeweller, charms
```

## Implemented in this slice

* Main menu, class selection with previews, settings, versioned save/load with 10 manual save slots and a rolling autosave (`user://saves/slot_01.json` ... `slot_10.json`, `autosave.json`). A save from the old single-file build (`user://pathofdan_save.json`) is imported into the first free slot once; the old file is left untouched. The autosave updates when you return to the hub, when you enter a dungeon, and every 2 minutes in the hub.
* Warrior, Ranger, Mage with distinct attributes, equipment restrictions, starting gear and 80 skills (Warrior 24, Ranger 26, Mage 30), unlocked by level; 7-slot hotbar with cooldowns; dodge roll; flasks.
* Warrior one-hand + shield (block) or two-handers; Ranger bows/firearms, mines and turrets; Mage elemental spells, blink and skeleton summons that follow you, path around walls, attack, die and carry over between areas.
* Passive web: 203 nodes in 21 named clusters (14 keystones), three class starts linked by hybrid roads, a central hub and an outer Wanderer's Road joining six outer clusters (Sanguine Rites, Prismatic Ward, Windwalker, Executioner's Path, Mind Fortress, Void Communion) so every keystone is reachable by every class. Pan/zoom, search box, cluster labels, click any reachable node to allocate the whole route (previewed in blue), stat-change previews, gold-cost refunds that never disconnect the tree.
* Loot: 129 item bases, 52 affixes with tiers, 5 rarities, item comparison tooltips with stat deltas, loot filter, sorting, selling, salvaging, stash, merchant stock.
* Crafting: upgrade base, reroll / add / remove affix, raise rarity, add socket, salvage - each with costs, preview and confirmation.
* Sockets and gems: gear rolls 0-3 sockets (by slot; more likely at higher item level). 8 gem types x 4 grades (Chipped, Flawed, Polished, Flawless); each gem gives different stats in a weapon, armour or jewellery. The Jeweller (hub) sockets and removes gems, combines 3 into the next grade and sells random gems. Gems drop from monsters and return to you when an item is sold, salvaged or destroyed.
* Charms: 10 charm bases for the charm slot with charm-only affixes (damage reduction, cooldown recovery, flask effect, life on kill, +1 to all skills and more).
* Legendaries: 20, including Emberheart, Wolfmother's Fang, Tyrant's Signet, Glacial Crest, The Thornwarden, Phantom Treads, Sigil of Echoes, Gunsmith's Pride, Warlord's Grip and Starfall.
* Dungeons: six tiers built from handcrafted room templates on a random tree (always connected), per-tier palettes and lighting, packs with elite modifiers (7 types), minibosses, hazards, run modifiers, objectives that seal the boss arena until completed, minimap with fog, exit / descend portals, first-kill passive points.
* Bosses: six, built from a reusable pattern library (cleave, charge, ring, eruption, mortar, fan, spiral, summon, teleport, burrow, ward, vent) with phase thresholds - all defined in `data/enemies.json`.
* Enemies: 15 monster types (melee, ranged, casters, assassins with dash strikes, shielded defenders that block frontal hits, summoners, swarms, explosive and brute types).
* Endgame items: Tempered (lv 15+) and Runeforged (lv 30+) versions of every weapon and armour base; affix tiers up to item level 42; void resistance affix.
* Skill behaviours: melee arc, projectile, ground AoE, nova, chain, dash, blink, summon, deploy (turrets/traps), buff, beam, leap, persistent zone and curse.
* Skill runes (17): socketed into skills (1 socket, +1 at skill level 6 and 12) to change area, projectiles, pierce/chain, cost, cooldown, duration, damage type and minions. Drop from monsters (more from elites, guaranteed from bosses) or bought from the merchant.
* Specialisations (16: Warrior 5, Ranger 5, Mage 6): chosen from level 12, with points at 12/20/28/36/44 spent on a six-node path ending in one of two capstones that add mechanics (rage, spreading flames, corpse blast, ricochet, deep freeze, arcane flow and more). Resettable for gold.
* Statuses: ignite, chill, freeze, shock (scaling magnitude), bleed, poison, stun, intimidate, frailty, marked, snare, agony; execute and range-based damage conditions.
* Elite modifiers (10) including damage shields, summoners and blinkers.
* Combat feedback: damage numbers, crits, hit flash, screen shake, telegraphs, status tints (ignite, chill, shock, bleed, stun).

## Known limitations / next steps

* Higher tiers are tuned with the autoplay bot (which never dodges); expect to refine numbers after real play.
* Skill catalogue is 80 of ~146 listed skills. New skills are mostly JSON entries using existing behaviours; channelled and transform skills need new behaviours.
* Sound effects are procedural; no music yet; no controller bindings yet (all input goes through the input map, so adding a pad is a binding change).
* Art is original placeholder-quality pixel art generated in code; swapping in hand-drawn sprite sheets is a change to `art.gd` only.
