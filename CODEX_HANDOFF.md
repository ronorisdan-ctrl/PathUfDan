# Codex handoff

Last updated: 2026-11-05

## Current objective

**Phase 3C stations/utility chrome complete** (2026-11-05). User assigned 3C; executed that batch only. Phase 1/2 and 3A/3B remain complete. Checklist: `docs/UI_VISUAL_PHASE0.md`; evidence/reproduction: `docs/UI_SHARED_PHASE3.md`. Stop after 3C; next suggested batch is menus/options.

## Completed work

- LootFilter.evaluate now returns `filter_hidden` (hide decision after safety net, independent of Alt). Alt only affects `visible/drawn/clickable`.
- LootDrop stores `filter_hidden`; `filtered_now()` re-evaluates and returns it; `level.collect_block` refuses pets with "hidden" (covers F fetch, auto-loot, magnet). Pet "hoot" quirk uses it too. Player pickup and targeting unchanged (Alt-revealed items still pickable).
- Tests: engine `_t_hide_and_reveal` +5 checks; `test_loot_filter()` +10 checks (stub level/pet).

## Verification

- Current 3C verification: stations **1732 headless / 1774 rendered**, corruption/actions **125**, shared slots **455**, inventory **1460**, character chrome **3288**, tree chrome **2530**, HUD **86**, all passed, 0 failed. Forty-one actual captures/bounds across five output sizes plus sealed/away/locked/training-result/history states. Final logs have no script errors or exit leak warnings; earlier station/tree runs had the known intermittent exit warning, final isolated verbose runs passed without it. Prior 2C full integration **47,844/0** remains historical; no new full-gameplay total claimed.
- Historical loot/filter run: full headless suite 1929 passed, 0 failed (first run had one known-flaky summon check, passed on rerun). Later feature-specific results remain recorded below.

## Remaining work / next stage

- Phase 3C complete. Suggested next batch: menus/options (including the filter editor as appropriate). Custom tree drawing remains later; preserve current corruption transactions and TREE_UI_CONTRACT. No further batch executed under this assignment.
- F4 on an overflowing panel tooltip freezes both cards for wheel/PageUp/PageDown/Home/End reading; Tab selects the other card. Escape/F4 or an outside dismiss click closes the reader. Ordinary hover remains pointer-passive. Artwork/fonts, OS DPI and other hardware remain future verification.
- Stray copies `level-1.gd` / `dungeon-1.gd` in scripts/world are unused duplicates (not touched).

## Blockers

None.

## Completed UI stage — 2026-10-28

- Assigned: interactive Dying Canvas inventory slice with hover, comparison and selected states.
- Implemented a standalone preview scene and launcher. Forty bag cells, eleven equipment cells, pin/transient hover, keyboard focus/activation, signed comparison, both ring targets, local equip swaps, unavailable/material states, sort/filter/clear/reset work against JSON fixtures.
- Verification: Godot 4.0.stable.official.92bee43ad, headless and rendered interaction checks each **31 passed, 0 failed**. Five actual 1280×720 state screenshots inspected; renderer logs clean. Focused checks include live-character/combat-RNG isolation. Full gameplay suite not rerun for this isolated preview stage.
- Open `Preview inventory.cmd` or run `tests/ui_inventory_preview.tscn` with F6. Controls, limitations and verification commands are in `docs/UI_INVENTORY_PREVIEW.md`.
- Art status: local cabinet-frame skin complete for sample; existing procedural icons/background, installed serif headings and Godot body font are provisional. Illustrated paper doll, painted textures, custom icons and functional final HUD remain pending.
- Main scene, saves, runtime gameplay UI and existing pet/loot-filter work were not changed. No commit or branch switch made; working tree already contains unrelated pet/filter changes.
- Next: Dan reviews the interactive skin; refine the art treatment before integrating it into the live inventory. No further production stage assigned.

## Phase 0 UI overhaul — audit stage complete, 2026-10-29

- Current assignment supersedes the prior waiting state: audit, architecture proposal and one isolated component only. Production overhaul requires review.
- Audited runtime UI root, helpers, base panels, HUD, inventory/slots, menus/options, passive view, procedural art, project resolution and prior inventory study.
- Existing Godot 4.0 / 1280x720 / canvas_items / expand / nearest world rendering already permits a sharper UI on the persistent layer-10 CanvasLayer. No SubViewport needed for the proposed first integration.
- Theme alone cannot reskin hardcoded HUD/slot/passive drawing or local overrides. Preserve their controllers, signals, input and stat/data paths; migrate visuals incrementally.
- Existing Dying Canvas inventory study remains a separate prior review artifact. New Phase 0 sample will demonstrate a reusable native Theme and HUD resource meter, without replacing that study.
- Remaining in assigned Phase 0: save audit/proposal/checklist, build and verify isolated meter, record evidence. No production UI integration authorized.

## Phase 0 UI overhaul — prototype/review stage complete, 2026-10-29

- Review document: `docs/UI_VISUAL_PHASE0.md` contains the audit, proposed Theme system, resolution/SubViewport decision, asset directory/naming brief, preservation risks and small HUD-first/inventory-next checklist.
- Prototype: F6 `tests/ui_phase0_preview.tscn`. Native resource-meter component with local reusable `.tres` Theme, life/mana sample values, hover tooltip, keyboard focus, sample button and disabled state. Temporary flat materials and system/fallback fonts; rectangular bar is not a final HUD/orb decision.
- Verification: installed Godot 4.0; **25 headless checks passed**, **30 rendered checks passed**, 0 failures. Final rendered run repeated after local filtering setting. Checks cover finite/clamped/zero-max values, keyboard activation, shared life/mana presentation, tooltip text, layout/readout fit and Game character/world/combat-RNG isolation.
- Visually inspected all five actual captures (1280x720, 1920x1080, 2560x1440, 1920x1200, 2560x1080): centered composition, readable labels and focus, no clipping. Captures live in ignored `tests/screens_out_phase0/`.
- Godot sandbox startup crashed before logs; approved out-of-sandbox focused CLI runs succeeded. Godot 4.0 `--log-file` attempt stalled; use plain commands in the review document. The owned stalled run was interrupted. No runtime/gameplay files or project display settings changed; prior inventory preview and unrelated work preserved.
- Full gameplay suite, live HUD binding, painted art, DPI behaviour and optional SubViewport trial were outside this isolated stage. No new dependencies or generated UI asset set.
- **Next: user reviews architecture and prototype. Stop at this gate.** If approved, take only assigned checklist task (suggested 1A HUD resources); preserve existing stat/input/controllers and update this handoff per task.
- Blockers: none for Phase 0. Font packaging, artwork and final HUD silhouette remain review/future-stage decisions.

## Phase 1 HUD — stage 1 complete, 2026-10-29

- User assigned the full Phase 1 HUD overhaul, authorizing production integration and superseding the Phase 0 review gate. Phase 2 remains excluded.
- Audited live HUD, player costs/cooldowns/held inputs, progression, status dictionaries, UIRoot tooltips and skill reassignment. Keep existing canvas_items/expand resolution, world filtering, controllers and input. No SubViewport required.
- Added scoped HUD semantic tokens, replaceable native frame material/drawing helper, real InputMap key labels and responsive dock foundation. Existing preview/theme consumers retain their styling.
- Focused Godot 4.0 foundation checks: 8 passed, 0 failed. Sandbox engine startup exits without logs; elevated console invocation works. Corrected native Skin class naming collision before passing.
- Remaining: stages 2 resources, 3 actions, 4 XP/status, 5 polish, 6 integration/resolution verification. No gameplay values, saves or unrelated changes modified.

## Phase 1 HUD — stage 2 complete, 2026-10-29

- Reusable life/mana reliquaries use crimson/violet pigment, iron/bronze rims, exact current/max readouts, smooth interruptible fills, delayed damage and restrained low-life rim warning.
- Presentation-only API sanitizes nonfinite/zero maxima and clamps display values. Player changes snap animation to avoid cross-character/zone carryover. Final decorative textures can replace the native shell independently.
- Focused Godot 4.0 checks: 16 passed, 0 failed, including bounds, delayed damage, interrupted recovery and zero mana. Components remain in the dock pending action integration; original runtime HUD is still available for baseline capture.
- Remaining: stages 3–6 of the assigned Phase 1.

## Phase 1 HUD — stage 3 complete, 2026-10-29

- Integrated the centered combat dock into the production HUD. Skill, flask and dodge wells use native reusable materials; original player input, flask/dodge logic and Skills-panel reassignment remain owned by existing controllers.
- Real InputMap labels, resolved skill icons/tooltips, cooldown masks/timers, cost/weapon/town/death restrictions, held selection and charge pips are bound to current player data. Added a presentation signal on successful casts so zero-cooldown/repeated casts also animate accurately.
- Hover is passive and suppressed under panels/context/confirmation. HUD only dismisses tooltips it owns. Captured original live 1080p HUD before replacement in ignored tests/screens_out_hud.
- Focused Godot 4.0 checks: 38 passed, 0 failed, covering live resource binding, all seven skills/two flasks, reassignment and activation for warrior/ranger/mage, remapped labels, cooldown completion and disabled states.
- Remaining: stage 4 XP/status/remainder; stage 5 visual review/polish; stage 6 resolution/integration regression checks.

## Phase 1 HUD — stage 4 complete, 2026-10-29

- Added reusable gold XP/class-level display, driven by CharacterData xp/xp_to_next/MAX_LEVEL. Real level rollover produces a short restrained accent without changing progression.
- Existing buffs and player statuses now use framed timed badges (harmful states have crimson edges), actual remaining times and hover descriptions; permanent live buffs remain visible. Objectives, minimap, interaction prompts, boss/poise and developer indicators remain intact.
- Focused Godot 4.0 integration checks: 50 passed, 0 failed, including actual XP rollover/level feedback and timed status presentation/removal for all three classes.
- Remaining: visual polish/remainder styling and rendered resize/input/integration verification.

## Phase 1 HUD — stage 5 complete, 2026-10-29

- Completed native iron/bronze frame treatment across objectives, minimap and boss health; retained poise, map markers and progression prompts. Interaction/key hints now use real action labels. Expanded map fits above combat dock.
- Reviewed actual rendered screenshots; refined pigment gradients and rim/plinth details, removed misleading disabled slashes on empty slots, fixed charge-mark spacing, and added charge-use/dodge feedback. Combat click-through and existing controllers remain intact.
- Animations are bounded scalar interpolation/short accents, reset on player replacement, freeze with pause and do not allocate Tweens or consume random numbers. Developer infinite flask state remains represented correctly.
- Focused checks: 50 headless passed; preceding rendered pass 104 passed at six sizes. One final headless run reported an exit-only ObjectDB leak warning; investigate teardown during final validation rather than claiming clean runtime logs prematurely.
- Remaining assigned stage 6: strengthen hover/input/pause/death/cooldown/map checks, recapture final visuals, run existing gameplay regression suite and record limitations/evidence.

## Phase 1 HUD — stage 6 complete, 2026-10-29

- Completed production integration and visual inspection. Final HUD uses existing Player/CharacterData values for all three classes, keeps original activation/reassignment/charges/progression and preserves objectives, interactions, map markers, boss/poise and developer indicators. No Phase 2 work, save-format changes, world viewport changes or new dependencies.
- Final focused results on Godot 4.0: **86 headless checks passed, 0 failed; 161 rendered checks passed, 0 failed**. Includes real skill cooldown start/completion, mouse press/release through HUD, keyboard dodge, actual OS-pointer hover, remapped labels, Skills-panel assignment, tooltip ownership, pause/death, XP rollover, statuses and character/combat-RNG isolation.
- Six actual render dimensions asserted: 1280x720, 1920x1080, 2560x1440, 1920x1200, 2560x1080 and 1024x768. Resizing, pointer slot hit tests and tooltip bounds pass at every size. Expanded map remains above the dock. Native HUD update loop observed ~0.11–0.25ms here (CPU update only, not an overall combat/render benchmark).
- Inspected final normal, low-life/mana, full loadout/cooldown, status, tooltip, expanded-map and real boss screenshots. Before/after 1080p images plus resolution/state captures are in ignored tests/screens_out_hud. Original baseline captured from committed HUD; temporary legacy script removed. Documentation and reproducible commands: docs/UI_GAMEPLAY_HUD_PHASE1.md.
- Existing full gameplay acceptance suite: **2056 passed, 0 failed** (tests/screens_out_hud/gameplay_regression.log). Expected malformed-JSON/corrupt-save negative-test logs are present. The suite also reports canvas/RID/resource warnings at engine exit; its teardown is outside this HUD change and has not been rewritten. No HUD script/runtime error was observed.
- Investigated focused headless ObjectDB warning: verbose output identified only active AudioStreamWAV/PlaybackWAV instances. The HUD harness now stops/releases pooled playback and allows a short audio flush before exit; final focused headless and rendered outputs are clean. No production audio behavior changed.
- Godot 4.0 input simulation needs push_input plus push_unhandled_input when not handled; real pointer queries require a rendered window. Resize checks keep the OS pointer over each target while layout settles, avoiding pointer-motion races. Stalled parser-error test processes were cleaned up; user's existing editor retained.
- Materials and current skill icons are native/procedural placeholders by design; system/fallback typography remains replaceable. OS DPI changes, other renderers and low-end hardware are not certified. Existing uncommitted Phase 0 assets/docs and unrelated prior work were preserved; no commit or branch switch made.
- **Phase 1 complete. Stop here; await a new assignment.**

## Visual overhaul Phase V0 (art pipeline), added by Claude, 2026-10-29

- Done outside Codex, delivered as uncommitted files (Dan's choice). Brief: `codex_master_prompt_v2.md`, with Art Bible v2 overriding it on sizes (64x64 canvas, feet y=58, enemies 4 directions, 10 fps, palette `dying_canvas.hex`).
- New: `data/render.json`, `data/art/sprites.json`, `scripts/gfx/sprite_anim.gd`, `scripts/gfx/anim_rules.gd`, `assets/palette/`, `assets/placeholders/`, `tools/art_*.py` and friends, `tests/test_art.gd`, `tests/art_only.tscn`, `tests/art_gallery.tscn`, `tests/screens_art.tscn`, `docs/ART_STYLE_GUIDE.md`, `docs/ART_ASSET_LIST.md`, `docs/adr/0001-art-scale.md`.
- Small edits: `actor.gd` (setup_sprite takes manifest ids, `anim`, `visual_height()`), `player.gd` (camera zoom from render.json, `swing_skill_kind`, `swing_impact`), `skill_exec.gd` (sets `swing_impact`), `enemy.gd`/`minion.gd` (pass ids), `art.gd` (manifest loading), `test_runner.gd` (runs test_art), `data/training.json` (Drillmaster sprite id fix).
- HUD/UI files were not touched. Tests 2158/0; smartbot identical art on/off.
- Next (not started): V1 (player art, weapon layer, death/corpses) once Dan delivers warrior sheets.


## Passive tree expansion Phase 0 (audit and design), added by Claude, 2026-11-04

- Plan: project doc "Path of Dan: A Phased Plan to Expand and Deepen the Passive Tree". Delivered as uncommitted files.
- `tools/gen_clusters.py` rebuilt (original was lost with the old cloud workspace). Sources: `data/tree_src/hand_nodes.json` (82 hand nodes, without links into generated nodes) + `data/tree_src/clusters_spec.json` (6 rings, paths, Wanderer's Road). `--check` reproduces `data/passive_tree.json` byte-for-byte. Rings and paths are formula-placed; the 36 Wanderer's Road positions are pinned in the spec. Never hand-edit passive_tree.json from now on.
- `tools/audit_tree.py` writes `docs/passive_tree_audit_phase0.{csv,json}`; `.xlsx` (Summary, Nodes, Keystones, Archetypes, Assumptions check) built from it. Proposals: 171 Keep, 18 Convert, 14 Cut.
- Findings that change the plan: points at L60 are already 65 (59 + 6 first boss kills); bridges already exist as 3 roads (only hybrid notables missing); only 15/203 nodes change behaviour (13 flagged keystones + bulwark + vampiric); Prismatic Soul has no flag; Mind over Matter has no drawback; Momentum's drawback is near-free; statuses never stack (actor.add_status), so every stack-based proposal is [H]; respec is 10+6*level gold per node with no free tier; no 'more' mods outside keystones.
- No game code, data or save format changed. Next: Phase 1 (schema, migrations, SAVE_VERSION 4, validator, behavioural tests) after Dan signs off the archetype list and point budget.
- Decisions (Dan, 2026-11-04): point budget ~72 at L60 (59 + 6 boss first kills + 4 Abyss milestones 10/20/30/40 + ~3 side content). MVP archetypes: W Bleed Berserker / Iron Riposte / War Herald; R Clockwork / Deadeye / Venom; M Embers / Legion / Hex. Bridges in Phase 3.

## Passive tree expansion Phase 1 (schema, migration, validator), added by Claude, 2026-11-04

- Delivered as uncommitted files. Details: `docs/PASSIVE_TREE_DATA.md`, CHANGELOG entry.
- Schema: `tags` on all 203 nodes, `drawback` on keystones, optional `exclusive_with`/`rev`/`art_id`; registry `data/passive_flags.json` (15 flags, tag vocabulary, statuses, budget 72); `data/passive_migrations.json` (tree_version 1). Generator copies the keys; `--check` byte-for-byte. Tree content unchanged.
- `scripts/core/tree_rules.gd` validator + `allocation_problem`; `CharacterData` SAVE_VERSION 4 writes `tree_version`; `_load_passives` does a full free refund when the tree version is older or the allocation is illegal (Dan's policy: always full refund); `Game` shows a one-time message on the next level_ready and keeps `<slot>.tree<N>.bak`. `exclusive_with` enforced in `can_allocate`/`path_to`.
- Tests: `tests/test_passive_tree.gd` (in full suite) + `tests/tree_only.tscn`. Behavioural test per flag (`flag_<id>`); 11-slot v3 fixture loads; refund cases; validator mutation cases. Full suite 2323 passed, 0 failed (Godot 4.0, Windows); tree_only 168/0. Old SAVE_VERSION==3 checks updated to 4.
- Smartbot: pre/post Phase 1 mini run (3 classes T3 x4, seed 900) identical. Frozen baseline `tests/smartbot/baseline/tree_v1.csv` via `run_baseline.ps1`; compare with `compare_baseline.py`.
- Known: Mind over Matter has no drawback (validator warning via `pending_rework`); status coverage is thin (report only). Next: Phase 2 (24 behaviour nodes), first tree_version bump there.

## Passive tree expansion Phase 2 (24 behaviour nodes), added by Claude, 2026-11-04

- Delivered as uncommitted files. Details: `docs/PASSIVE_TREE_DATA.md` (Phase 2 node table), CHANGELOG entry. Backups of the touched files from before Phase 2: `../_claude_xfer/phase2_backup/`.
- Decisions (Dan, 2026-11-04): accept two [H] hooks, Avatar of Embers conversion and poison stacking; new nodes go in as spurs (tree 203 -> 227).
- 6 keystones (Blood Frenzy ⟂ Iron Riposte, Clockwork Mind, Venom Pact, Avatar of Embers, Legion of Bone) + 18 notables (2 per archetype), all with flags, `rev` 2, tests. Mind over Matter drawback added. `tree_version` 2: every older save gets a full free refund.
- Code: combat.gd (conversion, crit rules, poison chance/stacks, `_on_hit_passives`, Clockwork Mind less), actor.gd (stacking statuses), player.gd (frenzy, riposte, block/kill/dodge hooks), skill_exec.gd (Herald's Voice, `retire()`), turret.gd, mine.gd, minion.gd, level.gd (passes killer to on_kill).
- Tests: tree_only 333/0; full suite 2538/0 (Godot 4.0, Windows). v3 fixture checks now expect the refund when tree_version > 1.
- Not done in Phase 2: archetype benchmark builds / ±15% DPS check (needs Phase 6 harness) and Dan's playtest notes.
- Smartbot re-baselined once (end of Phase 2): `tests/smartbot/baseline/tree_v2.csv`, row and summary in `baseline/BASELINES.md`. Bots take no keystones, so only the new notables are exercised. Mage T6 7 -> 8/10, ranger T6 10 -> 9/10.
- Next: Phase 3 (restructure ~320 nodes, bridge notables, Abyss bonus points, freeze/shock coverage), or Phase 6 benchmark builds first if Dan wants keystone numbers checked.

## Passive tree expansion Phase 3a (bridges, conversions, cuts, Abyss points), added by Claude, 2026-11-04

- Delivered as uncommitted files. Details: `docs/PASSIVE_TREE_DATA.md` (Phase 3a node table), CHANGELOG entry. Backups of the touched files from before Phase 3: `../_claude_xfer/phase3_backup/`.
- Decisions (Dan, 2026-11-04): Phase 3 split; 3a now, growth to ~320 nodes is 3b. Apply the 14 Phase 0 cuts. Abyss points at depths 10-70 (7), so the 72 budget is reachable today.
- Content: 3 bridge spurs (`p3_hk_*`, `p3_hs_*`, `p3_sb_*`) with 3 bridge keystones; 15 conversions (`rev` 3); Prismatic Soul rule + exclusive with Avatar of Embers. 27 new flags (66 total), each with a behavioural test. `tree_version` 3, history[3] lists the cut ids.
- Code: combat.gd (`_on_hit_phase3`, `death_burst`, conditional crits, status enablers, Spell Archer/Battlemage stat routing, Prismatic/Festering in `apply_status`, Commander crit in `minion_packet`), player.gd (`_before_skill`, `_hit_passives`, `add_status` immunities, Tailwind, death bursts), skill_exec.gd (Rift Step, `last_curse`), character_data.gd (`abyss_passive_points`), dungeon.gd (milestone message), tools/gen_clusters.py.
- Tests: tree_only 524/0; full suite 2762/0. Smartbot re-baselined (`tree_v3.csv`): T3 100% all; T6 W 10/10, R 9 -> 10/10, M 8/10.
- Next: Phase 3b (archetype spurs to ~320 nodes, second re-baseline rule applies), or Phase 6 benchmark builds; Dan's playtest of Phase 2 + 3a nodes.

## Passive tree expansion Phase 3b (archetype spurs), added by Claude, 2026-11-04

- Delivered as uncommitted files. Details: `docs/PASSIVE_TREE_DATA.md` (Phase 3b section), CHANGELOG entry. Backups: `../_claude_xfer/phase3b_backup/`; one-off build script and layout: `../_claude_xfer/phase3b/`.
- Decisions (Dan, 2026-11-04): archetypes Earthbreaker + Duelist (W), Trapper + Barrage (R, Barrage instead of Gunslinger), Tempest + Frostweaver (M); one keystone per class.
- Content: 84 nodes (tree 316), 18 flags (84 total) each with a behavioural test, 3 keystones with drawbacks, 2 new exclusive pairs, `tree_version` 4 (history[4] empty: nothing removed).
- Code: combat.gd (`_on_hit_phase3b`, `_freeze`, `arrow_rain`, Feint/Brittle in `deal`, Glacial Heart in `_conditional`, 3b enablers and keystone multipliers in `player_packet`, Conductive Web / Noxious Payload / Tremor Lines in `apply_status`), player.gd (Feint, Blade Dance, Thunderhead, Endless Quiver, Shockwave, turret block), skill_exec.gd (`proj_count` / `proj_pierce`, +1 trap), mine.gd (instant arming).
- Tests: tree_only 680/0; full suite 3017/0. Smartbot re-baselined (`tree_v4.csv`): T3 100% all; T6 W 10/10, R 10/10, M 8 -> 6/10 (noise: 14/20 on both trees with seed 2000).
- Next: Phase 4 (tree sockets) or Phase 6 benchmark builds; Dan's playtest of Phase 2 + 3a + 3b nodes.

## Passive tree expansion Phase 4a (mastery choice nodes), added by Claude, 2026-11-04

- Delivered as uncommitted files. Details: `docs/PASSIVE_TREE_DATA.md` (Phase 4a section), CHANGELOG entry. Backups: `../_claude_xfer/phase4_backup/`; build script and layout: `../_claude_xfer/phase4/`.
- Decisions (Dan, 2026-11-04): masteries before sockets. Sockets (Phase 4b): 9 sockets, 2 per class + 1 per bridge; a socketed gem gives a tree-specific stat table by grade plus a glyph-style radius boost to allocated nodes sharing the gem's tag.
- Content: 12 mastery nodes over 9 groups (3 doubled), 4 options each, registry `masteries` in `data/passive_flags.json`; `tree_version` 5 (history[5] empty).
- Code: tree_rules.gd (mastery schema/registry validation, `mastery_problem`, no route-through), character_data.gd (`mastery_choices`, `allocate(id, option)`, `allocate_path(id, option)`, `change_mastery`, `choices` param on build_stats/previews, save/load), passive_tree_view.gd (hexagon, effect menu via `ui.show_context`, tooltip), dev_tools respec clears choices, smartbot planner + tests/bot.gd skip masteries.
- Tests: `test_masteries` in tests/test_passive_tree.gd; tree_only 736/0; full suite 3088/0. New `tests/screens_tree_p4.tscn`. Smartbot `run_baseline.ps1` vs `tree_v4.csv`: 60/60 identical (no re-baseline).
- Next: Phase 4b (tree sockets), or Phase 6 benchmark builds; Dan's playtest of Phase 2-4a nodes.

## Passive tree expansion Phase 4b (tree gem sockets), added by Claude, 2026-11-04

- Delivered as uncommitted files. Details: `docs/PASSIVE_TREE_DATA.md` (Phase 4b section), CHANGELOG entry. Backups: `../_claude_xfer/phase4b_backup/`; build script, layout and placement search: `../_claude_xfer/phase4b/`.
- Content: 9 socket nodes `p4_s_*` (2 per class + 1 per bridge diamond), `tree_version` 6 (history[6] empty). Gems gained `tree` (stat table, scaled by tier mult) and `tree_tags` in `data/gems.json`; `tree_sockets` config (radius 240, boost 15/25/35/50%) in `data/passive_flags.json`.
- Code: tree_rules.gd (`NO_ROUTE`, socket schema/config validation, `socket_boosts`, `nodes_in_radius`), character_data.gd (`tree_gems`, `socket_tree_gem`, `unsocket_tree_gem`, `clear_tree_gems`, radius boost + gem table in build_stats, refund returns the gem, save/load `tree_gems` with pouch fallback), loot.gd (gem summary shows the tree line), passive_tree_view.gd (socket node, ring, boosted outline, gem menu, tooltip), ui_root.gd (context menu clamps to its real width), dev_tools respec returns gems, smartbot planner + tests/bot.gd skip sockets.
- Tests: `test_tree_sockets` in tests/test_passive_tree.gd; the 25% behaviour check now counts fixed nodes only. tree_only 782/0; full suite 47728/0. New `tests/screens_tree_p4b.tscn`. Smartbot `run_baseline.ps1` vs `tree_v4.csv`: 60/60 identical (no re-baseline).
- Next: Phase 5 (UI functionality) or Phase 6 benchmark builds; Dan's playtest of Phase 2-4b nodes. All socket numbers are placeholders for Phase 6.

## Corruption system spec v1 — Phase 1 (2026-11-04)

- Audited current loot, crafting, Blacksmith, Jeweller, character stats, UID ownership, gem recovery, personal/shared stash and atomic save conventions. Existing uncommitted passive/art/HUD work preserved.
- Added dedicated corruption fields, Abyssal Brand, immutable action planning, UID-based ownership/refusals, persisted replay receipts, atomic payment/destruction/survival and gem recovery. Failed persistence restores item/resources. Blacksmith confirmation/result uses its existing isolated RNG stream.
- Intentional compatibility resolution: old crafting corruption stays 60%/+25 below 100; at 100 the new spec supersedes historical upgrade/remove/socket exemptions. Optional fields retain SAVE_VERSION 4. Legacy items get no implicit reroll; unknown implicit records are quarantined on the item and remain sealed.
- Authoritative 82-row registry imported from spec section 5; 14 P4 families gated. Full validation and all-base pair coverage run on load. Phase 2 stat integration follows.
- Verification: Godot 4.0 deterministic foundation runner `tests/corruption_system.tscn -- foundation`: 467 passed / 0 failed. Existing 100%-exemption assertions updated for the explicit design change. Sandbox cannot launch Godot normally; escalated test runs work.

## Corruption system spec v1 — Phases 2/3 selection and stats (2026-11-04)

- Integrated all 62 P2 ordinary families and 6 P3 Signature families through Loot.item_mods / StatBlock with stable per-item source IDs. Normal and Legendary modifiers remain independent.
- Tested every family band endpoint, all 129 bases at eight levels, category/family selection, independent doubles, fixed effects with zero tier RNG calls, equip/remove/re-equip and malformed-record quarantine.
- Compatibility resolution: existing elite damage uses a separate multiplier. Corruption elite damage uses the additive increased bucket while preserving non-corruption elite behavior. Existing 75% temporary DR is preserved; any P4 hit-only contribution will stop at the normal 60% cap.
- Added one rare-material roll per eligible kill, isolated from the ordinary loot RNG; T5 10%, T6 15%, Endless depth up to 20%, endgame elite 0.1%. No merchant/salvage material-pool inclusion.
- Godot 4.0: existing item/crafting suite 322/0; dedicated corruption suite 43,753/0 including 1,000,000 outcomes (150049 destroyed / 250698 no modifier / 558887 single / 40366 double), tier and category distributions. P4 handlers are now being tested before gates are enabled.

## Corruption system spec v1 — Phase 4 (2026-11-04)

- All 14 P4 families now have tested typed handlers and individual enabled feature gates. Tagged melee/spell/all-active levels honor existing skill cap/stacking; offensive projectile filters honor the +2 corruption cap and existing rune/Volley Fire behavior; new chains/pierce do not leak into unrelated summons/deployables.
- Conditional target/minion damage, elite kill Mana, persistent game-time dodge ICD, derived elemental resistance caps, hit-only DR and per-type trap capacity integrated with existing consumers. Operations carry stable item sources and have explicit tooltip/stat UI descriptions.
- Actual disk save/reload and failed-save rollback tested. A failed manual commit never autosaves provisional state. Stale item references are preserved on survival and invalidated on destruction to prevent duplicate gem extraction.
- Dedicated suite passed with all gates enabled; full pre-polish suite 47,728/0. Final verification follows UI/benchmark additions. Existing malformed-save fixture errors and engine exit leak warnings are emitted by the broader legacy suite; the focused corruption suite is clean.

## Corruption system spec v1 — Phase 5 verification/polish (2026-11-04)

- Generated five-archetype baseline/T3/T2/T1 Training Grounds matrix and 100,000-hour-per-scenario economic simulations. These preserve the spec's numbers. Clear-time is labeled a DPS proxy, and income inputs are assumptions, not telemetry; real-run balance tuning remains a playtest activity.
- Rendered Blacksmith preview/irreversible confirmation/result and Legendary double tooltip. Moved long results into the existing scroll region to keep controls accessible; corruption and Legendary colors remain distinct.
- Persistent design/compatibility record and reproducible commands: `docs/CORRUPTION_SYSTEM.md`. Exact registry validation uses frozen spec tables in `tests/fixtures/corruption_spec_tables.md`.

### Final verification

- Godot 4.0 full suite: **47,781 passed, 0 failed**, including **44,639 corruption acceptance checks**. One million outcome draws matched 15/25/56/4; 100,000 ordinary double plans produced 9,834 prefix T1 / 9,905 suffix T1 / 960 both T1, validating independence. Standalone foundation: 491/0.
- Exact Python data validator passes. Screenshots verified preview, irreversible confirmation, actual double result, Legendary tooltip and 960x540 layout. Economic and Training Grounds reports generated without retuning data.
- Fixed the existing all-skills summon test's false failure: it now observes a newly created minion at the cast rather than requiring it to survive the subsequent fight. This changes only test measurement, not summoning gameplay.
- All 82 families implemented; no deferred/placeholder mechanics. P4 remains individually switchable in data. Remaining balance work is real-player dungeon-clear/economic/performance telemetry, explicitly distinguished from the scripted reports.

## UI overhaul — focused audit refresh complete, 2026-11-04

- Assigned audit preparation only. Updated the original audit and 2A/2B/2C checklist for current item corruption, implicit affixes, Blacksmith/Jeweller flows and passive-tree UI contract. Corrected stale Phase 1 status; preserved the existing architecture and completed HUD.
- Source review: current inventory/shared slots, Loot tooltip/comparison paths, corruption bar/rules/action callback, station scroll/actions, UIRoot placement/input and current tree controls/contract. Percentage, player lock, seal and corrupted implicits must retain independent meanings. Item sockets and tree gem sockets remain separate controllers.
- Fresh Godot 4.0 Compatibility captures: existing corruption scene (16 images) plus isolated local audit harness (17 images/bounds). Final capture stderr logs empty. Five output sizes measured: 1280x720, 1920x1080, 2560x1440, 1920x1200 and 2560x1080. Key comparison, crafting, confirmation/result, vendor and tree images visually inspected. Game.testing prevents character/settings saves; audit pointer restored. Sandbox startup exited before logs, so approved out-of-sandbox captures were used.
- Confirmed 2C issue: a socketed, upgraded, locked Legendary with two corrupted implicits produces an 801px logical tooltip; it clips at every sampled size (16:10 logical height is 800; other samples 720). Equipped comparison is 481px. Existing placement has no height/overflow handling and does not constrain the pair together. The existing corruption content harness manually positions tooltips; the additional audit harness measured actual bag-hover placement.
- Sample full inventory measures 430x649; Blacksmith 440x652 at 720 logical height. Inventory/station bounds and pinned crafting controls fit the five samples, with limited room for larger fonts/padding. Jeweller scrolls long descriptions and disables sealed gem edits. Tree controls fit at 1280x720; several Fit tree cluster labels overlap, deferred to later tree visuals/readability work without moving generator-owned nodes.
- Evidence/reproduction: ignored `tests/screens_out_hud/ui_audit_2026_11_04/`, with `corruption/`, `layout/bounds.json`, capture logs and local `audit_capture.{gd,tscn}`. Fixture recipe, scope limits and commands recorded in the audit. No gameplay acceptance suite rerun for this documentation/capture-only stage; no new acceptance totals claimed. Earlier suite results above remain historical.
- No production UI/gameplay/data/save changes. Passive-tree expansion need not finish before inventory work; consume its current APIs and preserve TREE_UI_CONTRACT. Planned-node state remains reserved for the future planner. **Stop after this completed audit stage. Next suggested assignment: 2A only.**

## UI overhaul — Phase 2A inventory chrome complete, 2026-11-04

- Assigned: start Phase 2. Executed its first small stage, 2A, following the audit sequence; stopped before 2B/2C.
- Integrated inventory-local native cabinet frame, serif heading, equipment/bag/material insets, occupancy and visible button focus. Preserved existing 40+11 ItemSlot instances, dimensions/signals, markers and action/data paths. Materials include Brands; asynchronous wrapping now refits the panel on open/currency growth. No root/HUD/tree/station Theme changes.
- Final focused inventory checks: **1460 headless / 1483 rendered passed, 0 failed**, clean logs. Actual viewport mouse input covers both station controllers, four bag corners, charm/both rings, context/Destroy menu and close. Refresh/reposition preserves character serialization and combat RNG.
- Exact rendered outputs at 1280x720, 1920x1080, 2560x1440, 1920x1200, 2560x1080; 23 captures/bounds retained in ignored `tests/screens_out_hud/inventory_2a/`. Full bag alongside Blacksmith/Jeweller/vendor/personal stash at every size; shared/empty/nine-digit currency growth at 720p. Inspected all five sizes and key states. Populated fixture 430x690; currency-growth fixture 430x708. All sampled bounds/materials/hints/actions fit; no station overlap.
- Existing affected item/crafting/lock/stash checks **322/0** (historical runner's exit ObjectDB warning persists); focused HUD **86/0**, clean. No broad gameplay rerun for this scoped presentation stage. Sandbox engine startup exited before logs; approved external runs succeeded.
- Reproduction/limits: `docs/UI_INVENTORY_PHASE2.md`. Native art/system fonts remain provisional. Known tooltip height/pair-placement defect is unchanged and belongs to 2C. DPI/other hardware remain unverified. No gameplay values, stat/save formats or unrelated edits changed.
- **Next suggested assignment: 2B shared ItemSlot skin only.** Preserve independent upgrade/player-lock/price/seal corners and reuse in stations/vendor/personal/shared stash. 2C tooltips/actions plus final integration regression follows; passive-tree art remains outside this phase.

## UI overhaul — Phase 2B shared slots complete, 2026-11-04

- Assigned and executed 2B only. Existing ItemSlot now uses native charcoal/bronze recessed wells, rarity rims, ivory hover, gold selection brackets, empty silhouettes and a non-colour restriction cue. Upgrade/player-lock/price/seal corners remain independent. Prices over 9,999 compact on the badge; transaction values and existing full-price descriptions remain exact. No new child Controls, controller/input rewiring, gameplay/stat/save changes or asset dependencies.
- Godot 4.0: shared-slot checks **455 headless / 465 rendered, 0 failed**. Actual viewport input verifies existing hover/unhover, click-before-double-click, equip/both ring targets, station selection, context callbacks, Shift sell, vendor confirmation and personal/shared stash round trips. All sixteen marker combinations across five rarities plus restricted/selected/hover/dim/empty states rendered. Marker bounds and nine-digit price fit verified at 44/46px. Presentation preserves character serialization and combat RNG; testing guards real saves and restores shared-stash memory.
- Rechecked inventory **1460 headless / 1483 rendered**, item/crafting/lock/stash **322**, HUD **86**, all passed. Slot/inventory/HUD logs clean; legacy item runner retains its known exit ObjectDB warning. Sandbox startup exited before logging; approved external runs succeeded. No broad gameplay rerun for this shared presentation stage.
- Evidence/reproduction: `docs/UI_INVENTORY_PHASE2.md`; ignored `tests/screens_out_hud/item_slots_2b/` has ten new captures, with 23 existing-harness recaptures/bounds in `integration/`. Visually inspected all five exact-size matrices plus full inventory, station, vendor and shared-stash states. Native art/fonts and target-hardware DPI remain provisional.
- **Stop after completed 2B. Next: 2C tooltips/actions and final integration regression.** Known 801px tooltip overflow is unchanged; no tooltip/corruption-transaction/tree-art work started. Blockers: none.

## Passive tree Phase 5b: presets, planner, build codes (2026-11-05, Claude)
- Presets: 3 per character (`CharacterData.presets/active_preset`, save key `passive_presets`, written only when used). Switching costs `refund_cost()` per node removed (or mastery effect changed); free below level 20; empty slot = copy of current tree (free). Gems go back to the pouch and are re-socketed from it when held.
- Planner: `plan`, `plan_choices`, `plan_gems` (save key `tree_plan`); `plan_add/plan_remove/apply_plan/clear_plan`; view `planner` mode.
- Build codes: `POD1-` codes via `TreeRules.encode_build/decode_build`; import fills the plan (`sanitize_plan` drops unknown/start/disconnected/exclusive nodes and bad mastery choices); gems are suggestions only. Older tree_version codes go through `migrate_id`.
- A tree refund on load empties presets and the plan; an illegal preset is emptied (`presets_dropped`).
- Tests: `ui5b` checks (25) in tests/test_passive_tree.gd. tree_only 843/0, full 47843/0. Screens: tests/screens_tree_p5b.tscn.
- Expected engine noise: "decompress ... err != 1" lines come from the bad-code tests.
- Open: preset renaming; no UI hint for presets_dropped on load.

## UI overhaul — Phase 2C tooltips/actions complete, 2026-11-05

- Assigned and executed 2C only. UIRoot uses bounded native cards with complete Loot/CharacterData text and comparison maths. Pair placement respects all viewport edges; F4 explicitly freezes overflowing panel cards for independent wheel/page/Home/End reading, Tab selects the other card, Escape/F4 closes only the reader. Outside dismissal consumes the press. Inventory/stat/character/level/panel changes invalidate reading. Ordinary hover remains passive; both ring targets and Ring 1 comparison semantics remain intact.
- Context and confirmation use scoped inventory materials/focus. Context clamps its measured dimensions; long confirmation text scrolls above pinned Confirm/Cancel. Existing Blacksmith/Jeweller controllers, corruption bar, transaction/RNG/stat/save rules and TREE_UI_CONTRACT preserved.
- Godot 4.0 focused checks: **125 headless / 143 rendered, 0 failed**, clean logs. Both long Legendary/socket/double-implicit cards fully readable at five exact output sizes. Verified resize, input scope, full text/tier/fixed/quarantine/percentage/lock distinctions and existing warning/cancel/stale UID/changed-character/failed-save callbacks, all four outcomes/gem recovery, seal refusals and pinned results/actions. Eighteen captures/bounds/logs: ignored `tests/screens_out_hud/tooltips_2c/`. Visually inspected all five sizes and action states; controls/reproduction in `docs/UI_INVENTORY_PHASE2.md`.
- Integration: inventory **1460 headless**, shared slots/ring/vendor/personal/shared stash **455 headless**, HUD **86 headless / 161 rendered**, full suite **47,844/0** including **44,639 corruption acceptance checks**. Final full logs retain expected negative-save/migration fixture errors and pre-existing legacy exit canvas/RID/resource warnings, with no script errors. Initial full run caught tooltip-text API suppression under menus; corrected and full suite rerun. One concurrent fixed-fps HUD run had the known intermittent exit warning; final verbose headless/rendered HUD runs have no leak warning. Rendered input tests must run alone: a concurrent input-driving run interfered with OS-pointer checks; final isolated run passed.
- Game.testing guards fixtures; failed-save UI check temporarily uses invalid manual slot 0 and restores state, so no real character file is written. Sandbox startup stalled without logs; owned stalled process stopped, approved external runs succeeded. No gameplay/data/save/dependency/tree-art changes or commit/branch switch. Existing unrelated work preserved. Native artwork/fonts, target DPI/other hardware and exhaustive arbitrary-length context menus remain outside this stage.
- **Phase 2 complete. Stop after 2C; await new assignment.** Blockers: none.

## UI overhaul — Phase 3A passive-tree chrome complete, 2026-11-05

- Assigned: start Phase 3. Executed its first small batch only, passive-tree chrome, per the existing rollout order. Rechecked current Phase 5b presets/planner/build codes and TREE_UI_CONTRACT before styling.
- Existing panel opts into local reusable cabinet materials: title, visible focus, search/code fields/tag selector, framed canvas and summary inset. Points, navigation, presets/planner, search and flow chips have separate rows; summary wraps and scrolls. Footer follows the current planner/allocation mode. No root/BasePanel/HUD theme rollout, controller/stat/data/save changes or custom tree/node/link/minimap drawing changes.
- Godot 4.0: focused **2530 headless / 2540 rendered**, existing tree **843**, inventory **1460 headless**, HUD **86 headless**, all passed, 0 failed. Viewport input checks cover filters/search/minimap/pan/zoom, allocation/refund, planner/apply/clear, presets, mastery/socket menus, import, summary scroll and close/reopen. Existing code export API tested without touching clipboard; confirmation callbacks and More-tag selection signal retain ownership. Presentation preserves character serialization, geometry and combat RNG.
- Ten actual expanded/closed screenshots plus measured bounds at 1280x720, 1920x1080, 2560x1440, 1920x1200 and 2560x1080 retained in ignored `tests/screens_out_hud/tree_3a/`; inspected all five sizes. 720p expanded tree canvas 900x361 logical; summary/code/actions/footer fit. Existing custom-view cluster/legend overlaps remain for later tree art/readability.
- Final focused chrome/HUD/inventory logs clean. Concurrent fixed-fps inventory run passed with its known intermittent exit warning; final isolated documented-timing run clean. Existing tree acceptance runner emits newer-version/malformed-code fixtures and legacy ObjectDB exit warning. No full gameplay rerun required for this scoped local theme/layout batch. Sandbox startup exited before logs; approved external engine runs succeeded. Fixtures use Game.testing; unrelated work preserved.
- Reproduction/limits: `docs/UI_SHARED_PHASE3.md`. Native art/system fonts, DPI/other hardware, remaining shared panels/menus and custom tree art remain future work. **Stop after 3A. Next suggested assignment: 3B character/skills/specialisation chrome.** Blockers: none.

## UI overhaul — Phase 3B character/skills/specialisation chrome complete, 2026-11-05

- Assigned and executed 3B only. Existing three panels opt into the reusable cabinet theme, serif headings, native focus and framed scrolling regions. Character rows wrap with aligned values; Skills uses framed cards, square icons, real InputMap labels, wrapping rune actions and an independently scrollable rune pouch. Specialisation choices use a three-column scrollable grid (all six Mage choices fit at 720p), with a framed existing graph and reachable reset action.
- Godot 4.0 focused results: **3288 headless / 3316 rendered**, 0 failed. Viewport input covers all three classes: hotbar selection/swap/clear/reopen, remapped labels, rune context/socket/return, nearby-enemy refusals, locked skills/sockets, keyboard action/focus, character breakdown hover and independent scrolling. All sixteen specialisations exercise Choose/Cancel/Confirm, graph allocation/duplicate refusal, reset cancellation/refund/cost and unaffordable reset; locked choices remain disabled.
- Presentation refresh/resize preserves character serialization and combat RNG. Existing controllers/stat maths/rune/spec rules and graph drawing remain authoritative. No gameplay, save/data, root/BasePanel/HUD-theme or tree-art change. Fixtures use Game.testing; unrelated working-tree changes preserved.
- Twenty-eight actual screenshots and measured bounds: ignored `tests/screens_out_hud/character_3b/`; inspected character/skills/chooser/graph at **1280x720, 1920x1080, 2560x1440, 1920x1200, 2560x1080**, plus class and locked examples. Final focused headless/rendered logs clean. Regression: tree chrome **2530**, inventory **1460**, HUD **86**, all passed. Concurrent HUD run emitted its known intermittent exit ObjectDB warning; final isolated verbose run has no script/engine errors or leak warning (engine verbose StringName shutdown listings remain). No broad gameplay rerun for this scoped presentation stage.
- Reproduction/limits: `docs/UI_SHARED_PHASE3.md`. Sandbox engine startup exited before logs; approved external runs succeeded. Native artwork/fonts, target DPI/other hardware and custom graph art remain future work. **Stop after 3B. Suggested next assignment: 3C stations/utility chrome.** Blockers: none.


## UI overhaul — Phase 3C stations/utility chrome complete, 2026-11-05

- Assigned and executed 3C only. Seven station panels opt into existing cabinet materials locally: Merchant, Blacksmith, Jeweller, personal/shared Stash, Pet Keeper, Training Grounds and Dungeon Gate. Framed grids/readouts, bounded independent scrolling, wrapping choices and reachable actions retain existing controllers/callbacks/costs/refusals. Four inventory-linked panels coexist without overlap; maximum stash tabs stay bounded.
- Godot 4.0 focused results: **1732 headless / 1774 rendered**, 0 failed. Viewport input covers merchant/crafting/gems/stash/pet/training/dungeon transactions, cancellation/confirmation, sealed/away/locked states, native keyboard activation, scrolling and actual dungeon entry. Existing corruption/actions **125**, shared slots **455**, inventory **1460**, character chrome **3288**, tree chrome **2530**, HUD **86**, all passed. Old theme-isolation assertions updated for the new station opt-in; no broad gameplay rerun for this presentation batch.
- Forty-one actual captures and bounds across **1280x720, 1920x1080, 2560x1440, 1920x1200, 2560x1080**, plus sealed/away/locked/training-result/history states, retained in ignored `tests/screens_out_hud/stations_3c/`. Inspected all seven panels at all five sizes and key state captures. Final focused/regression logs clean; initial station/tree exit-only ObjectDB warnings did not recur in final isolated verbose runs. Fixture affix counts may vary layout assertion totals. Initial owned stalled test process stopped; sandbox startup exited before logs, approved external runs succeeded.
- Refresh/reposition preserves character serialization and combat RNG. Fixtures use Game.testing; real character/account files are not written. No gameplay/data/save/dependency/global-theme/custom-tree-art change, commit or branch switch; unrelated working-tree changes preserved. Reproduction/limits: `docs/UI_SHARED_PHASE3.md`. Native artwork/fonts, DPI/other hardware remain future checks. **Stop after 3C. Suggested next assignment: menus/options.** Blockers: none.


## Endgame Phase 0: zone technical spike (2026-11-05, Claude)
- Plan: "Path of Dan Endgame Design: The Atlas of Ruin, Rot, Zone Mechanics and Pinnacle", section G Phase 0. Full report: `docs/ENDGAME_PHASE0.md`.
- Decisions (Dan): smaller zones (5-7 chambers of 30-40 cells, 3-5 min); biome Overgrown Ruin (CA + BSP, warren palette); dev-only access; target 60 fps with 150+ enemies, flow under 2 ms.
- New: `scripts/world/zone_gen.gd`, `data/zones.json` (`Data.zones`), `tests/test_zone.gd` + `zone_only.tscn`, `tests/zone_bench.gd` + `zone_bench.tscn`, `docs/ENDGAME_PHASE0.md`.
- Changed: `dungeon.gd` (is_zone, objective_pool, hazards_per_room, update_sleep, spike guard on boss rewards), `level.gd` (integer BFS, per-chamber walk maps patched by set_cell, flow_reach/flow_us, tile_chunk, separation_pool), `tile_drawer.gd` (chunk mode), `enemy.gd` (separation over `level.separation_pool()`), `main.gd`/`dev_tools.gd` (zone fallback), `data.gd`, `dev_panel.gd`. Dungeon and hub paths keep the old behaviour.
- Results: zone tests 48/0; full suite 47844/0; smartbot baseline vs `baseline/tree_v4.csv` 60/60 identical; smartbot zone T3 Competent 30/30 boss kills, 0 deaths, clear median 184-230 s. Bench (RTX 4070 Ti SUPER): zone 156-174 fps at ~180 enemies, 112-116 fps / p99 16.6 ms at 315; flow avg 1.4 ms, peak 2.2-2.5 ms (target 2 ms missed on peaks).
- Open: summoner add loops in zones (4/10 warrior runs 670-820 kills); flow peak; Phase 1 MVP next. Not committed (as before). Backups: `_claude_xfer/endgame_p0_backup/`.


## Endgame Phase 1E: Pigments, Varnish slots, Rot tuning (2026-11-05, Claude)
- Decisions (Dan): Pigments crafted from their own material (Flakes / Dust); each guarantees its mechanic + 1 seeded modifier, stacking (zones can run both mechanics); 4 charges, -1 per run, -1 on death; Varnishes drop from Hearts (Harvest always, Restore ~1/3), slots 1 + 1 per full ring (max 3); Rot tuned to ~50% Competent wins at Rot 4 + 2 Pigments; Dev shortcuts. Full report: `docs/ENDGAME_PHASE1.md` (1E section; the stale duplicate 1D section was removed).
- New: `scripts/ui/easel_panel.gd`, `tests/smartbot/run_atlas_p1e.ps1`, `tests/smartbot/p1e_summary.py`.
- Changed: `data/atlas.json` (`pigments`, `varnish`, Rot 3-5 `damage_mult`/`heal`/`attack_speed`, `filled_dust_chance`), `data/loot.json` (descs), `atlas_rules.gd` (Pigment/Varnish rules, Varnish-aware Rot), `main.gd` (`enter_atlas`), `dungeon.gd` (`mechanics`, `glaze_tune`/`sketch_tune`, Varnish, Rot heal/attack speed, death charges, Heart Varnish), `enemy.gd`, `atlas_panel.gd`, `atlas_map.gd`, `ui_root.gd`, `dev_tools.gd`, `dev_panel.gd`, `smartbot.gd`, `test_atlas.gd`.
- Save: atlas gains `pigments`, `easel`, `crafted`, `varnish`, `varnish_slots`; SAVE_VERSION stays 5.
- Results: atlas 321/0; full suite 47844/0; baseline vs tree_v4 60/60 identical; smartbot ring 3 Rot 4 + 2 Pigments 14/30 wins (Rot 3 10/15, Rot 5 5/15).
- Open: mage weakest in Rot (0-20% at Rot 4-5); Pigment danger small; Rot cap. Not committed. Backups: `_claude_xfer/endgame_p1e_backup/`. **Phase 1 MVP complete; next: Phase 2.**

## Endgame Phase 1D: Glazed Elites + The Unfinished (2026-11-05, Claude)
- Decisions (Dan): glaze poise bar peels layers, reworked to reward speed (draining burst poise, stuns, shatter on fast kills); sketches have a neutral raw fill; Flakes / Dust banked as materials; natural 30% mechanic roll per Atlas run. Full report: `docs/ENDGAME_PHASE1.md` (1D section).
- Changed: `data/atlas.json` (`mechanics`), `data/loot.json` (`glaze_flake`, `pigment_dust`, weight 0), `atlas_rules.gd` (mechanic roll / colours / layers), `game.gd` (`atlas_force_mechanic`), `main.gd` (`def.mechanic`), `dungeon.gd` (`mechanic`, `mech_rng`, `mech_stats`, glaze mods, sketch packs, Flake / Dust drops), `enemy.gd` (glaze poise + peel, sketch immunity + painting), `combat.gd` (statuses still apply on a sketch hit), `level.gd` (rank-up drops, extra rarity), `atlas_panel.gd`, `components/atlas_map.gd`, `tests/test_atlas.gd`, `tests/smartbot/smartbot.gd` (`--mechanic=`), new `tests/smartbot/run_atlas_p1d.ps1`.
- Results: atlas 254/0; full suite 47844/0; baseline vs tree_v4 60/60 identical. Smartbot numbers in the report.
- Open: colour painting is rare for the bot (raw fill does most of the work); see report. Not committed. Backups: `_claude_xfer/endgame_p1d_backup/`. **Next: 1E Pigment/Varnish slots + bot tuning.**

## Endgame Phase 1C: Rot v1 + Heart bosses (2026-11-05, Claude)
- Decisions (Dan): seeded Rot sources (2 at Rot 1, rings 2-3); the zone boss becomes the Heart at Rot 3+; Harvest = legendary + material cache. Full report: `docs/ENDGAME_PHASE1.md` (1C section).
- Changed: `data/atlas.json` (`rot` block), `data/enemies.json` (`rot_mutations` on the 6 atlas bosses), `atlas_rules.gd` (Rot state, spread, forecast, death, restore/fester, `apply_rot`, `heart_def`), `main.gd` (`enter_atlas` applies Rot; death hook), `dungeon.gd` (Rot density/reward, Heart boss, `complete_run`, Restore/Harvest portals, `choose_heart`, `apply_death_rot`), `death_panel.gd`, `atlas_panel.gd`, `components/atlas_map.gd`, `tests/test_atlas.gd`, `tests/smartbot/smartbot.gd` (`--rot=N`), new `tests/smartbot/run_atlas_p1c.ps1`.
- Save: atlas gains `rot`, `restored`, `spreads`, `fester`; SAVE_VERSION stays 5 (sanitize seeds Rot into pre-1C atlases).
- Results: atlas 196/0; full suite 47841/0; baseline vs tree_v4 60/60 identical; smartbot Rot 3/5 on ring 2 and 3: 68/75 boss kills incl. Rot 0, all deaths mage; warrior/ranger 20/20 at Rot 5.
- Open: Rot not hard enough for warrior/ranger (tune in 1E); cap 9 small on radius 3; no dev shortcut for Rot. Not committed. Backups: `_claude_xfer/endgame_p1c_backup/`. **Next: 1D Glazed Elites + The Unfinished.**

## Endgame Phase 1A + 1B: Atlas core and two biomes (2026-11-05, Claude)
- Plan section G Phase 1, split by Dan into 1A Atlas core, 1B biomes, 1C Rot + Hearts, 1D Glazed/Unfinished, 1E Pigments/Varnish + tuning. This session: 1A + 1B. Full report: `docs/ENDGAME_PHASE1.md`.
- Decisions (Dan): Atlas unlocks after Malgrath; rings L40/45/50; state **per character** (save v5 key `atlas`); lifetime summon cap in zones.
- New: `data/atlas.json`, `scripts/core/atlas_rules.gd`, `scripts/ui/atlas_panel.gd`, `scripts/ui/components/atlas_map.gd`, `tests/test_atlas.gd` + `atlas_only.tscn`, `tests/smartbot/run_atlas_p1.ps1`, `docs/ENDGAME_PHASE1.md`. Zone biomes `zone_ruined_nave`, `zone_flooded_catacomb` in `data/zones.json`.
- Changed: `character_data.gd` (SAVE_VERSION 5, `atlas`), `data.gd` (`atlas_cfg`), `main.gd` (`enter_atlas`, `atlas:q,r` ids, `_start_run`), `dungeon.gd` (`atlas_hex`, reveal on boss kill, `summon_lifetime`), `level.gd` (`summon_lifetime`), `enemy.gd` (`summoned_total`, `_summon_room`), `dungeon_panel.gd` (Atlas button), `ui_root.gd` (atlas panel), `smartbot.gd` (atlas seed 1 + reveal target hex), `test_zone.gd` (all biomes), version checks in `test_runner.gd` / `test_passive_tree.gd`.
- Results: atlas 114/0; zone 78/0; full suite 47842/0; smartbot baseline vs tree_v4 60/60 identical; smartbot atlas ring 1 42/45 (3 mage deaths to Stormheart), ring 3 15/15, clear medians 120-237 s, max kills 228 (was 820 before the cap).
- Open: Rot must add difficulty (bot barely dies); vantage count (~4/atlas) to review; no dev shortcut to unlock/reveal the Atlas; biome art and chamber archetypes. Not committed. Backups: `_claude_xfer/endgame_p1_backup/`. **Next: 1C Rot v1 + Heart bosses.**

## Endgame Phase 2C: Commission Board + Restorers' Guild (2026-11-05, Claude)
- Decisions (Dan): ranks R1 board+caches / R2 Pigment vendor / R3 Fixative / R4 4th slot + 4 cache choices; rank 3 after ~40-50 zones; new hub NPC; contracts credit Atlas zones on completion only. Full report: `docs/ENDGAME_PHASE2.md` (2C section).
- New: `scripts/core/guild_rules.gd`, `scripts/ui/guild_panel.gd`, `data/atlas.json` `guild`, sprite `npc_restorer`.
- Changed: `atlas_rules.gd` (sanitize keeps `guild`), `loot.gd` (Fixative rank gate), `dungeon.gd` (run report, Heart credit, `elite_kills`), `hub.gd`, `ui_root.gd`, `art.gd`, `dev_tools.gd`, `dev_panel.gd`, `tests/test_atlas.gd`.
- Save: atlas gains `guild`; SAVE_VERSION stays 5.
- Results: atlas 472/0; crafting 322/0; corruption 127/0; full suite 47882/0; baseline vs tree_v4 **60/60 identical** (`out/p2c_check.csv`). Pace sim: rank 3 median 48 zones.
- Open: pace not verified in real play; ranks 5-8 later. Not committed. Backups: `_claude_xfer/endgame_p2c_backup/`. **Next: 2D Collector's Wager + Pentimento Vaults.**


## Endgame Phase 2D: Collector's Wager + Pentimento Vaults + new contracts (2026-11-05, Claude)
- Decisions (Dan): gold stake 1x/2x/3x; vault types Treasure + Trap + Riddle; natural spawn only (no Pigments); new contract families Wager & Vault, kill counts, boss kills, challenge runs. Full report: `docs/ENDGAME_PHASE2.md` (2D section).
- New: `scripts/core/wager_vault_rules.gd`, `scripts/ui/wager_panel.gd`, `scripts/world/vault_seal.gd`, sprites `npc_collector`, `pentimento_wall`.
- Changed: `data/atlas.json` (`mechanics.list` minor wager/vault, `mechanics.wager`, `mechanics.vault`, 13 contracts), `atlas_rules.gd` (`minor_mechanics`), `guild_rules.gd` (stats, filters, `on_death`), `dungeon.gd`, `enemy.gd` + `level.gd` (`object` enemies), `player.gd` (`flasks_used`), `ui_root.gd`, `atlas_map.gd`, `atlas_panel.gd`, `art.gd`, `dev_tools.gd`, `dev_panel.gd`, `tests/test_atlas.gd`.
- Save: no new keys (wager/vault state is per run); SAVE_VERSION stays 5.
- Results: atlas 552/0; full suite 47884/0; baseline vs tree_v4 60/60 identical (`out/p2d_check.csv`); pace sim rank 3 median 47.
- Open: smartbot never bets; `_populate` uses the global RNG for shuffles (pre-existing). Not committed. Backups: `_claude_xfer/endgame_p2d_backup/`. **Next: 2E bot tuning.**

## Endgame Phase 2E: bot tuning (2026-11-06, Claude)
- Decisions (Dan): scope Wager bot + odds, Vault tuning, Mage balance; mage fix = bot behaviour only; Wager target ~60% Competent wins per bet with EV +10-20%. Full report: `docs/ENDGAME_PHASE2.md` (2E section).
- New: `tests/smartbot/sb_endgame.gd` (Collector / vault play), `run_atlas_p2e.ps1`, `p2e_summary.py`, `p2e_trap.py`, `tools/p2e/vault_type_check.gd`, `baseline/tree_v4_bot2e.csv`.
- Changed: `data/atlas.json` (wager bets, trap elites 3, wager `_doc`), `wager_vault_rules.gd` (`hits`, `min_monsters`), `dungeon.gd` (hit allowance, `wager_refusal`, monsters/elites ahead of the Collector, timed count bets), `wager_panel.gd`, `main.gd` (comma list in `atlas_force_mechanic`), smartbot `sb_controller.gd` (endgame hooks, Blink dodge, `--hits`), `sb_threat.gd` + `sb_profiles.gd` (`group_perception`, off), `smartbot.gd` (`--wager --stake --vaults --vault_type`), `tests/test_atlas.gd`.
- Results: atlas 559/0; full suite 47883/0; baseline vs tree_v4 55/60 identical (5 mage T6 rows changed by Blink, wins 6/10 both) -> re-frozen as `tree_v4_bot2e.csv`.
- Open: mage class balance (fragile + low kit DPS; every death hit was an unperceived telegraph); bot does not visit the hub; Rot 3+ Wardens. Not committed. Backups: `_claude_xfer/endgame_p2e_backup/`. **Next: Phase 3 (pinnacle).**

## Caster itemisation (2026-11-06, Claude)
- Why: the bot gear audit (`docs/BOT_GEAR_AUDIT.md`) found that caster gear had no flat spell damage and no +spell level, and spell base damage stops at skill level 20, so gear widened the mage gap. Decisions (Dan): apply the proposal; gloves get % spell damage and cast speed instead of flat spell damage; add a spell penetration affix. Bot answers: re-pick spec when the main skill changes (Phase B); no skill choice by target resistance. Report: `docs/CASTER_ITEMISATION.md`.
- Data: `affixes.json` +6 (`searing`, `frigid`, `crackling`, `of_sorcery`, `sorcerous`, `of_penetration`), `of_haste` also on gloves; `item_bases.json` `added_spell` implicit on `apprentice_wand_t2/t3`, `bone_wand_t2/t3`, `oak_staff_t2/t3`; `stats.json` +6 names; `loot.json` `caster` block (`added_ref`, `eff_min`, `eff_max`, `overcap`).
- Code: `combat.gd` (`spell_added_eff`, `_caster_added` in the spell branch of `player_packet`, packet key `ele_pen`), `character_data.gd` (`skill_level`: `spell_skill_level`, item levels up to cap + overcap), `enemy.gd` + `training_rules.gd` (`mitigate(..., pen)`) + `training_dummy.gd` (penetration). New tests `tests/test_caster_itemisation.gd`, `tests/caster_only.tscn`; hooked into `test_runner.gd`.
- Results (cloud Linux copy): caster 56/0, items/crafting 322/0, training 93/0, corruption 127/0, tree 843/0, atlas 559/0, full suite 47924/9 (the 9 are art placeholder-sheet checks that fail identically on unchanged code in that environment). Dan's PC: caster 56/0, **full suite 47965/0**. Smartbot baseline set re-run as `tests/smartbot/out/caster_v1.csv` (mage T6 6/10 -> 8/10 wins, clear 179 -> 114 s); **frozen as `tests/smartbot/baseline/caster_v1.csv`** (Dan, 2026-11-06; `BASELINES.md` row added). Compare future non-tree changes against it.
- Known: the smartbot gear score ignores enemy resistances, so bots undervalue `of_penetration` (Phase B). Not committed. Backups: `_claude_xfer/caster_backup/`.


## Smartbot gear profiles + keystone builds, bot gear audit Phase B (2026-11-06, Claude)
- Decisions (Dan, audit #1-6): `typical` for tuning and `geared` for upper-bound checks, with typical gear fairly decent (players craft); flag-less default stays `legacy`; bots play keystone builds picked by an analysis system; generate items directly with maths over the drop and crafting systems; no Abyssal Brand corruption, but crafts follow the crafting meter; geared = 3x farming; Atlas Rot-touched implicits and Fixative for geared only; retune Rot/Wager after Phase D. Report: `docs/BOT_GEAR_PROFILES.md`.
- New: `tests/smartbot/sb_gear.gd` (economy model, drop rolling, meter-aware crafting), `sb_builds.gd` (12 keystone builds), `build_analyser.py` (real runs per build -> `build_picks.json`), `gear_compare.py`.
- Changed (smartbot only): `smartbot.gd` (`--gear=legacy|typical|geared`, `--plan=<id>|auto|none`, kit-dump fields), `sb_kit.gd`, `sb_hub.gd`, `sb_planner.gd`, `README.md`. No game file changed.
- Results: legacy kits + legacy run byte-identical. Typical vs legacy kits: about 9 of 11 rare+ slots (legacy about 3), lowest res 57-73 from T6, EHP x1.4-2.2, static DPS x2-3.4 for warrior/ranger and x1.05-2.4 for the mage (no keystone). Analyser picks (typical, 4 runs x T3/T6/R3): warrior Earthbreaker 0.89x clear time, mage Avatar of Embers 0.88x, ranger Perfect Aim 1.01x (no clear gain).
- Open: rerun the analyser with 10 runs on Dan's PC; Phase C real-run measurements; Phase D Rot/Wager/Warden retune. Not committed. Backups: `_claude_xfer/phaseB/backup/`.
