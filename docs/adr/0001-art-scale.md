# ADR 0001: Art scale (32 px art inside the 16-unit gameplay grid)

- **Status:** accepted by Dan, 29 October 2026 (Phase V0)
- **Applies to:** every sprite sheet, tile, prop and effect added from Phase V0 on

## Context

Today every sprite is a 16x16 ASCII grid in `scripts/gfx/art.gd`. The gameplay grid is
`level.T = 16` world units per cell, and the player camera zooms 2x, so one old art pixel
is a 2x2 block of screen pixels at 1280x720.

The Art Bible ("The Dying Canvas v2") asks for 32x32 tiles, characters about 48 px tall
on a 64x64 canvas, and one art pixel per screen pixel at 1280x720 ("zoom 1x"). The master
prompt v2 asks that the visual work changes no gameplay: ranges, radii, collision, pathing,
timings, RNG order and saves stay identical.

## Options

1. **Literal zoom 1x with 32-unit cells.** Double `T`, every distance and radius in
   `data/*.json` and the code, and set the camera zoom to 1. This changes physics step
   sizes and float results, so the smartbot results would no longer match the baseline,
   and it touches almost every system. Rejected.
2. **Half-scale art in the existing grid (chosen).** Keep `T = 16` and the camera zoom of 2.
   Draw all new art at 2 art pixels per world unit and show it at node scale 0.5.
   With the zoom of 2 that is 1 art pixel = 1 screen pixel, so the picture on screen is
   exactly what the Art Bible describes, and no gameplay number changes.

## Decision

Option 2. All values live in `data/render.json`:

| Key | Value | Meaning |
|---|---|---|
| `world_cell` | 16 | gameplay units per cell (documentation; gameplay keeps `level.T`) |
| `tile_px` | 32 | art pixels per cell |
| `art_scale` | 0.5 | node scale for new art (`Art.ART_SCALE`) |
| `camera_zoom` | 2.0 | player camera zoom (read by `player.gd`) |
| `character_canvas` / `feet_y` | 64x64 / 58 | default sprite frame and pivot |

No script multiplies by 0.5 directly: they use `Art.ART_SCALE`.

## Consequences

- On-screen size per tile is unchanged; detail per tile is 4x (2x per axis).
- **Characters get taller on screen.** A 48 px figure is 24 world units tall, against
  today's 16. Collision radii don't change, so packs of humanoid enemies overlap more
  visually than today. Review once the first real warrior and ghoul are in (V1); if
  needed, draw normal enemies nearer the low end of the Bible's 44-50 px range.
- Old 16 px art and new 32 px art must never share a layer in a finished tier (master
  prompt rule 6). During the transition an actor shows either its old sprite or its new
  sheets, never a mix.
- Pixel-perfect output at other resolutions (1920x1080 gives a 1.5x factor) is a separate
  decision in V6 (integer window presets or a SubViewport with integer scaling).
- Fractional actor positions can make a sprite shimmer by one pixel while moving. If that
  shows up with real art, snap the sheet sprite's draw position to the art grid (visual
  only) rather than moving the actor.
