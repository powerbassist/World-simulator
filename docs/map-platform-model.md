---
title: Map Platform Model
tags:
  - model
  - ui
---

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

**V3.4's four gates, declared before any draw and measured after** (the
per-frame animated roads projected above did not happen: roads ride
`map_view`'s own event-driven pass, and the only animated surface is the flows
overlay):

| gate | declared | measured |
|---|---|---|
| G3 map band with roads, everything visible, 1440p vsync off | ≤ 8.0 ms | **6.94–7.88 ms** |
| G4 flows overlay alone, TRADE layer, deep zoom | ≤ 1.5 ms | **0.59 ms** (2.55 − 1.96) |
| G5 worst combined frame, the overlay animating over everything visible | ≤ 11.0 ms | **8.88 ms** |
| G6 clock health with the overlay running | ~0.999 days/sec | **1.000 days/sec** |

**Two of them failed first, and the number that forced the fix is the reason to
write these down.** Redrawing the overlay on every frame, G4 measured
**3.01 ms** (2.0× its gate) and G5 **13.73 ms** (1.25× its gate). The cost is
the `_draw()` re-record and not its pixels — the same picture drawn once and
then only re-submitted priced between −0.03 and 0.43 ms across runs, which is
this pair's own run-to-run spread.
Which part of the re-record dominates was not profiled. The design's named
fallback was taken: `src/ui/map_flows.gd` rate-limits its own `queue_redraw()`
to `REDRAW_HZ` (30), a camera move exempted so the overlay never lags the
coastline it is drawn over, and the table above is the re-measurement.
**A cap buys how OFTEN the frame is paid, not what it costs**: the worst single
frame at the opening fit is still 13.69 ms — inside the 16.67 ms budget, but
without the 1.5× headroom G5 was written to keep. A cheaper `_draw_convoys()`
is the lever left on the table.

### The cap covers a STILL camera, and a drag is not covered

Every gate row above sets the camera once and holds it for the whole sample, so
none of them saw the case the exemption creates. `_redraw_due()` returns true
unconditionally on a changed view rect, and during a **sustained drag** the view
rect differs on every frame — so the exemption fires on every frame and the
overlay is back at the uncapped rate for the length of the gesture. That is not
a bug in the exemption; it is what the exemption is for. It was measured rather
than argued: `tools/frame_probe.gd` gained three PAN rows that move the camera
once per frame through `center_on_lonlat()` — ~8 logical px, the same
`_clamp_pan()` + `queue_redraw()` pair a real `pan_by()` drag ends in — at the
opening fit, clock running, 1440p vsync off, 240 frames each.

| row, panning every frame | run 7 avg / max | run 8 avg / max |
|---|---|---|
| map alone, political layer, no overlay | 76.78 / 102.93 | 76.30 / 122.83 |
| trade layer, no overlay | 91.16 / 142.40 | 93.22 / 149.18 |
| trade layer, convoys on | **97.75** / 128.91 | **99.42** / 130.50 |

**The overlay's own share of a drag is 6.2–6.6 ms** (the third row minus the
second), against G4's 1.5 ms gate — **4.1–4.4× over**. It is not a new cost: the
pre-cap uncapped overlay at this same view measured 6.04 ms (13.73 − 7.69), and
the capped still-camera overlay measures 1.75–2.09 ms. So the cap buys about
4.5 ms **while the camera is still and nothing while it moves**, exactly as
written, and the number confirms the mechanism rather than surprising it.

**The whole frame under a drag is 97.75–99.42 ms — 10 fps, 9× G5's 11.0 ms
gate — and 91–93 of those milliseconds are not the overlay's.** Three
readings, none of which any earlier row could have produced:

1. **The map's own re-record under a drag is ~69 ms.** The same view, same
   layer, no overlay, costs 7.35–7.78 ms while the camera is still; a drag
   re-records it every frame and it costs
   76.3–76.8 ms, 13 fps. This is `map_view`'s cost, it predates V3.4, and no cap
   in `map_flows` touches it. It is also the strongest evidence yet FOR the
   V3.4 split: the file header's claim that animating inside `map_view._draw()`
   would have been unaffordable now has a number, and the number is 69 ms.
2. **The trade layer's roster fill costs ~14–17 ms more per re-record than the
   political one.** `map_layers.swatch()` on TRADE calls `Trade.weights()` twice
   per nation — `value()` once and `trade_even_share()` once, a full partner
   vector each — where POLITICAL is a hash into a palette. At event-driven rates
   that difference hides inside the run-to-run spread; under a per-frame
   re-record it does not. This is why the pan rows are a triple and not the pair
   the G4 rows use: a pair that varied the layer and the overlay together would
   have charged the overlay for the fill.
3. The three rows agree across two runs to within 2.1 ms, and the pattern
   reproduced in two earlier two-row runs (76.98/96.55 and 77.11/99.84).

**OPEN ITEM, and deliberately not fixed here.** Capping the camera move would
close the frame cost and open a worse defect — the overlay detaching from the
coastline under the cursor, which is the reason the exemption exists. The lever
that would actually help is the map's re-record, not the overlay's cap, and that
is `map_view`'s to spend. Nothing was tuned to make this table look better.

**The middle row cannot be sampled clean, and it is structural.** It is flagged
`PAUSED MID-SAMPLE` in both runs: at ~11 fps a 240-frame sample is 22 seconds of
running clock, which is long enough that an event decision reliably arrives
inside it. A decision pause cannot change what that row draws — the redraw comes
from the camera move, not from the clock — and no ~15 s stall landed inside it
(its worst frame is 149 ms, not 15 000), so the figure is reported with the flag
rather than re-taken indefinitely.

**The instrument was wrong before any of this was true, and the wrong answer was
a pass.** The gate rows first sampled with the clock PAUSED, and `map_flows`
only queues a redraw while the clock runs — so they priced an already-recorded
canvas item and reported the overlay at **0.24 ms** in the run that exposed it. `tools/frame_probe.gd` now
carries a `"run"` key for the rows that must pay the per-frame re-record, prints
the clock regime beside every sample, and flags a sample that an event decision
paused mid-way.

**The game opens on the overlay's expensive branch.** `map_flows` draws arcs
below `CITY_MIN_ZOOM` (2.0) and convoys at or above it; the opening fit is 2.08.
So the default view is convoys with every spine on screen and nothing for the
cull to remove, which is what makes G5's row the worst frame rather than a
corner case. The arc branch — the one the game does not open on — measured
**8.34 ms** at min_zoom with the clock running and the cap in place, against the
7.39 ms the same map row costs with the overlay off.

The split that made the rest of it possible: `map_view.gd` stays event-driven
and `src/ui/map_flows.gd` is a separate `Control` that redraws itself. Animating
inside `_draw()` would have re-recorded all eight passes to move a lorry — the
overlay's own re-record alone cost 3.01 ms at max zoom, and the map's is the
6.94–7.88 ms band G3 measures.

**One reading that is not a gate and should not be lost with the run that found
it:** one of the probe's clock windows is voided in every run so far by an event
decision arriving, and around that arrival the process accumulates ~15 s of wall
time the engine never counts as frame delta (15.78 s wall against 0.72 s
counted, in the first four runs). **It is not always the same window.** The
first four runs lost the last one (max zoom, overlay on); runs 7 and 8, whose
pan rows put four extra minutes of wall time in front of the windows, lost the
FIRST one instead (18.77 s wall against 2.96 s counted, 0.160 days/sec wall
against 1.014 counted) and all three others came back clean. So the stall
follows the decision and not the zoom. The clock is healthy per
counted second in every clean window, which is why the wall figure that window
prints (0.063 days/sec) is a stall and not a dead clock — the probe now prints
both rates so the two cannot be confused. **The stall itself has no owner.**

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
- **V3.4 (roads, arcs, convoys) — DISCHARGED.** The animated layer is its own
  control, culls in degrees before it projects, and runs only while the TRADE
  layer is selected, the clock is unpaused, **and its own cap says the frame is
  due** — `map_flows.REDRAW_HZ` is 30, with a camera move exempt so the overlay
  never lags the coastline it is drawn over. The cap is not a polish pass: at
  60 Hz the overlay measured 2.0× over G4 and put the whole frame 1.25× over G5
  (§4), so it is the thing that makes two of the four gates pass, and its
  cadence is therefore load-bearing. `tests/test_map_flows.gd` asserts that
  cadence directly — at ~REDRAW_HZ and not at the frame rate, one redraw and not
  a burst out of a 0.5 s stall, no drift below the rate over the long run, a
  zero delta inert and a negative one recovering rather than wedging — because a
  `queue_redraw()` leaves nothing readable behind afterwards.
  §4 carries the four gates.
  **THE CAMERA EXEMPTION IS UNCAPPED BY CONSTRUCTION, and whoever inherits this
  pattern has to know it before they copy it.** The exemption is not one-shot:
  a sustained drag changes the view rect on every frame, so every frame of the
  gesture takes that branch and the cap is off for the whole of it. Measured
  (§4): the overlay's share of a dragged frame is 6.2–6.6 ms against G4's
  1.5 ms, which is the uncapped cost the cap was introduced to avoid, arriving
  by the exemption's own front door. The exemption stays — an overlay that
  detaches from the coastline under the cursor is a worse defect than a frame
  cost — and the same measurement found that ~93 of the dragged frame's ~99 ms
  is `map_view`'s own re-record and the trade layer's fill, not the overlay.
  **A cap on a redraw is a cap on the IDLE rate only.** Any surface that exempts
  an input from its cap has to measure the frame while that input is held, not
  only while it is still.
- **V3.5 onward:** any further animated surface uses the same split, and budgets
  its redraw RATE before it budgets its draw: the cost here is paid per
  re-record, so how often is the only lever a cap gives you, and 60 Hz was not
  affordable. An eighth pass inside `map_view._draw()` that needs to move is a
  pass in the wrong file.
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

## 9. V4.10a — the ground at depth

**2026-10-18 · branch `v4.10-map-close-up` · probe: `tools/frame_probe.gd` (paired rows) · same machine as §1.**

**The satellite is retired at depth, not scaled.** §5's per-tile LOD refusal stands untouched: the
photograph stays one quad and keeps globe view, where its 15 texels per degree are honest, and a
second quad — a paper-and-hillshade ground baked once by `tools/ground_generate.py` — takes over as
the zoom outruns them. No tile, no stream, no mesh (the tier doc's three refusals, unchanged).

### The band, derived

`MapGround.band_alpha(zoom, BASE_SCALE)` is a smoothstep from **zoom 1.25** (the photograph drawn
1:1: 15 texels/deg over 12 px/deg) to **zoom 2.5** (a 2× upscale, visibly soft). Neither number is
taste: `SAT_TEXELS_PER_DEG` is asserted against the decoded raster's width by
`tests/test_map_ground.gd`, so a new photograph cannot move the band silently. The opening fit
(2.08) lands mid-crossfade; the author signed that off at the plan gate. Once the band is complete
and the view sits inside the ground's opaque core (its bounds less the 3° baked feather), the
photograph is not drawn at all; panned out to the feather, it shows through and the hand-off is a
fade, not a line.

### The asset

4920 × 3000 at 60 px/deg (ETOPO 2022's native arc-minute grid, so the resample is an identity),
extent −31…51 E / 28…78 N derived from the roster's rings plus 6°, WebP 654 KB on disk,
**78.7 MB decoded with mipmaps** (mipmaps because at the band's low edge it is minified 4:1).
Decode + mipmaps + upload: **~285 ms** timed alone, inside the plan's 300 ms line; the boot's
`enter` stage moved 780 → 1084 ms and its weight was re-measured. The coast is rasterised from
`data/geo/`'s own outer rings, not from the DEM, so paper coast and stroked coast agree; the DEM
only shades. One defect class was found by eye on the preview and is now handled in the generator:
the three geometry vintages (1:110m world, 1:50m roster, 1:10m regions) do not tile, and every
gap along a shared land border printed as a sea-coloured crack over paper — invisible over the
photograph. Narrow "sea" the DEM calls land (z > 0) is filled; real straits are below sea level
and stay open.

### The gate

**The tree was already over V3.1's G2 before this block touched it.** Two baseline runs on
today's tree: `1440 max_zoom` 3.44 / 3.79 ms against `1440 max, no map` 1.17 / 1.50 — **G2 =
2.27 / 2.29 ms** against the 2.0 gate (1.37 at EU-29, §4). The max-zoom draw grew from 451 to 574
calls through V3.4's roads, V4.6's plants and V4.11's outlines; G3's opening fit is 10.4–10.9 ms
against its 8.0. **Author's call (2026-10-18): V4.10a is judged on its own delta, and the absolute
2.0 is V4.10c's to recover** — c is the sub-block that re-declares the gate, so it attributes the
growth by pass.

The delta is priced inside ONE run: each new probe row has a `ground_off` twin that nulls
`map_view._ground` — the fresh-clone fallback, which is exactly the pre-V4.10a draw — because the
run-to-run spread on G2 (~0.3 ms) is the size of the thing being measured.

| row (1440p, vsync off) | ground off | ground on | delta |
|---|---|---|---|
| max zoom | 3.91 | 3.47 | **−0.44** (the photograph is skipped) |
| mid-band 1.9 (both quads) | 9.80 | 9.92 | +0.12 |
| opening fit 2.08 (both quads) | 10.20 | 10.52 | +0.32 |
| drag at max zoom, every frame | 23.27 | 23.37 | +0.10 |

G2 with the ground on, same run: **2.14 ms** (3.18 − 1.04). The ground costs nothing a player can
measure at depth and a third of a millisecond at the opening fit, where both quads draw.

### Handed to V4.10c

- **Recover G2 ≤ 2.0 ms at max zoom.** The overrun is not the ground's; attribute the 574 calls
  by pass (fill, hairline, roads, cities, plants, outlines) before any lever is pulled.
- If c's shaders re-bake the ground to channels (paper and sea tinted on the GPU instead of in
  the generator), the band, the sidecar and the opaque-core skip stay as they are.

## 10. V4.10b — borders, glyphs and names at depth

**2026-10-18 · branch `v4.10b-glyphs-labels` · probes: `tools/label_probe.gd`, `tools/frame_probe.gd` (paired rows).**

**Materials moved to V4.10c** (author's call at the b plan gate): a pattern and an edge darkening on
every region fill are a shader's job, and on the CPU they would be another pass per ring on every
re-record of a drag that already costs ~24 ms at max zoom.

### Borders by kind

One table, `map_view.BORDER_KINDS`, keyed by the roster grade (V4.11's derived playable / simulated
/ outline, read through `Roster.grade()` and cached in `setup()`) plus the regional hairline:
widths 2.0 / 1.4 / 1.0 / 0.75 px. Each kind carries a photo colour (the pre-V4.10b values) and a
paper colour (ink), blended by `ground_alpha()` so a line never sits on the wrong ground. Hover
takes the playable colour at full alpha instead of white, the weakest line there is over paper.

### Glyph tiers

`src/ui/map_glyphs.gd`: tier 1 the nation's capital, tier 2 live population ≥ 500 000, tier 3 the
rest; the mark changes (a capital is ringed, tier 3 is thinner), the size stays `radius_of()`.
Capitals are a folded name match against `data/nations/*.json` — 39 of 41 matched exactly, MDA's
"Chișinău" folds onto the city "Chisinau", and **MLT is a bound**: Valletta is below the city
register's cut, so Malta's largest city carries the ring.

### Names: the placer and the band

`src/ui/map_labels.gd` places names greedily in rank order (nation names first and centred, then
tier, population, id) over a 64 px grid hash; a name with no free anchor of four is dropped, so a
dense cluster shows its largest names. A total order keeps a still camera's labels still.

**The band, written before the run:** a tier is named from the lowest zoom of the grid
(2.0 … 8.0) where ≥ 70 % of its on-screen cities get a name in BOTH stress views, the Ruhr
(7.0 E 51.4 N) and the Po valley (9.5 E 45.6 N), with the tiers above it on.

| tier | Ruhr, % named | Po valley, % named | band |
|---|---|---|---|
| 1 | 98 % at 2.0 | 98 % at 2.0 | **named from 2.0** (= `CITY_MIN_ZOOM`) |
| 2 | 83 % at 2.0 | 80 % at 2.0 | **named from 2.0** |
| 3 | 64 % at 8.0 (max) | 71 % at 8.0 | **BOUND: hover only** (`LABEL_ZOOM_T3 = INF`) |

**The obstacle set decided the band, and it was changed for cost before the band was read.** The
first form blocked every on-screen glyph: ~1300 rects inserted per placement, 25–45 ms per
re-record, tier 1 named only from 3.5 and tier 2 never above 60 %. Tier-3 crosses (2–4 px) are no
longer obstacles; a haloed name over one still reads. The 70 % rule itself was not touched.

The shipped placement (tiers 1–2 named, tier 3 skipped before it is projected) costs **1.5–2.9 ms
per re-record** in the stress views; the placer alone places 1400 candidates in 13.5 ms headless
(a stress figure, printed and not asserted: a wall-clock cap failed at 22.7 ms inside the parallel suite; `tests/test_map_labels.gd` pins the native sort on the source instead).

### What it costs (paired labels off/on, one run, 1440p, vsync off)

| row | off | on | delta | budget |
|---|---|---|---|---|
| max zoom, still | 2.54 | 2.68 | +0.14 | ≤ 0.5 |
| opening fit, still | 10.39 | 10.75 | +0.36 | ≤ 1.0 |
| drag at max zoom | 24.24 | 24.24 | 0.00 | ≤ 2.0 |
| drag at the opening fit | 76.59 | 82.81 | **+6.2** | not budgeted |

G2 on this tree, same run: 2.71 − 1.01 = **1.70 ms**. The border, glyph and road changes are not
separable inside one run, so their share is only visible across runs (2.14 ms with V4.10a alone).
Read that as "b did not push G2 up", not as b recovering the gate: the run-to-run spread is
0.3 ms, and V4.10c still owes the attribution.

### Handed to V4.10c

- Materials (pattern, edge darkening) as the first canvas_item shader(s).
- The drag at the opening fit: 76–83 ms. The label pass adds 6.2 ms to it, and most of the rest
  is the map's own re-record (§8). c attributes by pass before pulling a lever.
- G2 against the absolute 2.0, measured across two runs.
