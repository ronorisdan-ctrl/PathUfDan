# Path of Dan loot filter: design and merge guide

Status: NEW FILES ONLY. Nothing here edits your game. It was written without access to the game source (only the three notes files), so every game-facing assumption is listed in section 5. None of the GDScript has been run: the sandbox has no Godot. Only the JSON presets were validated (`python tools/validate_loot_filters.py`, all four OK).

## 1. What the industry does

- **Path of Exile / PoE 2 (text file).** Ordered `Show`/`Hide` blocks, each with conditions (Class, BaseType, Rarity, ItemLevel, Sockets...) and actions (SetTextColor, SetFontSize, PlayAlertSound, PlayEffect beam, MinimapIcon). The first matching block wins unless it says `Continue`. An empty block matches everything, so a final `Hide` hides whatever was not shown. Hidden items can still be revealed by holding Alt. Players asked for level-aware hiding (item level vs character level) and the syntax lacks it.
- **Last Epoch (in-game editor).** Shift+F opens a rule editor. Each rule has conditions (affix, class requirement, level, rarity, item type) that must all match, and an action of show, hide or recolour. Rules are ordered by priority, filters can be imported, exported and duplicated, and there is a cap on rule count. Players ask most for copy/paste of rules and saved conditions, which is why this design has duplicate and JSON import/export.
- **Common ground:** ordered rules, AND conditions, show/hide/recolour/sound/beam/minimap actions, a reveal-hidden key, shareable files, built-in presets.

## 2. What fits Path of Dan

Facts from the audit: five rarities (common to legendary), 129 bases, 52 affixes, sockets 0-3 by slot, gems, runes, charms, a rarity-only filter, items need F or a click to pick up, 63% of trash drops are common. A real filter is therefore high value (audit jobs 07 and 08).

Included: rarity range, kind, slot, name/base text, item level, **item level minus your level** (the PoE gap), sockets, affix lists with "at least N", total affix count, "is upgrade", dungeon tier. Actions: show / minimal / hide, label colour, size, beam, sound id, minimap icon, continue.

Deliberately left out for now: auto-pickup (the audit's job 07 covers it; a filter result can feed it later), class-usable weapons (needs game knowledge), per-run modifiers.

Safety net: a legendary can never be hidden unless the filter turns the safety off (`safety.never_hide_min_rarity`).

**Hidden means not drawn.** A hidden item gets no sprite, label, beam, light, sound or minimap icon, and cannot be clicked, picked up with F, or auto-picked-up. `evaluate()` returns `drawn` and `clickable` (both false when hidden) so the caller has one flag to check. While Alt is held, hidden items are drawn and clickable again (`allow_reveal_key = true`; set false to disable). Releasing Alt hides them again.

**Per character.** Call `LootFilter.set_character(id)` whenever a character is loaded or created; use a stable id such as the save slot. Each character gets its own folder `user://loot_filters/<id>/` with its own saved filters and its own remembered active filter. A new character starts on the `default` preset. Presets are shared by everyone and cannot be overwritten. Moving filters between characters: Export (copy), switch character, Import (paste).

## 3. Files

| File | Purpose |
|---|---|
| `scripts/systems/loot_filter.gd` | Engine, autoload `LootFilter`: evaluate, validate, load, atomic save with .bak, import/export |
| `scripts/ui/loot_filter_panel.gd` | In-game editor built in code; dry run against sample items |
| `data/loot_filters/*.json` | Presets: default (Balanced), show_all, rare_plus, strict |
| `tests/test_loot_filter.gd` | Acceptance checks, standalone or called from test_runner |
| `tools/validate_loot_filters.py` | Schema check for hand-edited JSON |

User filters live in `user://loot_filters/<character>/NAME.json` (the panel shows the full path after saving). Preset names are reserved so a preset can always be restored.

## 4. JSON format (version 1)

```json
{ "version": 1, "name": "My filter", "default": "show",
  "safety": { "never_hide_min_rarity": "legendary" },
  "rules": [ {
    "name": "Good rings", "enabled": true,
    "conditions": { "rarity_min": "rare", "slot": ["ring"], "affix_any": ["life"], "ilvl_vs_player_min": -3 },
    "actions": { "visibility": "show", "color": "#ffd84a", "size": "large",
      "beam": "#ffd84a", "sound": "drop_rare",
      "minimap": { "shape": "diamond", "color": "#ffd84a" }, "continue": false } } ] }
```

Conditions (all must match): `rarity_min`, `rarity_max`, `kind`, `slot`, `name_contains`, `ilvl_min/max`, `ilvl_vs_player_min/max`, `sockets_min`, `affix_any` + `affix_min_matches`, `affix_count_min`, `is_upgrade`, `tier_min/max`. Actions: `visibility` (show, minimal, hide), `color`, `size` (small, normal, large, huge), `beam` (colour or "none"), `sound` (id or "none"), `minimap` (object or "none"), `continue`. Rules run top to bottom; with `continue`, later rules override the fields they set.

`evaluate(item, ctx)` returns `{visibility, visible, color, font_px, beam, sound, minimap, rule, safety_override}`. `color` and `beam` are `null` when unset and `font_px` is -1 when unset, so the caller keeps its default.

## 5. Assumptions to check when merging (all in `describe()` unless noted)

1. Item dictionary keys: `rarity` (string or int 0-4), `kind`, `slot` (ids in `LootFilter.SLOTS`), `ilvl`, `sockets` (int or array), `affixes` (array of `{id}` or ids), `base`, `name`. Adjust `describe()` only.
2. Gems, runes and materials may not drop as filterable items. If they are pickups rather than item dictionaries, give them `kind` there or drop those rules.
3. Sound ids `drop_legendary`, `drop_epic`, `drop_rare` do not exist yet. Map them to real `Sfx` ids, or add them with audit job 05, then set `LootFilter.known_sounds = Sfx.<list>` so the validator checks ids.
4. Rarity names are taken from the audit's loot table; confirm the strings.
5. Panel base class and theme are generic (PanelContainer, code-built). Dropping it into your UI layer and styling it is on the merge list.
6. GDScript targets Godot 4.0 stable. Places most likely to need a tweak: `HFlowContainer`, `ItemList.item_selected` argument, lambdas in the test, `DirAccess.rename_absolute` overwriting on Windows (the code removes the old file first).

## 6. Merge steps (when you are ready)

1. Copy the folders into the project. Add autoload `LootFilter` = `res://scripts/systems/loot_filter.gd`. Make sure the export filter includes `*.json`.
2. In the code that spawns a ground item, call `LootFilter.evaluate(item, {"player_level": ..., "tier": ...})`. Apply `visible`, `color`, `font_px`; spawn a beam if `beam != null`; `Sfx.play(sound)` if not empty; draw the minimap icon if `minimap` is not empty. Skip everything for items where `drawn` is false: do not create the sprite or label, and exclude them from click, F pickup and auto-pickup.
3. Connect `LootFilter.filter_changed` and `LootFilter.reveal_changed` to re-evaluate the items on the ground (a newly hidden item must be removed from view and from click/pickup, a newly shown one drawn).
3b. Call `LootFilter.set_character(slot_id)` from the code that loads a character. Today you have one slot, so pass a constant; when job 09 (multiple slots) lands, pass the slot.
4. Set `LootFilter.upgrade_checker` to the comparison-tooltip logic, and keep `LootFilter.player_level` updated.
5. Add an "Item filter" button (hub and pause menu) that opens the panel.
6. Migrate the old rarity-only setting: map it to a preset (for example min Uncommon to `rare_plus`-style rules).
7. Add `test_loot_filter.gd` to the test runner and run it.

## 7. Decisions made

- Hidden items are not drawn and not clickable.
- Filters are saved per character; a new character starts on the Balanced (`default`) preset.
- Holding Alt reveals hidden items.

## 8. Open questions

None outstanding.
