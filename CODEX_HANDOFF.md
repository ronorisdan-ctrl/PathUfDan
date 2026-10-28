# Codex handoff

Last updated: 2026-10-28

## Current objective

Pet must never collect loot-filter-hidden items (Alt held or not).

## Completed work

- LootFilter.evaluate now returns `filter_hidden` (hide decision after safety net, independent of Alt). Alt only affects `visible/drawn/clickable`.
- LootDrop stores `filter_hidden`; `filtered_now()` re-evaluates and returns it; `level.collect_block` refuses pets with "hidden" (covers F fetch, auto-loot, magnet). Pet "hoot" quirk uses it too. Player pickup and targeting unchanged (Alt-revealed items still pickable).
- Tests: engine `_t_hide_and_reveal` +5 checks; `test_loot_filter()` +10 checks (stub level/pet).

## Verification

- Full headless suite: 1929 passed, 0 failed (first run had one known-flaky summon check, passed on rerun).

## Remaining work / next stage

- Await next task. Stray copies `level-1.gd` / `dungeon-1.gd` in scripts/world are unused duplicates (not touched).

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
