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
it:** the probe's last clock window — max zoom, overlay on — is voided in every
run so far by an event decision arriving, and around that arrival the process
accumulates ~15 s of wall time the engine never counts as frame delta (15.78 s
wall against 0.72 s counted, in four runs out of four). The clock is healthy per
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
  a burst out of a 0.5 s stall, no drift below the rate over the long run —
  because a `queue_redraw()` leaves nothing readable behind afterwards.
  §4 carries the four gates.
- **V3.5 onward:** any further animated surface uses the same split, and budgets
  its redraw RATE before it budgets its draw: the cost here is paid per
  re-record, so how often is the only lever a cap gives you, and 60 Hz was not
  affordable. An eighth pass inside `map_view._draw()` that needs to move is a
  pass in the wrong file.
- **V3.3 watch-point:** `_nation_at_lonlat` bbox pre-reject (§5).
