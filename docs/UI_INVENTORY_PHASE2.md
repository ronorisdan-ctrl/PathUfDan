# Inventory UI — Phase 2

5 November 2026. **Phase 2 complete: 2A inventory chrome, 2B shared slots and 2C tooltips/actions.** Each stage was separately assigned and verified. Earlier stage evidence below is historical; current verification is under 2C.

## Stage 2A

Production inventory now has a native charcoal/bronze cabinet frame, serif title, recessed equipment/bag/material sections, bag occupancy and visible button focus. The local Theme copies the existing material resource before applying compact inventory spacing; it does not change root, HUD, tree, menus or station Themes. Existing ItemSlot instances, signals, markers, actions and item/data paths remain authoritative.

All 40 bag and 11 equipment cells remain visible, with 44px bag and 46px equipment targets. Material names/counts, including Abyssal Brands, wrap within the inset. The panel refits when asynchronous text wrapping changes its minimum size, including currency updates while open. Body/actions retain 14px defaults, materials use 13px and contextual hints/captions 12px to fit the measured height budget. Native materials and existing system/fallback typography remain provisional until the later art/accessibility pass.

## Verification

Godot 4.0.stable.official.92bee43ad, Compatibility renderer. From the project root:

```powershell
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --path . res://tests/ui_inventory_chrome_verify.tscn
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --rendering-method gl_compatibility --fixed-fps 60 --path . res://tests/ui_inventory_chrome_verify.tscn -- --capture
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --path . res://tests/items_crafting_only.tscn
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --path . res://tests/ui_hud_verify.tscn
```

- Inventory: **1460 headless / 1483 rendered passed, 0 failed**, clean final logs. Real viewport mouse events verify corner bag targets, charm and both ring targets through both station controllers, context menus, Destroy menu and close control. Geometry checks cover all cells, non-overlap, complete materials/hints and pinned station actions. Presentation refresh/reposition preserves serialized character data and combat RNG.
- Rendered outputs assert exact 1280×720, 1920×1080, 2560×1440, 1920×1200 and 2560×1080 dimensions. Full bag plus Blacksmith, Jeweller, merchant and personal stash at every size; shared stash, empty inventory/equipment and nine-digit currency/material growth at 1280×720. Visually inspected all five resolutions plus empty/growth/shared states. Full fixture measures 430×690 logical px; growth fixture 430×708, inside the 720px minimum height. All sampled station bounds remain separate and on screen.
- Existing affected item/crafting/lock/stash checks: **322 passed, 0 failed**; legacy runner reports its existing exit-only ObjectDB leak warning. Focused HUD input/tooltip checks: **86 passed, 0 failed**, clean logs.

23 captures and measured bounds: ignored `tests/screens_out_hud/inventory_2a/`. The harness uses `Game.testing`, test characters and only its own window settings. Godot exited before logging inside the sandbox; approved external engine runs produced the results above.

No broad gameplay run was required for this inventory-local presentation stage. No changes to gameplay/stat/persistence paths. DPI/other hardware and final typography remain unverified. The known 801px tooltip overflow is still owned by **2C**; current captures intentionally hide hover cards and do not certify tooltip placement. Next stage: **2B shared ItemSlot skin**, then **2C tooltips/actions and final integration regression**.

## Stage 2B — shared slots

The existing ItemSlot now draws recessed charcoal/bronze wells, inset rarity rims, ivory hover edges, gold selection brackets and stronger empty-equipment silhouettes. Restricted items retain their red tint and gain an exclamation cue. Upgrade, protective player lock, price and 100% seal keep independent corners; selection and dimming leave them readable. The seal still comes exclusively from CorruptionRules, independent of special implicits. The skin adds no child Controls or input handlers. Existing dimensions, signals, controller callbacks and icon filtering remain intact; presentation properties redraw when changed and hover resets on hiding.

Price badges retain exact numbers through 9,999, then compact to k/m/b to leave the seal clear. Stored prices, tooltip sell values, context actions and buy confirmations retain their exact values.

```powershell
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --fixed-fps 60 --path . res://tests/ui_item_slot_verify.tscn
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --rendering-method gl_compatibility --fixed-fps 60 --path . res://tests/ui_item_slot_verify.tscn -- --capture
```

Godot 4.0 Compatibility: **455 headless / 465 rendered passed, 0 failed**. Coverage includes all sixteen upgrade/lock/seal/price combinations across all five rarities; empty, placeholder, hover, selection, restriction and dim states; non-overlapping marker bounds at 44/46px; nine-digit badge fit; viewport hover/unhover, click ordering, double-click equip, both ring targets, station selection, right-click, Shift sell, vendor confirmation and personal/shared stash round trips. Drawing preserves character serialization and combat RNG. Fixtures use Game.testing and restore the in-memory shared stash.

Re-ran inventory layout/input at all five output sizes: **1460 headless / 1483 rendered**, affected item/crafting/lock/stash **322**, HUD **86**, all passing. Slot/inventory/HUD logs are clean; the legacy item runner retains its previously recorded exit-only ObjectDB warning. No broad gameplay run for this presentation stage.

Evidence: ignored `tests/screens_out_hud/item_slots_2b/` contains five exact-size state matrices and five production-surface captures; `integration/` contains 23 recaptured full/empty/currency-growth inventory layouts and bounds from the existing 2A harness. Visually inspected all five matrix resolutions plus full inventory, station, vendor and shared-stash states. Native art/fonts and OS DPI verification remain provisional. The tall-tooltip issue was deferred to 2C at this stage.

## Stage 2C — tooltips/actions

UIRoot now presents charcoal/bronze cards with 14px body text, measured height limits and an 8px viewport inset. Candidate and equipped comparison are placed together without overlap. Complete Loot tooltip text and CharacterData comparisons remain authoritative, including Legendary effects/flavour, ordinary affix tiers, sockets, fixed/tiered corrupted implicits, quarantine warnings, percentage, FINAL seal and player-lock explanations. Ring hover still compares Ring 1; both existing equip targets remain available.

When a panel is open and either card overflows, its footer offers **F4: read full cards**. F4 freezes the pair; wheel or PageUp/PageDown scrolls the active card, Home/End reaches its first/last line and Tab selects the other card. A gold rim/focus outline marks the active card. Escape/F4 closes the reader without closing the inventory. An outside button press dismisses it and consumes that press. Ordinary hover ignores pointer input; reading controls apply only in the explicit reading mode. Inventory/stat changes, character replacement, level transitions and panel close invalidate the reader. Resizing refits the frozen pair.

Context actions and confirmation dialogs reuse the inventory Theme locally, including disabled/focus states. Context placement now uses actual dimensions instead of estimating menu height. Long confirmation text scrolls while Confirm/Cancel remain visible. Existing Space/Escape confirmation shortcuts and transaction callbacks are retained. Blacksmith percentage bar, preview/results, pinned action/materials and Jeweller seal refusals continue through their existing owners. No gameplay, crafting RNG, corruption transaction, stat, save or tree-control code changed.

```powershell
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --fixed-fps 60 --path . res://tests/ui_tooltip_actions_verify.tscn
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --rendering-method gl_compatibility --fixed-fps 60 --path . res://tests/ui_tooltip_actions_verify.tscn -- --capture
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --path . res://tests/ui_hud_verify.tscn
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --rendering-method gl_compatibility --fixed-fps 60 --path . res://tests/ui_hud_verify.tscn -- --capture
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --fixed-fps 60 --path . res://tests/test_runner.tscn
```

Godot 4.0 Compatibility results:

- Tooltip/actions: **125 headless / 143 rendered passed, 0 failed**, clean focused logs. Real bag hover opens two socketed Legendary double-corruption cards, each longer than the logical viewport. Both cards' last lines, independent page/wheel scrolling, keyboard focus, unhover persistence, inert dismiss click, four viewport edges, frozen-pair resize, short-card reset and modal text compatibility pass. Existing corruption callbacks cover warning/cancel, stale UID, changed character, failed save rollback, destruction/gem recovery and no-modifier/single/double survival; sealed Jeweller edits refuse without mutation.
- Exact rendered outputs at **1280×720, 1920×1080, 2560×1440, 1920×1200 and 2560×1080**. Visually inspected all five sizes plus context, irreversible warning, result and Jeweller captures. Eighteen captures and measured bounds are in ignored `tests/screens_out_hud/tooltips_2c/`; engine logs and the full regression log are beside them. The reading fixture retains 824–825 logical pixels of candidate content inside a 704px card at 720 logical height.
- Inventory layout/input **1460 headless**, shared-slot actions/ring targets/vendor/personal/shared stash **455 headless**, HUD **86 headless / 161 rendered**, all passed. Final HUD verbose headless and rendered logs have no ObjectDB/resource-leak warning; one concurrent fixed-fps run produced the previously observed intermittent exit warning. Run rendered pointer checks alone: concurrent input-driving test processes interfered with the OS pointer in one run; the isolated final capture passed.
- Final full integration suite: **47,844 passed, 0 failed**, including **44,639 corruption acceptance checks**. Covers affected item/crafting/locks/stash, tree and gameplay behavior. Expected malformed-save/migration fixture errors and existing legacy exit canvas/RID/resource warnings remain; no script/runtime errors. First run caught suppression of the public tooltip-text API under context menus; corrected and the full suite rerun successfully.

Fixtures use Game.testing. The failed-save case temporarily uses invalid manual slot 0, preventing any real character save, then restores testing/slot state. Presentation preserves serialized character data and combat RNG. Sandbox engine startup stalled before logging; approved external runs supplied the results. Native artwork/fonts, OS DPI, other renderers/hardware and exhaustive arbitrary-length context menus remain outside this stage. **Stop after 2C; Phase 3 requires a new assignment.**
