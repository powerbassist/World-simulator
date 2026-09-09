# Map platform model — V3.1

**2026-09-06 · branch `main` · probe: `tools/frame_probe.gd` @ cfa3cd4 · instrument committed beside the verdict it produced.**

V3.1 was scheduled as "LOD, zoom, and the frame budget" off the 2026-09-05 playtest's
P4 finding: *max zoom halves the speed of the game*. The step-0 profile refuted that
finding's mechanism, kept its warning, and the block shipped the thing the measurement
actually justified. Every number below is from the committed probe on the dev machine
(RTX 3070 Ti, 2560×1440 screen, GL Compatibility renderer) unless marked as a projection.

## 1. The P4 correction: the clock was never eating itself

P4 read game-days per real second at speed 1: 1.12 at globe view, 0.99 mid, **0.50 at max
zoom**, and concluded render cost slows the sim. Two things are wrong with that reading:

**The clock is time-based, not frame-driven.** `src/core/clock.gd` accumulates real delta
and advances days on schedule with catch-up (`_accum_seconds += delta`, `while` loop).
Render cost cannot slow it; a slow frame is caught up on the next one. Frame-driven
stepping would have been a defect here: game speed would scale with monitor refresh (a
144 Hz screen would run a term 2.4× faster than a 60 Hz one).

**P4's own numbers say the clock was healthy at two of three zooms.** An 8-second sample
of a 1.0 day/sec clock reads whole days: 1.12 = 9/8 and 0.99 = 8/8 are quantization, not
rate. The 0.50 = 4/8 means the clock ran ~4 of the 8 sampled seconds — something paused
or starved it, and render cost is not a candidate. The likeliest biter is the V2.9
decision-arrival pause (`_paused_for_decision`), which fires whenever an event lands on an
idle run; P4's instrument did not record pause state.

**Measured under P4's exact regime** (vsync ON, 1440p, speed 1, clock running, days
counted from the clock's own signal, pause state logged): **0.999 days/sec at the opening
fit, 0.998 at max zoom, fps 59.9–60.0, no pause landed** — identical before and after this
block's changes. The instrument now records pause state, so this artifact class cannot
pass for a render number again. P4's *warning* survives in corrected form: the map's
frame cost was real and roster-scaled (§2), and the roster was about to triple (§4).

## 2. The frame profile: a constant, not a cliff

True frame cost (vsync OFF, 240-frame samples, clock paused so no month-tick redraws land
inside a sample), before this block:

| zoom (1080p) | avg ms | draw calls | primitives |
|---|---|---|---|
| min (cover fit) | 4.40 | 1032 | 65 451 |
| opening fit (~2.1) | 4.51 | 1034 | 68 103 |
| city crosses (2.98) | 4.58 | 1034 | 68 103 |
| max (8.0) | 4.66 | 1034 | 68 103 |

Three findings, all the same finding: **there is no deep-zoom cliff** (max/globe =
1.02–1.07, inside the tier's own 10 % gate before any work); **the cost is zoom-
independent** because the engine replays a cached command list and the CPU re-record
happens only on redraw events; and **the map is a ~3.6 ms constant** (no-map baseline
0.83 ms), ~900 draw calls and 68k primitives replayed every frame regardless of how
little is on screen. Fill rate does not move between 1080p and 1440p — GPU-bound work is
not the constraint; submission is. The minimap's every-frame `_process` redraw measured
0.35 ms of attribution delta.

Geometry inventory (live loader): world 1:110m 163 nations / 251 rings / 10 011 points;
roster 1:50m 58 rings / 4 100 points; regions 1:10m 265 rings / 9 267 points; 581 city
glyphs above `CITY_MIN_ZOOM`. The vertex mass is spread across all three vintages — no
single vintage owns it, so no vintage-swap fixes it; only drawing fewer of them does.

## 3. What shipped

**Off-screen culling inside each pass** (`src/ui/map_view.gd`):

- `_ring_reaches_view(ring, view)` — a lon/lat AABB test against `visible_lonlat_rect()`
  grown by `CULL_PAD_PX = 8.0`. The pad is **derived, not swept**: the widest stroke on
  the map is `HOVER_WIDTH` (4 px) plus antialias feather; no BALANCE_PLAN band, no
  measurement grid — a stroke in pixels converted to degrees at the current zoom.
- Applied in the world-border pass, the roster base-fill pass, the region fill pass and
  the national stroke pass. **The two-pass enclave rule survives by construction**: the
  cull gates the region fill, and the hairline list is built only from rings the cull let
  through — any ring drawn at all is drawn as both fill and hairline (Berlin/Bremen,
  geography-model §V2.2b's invariant).
- **City glyphs cull on the transformed screen point**, pad `radius + ring_radius + 8`,
  because their populations are live state — V2.6a's lesson about caching live quantities
  applies to the *cull* the same way it applied to the *draw list*. The hit test is
  untouched: a click cannot land off-screen, so an off-screen cross being a target costs
  nothing, and `_city_at_screen_point()`'s source-policing contract is unchanged.
- Ring bounds are read live rather than cached: rings are static content so a cache would
  be safe, but the per-redraw min/max walk is event-driven (redraws happen on hover, pan,
  zoom and the monthly tick — never per frame), and statelessness buys the absence of a
  V2.6b1-shaped staleness class for free.

**Minimap redraws on change, not every frame** (`src/ui/minimap.gd`): the `_process`
poll compares `visible_lonlat_rect()` and redraws only on change — the same poll the
control already made, with no signal added, so the map view still knows nothing
downstream of it. **Honest note:** the attribution delta only moved 0.35 → 0.27 ms —
the every-frame cost was mostly the GPU *replay* of the minimap's cached commands, which
any visible item pays, not the CPU re-record. The change is correct design; the measured
saving is small.

**Tests and tools:**

- `tests/test_map_cull.gd` — the predicate must agree with a naive bbox test over every
  region and world ring at two framings (Paris max zoom, opening fit), the region under
  the view centre must never cull, something must cull at each framing, and a two-point
  ring never reaches. **No fixed "far region" id**: the headless window is square
  (1920×1920, where a Paris-centred max-zoom view legitimately reaches Madrid), so a
  spot-check against one far id would be aspect-brittle; the consistency check is not.
- `tools/screenshot.gd --zoom Z` (Paris-anchored, frame_probe's point) and `--paused`
  (clock frozen from frame 1) — the identity-frame instrument pair, §6.

## 4. The gates, measured after

Pre-declared in the plan before the cull landed:

| gate | declared | measured |
|---|---|---|
| G1 max-zoom / globe-view total frame time | ≤ 1.10 | **0.51** at 1440p (2.10 vs 4.13 ms) |
| G2 map cost at max zoom, 1440p vsync off | ≤ 2.0 ms | **1.33 ms** (2.10 − 0.77 baseline) |
| clock health under P4's regime | ~1.000 days/sec | 0.999 / 0.998, unchanged |

Post-cull sweep (1080p): min 4.25, fit 3.60, 2.98 → 3.92, 4.0 → 3.51, **max 2.30 ms**
(451 draw calls, 37 363 primitives). Deep zoom got *cheaper* than globe view, which is
the point: **culling makes deep zoom viewport-bounded** — its cost depends on what is on
screen, not on the roster. That is the property V3.4's per-frame animated roads buy:
an animated layer re-records every frame, and a re-record that walks only on-screen
rings stays bounded as the roster grows.

**The EU-29 measurement (V3.3 tranche (a), the projection above replaced):**
the roster grew to 29 nations / 213 regions / 1 065 city glyphs / 29-nation world
backdrop, and `tools/frame_probe.gd` re-ran on it. The everything-visible band
(opening fit and the city-cross zooms, where culling has nothing to remove)
measured **7.08-7.23 ms at 1440p vsync off** — inside V3.1's 7-8 ms projection,
2.3x headroom against the 16.67 ms budget. G1 max-zoom/globe = **0.28** (2.08 vs
7.37 ms, declared <= 1.10); G2 map cost at max zoom = **1.37 ms** (2.08 - 0.71
no-map baseline, declared <= 2.0). Deep zoom got CHEAPER at EU-29 than the
ten-nation V3.1 numbers (viewport-bounded is viewport-bounded). **The
polyline-LOD lever was not reached for: the band held under the measurement.**
The probe's inventory at the new roster: world 145/231/9 460, roster 29/157/
9 370, regions 213/641/18 778, cities drawn 1 065.

## 5. Refusals, recorded where the next session will look

- **Per-tile raster LOD** — the tier's "expensive option". The raster is one quad; fill
  rate did not move between 1080p and 1440p. Dies on measurement.
- **City glyph clustering** — the handoff's step-3 clause, half-shipped: culling yes,
  clustering no. Glyphs do not overlap at the current thresholds; the ascending-draw
  rule already governs the overlap that exists (V2.2b's discipline).
- **Cached/batched region fills** — the engine already caches the command list; the cost
  was replaying off-screen commands, which culling removes at the source.
- **Hit-test bbox pre-reject** (`_nation_at_lonlat` walks ~13k points per mouse-move) —
  real at EU-27, event-driven today, out of this row's gate. **V3.3 watch-point**, to
  arrive with the roster that triples it.

## 6. The identity method, and two tool findings worth keeping

The acceptance for "culling changed nothing visible" is before/after pixel identity at
fixed zooms. Getting a clean comparison produced two findings the next UI session starts
from:

- **Same-tree runs are byte-deterministic; cross-tree runs are not.** Two sequential
  captures from one working tree at a frozen clock are byte-identical (0 differing
  bytes); the same code captured from a worktree at the same settings differs in
  ~0.3–0.4 % of bytes — sparse, small-amplitude anti-aliasing phase noise in text and
  stroke edges, best-aligned at offset (0,0) by registration. The final identity result
  is therefore **same-tree, files toggled, clock frozen: min/fit/cross/max all
  0 differing bytes of 8 294 400**.
- **A capture whose frame budget straddles a day flip is a different frame** — the
  clock display, the ribbon's today-underline and its past-dimming move (456 px in the
  first comparison), V1.4c's date/state race class live in the tool. `--paused` exists
  because of it, and it must freeze on **frame 1, never in `_init()`**: main's `@onready`
  vars do not exist while a SceneTree script's `_init` runs, the first version read a
  Nil clock, pushed a script error into filtered output, and three of eight captures
  ran unpaused. The same Nil-in-`_init` bit `frame_probe.gd`'s first draft the same
  hour — configure a SceneTree-driven scene from `_process`, the way every existing
  tool does.

## 7. Obligations this block hands forward

- **V3.3 (each roster tranche):** re-run `tools/frame_probe.gd`; the §4 projection is
  arithmetic until then. The instrument's clock windows now carry pause state, so the
  P4 artifact cannot recur as a false render number.
- **V3.4 (roads, arcs, convoys):** animated layers re-record per frame; build on the
  viewport-bounded property (cull first, transform second). The minimap's change-test
  pattern is the precedent for any surface that mirrors the camera.
- **V3.3 watch-point:** `_nation_at_lonlat` bbox pre-reject (§5).

## 8. The dragged frame: what the re-record actually walks

V3.4 measured a **dragged** frame at 97.75-99.42 ms on the trade layer against
7.35-7.78 ms with the camera held still. The still figure prices a canvas item the
engine has already recorded; the dragged one prices building it again. Everything
below is about that rebuild.

The two halves V3.4 separated by measurement: `map_view`'s own re-record at ~69 ms
(76.3-76.8 ms dragging with no overlay, minus the still 7.35-7.78), and the trade
layer's roster fill at ~14-17 ms above the political one.

### The roster fill, fixed

`MapLayers.swatch()` on TRADE read the viewer's partner vector **twice per nation** --
once through `value()` for the share, once through `trade_even_share()` for the anchor
it is measured against -- and `Trade.weights()` rebuilds that vector from scratch each
time. Twenty-nine nations, **fifty-eight full vector builds per re-record**, for a
quantity that is the same vector all fifty-eight times.

`MapLayers.fills()` derives the whole roster in one pass: **one** build. `_draw_roster()`
calls it once instead of `color_for()` per nation. The layer, the state and the viewer
are the only inputs -- a fill depends on nothing the camera does -- so this changes when
a colour updates not at all, and no cache and no new staleness class is introduced.
`tests/test_map_layers.gd` pins `fills()` against `color_for()` over every registered
layer and every roster nation from two viewers, exactly rather than approximately,
plus the null-state path.

> [!warning] Unmeasured as committed
> This was written and reasoned but **not re-run against the PAN rows** -- the session
> that made the change had no Godot and no renderer available, so it has no before/after
> number of its own and claims none. The prediction to falsify: the trade PAN row loses
> most of its ~14-17 ms gap over the political one, and the political PAN row does not
> move at all (a political fill is a hash of the nation id and never touched
> `Trade.weights()`).

### Where the other ~69 ms goes: counted, not profiled

Not a profile -- the counts below are exact, derived from the committed geometry
(`data/geo/*.geojson` read through `_outer_ring()`, which keeps the outer ring of each
polygon and drops the holes), and they agree with §4's inventory. **What no line here
claims is a share of the 69 ms in milliseconds.** That attribution is the probe's, and
the probe has not been run on it.

At the opening fit, zoom 2.08, culling has nothing to remove, so every ring is walked:

| pass | `_ring_reaches_view()` calls | points walked |
|---|---|---|
| `_draw_world_borders` | 231 | 9 460 |
| `_draw_roster` base fill | 157 | 9 370 |
| `_draw_roster` region fills | 641 | 18 778 |
| `_draw_roster` national stroke | 157 | 9 370 |
| **per re-record** | **1 186** | **46 978** |

Two findings, both of them counted redundant work rather than a guess about time:

- **The cull test recomputes a constant.** `_ring_reaches_view()` walks every point of
  a ring to derive its lon/lat bounding box, on every call, on every frame -- and its
  own docstring says why it need not: *"Static geometry (loader data never mutates)."*
  That is **46 978 point visits and ~188 000 `minf`/`maxf` calls per re-record spent
  deriving numbers that were fixed at load.** The fix has a precedent in the same file:
  `_nation_boxes`, built once in `setup()` for V3.3's hit-test pre-reject, from the same
  arrays the test walks so the two cannot disagree.

  This is also why V3.1's cull did not expose it. Culling saves a rejected ring's
  projection, its appends, its draw call and its rasterisation -- everything except the
  walk that decides to reject it. So the walk is a **floor that does not vary with
  zoom**, and deep zoom, where culling wins, is precisely where it is hardest to see.

- **The roster outline is projected twice.** `_draw_roster()` builds `base_points` from
  `_polygons[id]` for the same-hue base fill, then builds `stroke_points` from the same
  rings for the national stroke -- same input, same projection, same output, discarded
  and recomputed. **9 370 of the 46 978 point visits and 9 370 of the projections per
  re-record are exact duplicates.** The two-pass fill/hairline order §4's comment
  defends is about the *region* rings and is not what this is; reusing one projected
  array for both national passes leaves every draw call in the order it is in today.

Every projected point also costs a `_lonlat_to_screen()` call, which itself calls
`_control_center()`, plus a `PackedVector2Array.append()`: **46 978 projections and
~94 000 GDScript-level calls per re-record** before any of it reaches the renderer.

### Ruled out as the ~69 ms

- **The city glyph loop.** 1 065 glyphs, a handful of draw calls each, and no per-point
  ring walk anywhere in it -- an order of magnitude below the 46 978 above. Not zero,
  not this.
- **`refresh_cities()`.** Not on the draw path at all: monthly since V2.6b1, and the
  comment there records why it was moved off.
- **`_draw_labels`.** Twenty-nine strings, gated on `LABEL_MIN_ZOOM`.
- **`_draw_raster`.** One `draw_texture_rect`; §5 already killed per-tile raster LOD on
  a fill-rate measurement.
- **`_refresh_markers()`.** Walks started projects, of which there are a handful.
- **Throttling the redraw during a drag.** Refused, not deferred. A map that lags the
  cursor is a worse defect than a slow frame, and it is the trade V3.4 declined for its
  own overlay.

### What to measure next, and how

Both findings are behaviour-preserving by construction, so each is a small revertable
patch and one PAN row prices it:

1. Precompute the ring bounding boxes in `setup()` (`_nation_boxes`' shape, keyed the
   way the ring arrays are keyed), have `_ring_reaches_view()` read them, and re-run the
   PAN rows. `tests/test_map_cull.gd` calls the predicate directly over arbitrary
   feature sets, so it must be extended to assert the precomputed box agrees with the
   walk -- otherwise the suite would cover less than it appears to, which is the failure
   class `tools/run_tests.sh` has shipped four times.
2. Project the roster outline once and use it for both the base fill and the national
   stroke; re-run the PAN rows.

Acceptance for either is §6's method unchanged: same-tree, files toggled, clock frozen,
pixel identity at min/fit/cross/max. Neither changes a drawn pixel, so a non-zero
differing-byte count is a defect and not a tuning question.
