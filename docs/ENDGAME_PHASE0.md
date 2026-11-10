# Endgame Phase 0: zone technical spike (2026-11-05, Claude)

Plan: "Path of Dan Endgame Design: The Atlas of Ruin, Rot, Zone Mechanics and Pinnacle", section G, Phase 0.
Goal: show that large "chamber-stitched" zones work in Godot 4.0 with the existing combat, pathing and smartbot
before any Atlas, Rot or mechanic work starts.

## Decisions (Dan, 2026-11-05)
- Section H defaults accepted, **but smaller zones**: 5-7 chambers of 30-40 cells (3-5 minute clear).
- Spike biome: **Overgrown Ruin**, cellular-automata caves plus BSP ruined halls, `warren` palette.
- Access: **dev-only** (Dev panel > Dungeon > Start run > "Zone spike: ...") plus the smartbot `--dungeon=` flag.
  Normal players never see it. The spike grants no first-kill passive point and no tier unlock.
- Perf target: 60 fps windowed with 150+ enemies placed, flow-field build under 2 ms.

## What was built
| File | What |
|---|---|
| `data/zones.json` | Zone defs. A zone def is a dungeon def plus `"generator": "zone"`, a `gen` block, `objective_pool`, `hazards_per_room`, `wake_chambers`, `wake_radius`, `flow_reach`, `tile_chunk`. |
| `scripts/world/zone_gen.gd` | Generator. Macro grid 4x3 of 48-cell cells; chamber tree (biased right, +1 loop link); start clearing, 5-7 CA/BSP chambers, authored boss arena (`rooms.json` "arena") at the deepest leaf; 4-6 wide drunkard's-walk connectors clamped to the two linked macro cells; flood fill removes unreachable pockets; 3+ cells of rock to every macro edge. Output = dungeon layout format + `cell_chamber`, `adjacency`, `edges`. |
| `scripts/world/dungeon.gd` | Runs zones unchanged (`is_zone`). Picks objectives from `objective_pool`; `update_sleep()` every 0.25 s; `chamber_at`, `chamber_dist`, `separation_pool`. Spike flag skips first-kill point and tier unlock. |
| `scripts/world/level.gd` | Integer-index flow BFS (same distances as before, ~2x faster). Zones: BFS walks a per-chamber walkable map (player chamber + linked chambers), patched by `set_cell` (arena seal). `flow_reach`, `flow_us`. Optional chunked tile drawing (`tile_chunk`). |
| `scripts/world/tile_drawer.gd` | `area`/`rvals`/`chunked`: chunk drawers with the same variant rolls as the whole-grid draw. Dungeons and hub still draw the old way. |
| `scripts/entities/enemy.gd` | Pack separation iterates `level.separation_pool()` (dungeons: all enemies as before; zones: awake enemies). |
| `scripts/main.gd`, `scripts/core/dev_tools.gd`, `scripts/core/data.gd`, `scripts/ui/dev_panel.gd` | `Data.zones`; `enter_dungeon`/`Dev.start_run` fall back to zones; dev panel lists the zone. |
| `tests/test_zone.gd` + `zone_only.tscn` | 48 checks (200 seeds): connectivity, border, chamber map, counts/sizes, spawns, boss arena is a leaf and its seal never cuts another chamber off, unlinked chambers 6+ cells apart, determinism, live level (local flow, sleeping/waking, seal patching, boss, no progression). `--png` writes layouts to `tests/zone_out/`. |
| `tests/zone_bench.gd` + `zone_bench.tscn` | Windowed perf bench (see below). |

### Sleeping packs
An enemy sleeps (`process_mode = DISABLED`: no AI, no drawing, body removed from physics) when its chamber is more than
`wake_chambers` (1) links from the player's chamber; aggro'd enemies get one extra link; bosses never sleep.
Unlinked neighbour chambers sleep too (the generator keeps 6+ cells of rock between them, more than the 70-unit
no-line-of-sight alert range). `wake_radius` (default 0) can force-wake anything within N units.

## Results (Godot 4.0, Windows, RTX 4070 Ti SUPER, vsync off)
Generator: 200/200 seeds first try, 57-60 ms per zone (max 87 ms), 194x146 cells, floor 4.4k-7.4k cells.

Bench, invulnerable scripted fast clear through every chamber, windowed, 2 repetitions:

| Mode | Enemies placed | fps avg | p95 ms | p99 ms | frames > 16.7 ms | flow build avg / max |
|---|---|---|---|---|---|---|
| zone (shipping), Rot-5-like packs 7-9 | 176-183 | 156-174 | 8.2-8.7 | 9.4-10.3 | 0.1% | 1.43 / 2.2-2.5 ms |
| zone, stress packs 12-14 | 315 | 112-116 | 13.1-13.6 | 15.8-16.6 | 0.8-0.9% | 1.40 / 2.4 ms |
| no sleep, whole-grid flow, packs 12-14 | 315 | 99-100 | 15.2-15.3 | 17.7-18.7 | 2.4-2.7% | 1.5 / 2.1-2.4 ms |
| T3 dungeon (Abyssal Warrens) | 63 | 167 | 7.0 | 7.8-8.0 | 0% | 0.55 / 0.7-1.0 ms |

Raw lines: `tests/zone_bench_results.txt`, older runs in `tests/zone_out/bench_*.txt`.
- **60 fps with 150+ enemies: met** with large margin (p99 about 10 ms at Rot-5-like density; still under 16.7 ms at 315 enemies).
- **Flow under 2 ms: average met (1.4 ms), peaks 2.2-2.5 ms missed.** It runs every 0.2 s only when the player
  changes cell. Options if it matters on weaker PCs: `flow_reach` 160 -> 120, or split the BFS over two frames.
- Sleeping is worth about 15% fps and 3x fewer slow frames at stress density; at normal density it is a small win
  (small zones: a central chamber links to most others).
- Rendering is not the bottleneck; awake chasers (physics + AI) are.

Smartbot, Competent, balanced, T3 kit (L18), seed 900, 10 runs per class (`tests/smartbot/out/zone_p0b_*.csv`):

| Class | Boss kills | Deaths | Timeouts | Clear time median (min-max) | Kills median (max) |
|---|---|---|---|---|---|
| Warrior | 10/10 | 0 | 0 | 230 s (84-396) | 263 (823) |
| Ranger | 10/10 | 0 | 0 | 226 s (158-316) | 152 (372) |
| Mage | 10/10 | 0 | 0 | 184 s (98-293) | 179 (310) |

For comparison the same warrior on the T3 dungeon: 9/10, clear median 140 s, 96 kills.
Median clears of 3-4 minutes sit inside the agreed 3-5 minute target.

## Findings
1. **Summoner add loops (warrior).** 4 of 10 warrior runs killed 670-820 enemies: Grave Callers (Plague Rats) and
   bat summoners keep re-summoning while a melee bot fights the adds. Existing behaviour (summon_max caps live adds,
   not total), made worse by bigger zones. The first layout (44-cell macro cells, 2-cell rock between unlinked
   chambers, wake radius 320) was worse: warrior median 415 s; fixed by the 6+ cell gap and no radius wake.
   **Suggest for Phase 1:** a lifetime summon cap per summoner in zones, or summoning only with line of sight. Not changed here (balance).
2. **Difficulty**: no deaths at T3 L18, consistent with the bot study (Competent wins 80-100%). Rot will need to add the challenge.
3. Chamber "rooms" are big; `_room_floor` random sampling and existing objectives worked unchanged (all five objective
   options appear across seeds).
4. Small zones mean a central chamber wakes most of the zone. Larger Atlas zones should use 1 wake link (current).

## Regression
- Dungeons still use `dungeon_gen.gd`; flow distances are identical (same BFS values, new loop), hazards use the same
  RNG calls, `objective_pool` only exists on zones. See the CODEX_HANDOFF entry for the full suite and smartbot
  baseline results.

## Open / next
- Flow peak above 2 ms (see above).
- Summoner loop (finding 1).
- Phase 1 MVP next: hex Atlas (radius 3), ring scaling, 2 more biomes, Rot v1, Heart bosses, Glazed Elites,
  The Unfinished, Pigment and Varnish slots, save v4 -> v5.
- Biome art: the spike reuses the `warren` tiles; chamber archetypes (8-12) are still to design.
