# UI visual overhaul — Phase 0 review

Original audit: 29 October 2026. Focused refresh: **4 November 2026**, after the corruption system and ongoing passive-tree expansion. Phase 1 gameplay HUD integration is complete; see [Phase 1 evidence](UI_GAMEPLAY_HUD_PHASE1.md). Subsequent implementation: **Phase 2A/2B/2C complete** (5 November); see [Phase 2 evidence](UI_INVENTORY_PHASE2.md). The refresh findings below describe the pre-implementation baseline, including the tooltip overflow resolved in 2C.

## Audit

| Area | Current implementation / implication |
| --- | --- |
| Engine / display | Installed Godot 4.0.stable.official.92bee43ad; project targets 4.0. Logical base 1280×720, `canvas_items`, `expand`, global nearest filtering. Keep these settings initially. |
| Scenes / ownership | `scenes/main.tscn` delegates construction to `scripts/main.gd`. World is a Node2D; persistent UIRoot is CanvasLayer 10; menus use layer 20. No existing SubViewport. Most UI is script-built, rather than authored Control scenes. |
| Shared UI | UIRoot owns 16 panel types, hotkeys, modal/context/confirmation state, paired tooltips and toasts. BasePanel supplies title, close button and placement. Reuse both. Menus independently call UIKit's theme factory. |
| Theme / fonts | Runtime UIRoot still uses UIKit's code-built Theme, fallback font and 14px default. Helpers/panels retain local overrides and empty Button focus styling. Phase 0 added a scoped prototype `.tres`; Phase 1 added HUD tokens/components. Root/menu theme rollout and packaged production fonts remain pending. |
| HUD | Phase 1 now uses reusable native life/mana reliquaries, action wells, XP/status presentation and matching objective/map/boss frames, supplied by the existing HUD controller. Preserve the completed dock, input pass-through and tooltip ownership; do not restart its implementation from the original audit. |
| Inventory / shared slots | Still 40 bag cells, 11 equipment cells, right-side panel, fixed equipment coordinates and 8-column grid. ItemSlot is shared with vendor/stash. Rarity, restriction tint, upgrade, price, player lock and 100%-corruption markers coexist. Partial corruption is shown in tooltip text/bars, not as a progress bar on every cell. |
| Corruption / crafting | Loot supplies ordinary and Legendary sections plus separate corrupted prefix/suffix text, tiers/fixed labels and sealed status. Blacksmith owns a drawn percentage bar, scrolling item/operations/preview/results, pinned action/materials and irreversible Corrupt Item confirmation. Jeweller scrolls the full item description and disables sealed-item gem edits. See the refresh below. |
| Passive tree | Expansion now includes mastery choices, tree gem sockets/radius boosts, exclusive nodes, migration refund states, filters/search navigation, zoom LOD, minimap and summary. Preserve the current [tree UI contract](TREE_UI_CONTRACT.md); its custom rendering belongs to a later stage. |
| Other panels | BasePanel is still shared by character, skills, specialisation, stations and menus. The original options/UI-scale finding is unchanged; unrelated panel functionality was not re-audited in this refresh. |
| Textures / prior study | Art autoload bakes ASCII/palette sprites and item icons at startup. No established UI asset directory or painted panel texture set. Existing Dying Canvas inventory preview has its own skin, local fixtures, custom frames and installed serif headings; preserve it as a separate visual reference. It is not production inventory logic. |

Limitations: fixed minimum widths and placements can overlap; the two-tooltip path does not fully clamp its second panel; smaller 10–11px marker/hint text will need legibility review. Theme overrides and direct `draw_*` calls limit inherited styling. Existing preview uniformly scales a fixed canvas; future production panels should use anchors and containers.

## Focused refresh — Phase 2 preparation, 4 November 2026

### Current ownership and preservation requirements

| Surface / owner | Phase 2 must preserve |
| --- | --- |
| `InventoryPanel` / `ItemSlot` | Existing slot signals, double-click equip, both ring action targets, station-specific single-click selection, Shift actions, locks, sorting and transfers. Slot corners currently reserve top-left for upgrade, top-right for player lock, bottom-left for price and bottom-right for the 100% seal. |
| `Loot.tooltip` / `corrupted_implicit_text` / `CorruptionRules` | Base implicits, normal/fixed affixes, Legendary effect/flavour, sockets/gems, requirements, corrupted prefix/suffix with their actual effects, quarantine warning, percentage/bar and FINAL restrictions. Reuse these data/text paths instead of rebuilding affix or stat logic in views. |
| `UIRoot` | Paired tooltip lifecycle and existing `CharacterData.preview_final` comparisons, including current passive/mastery/tree-gem effects. The hover comparison currently defaults rings to ring1; the Ring 2 action exists separately. Verify both existing equip targets without silently changing comparison semantics. |
| `BlacksmithPanel` | Dedicated `corruption_bar.gd` readout and events-remaining note; operation cost/availability/reasons; scroll-to-preview/result; pinned Craft/Corrupt Item button and materials including Abyssal Brands. The selected-item text deliberately calls `Loot.tooltip(..., false)` to avoid duplicating the percentage line, while keeping corrupted implicits. |
| `CharacterData.corrupt_item` / Blacksmith callback | UID ownership, refusal checks, action ID/replay protection, isolated crafting RNG, atomic payment/save/rollback and gem recovery on destruction. Styling must continue to call the existing transaction. Handle stale selection or changed character, failure, destruction and survival through its existing result. |
| `JewellerPanel` | Existing description/pouch scroll regions, socket selection and sealed-item refusal tooltips. Item sockets and passive-tree sockets are different interactions; tree gems return through their own controller. |

Corruption percentage, player lock and corrupted implicits are independent meanings. An item can reach 100% through ordinary crafting with **no** corrupted implicit; Corrupt Item survivors also reach 100% with zero, one or two implicits. Do not use the seal marker to imply that special affixes exist, or make the protective player padlock represent the seal. Current red/amber percentage semantics, magenta corruption affix semantics and orange Legendary semantics must remain distinguishable with text as well as colour.

Ordinary rolling crafts currently retain their configured 60% chance of +25 percentage points. The dedicated Corrupt Item action currently costs one Abyssal Brand and has destruction/no-modifier/single/double outcomes of 15/25/56/4%; every survivor is sealed. At 100%, all crafting and item socket/gem editing are blocked. Equipping, selling and ordinary salvage remain available subject to their existing restrictions. Keep values and warnings sourced from existing helpers/configuration; this audit does not rebalance them. Detailed rules: [corruption system](CORRUPTION_SYSTEM.md).

### Fresh layout evidence and findings

Rendered the existing corruption capture scene and a local audit-only capture harness on Godot 4.0, Compatibility renderer. `Game.testing = true` prevents character/settings saves. Final capture stderr logs are empty. The audit harness uses a full 40-cell bag and the real production panels, plus a level-60 ranger with an equipped comparison item and an upgraded, player-locked, socketed Widowmaker carrying two corrupted implicits. The fixture is for layout coverage, not a balance/build recommendation.

Evidence is retained locally in ignored `tests/screens_out_hud/ui_audit_2026_11_04/`: `corruption/` (16 state captures), `layout/` (17 captures and `bounds.json`), capture logs and `audit_capture.{gd,tscn}`. Inspected key item/comparison, station, confirmation/result, vendor and tree captures. Bounds measurements cover all five sizes below; they are observations of these fixtures, not a general fit certification.

| Actual output | Logical UI extent | Double-implicit main tooltip | Sampled station/inventory bounds |
| --- | --- | --- | --- |
| 1280×720 | 1280×720 | 801 logical px tall; clipped | Blacksmith, Jeweller and inventory fit |
| 1920×1080 | 1280×720 | 801 logical px tall; clipped | Blacksmith, Jeweller and inventory fit |
| 2560×1440 | 1280×720 | 801 logical px tall; clipped | Blacksmith, Jeweller and inventory fit |
| 1920×1200 | 1280×800 | 801 logical px tall; clipped | Blacksmith, Jeweller and inventory fit |
| 2560×1080 | 1706×720 | 801 logical px tall; clipped | Blacksmith, Jeweller and inventory fit |

- **Confirmed Phase 2 defect: tall hover cards lose content.** The sample main tooltip exceeds the logical viewport, hiding its lower lines. The equipped comparison card is 481 logical px tall. Increasing physical resolution at the same aspect ratio does not provide more logical height under the current stretch settings. `UIRoot._place_tooltips` clamps position only; it has no height limit or overflow interaction. The second card shares the main card's y without independent vertical clamping, and the pair is not constrained as one group horizontally. The latter are source-level risks; these captures establish the main card's vertical overflow.
- **Required 2C decision:** provide bounded cards and an explicit way to read overflow for both items; merely moving the cards or shrinking text is insufficient. Preserve ordinary hover/combat input behaviour and deliberately scope input consumed by any overflow interaction. Retain complete affix/effect text and comparison calculations.
- **Limited vertical budget:** the current populated inventory measures 430×649 logical px after material wrapping, despite its declared 430×560 minimum. The sampled Blacksmith measures 440×652 at 720 logical height; its action/materials remain visible. Larger body fonts, padding or new ornaments must be budgeted before rollout. The bar/result can scroll out of view today; this is not a missing bar. Keep the pinned action accessible and avoid making a long result push it offscreen.
- **Slot marker baseline:** player lock and seal are separate corners; a sealed, locked, upgraded item remains readable in the sample. Vendor prices occupy the other lower corner and are suppressed on player-locked inventory items. Test both a locked item and an unlocked sealed/upgraded/priced item before accepting a new skin. Partial percentage/implicit detail remains in the tooltip/selected-item readout unless a later task explicitly adds another slot indicator.
- **Jeweller:** the sample long item text is intentionally inside a short scroll area; sealed gem buttons are disabled. Preserve a readable refusal and access to the entire description, rather than expanding the text until it displaces pouch/actions.
- **Passive tree baseline:** at 1280×720 the sampled full panel, search and filter controls fit. At Fit tree zoom, several cluster labels overlap; record this for later tree visuals/readability work, without moving generator-owned nodes in an inventory stage.

The existing corruption screenshot scene manually positions its tooltip cards for content captures. Those images do **not** validate natural hover placement. The local audit harness additionally uses the actual bag-cell pointer position and `UIRoot._place_tooltips`, records bounds, and restores the OS pointer afterwards. It does not test every pointer edge, both ring comparisons, all item families, persistence or gameplay performance.

### Phase 2 state coverage

| Cases | Acceptance during the owning implementation stage |
| --- | --- |
| Clean 0%; intermediate 25/50/75%; legacy/non-step value such as 37%; sealed 100% without implicits | Exact percentage and current restrictions remain visible; no rounded/derived value replaces the stored percentage. Step ticks/events remaining come from CorruptionRules. |
| Prefix only; suffix only; double; fixed/signature/mythic effect; quarantined inactive record | Preserve side, tier or fixed label, complete effects and inactive warning. Text fits or is reachable through explicit overflow handling. |
| Legendary + double + sockets/gems + long name/flavour | Legendary and corruption sections remain distinct; both complete hover cards and selected-item descriptions are readable. |
| Empty/occupied, selected, restricted, locked, upgraded, sealed and vendor-priced cells | All 40 bag and 11 equipment cells retain hit areas and independent markers. Verify reuse in vendor/personal/shared stash and station selection. |
| No selection; eligible craft; insufficient Brand/materials; equipped/locked/sealed refusal | Correct labels/reasons and action availability. Readability and focus persist through scrolling, resizing and theme changes. |
| Irreversible confirmation: cancel/confirm; destruction; no modifier; single; double; transaction failure | Existing outcomes/resources/gems remain authoritative; confirmation input stays owned by UIRoot, result is reachable, stale selection is cleared/refreshed, and the action cannot be replayed by new presentation code. |
| Comparisons/equip actions for both rings; requirements; station hand-off; sell/salvage/destroy; stash round trip | Preserve existing stat previews, callbacks, ownership and safeguards. Include tree socket/mastery effects in representative comparison fixtures. |

### Ongoing passive-tree dependency

The existing [tree UI contract](TREE_UI_CONTRACT.md) is the boundary for later styling. Preserve `node_state`, `node_overlays`, `lod`, geometry/transforms, filters, search navigation, minimap and summary. Preserve mastery choice menus, socket gem menus/radius/boost states, exclusions, allocation/routes/refunds and migration notices. Planned state is currently reserved for the future planner; do not imply the planner is already complete.

Phase 2 may proceed while tree functionality evolves: inventory uses current CharacterData/Loot APIs, not a frozen copy of the tree schema. Avoid global Theme/BasePanel/UIRoot changes spilling into tree controls, menus or tooltips. Smoke-check those consumers whenever a shared resource changes. Custom node/link/minimap art and tree layout/readability fixes belong to a separately assigned later stage. Tree node ids/positions/links remain generator-owned. The passive expansion's phase numbers and the contract's V5 art label are separate from this UI overhaul's Phase 2/3 numbering.

### Verification plan for implementation

For each small stage below, check its affected behaviour and capture the same five resolutions; include tooltip pointer edges and overflow access in 2C. Use existing `tests/items_crafting_only.tscn` for affected item/crafting/lock/stash paths and `tests/corruption_system.tscn` for changes touching corruption presentation bindings/transactions. Use `tests/tree_only.tscn` when shared work affects tree interaction or comparisons. A shared UIRoot/theme change also needs the existing focused HUD checks for input and tooltip ownership. Run broader gameplay regression at final Phase 2 integration or when a change crosses gameplay/stat/persistence boundaries.

No gameplay acceptance suite was rerun for this documentation/capture-only stage; prior suite totals in the handoff are historical, not a new certification. No production UI, data, stats, save schema or world rendering was changed. Small-window 960×540 captures are stress evidence only; 1280×720 remains the planned minimum. DPI, other renderers/hardware, final fonts/art and exhaustive state coverage remain implementation/release checks.

Local reproduction from the project root (substitute the installed Godot executable):

```text
godot --rendering-method gl_compatibility --fixed-fps 60 --path . res://tests/screens_corruption.tscn -- res://tests/screens_out_hud/ui_audit_2026_11_04/corruption
godot --rendering-method gl_compatibility --fixed-fps 60 --path . res://tests/screens_out_hud/ui_audit_2026_11_04/audit_capture.tscn
```

The second command uses the retained local, ignored capture harness. Its fixture recipe and measured findings are recorded above so the audit remains useful without generated evidence. Sandbox engine launches exited before logging; final captures used approved out-of-sandbox runs. **Preparation complete; next suggested assignment is 2A only.**

## Recommended architecture

Keep the existing world, CanvasLayers, controllers and event connections. Retain the 1280×720 logical layout; use anchors for HUD edges and containers for internal layout. Support 1280×720 minimum, 1080p, 1440p, 16:10 and ultrawide, with a later explicit UI-scale setting tested for panel fit.

The existing `canvas_items` mode renders 2D at the target resolution, making smooth UI possible above nearest-filtered sprites. It does not enforce a fixed world pixel grid. Keep nearest filtering for world/icons and use linear filtering locally for painted UI. A CanvasLayer separates camera transforms, not render resolution. See [Godot 4.0 multiple resolutions](https://docs.godotengine.org/en/4.0/tutorials/rendering/multiple_resolutions.html).

**No SubViewport for initial integration.** If review requires a strictly low-resolution world, separately trial `SubViewport(World + Camera2D) → nearest ViewportTexture → main window`, with UIRoot outside that viewport. This needs coordinate/input forwarding, aspect and camera tests, world-space label decisions, pause checks and an extra render target. A [SubViewport](https://docs.godotengine.org/en/4.0/classes/class_subviewport.html) needs a display container or ViewportTexture. Do not move the world during this phase.

Use one editor-visible `assets/ui/themes/decaying_oil.tres`, assigned to the UIRoot Control and menu branch during a future approved stage. Scope it locally while prototyping. [Godot Themes](https://docs.godotengine.org/en/4.0/classes/class_theme.html) support inherited styles and type variations. Keep UIKit's widget builders; later make its theme factory return the shared resource. Remove local overrides only as each owning view migrates. Custom drawing should fetch semantic theme values rather than duplicate hex strings.

Small view scenes take display values or emit UI intent; their existing controllers retain calculations and actions. No new data model, UI framework or dependencies.

## Visual system / asset brief

Charcoal reading surfaces, warm ivory text, tarnished bronze edges, weathered iron recesses, aged leather backing and sparing stone/gothic accents. Keep wear at edges and shadows; leave reading areas calm. Reserve brighter gold for emphasis and interaction. Keep existing rarity and combat semantics.

| Token / variation | Proposed treatment |
| --- | --- |
| Palette | Ink `#101310`, surface `#191815`, bronze edge `#66583b`, gold `#b29a65`, ivory `#e2dcc7`, muted `#9c998a`; subdued red/blue resources. Retain Data rarity colours. |
| Fonts | Packaged licensed serif headings, readable sans body and numeric readouts. Logical sizes: headings 24–28, section 18, body 16, secondary 14. Current SystemFont serif and engine fallback are temporary. Include licence and glyph coverage checks before shipping. |
| Spacing | 4px base unit; 8/12px widget gaps, 16/20px panel padding; 44–48px minimum interactive cells. Borders and ornaments must not cover markers. |
| Panel / inset | `PanelContainer` variations for window, leather inset, iron well and tooltip. Start with StyleBoxFlat; substitute StyleBoxTexture nine-slice resources after material approval, preserving padding. |
| Button | Normal, hover, pressed, disabled and visible ivory keyboard focus; later primary, quiet and destructive variations. States need shape/border changes as well as colour. |
| EquipmentSlot | Native Button-backed view or themed existing ItemSlot drawing; empty/occupied, hover/focus, selected, restricted, locked, corrupted, priced. Separate overlays retain independent meaning and hit area. Do not change existing signals in a skin pass. |
| Tooltip | Dense opaque surface; title, rarity/type, requirements, stats, comparison and corruption sections; paired cards clamped together to viewport. Preserve BBCode/stat generation. |
| HUD | Phase 1 has delivered native life/mana reliquaries, XP track, action wells, flask charges, status badges, minimap frame and boss/poise. Preserve its silhouette/components; final replaceable materials and packaged fonts remain future art work. |

First art batch after approval: one bronze nine-slice frame, one leather/charcoal inset, button state set, iron slot well, subtle divider/corner ornaments, resource frame/fills and packaged fonts. Then empty-slot glyphs, lock/corruption/upgrade overlays and HUD accents. Keep existing procedural item/skill icons until a separate icon batch is commissioned. Author raster materials at 2× logical size, document nine-slice margins, use lossless alpha, and inspect downsampling at 720p. No asset generation is required for this prototype.

Proposed layout and naming:

```text
assets/ui/themes/decaying_oil.tres
assets/ui/fonts/{body_regular,heading_regular}.{ttf,otf} + LICENSE.txt
assets/ui/textures/{panels,buttons,slots,hud,ornaments}/
    panel_bronze_9slice.png   button_bronze_hover.png   slot_iron_empty.png
assets/ui/icons/{equipment,status}/
scenes/ui/components/<component>.tscn
scripts/ui/components/<component>.gd
scripts/ui/preview/ + tests/ui_<study>_preview.tscn
```

Use lowercase snake_case, semantic material/state suffixes, explicit `_9slice` where applicable, no `final_v2` names. Record intended logical dimensions, source scale and margins alongside each texture batch. Existing world art/data paths remain valid.

## Preservation and risks

Keep UIRoot panel lifecycle, station coexistence, pause/death handling, input release, context actions, confirmations, tooltip comparisons and Events wiring. Preserve equip restrictions, ring targets, double-click equip, lock/destruction protection, vendor/stash transfers, gem reclamation, crafting/socket selection and corruption rules. Stats and comparisons continue through CharacterData/Loot; passive allocation and pan/zoom/search remain owned by the current passive controllers.

Highest risks are broad theme changes spilling into every panel, new HUD Controls consuming combat clicks, clipped text at larger fonts, and losing tiny status overlays. Integrate one view at a time; decorative HUD Controls ignore pointer input. Do not change world filtering globally. Fonts need deterministic packaged files; system fonts vary across machines. Godot 4.0 compatibility is required; avoid relying on later integer-scaling settings. SubViewport routing and full gameplay regressions are deferred because this phase changes no runtime wiring.

## Independently testable implementation order

- [x] **0A:** Audit and architecture/asset proposal; preserve prior inventory study.
- [x] **0B:** Isolated native Theme + resource-meter prototype; verify bounds/input/layout and capture desktop sizes.
- [x] **Phase 0 review gate superseded:** user's Phase 1 assignment authorized HUD production integration. Final font/art packaging remains future work.
- [x] **1A — HUD resources:** delivered and verified in Phase 1; see the Phase 1 document/handoff.
- [x] **1B — HUD actions:** delivered and verified, preserving activation, cooldowns, costs, charges, remapped labels and tooltip priority.
- [x] **1C — HUD remainder:** delivered and verified, including XP/statuses, objectives, minimap, boss/poise and resize/input integration.
- [x] **Phase 2 preparation — focused audit refresh:** current corruption/item/tree ownership, state matrix, measured layout baseline and preservation risks recorded above. No production Phase 2 work started.
- [x] **2A — Inventory chrome:** inventory-local native frame/title/insets, all 40+11 cells, occupied count and wrapped materials including Brands. Rendered beside Blacksmith/Jeweller/vendor/stash at all five sizes; populated fixture 430×690, large-currency stress 430×708. Station controls remain reachable. HUD/root/tree themes unchanged; focused HUD checks pass. [Implementation and verification](UI_INVENTORY_PHASE2.md).
- [x] **2B — Shared slot:** native recessed wells, rarity rims, hover/selection and restriction cue on the existing ItemSlot. Independent upgrade/lock/price/seal corners, signals/hit areas and station/vendor/personal/shared-stash controllers preserved. Sixteen marker combinations across all rarities, real viewport input, both ring targets and five rendered sizes verified; no special implicits inferred from percentage. [Implementation and verification](UI_INVENTORY_PHASE2.md).
- [x] **2C — Tooltips/actions:** bounded paired cards with explicit F4 reading/independent scrolling; complete source text/comparisons and existing ring targets retained. Scoped context/confirmation styling and measured placement; long warnings scroll above pinned actions. Existing irreversible/cancel/results/refusal/stale/failed-save callbacks, Jeweller seals and stash transfers verified. Focused **125 headless / 143 rendered**, full integration **47,844/0**; [evidence and controls](UI_INVENTORY_PHASE2.md).
- [ ] **3 — Shared rollout:** remaining panels/menus in small batches; custom nodes later under TREE_UI_CONTRACT. Preserve allocation/masteries/gems, presets/planner/build codes, filters/search/navigation/minimap/LOD and generator geometry.
- [x] **3A — Passive-tree chrome:** scoped cabinet theme, heading/fields/focus, separate responsive control rows, framed canvas and wrapped scrolling summary. Current tree functions rechecked; custom drawing/geometry/controllers preserved. **2530 headless / 2540 rendered**, tree **843**, inventory **1460**, HUD **86**, all passed. Five exact output sizes inspected. [Evidence and remaining batches](UI_SHARED_PHASE3.md).
- [x] **3B — Character/skills/specialisation chrome:** scoped cabinet materials, readable stat rows, framed skill/rune controls and a bounded three-column specialisation chooser. Existing stats, reassignment, runes, allocation and reset rules preserved; all three classes/all sixteen specialisations and five rendered sizes verified. [Implementation and verification](UI_SHARED_PHASE3.md).
- [x] **3C — Stations/utility chrome:** seven station panels opt into cabinet materials; framed item grids/readouts, bounded scrolling, wrapping choices and reachable actions. Existing crafting/corruption, gems, merchant/stash, pets, training and dungeon controllers preserved. **1732 headless / 1774 rendered**, focused regressions passed; five exact output sizes inspected. [Implementation and verification](UI_SHARED_PHASE3.md).
- [ ] **Next shared batch — Menus/options:** await assignment; global theme rollout and custom tree art remain separate.
- [ ] **4 — Art/accessibility pass:** replace approved placeholders, test focus/contrast/UI scale and DPI on target hardware; broader gameplay suite before release.

## Prototype and verification

Open `tests/ui_phase0_preview.tscn` in Godot and press F6. **Cycle sample** switches normal/depleted/empty/full life and mana; Tab/Enter demonstrate focus and activation; hover the meter for its native tooltip. This is one component and a small review harness. Fonts, flat material blocks and the rectangular resource silhouette are provisional.

The reusable meter is a PanelContainer with HBox/VBox layout, Labels and ProgressBar, on the same layer-10 pattern as the runtime UI. Its `present()` method accepts values only and has no gameplay imports, signals, stat computation or persistence calls. The default theme can be overridden on the instance. Normal project autoloads still initialise/read settings; the preview creates no character and does not invoke save flows. Window size changes affect this preview process only.

```text
godot --headless --path . res://tests/ui_phase0_preview.tscn -- --verify
godot --rendering-method gl_compatibility --path . res://tests/ui_phase0_preview.tscn -- --verify --capture
```

Verified with installed Godot 4.0: **25 headless checks and 30 rendered checks passed**, including bounds/nonfinite values, keyboard activation, life/mana reuse, tooltips, minimum/readout fit and character/world/combat-RNG isolation. Rendered captures: 1280×720, 1920×1080, 2560×1440, 1920×1200 and 2560×1080, in ignored `tests/screens_out_phase0/`. Layout inspection is recorded in the handoff. These checks establish the component approach; they do not validate final painted assets, live HUD integration, OS DPI or a SubViewport design. No full gameplay suite was needed for this isolated phase.
