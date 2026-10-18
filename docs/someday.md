---
title: Someday
tags:
  - decision
  - parking
---

# Someday

The parking lot: observations and product gaps that are real but not scheduled.
Everything here carries its own re-raise trigger — the condition under which the
item stops being parking and becomes work. An item without a trigger is a wish,
and does not belong on this page.

## Open author calls

Decisions only the author can take. Each is a checkbox so the Tasks query on
[[vault-dashboard]] lists what is still open; tick it with the decision's date
when it is taken, and record the decision where the line points.

- [x] V4.4 re-baseline: 24 outcome flips, 20 of them HELD→LOST at the 2032 election through the default-drain channel. Tune the defaults' authored means, tune `CATEGORY_QUIET_MONTHS`, or accept the bound (`reports/v44-rerun-prediction.md`). **Decided 2026-10-14: accept the bound** -- ignoring the desk is meant to cost; the defaults' means and the quiet stay as shipped ✅ 2026-10-14
- [x] Event-art contact sheet: the plates lean photographic, not painterly. Accept or re-render ([[event-art-plan]]). **Decided 2026-10-19: accept the photographic style**, with one shared grade across the library in V5.1a ([[v5]]) ✅ 2026-10-19
- [x] The book has no true "protect industry" option: `com_industry_bills.protect_the_makers` is a regulation. **Decided 2026-10-19: add a true one** in V5.3b's law tiles ([[v5]]) ✅ 2026-10-19
- [x] Re-run `events_probe` E4/E5 since the two commodity events were unbound from their hook (over an hour, run alone). **Re-run 2026-10-14** on the split events.gd and the drift-fixed commodities: E4 shipped quiet 3 = 37 arrivals, 12.0 per term, max desk 3, 0.0 % overfull; E5 every category <= 18.9 % (scandal) against 30, commodity 8.1 %; every declared band PASSED. Unchanged from V4.4's recorded 12.0/term and 18.9 % ✅ 2026-10-14
- [x] The portrait wall's face verdict. Generation is no longer open: it closed inside V4.3 (PR #44, `cf329b5d`; [[v3]] close-out, item 3), wall and bench harvested, no person without art. What only the author can do is judge the faces: the contact sheet `.superpowers/sdd/frames/v43_wall_contact_neutral.png` and the counterpart table `reports/portrait_counterparts_review.md`; rejects via `tools/curate_references.py --reject` (both files are machine-local) **Decided 2026-10-19: reject the faces the V5 reflection flagged on the contact sheet** (about eight unusable, about fifteen streaked backgrounds) and regenerate them in V5.2a's portrait pass ([[v5]]) ✅ 2026-10-19
- [x] Effects-blind divisions: make `resolve_vote()` effects-aware, or keep the measured bound (the V4.2 P1(ii) call, below). **Decided 2026-10-19: make it effects-aware**, in V5.3b ([[v5]]) ✅ 2026-10-19
- [x] Hand-curate the 25 generated nations' majors, or leave them generator-owned (open since V4.7a's A3 review; "Carried from earlier blocks", below). **Decided 2026-10-19: leave them generator-owned** ✅ 2026-10-19
- [x] The events book's dominance standard: re-tune the grown book to V1.8's 0 dominated pairs, or retire E3's kill-switch claim (E3 measures 35 and 4; "The probe's E2/E3 bands", below). **Decided 2026-10-19: re-tune to 0** and wire E2/E3 to fail the run, in V5.2d ([[v5]]) ✅ 2026-10-19
- [x] The calendar booking composed laws: wanted or not (the diary item, below). **Decided 2026-10-19: wanted**, in V5.2's diary rework ([[v5]]) ✅ 2026-10-19
- [x] The month tick at 41 nations: 392 ms against the 300 ms band V4.6's synthetic probe was set on. Accept, or open a tick-cost block ("Carried from V4.11", below). **Decided 2026-10-19: open it** — V5.0c, against 300 ms mean and 450 ms worst month, median of three runs (re-measured at 446 ms mean, [[v5]]) ✅ 2026-10-19

## Carried from V4.2's close-out (2026-10-05)

Found during the version-close ultra's eight-pass review of PR #48, refuted as
*not this PR's defect* or *not yet reachable* — recorded here so the refutation
is not the last anyone hears of them.

### Negative pending rates through `Budget.apply_pending()` -- FIXED (V4.2 ultra pass 9)

RECORD, not an open item. The fix shape this entry named is in the tree: the one
writer floors every landed tax rate and spending line at zero, whoever calls it
(`src/sim/budget.gd:385` for the authored tax keys, `:413` for spending; a born
key's rate is floored and yield-gated at `:400-406`). A future `apply_pending()`
caller cannot land a negative rate. Verified against the code at the V4
close-out, 2026-10-18.

### The calendar cannot book composed laws

`data/laws` picker and `_law_by_id` are loader-only, so a composed law can be
proposed but never scheduled in the diary. Two call sites (picker concat with
`Statute.custom_laws(ns)` + the same id fallback the briefing's `_repeal_line`
uses). **Trigger:** whenever the diary feels empty without them — an author
call, recorded as such by the pass that refuted the finding.

### Composed bills cannot move a born key's rate

The composition channel validates tax keys against the authored five, so a
later bill cannot carry `tax_rates_pct` for a custom key; the Tax Code slider
is the only lever. `commit()` already applies whatever it is sent. **Trigger:**
the general compose window (same as the first item) — at which point the
channel validator learns the live key set.

### Effects-blind divisions (the P1(ii) author call)

`resolve_vote()` scores position and nothing else, so a broad bill and a narrow
one at the same position divide identically — the composition bands'
P1(ii) recorded this as a measured bound, and the anti-all-upside load rides
`CHANNEL_PRICE` through approval (the negative control confirms the price table
closes the hole). **Trigger:** the author's call on making divisions
effects-aware — a machine change on `resolve_vote()`, whose ~25 call sites and
forecast consumer all read it. The bound and the sweep live in
[[legislature-model]]'s drafting-budget section.

### Held-bill ghost ids fall silently

A held bill whose law id resolves to nothing is dropped at release with no log
line (pre-existing shape; no gameplay reaches it since composed holds are
handled). A dev-log nicety, listed here so the silence is recorded rather than
discovered. **Trigger:** never on its own; fold into any future held-bills
work.

## Carried from V4.4's convergence loop (2026-10-11)

Found by the light-review passes on PR #49, verified real, unreachable with the
shipped 102-event book — recorded so the refusal is not the last anyone hears.

### A choice whose every effect is 0.0 loads

`event.gd`'s "costs nothing" refusal fires only when a choice carries NO keys;
`{"bloc_offset": {"workers": 0.0}}` passes the loader, `tools/event_lint.py` and
`tests/test_event_content.gd`, and can be the default the desk auto-applies. The
lint and the loader also disagree both ways (the lint refuses `{}` where the
loader accepts it; the lint accepts society/company values the loader refuses —
burden 0.0 or past `REGULATION_BURDEN_MAX`, society 0.0, company beside
`structural_unemployment_pct`). **Trigger:** the first authored event past the
current 102, or any lint-clean book that fails to load. **Fix shape:** one
zero-effect rule at the loader, and the lint's society/company checks lifted to
the loader's own.

### The probe's E2/E3 bands are declared but cannot fail the run

`events_probe.gd`'s E2 (legibility) and E3 (dominance — its own comment says "THE KILL
SWITCH FOR THE CONTENT") print tables and never call `_band_failed`, so the exit
contract ignores them. On the shipped 102-event book E3 measures 35 dominated
non-default pairs and 4 toothless defaults against the V1.8 six-event book's recorded
0 and 0 (events-model §6 now carries both numbers). **Trigger:** the author call on
re-tuning grown content to the V1.8 standard — wiring the bands before that call would
make the probe permanently red. **Fix shape:** wire `_band_failed` into E2/E3 at
whatever thresholds the author accepts, or retire the kill-switch claim.

### The AI chooser's bloc term averages over the NAMED blocs only

`EventChooser.score_choice` (src/sim/event_chooser.gd) divides the size-weighted bloc offset by the weight of the blocs a
choice names, so `rural -0.08` scores -0.08 while `-0.05` on all six blocs scores
-0.05, though by electorate share the second costs four times more. Measured on the
book (python, bloc term alone, 307 choices, 197 of them naming fewer than six blocs):
the argmax differs in **1 of 102 events**, so the AI's picks are nearly unmoved.
Changing the divisor to the total `BLOC_SIZE` shrinks the term's scale against the
fiscal, cleanliness and unrest terms, so it re-tunes the `CHOOSER_*` weights and
moves 28 nations' trajectories. **Trigger:** a tuning pass on the chooser, or an
authored event where narrow-versus-broad is the whole decision. **Fix shape:** the
size-weighted SUM, with the `CHOOSER_*` weights re-swept by `events_probe` E7.
Kept parked by the author on 2026-10-14 (argmax moves in 1 of 102 events; a re-tune of
`CHOOSER_*` against E7 is a tuning task).

### `Budget.project()` ticks every nation's events

`project()` calls `Events.tick_month(sim, loader)` for all 29 nations per projected
month; only the player's desk is read back. Measured 2026-10-12: **362 ms for 24
months x 29 nations** (328 ms once the hazard loop tests the hash before the
precondition scan; the rest is hooks and the AI chooser), two projection passes per budget-panel refresh, so ~0.7 s
added to the panel's recorded ~4.5 s. Not dropped because the AI nations' events move
their partners' figures, which reach the player's forecast through trade, and
`tests/test_budget.gd` pins the projection against the real run to 1e-9. **Trigger:**
the budget panel's projection-cost work (PR-46's finding 6). **Fix shape:** a
player-only `Events` tick for the projection, with the mirror in `test_budget.gd`
re-derived and the partner effect measured first.

### The AI nations' unrest and deficit registers never tick

`Unrest.tick_month` skips nations without `has_budget` and `Budget.tick_month`
recomputes only the player, so for the AI nations `unrest_pct` stays at its start
value (0.0) and `deficit_pct_gdp` stays at its authored start (AI event answers skip
the fiscal channels since pass 23, so nothing recomputes it either). Consequences for the events machine: the chooser's unrest term
(`CHOOSER_UNREST_FLOOR`) cannot fire for them, unrest-gated events never open for
them, and deficit-gated ones read starting data — so an AI nation's event frequency
and choices are set by its authored start rather than by anything it did. The
"deficit-running government in unrest prefers the concession" behaviour is therefore
a player-and-budgeted-nations property. **Trigger:** AI nations getting a budget
tick (a later AI-economy block) — the chooser then reads live figures with no edit.
**Fix shape:** none in the events machine; state the bound where the chooser is
described.

One edge of the same gap, closed at pass 23: an AI nation's first fiscal event used to
refresh that nation's long-frozen deficit in one step (`Legislature.apply_effects` ->
`Budget.apply_pending` + `Budget.recompute`: GDP growth, debt service and tariffs since
the new game all landing at once), so a deficit gate or the chooser's deficit floor
could flip on that refresh rather than on the event's own delta. That refresh no longer
happens: AI answers skip the `tax_rates_pct`, `spending_pct_gdp`, `company` and
`other_revenue_pct_gdp` channels (`Events._resolve`), so an AI nation's deficit stays
at its authored start until the budget tick below exists. **Trigger:** AI nations
getting a budget tick -- at which point the skip can be lifted and the fiscal answers
become a real policy. **Fix shape:** drop the filter in `_resolve`.

### The projection prices no goods, and `law_passed` has no consumer

`Budget.project()` ticks Events but not Commodities, so the `commodity_price_high` hook
reads a crossing stamp nothing writes inside the forecast (since pass 22 the hook is an
edge on `commodity_high_month`), so it is false in every projected month and a
shortage that develops in the window never appears. `test_budget`'s 1e-9 projection-equals-reality
check cannot see it because its mirror omits Commodities too. **Trigger:** the budget
panel's projection work, or a commodity event that moves the deficit. **Fix shape:**
tick Commodities in `project()` and in the mirror together.

The `law_passed` hook reads `ns.law_ledger`, which records only laws that moved a
ledgered register by a non-zero amount and ignores the institutional channel, so a
constitutional amendment or electoral-reform Act never stamps a month; and no shipped
event uses `law_passed` (6 of 8 vocabulary entries have a consumer since pass 23 unbound `commodity_price_high` too). **Trigger:** the
first authored `law_passed` event. **Fix shape:** stamp passage in `Legislature.apply`
itself rather than reading it back off the ledger.

Two more facts about the same hook (Task 15, `events.gd`'s emitter comment states them):
it misses every ledger-less passage (the ledger's writer returns early when no ledgered
channel moved, so a passage that writes no ledgered channel -- for example a purely institutional Act, or a pure repeal -- never fires it),
and one happening can fire two hooks (a carried private member's bill fires
`member_bill_passed` at month M and `law_passed` at M+1; `law_repealed` can pair with it
likewise). Same trigger and fix shape.

### Flavour text that assumes the Union

`river_flood` mentions "the Union's solidarity fund" and reads oddly for a non-member
player; it is not gated (a flood is a flood) and the copy would need a membership-aware
variant. **Trigger:** the first non-EU playthrough note. **Fix shape:** drop the clause
or split the summary.

### `commodity_price_high` was a level read -- converted to an edge at pass 22

RECORD, not an open item. The hook was true every month while any good sat at >= 1.25x
base, and the world price vector drifts to its clamp within months, so it fired about
every month and flooded the desk (measured over 168 months, FRA: the level was true in
168 of 168 months and commodity events were 33 of 67 desk arrivals). It is an edge now:
`Commodities` stamps `ns.commodity_high_month` in the month a good goes from below
`HIGH_PRICE_RATIO` of base to at or above it, and the hook reads that stamp (5 months in
the same run; commodity arrivals 4 of 38). The hook door still does not respect the
category quiet, which an edge makes unreachable in practice rather than fixes.

**Pass 23 update -- the two events were unbound.** Even as an edge, the hook is true in
months 1-5 of every new game for all 29 nations (the drift below crossing goods one
after another) and never again, so it fired only inside that artefact.
`com_price_high_desk` and `com_industry_bills` lost their `on_action` and are ordinary
hazard events in the `commodity` category at the median likelihood of the category's
other six (0.0033); `commodity_price_high` stays in `ON_ACTIONS` with no consumer, like
`law_passed`. **Trigger to re-bind:** the V4.6 drift fix below, after which the crossing
means a real shock. **Fix shape:** restore `on_action` and the per-happening likelihoods
(0.45 / 0.40) on both events and rewrite their summaries to name the crossing.

### World prices drift to their clamp within months -- FIXED 2026-10-14

RECORD, not an open item. The gap counted intermediate use twice, six recipes cost
more in inputs than their output was worth, and demand's sector mix moved with
supply so no shock reached a price. All three fixed; before and after are in
[[commodities-model]] §3b (15 goods >= 1.25x at month 3 before, 0 after; a supply
shock now moves steel by 10 %). **Re-bind decided against, 2026-10-14 (author's call).**
With the drift fixed, no good crosses 1.25x base in an idle run until clothing's
unexplained creep at month ~160 (its likely cause is the fixed world volume, "World
production does not grow" under V4.11b below -- one open item, recorded twice), so the hook would fire almost never, and its one
firing would be that creep rather than a shortage; bound to it, the two events
would also leave the hazard roll, where they arrive ~3 times a run (E5: commodity
8.1 %). **New trigger to re-bind `com_price_high_desk` and `com_industry_bills`**,
all three together: (1) a player verb or world event that can cause a real world
shortage; (2) clothing's creep attributed, so it cannot fire the hook by
mistake; (3) `events_probe` E4/E5 ticking Commodities, with the hook's real
arrival rate measured before it ships. Left open: clothing creeps from 1.04x to 1.27x base over 168 months,
unattributed. **V4.11b2 (2026-10-16):** real endowments bring the crossing forward,
1.278x at month 96 (was ~160), with a manufactures wave near 1.13x around month 84 --
[[commodities-model]] §8 as measured. Trigger (2) is further away, not closer. **V4.11 review (2026-10-17):**
once the energy endowments read every producer (Europe's own oil, gas and coal had
been zeroed by a year-selection bug), the crossing went away again: clothing peaks at
1.202x at month 120, the wave at 1.136x near month 85, 0 crossings in 120 months. The
creep is still unattributed and still rising at month 120.

### Same-month category collisions favour the early alphabet

The pulsing categories deliver in sorted-name order and the loop stops at a full
desk, so on a nearly-full desk `disaster` beats `unrest` every time. A fixed bias,
swept into E5's spread (all <= 18.9 % against 30) rather than introduced after it.
**Trigger:** a category whose measured share runs below its authored weight, or
QUEUE_MAX shrinking. **Fix shape:** rotate the order by the month or choose among the
pulsing categories by their authored weight.

### The desk bound outranks severity

With the desk at `QUEUE_MAX`, any further delivery is dropped whatever its severity or
interrupt flag: a severity-3 interrupt such as `blackout_night` is lost without trace if
four minor entries hold the desk. Same-month collisions between categories are decided by
sorted category name, not severity (the entry above). Measured rarity: E4's overfull
share is under 5 %, and `blackout_night` draws at 0.008/month while debt >= 95 %.
**Trigger:** a playtest or probe run where a critical event is lost to a full desk.
**Fix shape:** a critical or interrupt arrival displaces the lowest-severity entry (which
defaults at once, with its "Decided for you" card), or interrupts may exceed `QUEUE_MAX`
(needs the card column's capacity revisited — next entry).

### The card column is nearly all protected

Decision cards (up to `QUEUE_MAX` 4) and the term-start programme card are protected from
`MAX_CARDS` (6) eviction, leaving 1-2 slots for plain news. Several plain cards pushed in
one tick ("Decided for you", a takeover bid, an assembly division) evict each other before
the frame draws, and an already-marked-announced notice is never re-shown. **Trigger:** a
playtest note of a missing "Decided for you" card, or `MAX_CARDS` changing. **Fix shape:**
a larger column, or one-tick coalescing of plain cards.

### Hook events are rare by construction

Most hook events carry 0.015-0.03 per happening, on happenings that are themselves
rare (a firm failure runs ~0.62 per nation per 168-month run), so they practically
never reach the desk -- the book's "the game watches you" layer is mostly latent.
Authored for the hook's meaning and never measured against its real arrival rate.
**Trigger:** a tuning pass that measures each hook's real arrival rate in
balance_probe-style runs. **Fix shape:** per-hook likelihoods set from that
measurement (the way pass 23 set the commodity pair from the category median).

## Carried from V4.11 (2026-10-16)

- **An outline relation.** The V4.11 brief gave every outline "a relation"; nothing in
  the sim would read one -- outlines have no diplomacy, no agreements and no verbs aimed
  at them -- so the author refused it for now (inert content). **Trigger:** the first
  machine that acts on an outline (an export control against a supplier, a sanction on
  the world pool, an agreement with a non-European partner).
- **An export-control verb.** The V4 tier lists export controls as lifted to V4.6; no
  machine was built. V4.11b's real endowments are what one would stand on (the world
  pool's supply is now a price lever). **Trigger:** a block that gives the player a
  supply-side commodity verb.
- **World production does not grow.** `W` (the world volume a natural good's shares
  divide) reads authored figures only, so it is fixed at the start while every
  economy's requirement grows. The likely cause of V4.11b2's manufactures wave at
  month ~84 (unverified -- [[commodities-model]] §8 as measured). **Trigger:** the
  first block that reads commodity prices into GDP or lets a shortage reach the
  player; **fix shape:** grow `W` with world GDP (the outline register gains a trend,
  or the roster's realised growth stands in), then re-run the probe.
- **The month tick at 41 nations is 392 ms** (V4.11a's tick probe: 218 -> 392,
  Diplomacy 70 -> 159 and Economy 37 -> 76, the N² of (41/29)²), above the 300 ms
  band V4.6's synthetic probe was set on. Two known shares of Diplomacy's growth,
  recorded by the V4.11 review and not fixed: `target_terms` recomputes the exposure
  yardstick per target, and the accept/refusal/pact terms build the trade vector
  twice. **Trigger:** the author's call above, a roster past 41, or a playtest that
  feels the month. **Fix shape:** measure first (the tick probe, one run), then the
  two Diplomacy recomputations.

## Carried from V4.11c (2026-10-17)

- **Portraits for the twelve neighbours.** Skipped at the V4.11c gate (author's
  call): their people files hold 16–22 people each, ~235 with executives, so the pass
  is ~2.5x the brief's 80–100 and nothing yet seats one of them across the player's
  desk. Until then a person with no portrait draws the silhouette
  (`tests/test_portraits.gd` pins the fallback); `tools/portraits_generate.py --only
  <id>` generates a slice resumably. **Trigger:** the first
  surface that seats a neighbour's person in front of the player (a summit, a council
  face for a non-member, a neighbour's cabinet read).

## Carried from V4.8b (2026-10-17)

- **A player-chosen watchlist for the outliner.** The tier doc says "watched
  firms"; nothing in the game is watched, so the outliner shows firms in trouble
  (a failing major in its rescue window, a standing foreign bid). A real watchlist
  is a register the player writes -- a save field (a bump, since an absent list
  would read as "watching nothing", which is correct for an old save, so possibly
  no bump: decide at the plan) and a command, not a UI-only change. **Trigger:** a
  playtest where a player says they lost track of a firm that was not failing.
- **Level-2 breakdowns for GDP, unemployment, inflation and unrest.** None has a
  decomposition in the machine (the V4.8a call: no `src/sim/` diff), so their tips
  say what the number is and stop. **Trigger:** a block that adds such a query (a
  growth-accounting split would feed both the tip and the Economy panel).
- **The popup's felt timings** (`OPEN_DELAY_S` 0.3 s, `GRACE_S` 0.2 s) were set by
  reasoning, not by a hand on a mouse: a headless suite cannot feel them. **Trigger:**
  the first hands-on pass; V5 reworks the layer anyway.

## Carried from V4.10 (2026-10-18)

The design questions PRs #10 and #11 raised, settled at V4.10c. Two were decided and
are not parked: **every data layer sits on the parchment at depth** (the ground is the
map there, and a fill is a tint over it at the layer's alpha -- by design), and **the
hovered city's reserved label beats a nation's name** (the player asked for it with the
cursor; the name returns when the cursor leaves). The rest are parked:

- **The ground's edge fade shows** around Iceland, Turkey, Ukraine and Cyprus: the baked
  extent is the roster's rings + 6 deg, and its 3 deg feather lets the photograph back
  in where those coasts run near the edge. Widening the extent grows the asset.
  **Trigger:** V5's map art pass, or a playtest that zooms there and says so.
- **The ground's decode costs the boot ~300 ms** (`enter` 780 -> 1080 ms). It could move
  to the boot's worker beside the scene compile. **Trigger:** the next boot-time budget.
- **Malta's capital ring sits on St Paul's Bay**: Valletta is under the city register's
  cut, so MLT's largest city carries the ring (a bound, [[map-platform-model]] §10).
  **Trigger:** the city register gains capitals below its cut.
- **Hovering a city reshuffles nearby names**: the reserved hover box frees or takes
  slots, so names move while the cursor moves. **Trigger:** a playtest that notices.
- **The legend's road key is brass; roads at depth are ink.** The legend is UI, and V5
  reworks the UI. **Trigger:** V5's legend.
- **Small nations' names drop between zoom 1.4 and 2.0** (or on small windows): a
  collision drops the later name, and the placer's tie-break is alphabetical. Fix shape:
  rank by area, or by relevance to the player. **Trigger:** a playtest on a small window.

## Carried from earlier blocks (pointers, not duplicates)

- **The 25 generated nations' majors are generator-owned** — hand-curating
  them means narrowing `firms_generate.py --check` to the body tier first.
  The AUTHOR's call, open since V4.7a's A3 review.
- **The from_dict aliasing sweep** for `plants`/`projects`/`sector_investment`
  (companies itself is fixed, T5 rebuild) — V4.6 §6's record.
- **`PRICE_ELASTICITY` is unvalidated** — the sweep belongs to the first task
  that lets a player cause a shortage (V4.6's record).
- **The budget panel's projection cost** (~4.5 s per refresh, PR #46's finding 6;
  [[history]] §V4.7) is the trigger two V4.4 items above share ("`Budget.project()`
  ticks every nation's events", "The projection prices no goods"). **Trigger:** a
  playtest that feels the panel, or V5's UI rework of the budget panel.
- **The 2026-09-16 playtest's open rows** — B12 (month-0 dash placeholders, a copy
  call), B13 (the Summit ObjectDB leak, one run in 105) and the termed-out player's
  stale vote date — live in `reports/playtest-2026-09-16/report.md` (machine-local).
  Its perf rows 3.2 (pan fps) and 3.3 (no loading screen) are CLOSED by V4.10c and
  V4.9a. **Trigger:** the next playtest.

---

Related: [[index]] · [[legislature-model]] · [[companies-model]] · [[tax-model]]
