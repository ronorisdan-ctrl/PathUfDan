# Gameplay HUD — Phase 1

29 October 2026. Production HUD integration; inventory/equipment and other panel interiors remain outside this phase.

## Runtime

The bottom-center combat dock contains reusable resource reliquaries, seven skill wells, life/mana flasks, dodge, XP/class-level information and live status badges. Charcoal reading surfaces, native weathered iron/bronze frames, crimson life and muted violet mana follow the Phase 0 direction. Existing procedural skill/item icons remain in use. Native materials and system/fallback fonts are intentional substitutes for commissioned artwork and packaged typography; no generated full-screen interface or external dependency is required.

The existing HUD controller supplies Player/CharacterData values. Player still owns activation, costs, cooldowns, held input, flasks and dodge. The Skills panel still owns reassignment and its combat restrictions. A successful-cast signal drives the short slot accent, including skills with no cooldown. Hover reads existing skill data and blocked reasons without consuming combat input; panel/context/confirmation tooltips retain priority.

Resource readouts update immediately while fills interpolate toward the newest value. Damage has a brief trailing indicator; low life has a dim rim warning. Cooldown completion, charge use, dodge, hover, selected state, XP and real level changes use bounded accents. Player replacement resets animations and pause freezes them. No animation creates Tweens or consumes gameplay randomness.

The original 1280×720 `canvas_items`/`expand` setup remains. The UI renders at the actual window resolution; the dock fits the logical viewport and scales down for narrow layouts. Native shapes/text stay sharp; pixel icon textures retain nearest filtering locally. No world viewport, camera/input routing, display settings or save format changes were needed.

## Verification

Installed Godot: 4.0.stable.official.92bee43ad. From the project directory:

```powershell
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --path . res://tests/ui_hud_verify.tscn
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --rendering-method gl_compatibility --path . res://tests/ui_hud_verify.tscn -- --capture
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --path . res://tests/test_runner.tscn
```

The focused harness uses test characters and `Game.testing`; it does not save characters/settings. Rendered checks resize only their own borderless test window and position the pointer to verify hover. Godot 4.0 synthetic input requires both `push_input` and, when unhandled, `push_unhandled_input`; headless runs cannot validate the OS pointer. See the [Godot 4.0 Viewport API](https://docs.godotengine.org/en/4.0/classes/class_viewport.html#class-viewport-method-push-input).

Coverage includes all three classes; actual skill activation and Skills-panel reassignment; exact resource values, zero/nonfinite maxima and interrupted healing; cooldown completion; remapped labels; flask recovery/charges and dodge; existing buffs/debuffs; XP rollover; pause/death; mouse click/release and keyboard input; tooltip ownership; expanded-map clearance; and presentation isolation from character data/combat RNG.

Final rendered checks: **161 passed, 0 failed**. Captures assert actual output dimensions at 1280×720, 1920×1080, 2560×1440, 1920×1200, 2560×1080 and 1024×768, with pointer hit tests and tooltip bounds after each resize. The CPU update loop measured approximately 0.16–0.25ms per HUD update on this workstation; this excludes rendering and is not a low-end hardware benchmark. OS DPI changes and other GPU renderers were not exercised.

Final focused headless checks: **86 passed, 0 failed**, with clean output after stopping pooled audio before test shutdown. Final existing gameplay acceptance suite: **2056 passed, 0 failed**. Its negative save tests intentionally log malformed JSON/corrupt-save errors; its final engine shutdown also reports canvas/RID/resource cleanup warnings. The full suite's teardown was not changed in this HUD task. Focused HUD rendered/headless runs have no script/runtime/resource errors or exit warnings.

## Captures

Actual in-engine screenshots are in the ignored `tests/screens_out_hud/` directory:

- [Original HUD at 1080p](../tests/screens_out_hud/before_1920x1080.png) and [new HUD at 1080p](../tests/screens_out_hud/after_1920x1080.png). The original was captured from the committed HUD implementation; dungeon encounter counts vary between runs.
- [1440p](../tests/screens_out_hud/after_2560x1440.png), [ultrawide](../tests/screens_out_hud/after_2560x1080.png) and [4:3](../tests/screens_out_hud/after_1024x768.png).
- [Skill hover](../tests/screens_out_hud/skill_tooltip_1920x1080.png), [low resources/cooldown/statuses/full loadout](../tests/screens_out_hud/combat_states_1920x1080.png), [expanded map](../tests/screens_out_hud/expanded_map_1920x1080.png) and [boss frame](../tests/screens_out_hud/boss_1920x1080.png).

State captures deliberately seed a level-30 test character and freeze world processing for inspection. The HUD still reads the real gameplay objects; none of those fixture values enter normal play or persistence. The baseline image is retained; `--capture` regenerates the new HUD captures only.
