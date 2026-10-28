# The Dying Canvas — interactive inventory slice

28 October 2026. A standalone Godot 4.0 preview of the UI direction, using local sample items.

## Open

Double-click `Preview inventory.cmd` in this project folder. Alternatively, open `tests/ui_inventory_preview.tscn` in Godot and press F6. The launcher expects the existing Godot 4.0 executable in `W:/AI game`.

The preview opens at 1280×720. Its window setting applies to this process only. It does not create a character or write saves/settings. Close the window when finished.

## Try

1. Hover the first sword in the bag. Its comparison shows **+14 weapon damage** and **−5 Strength** against the equipped sword.
2. Click the sword to pin it. Hover the helmet, then move into empty space: the sword comparison returns. The selected cell has an inset ivory border and a small check mark; hover has an outer gold border.
3. Click **Equip in preview**. The old sword moves into the bag; the sample summary changes from 54 to 68 damage and from 58 to 53 Strength.
4. Select the ring. Switch **Compare: Ring I / Ring II** to inspect either equipped ring.
5. Select the orange chest piece. It can be inspected, but equipping is disabled because it requires level 24.
6. Select a gem or rune. Materials have no equipment comparison or equip action.
7. Try **Sort by rarity**, **Bag: rare+**, **Clear selection**, and **Reset sample**. Filtering is a local bag-view demonstration, not the game's loot-filter editor.
8. Use Tab or directional keys to focus controls, Enter/Space to activate, and Escape to clear selection. Focus is shown with dashed ivory edges.

## Art and scope

Charcoal reading surfaces, warm ivory text, tarnished-gold cabinet moulding and localized pigment wear establish the initial skin. All forty uniform bag cells and eleven equipment slots are present. The background and icons reuse current procedural game art. Heading text uses an installed serif font with a fallback; body text uses Godot's existing font. Custom item illustrations, a licensed packaged production font, painted panel textures and the final HUD art remain future art work.

The equipment layout is a compact labelled cabinet arrangement for testing states. It does not yet reproduce the illustrated paper-doll composition. The bottom strip is a visual HUD reference; its skills/resources do not operate. The item comparison numbers are direct fixture deltas, not a replacement for the game's full stat calculations. No drag/drop, vendor, crafting or save integration is included in this assigned slice.

All visual code and JSON fixtures are local to the preview. The live inventory, item slot, theme, gameplay and main scene are unchanged.

## Verify and capture

Run from this project with Godot 4.0:

```text
godot --headless --path . res://tests/ui_inventory_preview.tscn -- --verify
godot --rendering-method gl_compatibility --path . res://tests/screens_inventory_preview.tscn
```

The first command runs focused input/state checks and exits. The second checks a rendered window, saves five screenshots to `tests/screens_out_inventory_preview/`, and exits. Pass/fail is printed as `UI inventory preview: N passed, N failed`. Screenshots include idle, hover comparison, selected, equipped and unavailable states. Generated test logs/screenshots are ignored by Git.
