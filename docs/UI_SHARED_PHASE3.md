# UI overhaul — Phase 3 shared rollout

## 3A — passive-tree chrome complete, 5 November 2026

The first small batch of the Phase 3 assignment opts the existing passive-tree panel into the native charcoal/bronze cabinet materials. It adds a serif heading, visible button/field focus, styled search/build-code fields and tag selector, framed tree canvas and inset summary. Materials are derived locally from the existing inventory/HUD palette; UIRoot, BasePanel and other panels keep their themes.

Points/refund/plan information has its own row. Navigation, presets/planner, search and tag chips have separate rows; presets and chips use flow containers. The summary wraps inside its existing scroll area. Both optional sections fit together at the supported minimum. The footer describes the current planner/allocation mode. The tree canvas keeps its existing clipping, input, transforms, node/link/minimap rendering, LOD and geometry under [TREE_UI_CONTRACT](TREE_UI_CONTRACT.md).

Current functionality was rechecked before styling: Phase 5b supplies working presets, plans and build codes. All existing controller methods, allocation/refund/route validation, mastery/socket menus, gem ownership, code import/export and save logic remain authoritative. No data, stat, save or generator changes. Custom tree art and the existing Fit-tree cluster-label collisions remain later work.

## Verification

Godot 4.0 Compatibility, NVIDIA RTX 4070 Ti SUPER:

| Check | Result |
| --- | --- |
| Focused tree chrome, headless | 2,530 passed, 0 failed |
| Focused tree chrome, rendered | 2,540 passed, 0 failed |
| Existing tree acceptance | 843 passed, 0 failed |
| Existing inventory chrome, headless | 1,460 passed, 0 failed |
| Existing HUD, headless | 86 passed, 0 failed |

The focused harness drives viewport input for tag/behaviour filters and clear, search jumping, minimap toggle/jump, wheel zoom, drag pan, planner and ordinary node clicks, apply/clear plan, preset/refund confirmations, mastery/socket menus, import, summary scrolling and close/reopen. More-tag selection is tested through its existing selection signal; export uses the character API without changing the user's clipboard. Confirmation callbacks use the existing UIRoot callable. Layout checks cover control bounds/text, independent hit areas, usable canvas/minimap, wrapped/scrollable summary and visible focus materials. Repeated refresh/reposition preserves character serialization, passive data/geometry and combat RNG.

Ten actual screenshots (expanded summary + code, and Fit tree with those sections closed), measured bounds and final focused/HUD/inventory logs are in ignored `tests/screens_out_hud/tree_3a/`. Visually inspected actual outputs at **1280×720, 1920×1080, 2560×1440, 1920×1200 and 2560×1080**. The 720p expanded tree canvas measures 900×361 logical pixels, with controls and footer accessible. Existing cluster labels/legends inside the custom view can overlap nodes; this stage preserves that renderer.

Final focused headless/rendered, HUD and inventory logs are clean. A concurrent fixed-fps inventory run passed but emitted its known intermittent ObjectDB exit warning; the final isolated inventory run uses its documented timing and is clean. The tree acceptance runner retains its existing newer-version warning, malformed-code decompression errors and legacy exit ObjectDB warning. No new full-gameplay total is claimed for this scoped presentation batch.

Fixtures set `Game.testing = true`; real characters/settings are not saved. Sandbox engine startup exited before logging, so approved external Godot runs were used. Fonts/native artwork remain provisional; target OS DPI, other hardware and final accessibility/artwork are future checks.

```powershell
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --fixed-fps 60 --path . res://tests/ui_tree_chrome_verify.tscn
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --rendering-method gl_compatibility --fixed-fps 60 --path . res://tests/ui_tree_chrome_verify.tscn -- --capture
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --fixed-fps 60 --path . res://tests/tree_only.tscn
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --path . res://tests/ui_inventory_chrome_verify.tscn
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --fixed-fps 60 --path . res://tests/ui_hud_verify.tscn
```

## 3B — character/skills/specialisation chrome complete, 5 November 2026

The existing panels opt into the cabinet theme locally, reusing the 3A heading, bronze borders and native focus materials. Character uses a bounded inset stat list with wrapping names and aligned values. Existing stat source breakdowns and calculations are preserved. Skills uses framed skill cards, square procedural icons, real InputMap hotbar labels, wrapping rune actions and a separate bounded rune-pouch scroll region. The seven-slot controller, swaps, clear action, skill/rune restrictions and context callbacks remain unchanged.

Specialisation uses a three-column grid inside a scroll region, replacing the previous unbounded horizontal row. All six Mage choices fit at 1280×720 with descriptions, capstones and Choose actions readable. Chosen specialisations retain the current custom graph geometry/drawing/hit tests, with an inset frame and a pinned reset action. Choice, allocation, point/capstone rules, confirmation callbacks and gold costs remain owned by the existing controllers and CharacterData. No gameplay, data/save or global theme changes.

### 3B verification

Godot 4.0 Compatibility, NVIDIA RTX 4070 Ti SUPER:

| Check | Result |
| --- | --- |
| Character/skills/specialisation chrome, headless | 3,288 passed, 0 failed |
| Character/skills/specialisation chrome, rendered | 3,316 passed, 0 failed |
| Existing tree chrome, headless | 2,530 passed, 0 failed |
| Existing inventory chrome, headless | 1,460 passed, 0 failed |
| Existing HUD, headless | 86 passed, 0 failed |

The focused harness drives viewport input for hotbar selection, assignment/swap/clear, reopen, rune context/socket/return, locked skill refusal, character source hover and list/pouch scrolling. It verifies real remapped labels, visible native keyboard focus/activation and nearby-enemy guards. All sixteen specialisations exercise choice cancellation/confirmation, node allocation, duplicate refusal, reset cancellation/refund/cost and insufficient-gold refusal. Below-level choices and rune sockets remain visibly disabled. Refresh/reposition preserves character serialization and combat RNG.

Twenty-eight actual screenshots and measured bounds are in ignored `tests/screens_out_hud/character_3b/`. Inspected character, skills, chooser and graph outputs at **1280×720, 1920×1080, 2560×1440, 1920×1200 and 2560×1080**, plus three-class and locked examples. Long character names wrap; full rune-pouch content scrolls independently of the skill list. Native artwork/fonts and custom graph rendering remain provisional; OS DPI/other hardware are not newly verified.

Final focused headless/rendered, tree and inventory logs have no errors or leak warnings. A concurrent HUD run passed its checks but emitted the known intermittent ObjectDB exit warning; the final isolated verbose HUD run has no script/engine errors or leak warning (Godot's verbose StringName shutdown listings remain). Logs are retained beside the evidence; focused logs also live at `tests/screens_out_hud/character_3b_headless.log` and `character_3b_rendered.log`. No broad gameplay rerun was required for this local presentation batch. Fixtures use `Game.testing = true` and do not save real characters/settings. Sandbox engine startup exited before logs; approved external runs succeeded.

```powershell
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --fixed-fps 60 --path . res://tests/ui_character_chrome_verify.tscn
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --rendering-method gl_compatibility --fixed-fps 60 --path . res://tests/ui_character_chrome_verify.tscn -- --capture
```

Use the 3A commands above for the tree/inventory/HUD regressions. Run rendered input harnesses alone.

## 3C — stations/utility chrome complete, 5 November 2026

Merchant, Blacksmith, Jeweller, personal/shared Stash, Pet Keeper, Training Grounds and Dungeon Gate now opt into the shared cabinet theme locally. Existing root/BasePanel/HUD themes and transaction controllers are unchanged. The four inventory-linked stations fit beside the inventory. Readouts and item grids have inset frames; instructions wrap. Blacksmith keeps Craft and materials outside its scroll area, and long affix/operation buttons wrap using Godot 4.0 font measurements. Jeweller has independent item/socket/pouch scrolling and pinned gold/purchase controls. Maximum stash tabs wrap inside a bounded strip.

Pet choices use framed rows, independent list/detail scrolling and pinned upgrade/follow/rename controls. Training uses flowing setup choices and bounded Setup/Result/History areas; expanded history details wrap. Dungeon tiers and details scroll independently above the existing Enter/Reroll actions. Existing selection, callback ownership, guards, costs, seals, RNG and saves remain authoritative. Menus/options and the filter editor are outside this batch.

### 3C verification

Godot 4.0 Compatibility, NVIDIA RTX 4070 Ti SUPER:

| Check | Result |
| --- | --- |
| Stations/utility, headless | 1,732 passed, 0 failed |
| Stations/utility, rendered | 1,774 passed, 0 failed |
| Existing corruption/tooltips/actions, headless | 125 passed, 0 failed |
| Existing shared slots/vendor/stash, headless | 455 passed, 0 failed |
| Existing inventory chrome, headless | 1,460 passed, 0 failed |
| Existing character/skills/spec chrome, headless | 3,288 passed, 0 failed |
| Existing tree chrome, headless | 2,530 passed, 0 failed |
| Existing HUD, headless | 86 passed, 0 failed |

The focused harness drives viewport input for purchase cancellation/confirmation/refusal, refill/stock/rune purchases, bag selection, upgrade cancellation/payment, sealed craft/socket refusals, socket/unsocket/combine/buy, personal/shared stash deposit/withdraw/tab purchases, pet buy/follow/dismiss/rename/upgrade and away restrictions. It also drives training choices/spawn/reset/remove/result/history/clear, locked dungeon selection, modifier reroll and actual dungeon entry. Native keyboard focus/activation, pouch/crafting wheel input and last-row reachability pass. Refresh/reposition preserves character serialization and combat RNG. Previous-stage assertions that expected unstyled stations now check independent themes against the still-unstyled menus.

Forty-one actual screenshots with measured bounds are retained in ignored `tests/screens_out_hud/stations_3c/`, plus review contact sheets derived from those captures. Inspected all seven panels at **1280×720, 1920×1080, 2560×1440, 1920×1200 and 2560×1080**, with additional sealed/away/locked/result/history states. Layout checks cover panel/close/action bounds, text width, independent scroll areas, maximum stash tabs and inventory separation. Random fixture affix counts can vary the number of layout assertions between runs.

Final focused/regression logs in `tests/screens_out_hud/stations_3c_*.log` have no script errors or exit leak warnings. Earlier station/tree runs passed their assertions but emitted the known intermittent ObjectDB exit warning; final isolated verbose runs passed without it. Verbose StringName shutdown listings are engine output. The initial owned stalled test process was stopped and rerun; sandbox startup again exited before logs, so approved external engine runs were used. No full gameplay rerun for this presentation-only batch. Fixtures use `Game.testing = true`; real character/account files are not written. Native artwork/fonts, OS DPI and other hardware remain future checks.

```powershell
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --fixed-fps 60 --path . res://tests/ui_station_chrome_verify.tscn
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --rendering-method gl_compatibility --fixed-fps 60 --path . res://tests/ui_station_chrome_verify.tscn -- --capture
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --fixed-fps 60 --path . res://tests/ui_tooltip_actions_verify.tscn
& 'W:\AI game\Godot_v4.0-stable_win64_console.exe' --headless --fixed-fps 60 --path . res://tests/ui_item_slot_verify.tscn
```

Use the earlier commands for inventory/character/tree/HUD regressions. Run rendered input harnesses alone. Stop after assigned 3C; menus/options require a separate assignment.

## Remaining rollout

3A, 3B and 3C are complete. Suggested next batch: **menus/options**, preserving current panel lifecycle, settings and filter behaviour. Global root/theme rollout and custom node/link/minimap art have not been undertaken. Stop after the assigned 3C batch.
