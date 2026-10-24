# Smart player bot (`tests/smartbot/`)

A layered autoplay bot that plays Path of Dan the way a human who uses every progression
system would: it dodges telegraphs with human-like reaction time and mistakes, equips and
crafts gear, sockets and combines gems, follows a passive-tree build plan, picks a 7-slot
hotbar, applies runes and specialisations, drinks flasks, does objectives, and writes one CSV
row per run. It exists for Monte Carlo balance studies. **It never changes game data or game
logic.** The old probe `tests/bot.tscn` is untouched and still works.

Version string written to every row: `smartbot-1.0`.

---------------------------------------------------------------------------------------------
## 1. Files and scenes

| File | Role |
|---|---|
| `smartbot.tscn` / `smartbot.gd` | Entry point. Argument parsing, seeding, coordinator (one child process per run), run loop, CSV/trace output, checkpoints. |
| `launcher.tscn` / `launcher.gd` | Batch runner for tools that cannot pass CLI arguments (the Godot MCP `run_project`). Reads `jobs.txt`. |
| `jobs.txt` | Job list for the launcher (one smartbot argument line per job). |
| `sb_profiles.gd` | Skill profiles `NoDodge`, `Competent`, `Expert` (behaviour parameters only). |
| `sb_threat.gd` | Perception: reads on-screen telegraphs, rolls awareness/mistakes, reaction delay, danger evaluation, damage attribution. |
| `sb_controller.gd` | In-dungeon play: avoidance + dodge roll, targeting, class spacing, skill choice, flasks, retreat, objectives, loot. |
| `sb_hub.gd` | Town: gear score / equip, sell / salvage, crafting with a gold budget, vendor, gems, hotbar, runes, specialisation. |
| `sb_planner.gd` | Passive-tree build planner (keystone targets + value-per-point frontier, using `CharacterData.path_to`). |
| `sb_kit.gd` | Entry-kit generator (plausible character for a tier and level). |
| `out/` | Results (has a `.gdignore` so the editor does not import CSVs as translations). |

Game files touched: **none**. No hooks were needed: telegraphs, hazards, projectiles and boss
patterns are all readable from public node variables, seeding uses the existing RNGs
(`seed()`, `Loot.set_seed()`, `Combat.rng`, the dungeon seed argument of
`main.enter_dungeon`), and headless / fixed-delta are Godot command-line options.

---------------------------------------------------------------------------------------------
## 2. Running it

### 2a. From a terminal (preferred)
```
godot --headless --fixed-fps 60 --path "<project>" res://tests/smartbot/smartbot.tscn -- \
      --class=warrior --tier=2 --runs=20 --seed=100 --profile=Competent --build=balanced \
      --jobs=12 --out=res://tests/smartbot/out/study.csv
```
`--fixed-fps 60` must match `--tps` (default 60): it makes every frame advance the game by
exactly `ts/60` s, which is required for determinism (AoE telegraphs, hazards and damage
numbers tick in `_process`). The coordinator passes the same value to its child processes.

### 2b. Through the Godot MCP (no CLI arguments possible)
1. Edit `tests/smartbot/jobs.txt` (see format below).
2. `run_project(projectPath, scene="res://tests/smartbot/launcher.tscn")`.
3. Poll `tests/smartbot/out/launcher_status.txt` until the first line says `ALL DONE`
   (it lists every job with state, exit code, seconds, error count and the CPU count).
   Each job's console output is in `out/job_<n>.log`.

`jobs.txt` format:
```
parallel=1                         # launcher-level parallelism (jobs at once)
--class=ranger --tier=2 --runs=20 --seed=100 --profile=Expert --jobs=14 --out=res://tests/smartbot/out/x.csv
scene=res://tests/test_runner.tscn # run another scene headless (with --fixed-fps)
realtime scene=res://tests/bot.tscn # 'realtime' = no --fixed-fps (normal frame timing)
```
Before the batch the launcher runs a pre-flight (`--check=1`): if the bot does not boot
within 60 s (a script error leaves headless Godot hanging) the status file says
`PREFLIGHT FAILED` and nothing runs. **Always smoke-test code changes (1-2 runs) before a
long batch.**

Prefer `parallel=1` with a large `--jobs=` per line: one coordinator then owns its CSV.
Several lines may append to the same CSV only when they run one after another
(`parallel=1`), because the coordinator is the only writer of its CSV.

### 2c. Arguments (`--key=value`; flags without value)

| Argument | Default | Meaning |
|---|---|---|
| `--class=` | `warrior` | `warrior`, `ranger`, `mage` |
| `--tier=` | `1` | dungeon tier 1-6 (the dungeon with that `tier` in `data/dungeons.json`) |
| `--dungeon=` | | override the dungeon id |
| `--level=` | tier `min_level + 3` | start level of the entry kit (T1 4, T2 11, T3 18, T4 25, T5 33, T6 41) |
| `--runs=` | `5` | number of characters (fresh mode: = runs) |
| `--mode=` | `fresh` | `fresh`: new entry kit for every run. `carry`: each character plays `--carry` consecutive runs |
| `--carry=` | `3` | runs per character in carry mode |
| `--seed=` | `1` | master seed (see section 5) |
| `--profile=` | `Competent` | `NoDodge`, `Competent`, `Expert` |
| `--build=` | `balanced` | `balanced`, `glass`, `defensive` (section 4) |
| `--no-gems` `--no-passives` `--no-dodge` `--no-crafting` | off | ablation toggles (section 7) |
| `--out=` | `res://tests/smartbot/out/results.csv` | CSV path (absolute paths work too) |
| `--jobs=` | `1` | child processes run in parallel by the coordinator (one per character chain) |
| `--ts=` | `1` | `Engine.time_scale` (section 6) |
| `--tps=` | `60` | physics ticks per second (must equal `--fixed-fps`) |
| `--timeout=` | `900` | game seconds before a run counts as `timeout` |
| `--trace=1` | off | per-run human-readable trace in `out/trace/<run_id>.txt` |
| `--kit_only=1` | off | only generate entry kits; writes `<out>_kits.json` (full `CharacterData.to_dict()` + summary) |
| `--only=N` | | only character chain N (for reproducing one run) |
| `--isolate=0` | `1` | play every run in this process instead of fresh child processes (faster to debug; rows then depend on what ran before in the process, see 5) |
| `--set=k:v,k:v` | | override single profile parameters, e.g. `--set=reaction_ms:250,awareness:0.85` (sensitivity studies; becomes part of the profile name and run id, e.g. `Expert[reaction_ms:250]`) |
| `--max_wall=` | `1800` | wall-clock seconds after which the coordinator kills a hung child (logged in `_errors.txt`) |
| `--check=1` | | boot check only (used by the launcher pre-flight) |
| `--debug` | off | extra diagnostics in the trace: STUCK grid dumps, periodic position / target lines, `CONTACT` lines for hits that matched no telegraph (with the boss state), objective reachability on a timeout |
| `--unit=c:r` | | internal: what the coordinator passes to a child |

Examples
```
# smoke test: 5 Tier 1 warrior runs with traces
... smartbot.tscn -- --class=warrior --tier=1 --runs=5 --seed=1 --trace=1 --out=res://tests/smartbot/out/smoke.csv
# carry-over: 10 mages, each plays 3 consecutive Tier 3 runs
... -- --class=mage --tier=3 --runs=10 --mode=carry --carry=3 --seed=42 --jobs=10 --out=res://tests/smartbot/out/carry.csv
# ablation: same characters and seeds without gems
... -- --class=ranger --tier=2 --runs=50 --seed=7 --no-gems --out=res://tests/smartbot/out/abl.csv
# entry kits only
... -- --class=warrior --tier=4 --runs=5 --seed=3 --kit_only=1 --out=res://tests/smartbot/out/kits.csv
# glass build, expert player
... -- --class=ranger --tier=3 --build=glass --profile=Expert --runs=20 --out=...
```

### 2d. Output files (all next to `--out`)
| File | Content |
|---|---|
| `<name>.csv` | one row per run (section 8). Appended and flushed per run. |
| `<name>_perf.csv` | `run_id, wall_s, game_s` (wall-clock time is not deterministic, so it is kept out of the main CSV) |
| `<name>_rows/<run_id>.json` | the row as written by the child process (crash recovery; merged into the CSV on the next start) |
| `<name>_ckpt/<run_id>.json` | carry mode: character after run r (after the town visit), loaded by run r+1 |
| `<name>_errors.txt` | output of child processes that failed |
| `trace/<run_id>.txt` | with `--trace=1` |

---------------------------------------------------------------------------------------------
## 3. Skill profiles (behaviour only)

Profiles are defined only by human-behaviour parameters. They were **never tuned towards a
success rate**. During validation the bot's decision logic was fixed where a *better*
parameter value produced *worse* play (bot bugs, fixed for every profile alike): the
safety margin was inverted (the better player now keeps the smaller buffer), "best target"
and "best skill" logic lost to random choices for melee (fixed: reach-first targeting,
defensive cooldowns used in fights, no gap-closing into packs), and avoidance danced away
from chip damage (fixed: expected-damage judgement, attack windows, pack-edge positioning,
ranged keep-out by enemy reach, crowds blocking escapes, endless re-summoning of fragile
minions), and - the largest one - ground AoE circles were registered without the player's
5 px body radius (the game hits at `distance <= radius + player.radius`), so with Expert's
3 px margin every "safe" spot was 2 px inside the circle; this made Expert worse than
Competent for the ranger at Tier 4 (42% vs 80% of decided runs) and is fixed in
`sb_threat.gd`. Parameter values were never changed to hit a success rate. `NoDodge` uses exactly the `Competent` values except that it never
avoids telegraphs and never dodge-rolls (it still keeps class spacing, i.e. ranged classes
stand at range, which is positioning, not dodging).

| Parameter | NoDodge | Competent | Expert | Meaning |
|---|---|---|---|---|
| `reaction_ms` | 350 | 350 | 180 | delay from a telegraph appearing on screen to acting on it |
| `mistake_rate` | 0.20 | 0.20 | 0.05 | chance that a noticed telegraph is still not acted on |
| `awareness` | 0.75 | 0.75 | 0.95 | chance to notice a telegraph at all, rolled once when it enters the screen (projectiles use awareness^2) |
| `avoid_threats` | **false** | true | true | move out of / around telegraphs |
| `use_roll` | **false** | true | true | may use the dodge roll |
| `safety_margin` (px) | 6 | 6 | 3 | extra buffer around telegraph edges |
| `positioning` | 0.6 | 0.6 | 0.9 | ranged keep-away 70..120 px, melee uses 75..95% of reach, when to leave a pack |
| `target_quality` | 0.7 | 0.7 | 0.95 | chance to pick the best-priority target instead of the nearest |
| `skill_quality` | 0.75 | 0.75 | 0.95 | chance to use the best skill for the situation instead of a random usable one |
| `potion_discipline` | 0.7 | 0.7 | 0.95 | life flask below `0.30 + 0.20*d` of max life (Competent 44%, Expert 49%); d >= 0.9 also drinks to cleanse ignite / bleed below 70% |
| `decision_ms` | 120 | 120 | 60 | re-evaluation interval for targets / movement / flasks (+-20% jitter) |
| `lead_targets` | false | false | true | aim projectiles ahead of moving targets |

Perception is limited to the screen (330 x 190 px around the player at the game's zoom).

---------------------------------------------------------------------------------------------
## 4. What the bot does

**Dodge / movement** (`sb_threat.gd`, `sb_controller.gd`)
- Reads every visible telegraph each physics tick: enemy ground AoEs (`aoe.gd`: boss ring,
  eruption, mortar, burrow, vent, slams, bloater and elite death explosions), melee wind-up
  arcs (`state == "windup"`, `attack_dir`, `state_t / attack_speed_mult`), dash and boss
  charge lines (wind-up and in progress), boss cleave cones, projectiles in flight
  (position, velocity, radius, remaining range) and hazard warnings (spikes, vents, tempest
  lightning). Miasma pools and idle spike plates are soft areas to walk around.
- Simulates "where will I be at impact" for 17 walking directions (incl. standing) and 16
  dodge-roll directions (real `player.start_dodge()`: 85 px, 0.24 s invulnerable, 1.1 s
  cooldown), including the slow-down from an attack in progress, walls, and enemy bodies
  (the player collides with enemies, so a crowd blocks an escape), and picks the cheapest
  plan. Rolls only when walking is not enough.
- While stepping out it still attacks if the slower walk (casting slows movement) remains
  safe: it uses attack windows between telegraphs.
- Judgement shared by all avoiding profiles (`sb_controller.gd` constants): a telegraph's
  expected cost is computed from its damage packet after the player's armour /
  resistances / damage reduction. Hits worth < 5% of max life (`TANK_FRAC`) are taken
  instead of giving up attack time; the dodge roll is kept for hits >= 8% (`ROLL_FRAC`);
  if no escape saves at least 40% of a sub-15% hit it keeps fighting instead of dancing.
- Kiting per class: warriors close to melee reach and work to the edge of a pack when it is
  surrounding them; rangers and mages keep 70-210 px, keep LOS, and back off from melee
  enemies before they are within that enemy's own reach (attack range + slam radius) - but not
  from enemies at least as fast as themselves (it cannot out-run them, so it fights).
- Targeting: melee prefers what is in reach (distance dominates), finishes wounded enemies in
  reach and only goes for back-liners when nothing is on it; ranged prefers casters,
  summoners and wounded enemies; ward adds before a warded boss; only enemies in line of
  sight (or already chasing) are considered.

**Skills** - hotbar from the class's unlocked skills by role (best single-target, best AoE,
offensive buff, defensive buff, mobility/turret/summon, curse/zone, then best damage),
damage ranked with the game's own `preview_skill_avg` and use time. In combat: buffs before
engaging bosses / elites / packs, defensive buffs in real fights (2+ enemies, elites,
bosses or below 60% life; heals below 40%), war cry when 2+
enemies are near, summons valued like damage (minion hit x attack rate x ~6 s expected
lifetime per cast second, x1.5 when no minion is up; topped up freely out of combat),
turrets kept up, traps on the target, curses on bosses / packs,
gap closers for melee beyond 110 px, damage skills by `average hit x targets hit / use time` with a
cooldown bonus. Runes are socketed by a role table (split/pierce/chain/haste/echo on the
main damage skills, horde on summons, efficiency on expensive skills, recharge on cooldowns).

**Gear** - score = `w_off*log(dps) + w_def*log(ehp) + small move-speed term`, where dps uses
the game's `preview_skill_avg` of the two main hotbar skills and `ehp` uses `preview_final`
(life, armour vs a level-scaled hit, evasion, block, fire/cold/lightning/void resistances,
damage reduction, regen / leech) -> class- and build-aware. Empty sockets and item level
are tie-breakers. After each run (and mid-run for >=3% upgrades picked up when no enemy is
near) it equips the best item per slot (rings both ways, 2H vs off-hand, bow + quiver),
sells commons / salvages rare+ (and uncommons while short of scrap / iron), keeps up to 6
rare+ items it cannot wear yet, buys vendor items that are a >=2% upgrade for <=60% of its
gold, and crafts with a budget of 50% of its gold: Add Socket (only when gems are waiting),
Upgrade Base, Raise Rarity, Add Affix, Reroll the weakest affix of rare/epic gear.

**Gems** - combines 3 -> next grade when the next grade is usable, buys random gems when
there are empty sockets and gold >= 3x the price, sockets the best gem per socket by score
(weapon / armour / jewellery stats differ), unsockets for an upgrade if it pays off. Gems in
sold or salvaged items come back to the pouch (game rule).

**Passive tree** - one point at a time on level-up (also mid-run) and in town. Build
variants (`sb_planner.gd`):

| Class | balanced | glass | defensive |
|---|---|---|---|
| warrior | no keystone | Overwhelming Momentum @8, Glass Cannon @16 | Fortress of Flesh @8, Prismatic Soul @24 |
| ranger | no keystone | Perfect Aim @8, Glass Cannon @16 | Prismatic Soul @12, Mind over Matter @26 |
| mage | no keystone | Elemental Convergence @8, Glass Cannon @16 | Mind over Matter @10, Prismatic Soul @20 |

From the listed level on, points walk the game's shortest route (`CharacterData.path_to`,
the tree UI's click-to-route logic) to the keystone (saving a point for the 2-point
keystone). Otherwise the point goes to the frontier node with the best power-score gain per
point (one-node look-ahead). Build weights (offence, defence): balanced 1.0/1.0, glass
1.25/0.8, defensive 0.8/1.3 - they also steer gear and gems.

**Specialisation** (level 12+, nodes 1-4 then a capstone): warrior balanced Weapon Master
(Executioner), glass Berserker (Reckless Abandon), defensive Juggernaut (Unstoppable);
ranger balanced Deadeye (Split Shot), glass Deadeye (Far Shot), defensive Wraith Hunter
(Predator); mage balanced/glass = element of the main skill (Pyromancer / Cryomancer /
Stormcaller, `_6` capstone), defensive Cryomancer (Ice Armour).

**Survival and objectives** - flasks by profile; mana flask below 15% in combat; retreat
for 5 s when below 30% life with no life flask (re-engage at 60%). Objectives that unseal
the boss arena: guardian (kill), mechanisms and the Blood Altar (walk up and `on_interact`,
the same call `level.interact` makes), relics (walk over), waves (kill). Picks up items
(F-key equivalent `level.pickup`) and walks over gold / gems / runes / materials when no
aggressive enemy is in sight; after the boss it loots for up to 15 s and leaves through the
exit portal.

**Stuck handling** - BFS path to the goal (recomputed when stale), sidestep after 2.5 s
without progress, unreachable targets ignored for 8 s, targets that do not lose life for
4 s are approached, after 10 s switched.

---------------------------------------------------------------------------------------------
## 5. Seeds, determinism and resuming

- `--seed=S` determines everything. Character chain `c` kit seed = `hash([S, c, "kit"])`;
  run `r` seed = `hash([S, c, r])` (written as `run_seed`); the town visit after run r uses
  `hash([S, c, r, "town"])`. Each seeds the global RNG (`seed()`: enemy AI, boss pattern
  choice, hazards, run modifiers, shuffles), `Loot.set_seed()`, `Combat.rng.seed` and the
  bot's own RNG, and the run seed is passed to `main.enter_dungeon(id, seed)` (layout,
  packs, elites).
- Every run is played in a **fresh child process** (`--unit=c:r`). Godot's physics
  broad-phase keeps history across levels in one process, which made results depend on
  what ran before; one process per run removes that. Consequences: a batch can be split,
  run in parallel, interrupted and resumed and still produce the same rows.
- Carry mode: run r+1 starts from the JSON checkpoint written after run r. Uninterrupted
  chains go through the same JSON round trip, so resumed == uninterrupted.
- Resuming: run ids are unique (`<class>-<build>-<profile>-T<tier>-L<level>-s<seed>-<mode>-<flags>-ts<ts>-c<chain>-r<run>`).
  On start the coordinator skips ids already in the CSV and merges `_rows/*.json` left by a
  crash. Never two coordinators on the same CSV at the same time.
- **Scope of "same seed => same result": same machine, OS and Godot build.** The Windows PC
  and a Linux build of the same Godot 4.0.stable generate identical entry kits but runs
  diverge after a few seconds (floating-point / physics differences). Do not mix machines
  inside one comparison.
- Evidence (Phase 3): on the PC, `--class=warrior --tier=1 --runs=10 --seed=7` twice ->
  10/10 rows byte-identical; `--class=mage --tier=2 --runs=5 --mode=carry --carry=2 --seed=7`
  twice -> 10/10 identical; on Linux: a chain run alone (`--only=2`) == the same chain
  inside a batch, and a carry chain resumed after deleting its last row == uninterrupted.
  The only non-deterministic number (wall time) lives in `_perf.csv`.

---------------------------------------------------------------------------------------------
## 6. Headless fast mode and time scale

The bot always runs headless with `--fixed-fps <tps>`: no rendering, no real-time waiting,
as fast as the CPU allows. On the 16-thread PC one Tier 1 run takes ~10 s wall
(~80 s game), Tier 2 ~40 s, Tier 3 1-3 min; `--jobs=14` runs 14 at once.

`--ts` multiplies the physics step (`dt = ts/60`). Drift check (PC, 20 runs per cell,
seed 300, Competent):

| Setting | warrior T1 win% / clear s / dmg | ranger T2 win% / clear s / dmg / avoided% | wall s per run (ranger T2) |
|---|---|---|---|
| ts=1 | 100 / 76 / 317 | 65 / 184 / 809 / 93% | 40 |
| ts=2 | 100 / 81 / 320 | 75 / 209 / 945 / 88% | 27 |
| ts=4 | 100 / 87 / 358 | 55 / 252 / 998 / 73% | 19 |

ts=2 is within noise for win rate but slightly worse dodging (+5-15% damage taken) for a
1.5x speed-up; ts=4 clearly degrades dodging (projectiles move 27 px per step) and slows
clears. **Use ts=1 for the study**; ts=2 only for quick screening. The ts value is part of
the run id and the CSV.

---------------------------------------------------------------------------------------------
## 7. Ablation toggles

| Toggle | Effect |
|---|---|
| `--no-dodge` | avoidance layer off (same as the NoDodge profile's dodge settings) |
| `--no-gems` | never combines, buys or sockets gems (kit gems stay in the pouch) |
| `--no-passives` | allocates no passive points (kit and level-ups) |
| `--no-crafting` | no blacksmith crafts, sells instead of salvaging |
| `--build=` | `balanced` / `glass` / `defensive` |
| `--profile=` | `NoDodge` / `Competent` / `Expert` |

Toggles are part of the run id and the `flags` column, so ablation runs never collide with
baseline runs in one CSV and use identical seeds.

---------------------------------------------------------------------------------------------
## 8. CSV schema (one row per run)

| Column | Meaning |
|---|---|
| `run_id` | unique id (section 5) |
| `version` | bot version |
| `class`, `build`, `profile`, `tier`, `dungeon`, `mode` | configuration |
| `chain`, `run` | character index and run index within the character |
| `seed`, `run_seed` | master seed and the derived run seed |
| `start_level`, `end_level` | character level at run start / end |
| `outcome` | `boss_killed`, `died`, `timeout` |
| `cause_of_death` | the attack that dealt the killing blow: `<enemy>:<attack>` (`melee`, `dash`, `aoe`, `projectile`, `charge`; bosses use the pattern name, e.g. `The Gravemaw:quake`), `(elite)` marks elites, `hazard:<kind>`, `death_explosion`, `dead_enemy:projectile` (shooter died), `<enemy>:contact` (hit not matched to a visible telegraph), `status:<ignite/bleed/poison/agony>` (DoT death) |
| `time_to_boss` | game seconds until the boss spawned (-1 never) |
| `clear_time` | game seconds until the boss died (or run end) |
| `boss_hp_pct` | boss life % at the end (0 killed, -1 never reached) |
| `damage_taken`, `hits_taken` | total damage and number of damaging hits |
| `dodge_attempts` | telegraphs the bot moved / rolled away from (counted once per telegraph) |
| `dodge_rolls` | dodge rolls used |
| `hits_avoided`, `evade_failed` | dodge attempts that were not / were still hit |
| `threats_seen`, `threats_perceived` | telegraphs that entered the screen / were noticed |
| `potions_used`, `mana_potions_used` | flask uses |
| `kills`, `deaths_total` | kills this run, character deaths including this run |
| `gear_power` | `round(sqrt(dps_est * ehp_est))` after the run |
| `dps_est`, `ehp_est`, `max_life` | power score components (section 4) |
| `keystones` | allocated keystone ids (`|` separated) |
| `passives` | number of allocated passive nodes |
| `spec` | specialisation id and node count |
| `gems` | socketed gems in equipment (`type:grade`, grade 0 = Chipped) |
| `hotbar` | skills on the hotbar at run end |
| `runes` | `rune>skill` pairs |
| `skill_uses` | `skill:count` successful uses this run |
| `run_mods` | dungeon run modifiers |
| `monster_level` | dungeon monster level |
| `top_damage` | the three largest damage sources this run (`label=damage`) |
| `pickups`, `midrun_equips` | items picked up / equipped during the run |
| `flags` | ablation flags (`none` or `no-gems|...`) |
| `ts`, `tps` | time scale and physics ticks |
| `notes` | for timeouts: unfinished objectives (`open:waves(1/1)`), `arena_sealed`, `waves_active:N_alive`; `unreachable_targets:N` |

---------------------------------------------------------------------------------------------
## 9. Game rules the bot applies (found in code)

- **Death** (`death_panel._return`): lose 10% of the XP needed for the current level (never
  below 0, no de-level), `progress.deaths += 1`, back to town with full flasks; gear, gold,
  materials and gems are kept; the run, unpicked loot and its modifiers are lost.
- **Win** (exit portal = `main.go_hub(true)`): `progress.runs += 1`, vendor restocked, first
  boss kill of a dungeon gives +1 passive point, `highest_tier` = tier + 1.
- **Timeout**: the bot takes the town portal (`main.go_hub(false)`), no death penalty.
- Monster level = clamp(max(character level, dungeon min), min, max).

## 10. UI-only systems: what is called instead

| UI | Called directly (same calls the panel makes; confirmation dialogs skipped) |
|---|---|
| Death screen button | `ui.panels["death"]._return()` |
| Inventory sell / salvage | `inventory_panel.sell()` / `salvage()` logic: `reclaim_gems`, `Loot.sell_value`, `Loot.salvage_yield`, vendor buy-back list |
| Merchant buy / restock | `vendor_panel._on_click` logic (`Loot.buy_value`, `Game.vendor_stock`); `Game.refresh_vendor()` when empty (what `on_open` does) |
| Blacksmith | `Loot.craft_check` -> `ch.pay(Loot.craft_cost)` -> `Loot.craft_apply` -> `ch.recalc()` |
| Jeweller | `ch.socket_gem`, `ch.unsocket_gem`, `ch.combine_gems`, buy = `jeweller_panel._buy_gem` logic (`30 + 10*level` gold, `Loot.random_gem`) |
| Skills panel | `ch.loadout[i] = id` + `Events.loadout_changed` (only when `skills_panel.can_change()` would allow it: no aggressive enemy within 320 px), `ch.socket_rune` |
| Passive tree | `ch.path_to` + `ch.allocate` (one node per point) |
| Specialisation panel | `ch.choose_spec`, `ch.alloc_spec` |
| Dungeon gate | `main.enter_dungeon(id, run_seed)`; tier unlock is satisfied by the kit (`highest_tier`) |
| Player input | analog `Input.action_press("move_*", strength)`, `player.start_dodge()`, `player.try_use_slot(i)` with `auto_aim_override`, `player.use_flask(i)`, `level.on_interact(it)`, `level.pickup(n)` |

Not used: stash, gate modifier reroll, merchant "buy random rune", training dummy.

---------------------------------------------------------------------------------------------
## 11. Validation summary (Phase 3)

All numbers are from the Windows PC, `--fixed-fps 60`, ts=1, balanced build, seed 700, fresh
mode, default entry kit (T3 at `--level=15`, other tiers at `min_level + 3`).

- **Determinism**: section 5. Re-checked on the PC after the last bot change (AoE body-radius
  fix): `--class=ranger --tier=2 --runs=10 --seed=7 --profile=Expert` twice -> 10/10 rows identical;
  `--class=mage --tier=2 --runs=5 --mode=carry --carry=2 --seed=7` twice -> 10/10 identical.
- **Drift / time scale**: section 6.
- **Regression**: `tests/test_runner.tscn` on the PC (realtime, the documented way) ->
  1404/0, 1404/0, 1402/0, 1405/0 (passed/failed) over four runs. The total varies because a
  few checks depend on random rolls (e.g. which charm affixes get sampled). The criterion
  is 0 failed. Under `--fixed-fps`, one PC run showed a single pre-existing flaky failure
  (`mage: army_of_the_damned summons minions`), and the final realtime run after the last
  bot change gave 1403/1 (`mage: summon_skeleton_archers summons minions`). Both are the same
  timing-dependent check (`test_runner.gd` line 455 counts minions about 165 frames after the
  cast, and nearby enemies can already have killed them). The test runner never loads smartbot code,
  and smartbot changes no game file. `tests/bot.tscn` (old probe) still runs and reports
  as before.
- **Profile ordering**: section 12. Combined file: `out/validation_v2.csv`. The data is in `out/val2.csv` (Competent and Expert,
  after the AoE body-radius fix) plus the NoDodge rows of `final3/4/5.csv`, `final_t4.csv`
  and `final_t5.csv`, and ranger T4 from `fix_t4r.csv` (seed 700). NoDodge never evaluates
  telegraphs, so the fix does not change its outcomes. Only some `cause_of_death` labels
  differ, because hits at a circle's edge are now attributed to the AoE instead of `contact`.
- Summarise any CSV with `python tests/smartbot/summarize.py out/x.csv [--by=tier,class,profile,seed]`
  (stdlib only; Wilson 95% intervals).

## 12. Profile ordering

| Tier (level) | class | n | win % NoDodge / Competent / Expert (95% CI) | died % | timeouts | mean damage taken |
|---|---|---|---|---|---|---|
| T1 (L4) | warrior | 10 | 100 (72-100) / 100 (72-100) / 100 (72-100) | 0 / 0 / 0 | 0 / 0 / 0 | 415 / 371 / 274 |
| T1 (L4) | ranger | 10 | 100 (72-100) / 100 (72-100) / 100 (72-100) | 0 / 0 / 0 | 0 / 0 / 0 | 162 / 65 / 31 |
| T1 (L4) | mage | 10 | 100 (72-100) / 100 (72-100) / 100 (72-100) | 0 / 0 / 0 | 0 / 0 / 0 | 24 / 9 / 2 |
| T2 (L11) | warrior | 40 | 68 (52-80) / 85 (71-93) / 95 (83-99) | 32 / 15 / 2 | 0 / 0 / 1 | 2639 / 1981 / 1520 |
| T2 (L11) | ranger | 40 | 45 (31-60) / 92 (80-97) / 98 (87-100) | 55 / 8 / 2 | 0 / 0 / 0 | 981 / 790 / 321 |
| T2 (L11) | mage | 40 | 85 (71-93) / 100 (91-100) / 100 (91-100) | 15 / 0 / 0 | 0 / 0 / 0 | 534 / 277 / 92 |
| T3 (L15) | warrior | 40 | 85 (71-93) / 82 (68-91) / 92 (80-97) | 12 / 18 / 8 | 1 / 0 / 0 | 3596 / 3216 / 2701 |
| T3 (L15) | ranger | 40 | 80 (65-90) / 75 (60-86) / 92 (80-97) | 20 / 25 / 8 | 0 / 0 / 0 | 1069 / 750 / 423 |
| T3 (L15) | mage | 40 | 88 (74-95) / 98 (87-100) / 100 (91-100) | 10 / 2 / 0 | 1 / 0 / 0 | 1649 / 626 / 306 |
| T4 (L25) | warrior | 40 | 28 (16-43) / 48 (33-63) / 42 (29-58) | 28 / 2 / 2 | 18 / 20 / 22 | 9862 / 8659 / 5666 |
| T4 (L25) | ranger | 40 | 18 (9-32) / 42 (29-58) / 42 (29-58) | 50 / 10 / 18 | 13 / 19 / 16 | 3220 / 2111 / 1400 |
| T4 (L25) | mage | 40 | 12 (5-26) / 35 (22-50) / 55 (40-69) | 42 / 20 / 2 | 18 / 18 / 17 | 2788 / 2033 / 1172 |
| T5 (L33) | warrior | 30 | 83 (66-93) / 97 (83-99) / 100 (89-100) | 17 / 3 / 0 | 0 / 0 / 0 | 10763 / 8085 / 5446 |
| T5 (L33) | ranger | 30 | 87 (70-95) / 97 (83-99) / 80 (63-90) | 10 / 0 / 7 | 1 / 1 / 4 | 2203 / 1073 / 830 |
| T5 (L33) | mage | 30 | 17 (7-34) / 100 (89-100) / 90 (74-97) | 83 / 0 / 3 | 0 / 0 / 2 | 4123 / 2563 / 1253 |

Pooled over T2-T5 (150 runs per class and profile):

| class | NoDodge win / died % | Competent win / died % | Expert win / died % |
|---|---|---|---|
| warrior | 64.7 / 22.7 | 76.7 / 10.0 | 81.3 / 3.3 |
| ranger | 55.3 / 35.3 | 75.3 / 11.3 | 78.0 / 8.7 |
| mage | 52.7 / 34.7 | 82.0 / 6.0 | 86.0 / 1.3 |

Reading the table:
- **Damage taken is strictly ordered NoDodge > Competent > Expert in all 15 cells.** Win rate
  and death rate are ordered in every pooled class. Single-cell inversions are all inside
  overlapping 95% intervals:
  - T3 warrior/ranger: Competent 82/75 vs NoDodge 85/80.
  - T4 warrior: Expert 42 vs Competent 48. Both died 2%; the gap is timeouts.
  - T5 ranger and mage: Expert 80/90 vs Competent 97/100. Most of the gap is timeouts.
- **Tier 1 is a ceiling** (100% for everyone). Profiles separate only by damage taken there.
- **Tier 4 timeouts are a game softlock, not the bot** (about 44% of all T4 runs, the same
  for every profile). In the Blood Altar waves, enemies spawn outside the map grid (seen at
  cell (93,-2)) or in a disconnected floor pocket, so the waves objective never completes
  and the boss arena stays sealed. The `notes` column says `waves_active:N_alive|arena_sealed`.
  For T4, compare deaths, or wins among decided runs. Ranger T4 over seeds 700+800
  (80 runs each): Competent 33 wins / 10 deaths, Expert 34 wins / 10 deaths.
- T5 timeouts without `arena_sealed` (`open:boss(0/1)`) or with an unfinished guardian or
  mechanisms objective are navigation or objective failures. A few repeat on the same seed
  for several profiles (chain 12: mechanisms 2/3; chain 23: boss never reached), so they
  are probably map-specific. Check them with `--only=N --trace=1 --debug` before the study
  relies on T5 timeout counts.
- Tier 4 is harder than Tier 5 at the default entry levels for every class.

## 13. Known limitations / where the bot differs from a human

Weaker than a human:
- No route planning across the whole map: it fights what it sees and walks towards
  objectives / the boss room; it does not deliberately pull single enemies or reset fights.
- Pack fighting for melee is simple (edge-of-pack heuristic); humans use doorways and kite
  packs into lines.
- Damage attribution is inferred from telegraph geometry and timing; hits that match no
  visible telegraph are logged as `<enemy>:contact`.
- Skill choice uses expected value per cast; it does not plan combos (e.g. curse -> burst),
  and summon / turret builds are under-valued by the gear score (dps uses direct hits).
- Crafting is greedy (one pass per town visit), no long-term item projects; never uses the
  stash or rerolls run modifiers at the gate.

Stronger than a human:
- Perfect knowledge of telegraph geometry and timing once a telegraph is noticed (only
  awareness, mistakes, reaction time and margin limit it); evaluates 33 escape options per
  tick. Expert in particular is close to frame-perfect.
- Never tilts, never gets bored, plays every run at the same quality.
- Exact gear comparisons using the game's own stat previews.

Game observations made while building (not changed):
- **T4 Blood Altar softlock (about 44% of T4 runs)**: wave enemies spawn outside the map grid
  (cell y = -2) or in a disconnected floor pocket (`random_floor_near` picks cells across
  thin walls). The waves objective cannot finish and the boss arena stays sealed. Such runs
  end as `timeout` with `notes=...waves_active:N_alive|arena_sealed`. `--debug` prints the
  unreachable enemy cells.
- Tier 1 is not difficult enough to separate profiles by success rate (100% for all at the
  default level and at level 1); damage taken still orders them.

---------------------------------------------------------------------------------------------
## 14. Notes for the next session (running the study)

- Use ts=1, `--fixed-fps 60`, and one machine per comparison. Smoke-test 1-2 runs after any
  code change, before a long batch (the launcher pre-flight only catches boot errors).
- Typical PC throughput with `--jobs=15`: T2 40 runs about 2.5 min, T3 about 3.5 min,
  T4 about 7 min (timeouts run the full 900 game-seconds), T5 30 runs about 4-8 min.
- When the PC is reachable only through file staging plus the Godot MCP: write `jobs.txt`,
  start `launcher.tscn` with `run_project`, and poll `out/launcher_status.txt` for `ALL DONE`.
  Do not replace bot scripts while a batch runs (each child loads the scripts when it
  starts). When pushing files with `device_commit_files`, use a new staged path for every
  push and check the sizes afterwards, because a reused path can resend a cached older file.
- T4 timeouts come from a game softlock (section 12). Either report wins among decided
  runs, or wait for a game fix. Do not let the bot work around it.
- The profiles are fixed behaviour definitions. Do not retune them to hit success rates.
  If a better parameter value produces worse results, look for a bot decision bug
  (section 3 lists the ones already fixed).
