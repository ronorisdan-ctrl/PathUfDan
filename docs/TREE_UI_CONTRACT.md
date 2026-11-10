# Passive tree UI contract (function vs Codex V5 art)

Phase 5a of the passive tree plan. The game code owns **what state a node is in**; Codex V5
owns **how each state looks**. Placeholder visuals today are circles/octagons/hexagons drawn
in `scripts/ui/passive_tree_view.gd`. When V5 lands, it replaces the drawing in `_draw()` /
`_draw_minimap()` and keeps every function below unchanged.

## Rules
- V5 never changes node ids, positions (`x`, `y`) or links. Those belong to
  `tools/gen_clusters.py` and its sources in `data/tree_src/`.
- V5 may fill the optional `art_id` key on nodes (validator already allows it). Default art by
  node type: `start`, `minor`, `greater`, `notable`, `keystone`, `mastery`, `socket`.
- Cluster background ids: the node `cluster` name (e.g. `Weapon Master`, `Warrior-Ranger Road`).
  `PassiveTreeView.cluster_centres()` gives each cluster's centre.
- Do not start custom line styling or node rendering in game code before V5; add states here.

## Base state: `node_state(id) -> NodeState` (exactly one)
| Value | Name (`STATE_NAMES`) | Meaning | Placeholder look |
|---|---|---|---|
| 0 | `locked` | Not connected to the web (or another class start) | grey ring |
| 1 | `available` | Connected, enough points, not excluded | pulsing green ring |
| 2 | `unavailable` | Connected but not enough points, or exclusive with an allocated node | red ring |
| 3 | `allocated` | In `ch.allocated` | gold fill + ring |
| 4 | `planned` | Ghost node in the planner (Phase 5b; `Game.ch.plan`, plus `view.planned` for tools) | blue ring |
| 5 | `migrated_refunded` | Was allocated before a tree-version refund (`ch.tree_refund.ids`) | light-blue ring |

Priority when several apply: allocated > planned > migrated_refunded > (start = locked) > available/unavailable > locked.

## Overlays: `node_overlays(id) -> Array` (any number)
| Overlay | Meaning | Placeholder look |
|---|---|---|
| `search_hit` | Name/desc/cluster/mod text matches the search box | pulsing yellow ring |
| `filtered_out` | A tag chip or "Behaviour only" is on and the node does not match | dark disc over the node |
| `boosted` | Allocated and inside a socketed gem's ring with a shared tag | purple outline |
| `route` | On the cheapest route to the hovered node | blue outline + blue line |
| `hover` | Under the mouse | white outline |
| `lod_hidden` | Not drawn at the current zoom level | not drawn, not clickable |

## Zoom levels of detail: `lod() -> 0/1/2`
- `0` far (`zoom < LOD_FAR` = 0.35): cluster labels (large), class starts, keystones,
  allocated nodes, search hits. Links drawn thin.
- `1` mid (`zoom < LOD_NEAR` = 0.7): + greater, notable, mastery, socket. Minors are small dots.
- `2` near: every node, with greater/keystone/mastery labels.

## Filters
- `FILTER_CHIPS` (12 chips) + a "More tags..." list of every other used tag. Several tags match
  any of them (OR). `behaviour_only` keeps `TreeRules.is_behaviour_node` (keystones, masteries,
  sockets, flagged nodes) and combines with the tags (AND).

## Minimap
- `minimap_rect()` top-right, 190x140; `world_to_mini` / `mini_to_world`; white rectangle =
  `view_world_rect()`. Click to centre the view there.

## Planner (Phase 5b)
- `view.planner` on: LMB plans a node and its route (`ch.plan_add`), RMB removes it and any
  planned node it cut off (`ch.plan_remove`). Hover route = `view.hover_route(id)` (`ch.plan_route`).
- Planned links (both ends allocated/planned, one planned) drawn in `PLAN_COL`; planned nodes
  show at every zoom level and as blue dots on the minimap. V5 may restyle these.
- `ch.apply_plan()` allocates planned nodes nearest-first as far as points allow.

## Presets and build codes (Phase 5b, no art needed)
- 3 presets per character (`ch.presets`, `ch.active_preset`); the live tree is the active preset.
- Build code: `POD1-` + URL-safe base64 (no padding) of 3-byte length + DEFLATE(JSON
  `{v, c, t, n, m, g}`). `TreeRules.encode_build` / `decode_build` / `sanitize_plan`.
