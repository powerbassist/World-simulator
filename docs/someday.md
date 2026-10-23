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
a larger column, or one-tick coalescing of plain cards. **Paid by V5.1-c's inbox (`ae802108`):** decisions are never evicted and the notes have their own lane of 40.

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

## Carried from the V5.1 close-out (2026-10-23)

The QA record on #61 to #85, what is still open in the tree on 89dddf4a (the ones a later PR fixed are gone: #77, #81, #82 and #84 closed their own predecessors' items). The detail is in each PR's QA section. All of them sit below the V5.1 bar -- a player does not meet one in thirty minutes -- and they are cleanup, not blockers. Items marked † were QA findings on code no later PR touched; they were not re-read at the close-out.

**Interface**

- **The country box** (#85): the month rebuild re-centres the box on the pointer; a scene refusing the rebuild leaves a stale box up; its Escape is taken before the console and the stack; its nation and capital names are raw (`country_box.gd`). †
- **Raw names, one family**: the Diplomacy host line (`nation_panel.gd:432`), the box's headings, the "Received in %s." capital (`world_news.gd:305`), and the hold line's `visiting` carry a raw `nation_name` or capital id; no nation accessor exists. The visit tally appends a nation twice if it hosts twice (`world_news.gd:183`).
- **`PanelKit.line()` changes class with the text's marks** (#83): a translation that drops a mark changes the line's minimum size and wrap; `TermText.has_marks()` is a raw substring test; the A-Z tab does not rebuild on a text-size change, nor fold accents (French, parked).
- **Term marks** (#76): N1's holder check ignores visibility and reads `_section()` at set time, so a hidden or detached holder keeps or misses a section's mark; `next_term` keys the walk by instance id, so a panel that rebuilds its rows restarts it; `screen_stack`'s `_press_at` releases a code `grab_focus()` made during a held click; `window_manager.gd:148` spells `&"term_section"` instead of `TermText.SECTION_META`. †
- **Clocks**: a second press deferred inside one month close is a no-op (fails safe, #63); a summit's close resumes the clock unless a decision holds, and an election scene on the same 1st is not checked (#70); the cluster lags up to one game day after a summit closes (#73). †
- **Design calls left to the author**: the Energy tab is not restored after a placement (#67); polls are now free in game terms and limited only to once per bill per kind (#66).
- **Tests**: `law_verdict.gd:27`'s `pending_law_id` guard can be removed with test_dead_ends, test_law_panel and test_referendum green (#69); `test_play_gate_terms` keys FRA/DEU/GBR/POL by id (`PLAYED`) instead of deriving from `formation_method` (#61); `GlossaryHint._shown_in` is a static, so a leg that boots a main earlier in the same process spends `test_statute_assembly`'s private flag (#78); the cross-month away range reads "(away 28–05, MAR–APR)" beside the travel note's "Away 28 MAR – 5 APR" (#76 †).
- **Pinned person card and a wheel tick** (#70): `glossary_tip.gd`'s `_input` closes on any pressed mouse button, so one wheel tick unpins a pinned card.
- **Small cleanups** (#71, #75, #76): `tools/decision_surfaces_probe.gd:137` matches `action_id` "state_visit" by id, not by `opens_meeting`; the comment at `src/sim/world_month.gd:13` still says the UI side "stays in main.gd"; `tests/test_effects_ledger.gd:168` builds `code +=` line by line (quadratic); `tests/test_no_raw_tags.gd:57` says it runs over every window as it opens, but `_scan` runs once after the last.
- **`tools/screenshot_all.py`** (#76): the target PNG is not deleted before a run, so a stale frame passes a staging that wrote nothing; `args.split()` ignores quoting (`shlex.split`).

**Systems**

- **`recent_effects`** (#75): the command takes an entry the UI built, and `Trends` lives in `src/ui`; the deeper fix moves the measurement under `src/sim` or `src/core`.
- **The budget projection** (#77, #81): the order "Discipline before Statute" is not pinned; the projection reads an approval it never moves (a recorded bound of the subset); the election month reading 0 is not pinned (a `>=` mutation passes); the election-roll rule is written twice (`budget.gd:514`, `elections.gd:157`); only the player's clock rolls while Discipline ticks every nation with a budget.
- **The k-format** of a poll price has no range guard (#66, cosmetic).

**Health**

- **Test walkers**: `_gd_files` is written five times (`test_effects_ledger`, `test_geography`, `test_panel_kit`, `test_programme`, `test_world_month`), and `test_effects_ledger`'s comment strip works line by line, so a triple-quoted string's body is scanned as code (#75, #77).
- **`.claude/.gdignore`** is kept only through `.git/info/exclude` in the author's checkout; whether it belongs committed beside `settings.json` is Health's call (#64). †

**The author's automation session (#79)**

- **`tools/protect_files.py` under bypass or auto mode**: the author's call (2026-10-22, "refuser en mode auto") is that the hook reads `permission_mode` and denies with its reason there, asking otherwise; `protect_files.py` does not read it yet. The hook command is Bash syntax (`$CLAUDE_PROJECT_DIR`, `||`): on a machine without Git Bash it is a PowerShell parse error, a non-blocking failure (fail-open). †

**Gameplay**

- `docs/design/v5.1-gate-triage.md` lists the `SIZE_*` constants without `SIZE_MAP = 10` (#65, harmless). †

**Parked with French** (translation is not a priority, the author, 2026-10-21): the placement hint, the briefing's assembly forecast line and the A-Z tab's order have no French yet.

## Carried from the V5.1 closing gate (2026-10-23)

The author's closing gate scored 2/5; N1, N2 and N10 (the placement freeze and reticle, the oversized buttons) were fixed in #89 and #90. The rest are class C or D, found at the gate and not fixed in V5.1; the numbers are the gate report's. Each has the tier that should take it.

- **N3, "still a lot of useless text everywhere".** Less text per panel. **Owner:** Interface and Content; taken by V5.2's sub-block 0b, the text diet, per the V5.2 brief (parent, 2026-10-23, gitignored under `.superpowers/sdd/`); the rest of G14 stays with V5.3b (`docs/design/v5.1-gate-triage.md`).
- **N4, "what is the point of notes?"** Notes ask nothing and carry no action. **Owner:** Gameplay and Interface; V5.2's requests replace asking-notes (`docs/design/decision-surfaces.md`: notes never hold the clock).
- **N5, "legislature tab is clunky and heavy".** A 140 ms frame on opening it; see "An OPEN panel's own refresh" (law 174 ms) in this page. **Owner:** Interface (`src/ui/legislature_panel*`); taken by V5.2's sub-block 0c, light panels (the brief names the Legislature and Energy opening in one ~140 ms frame).
- **N6, a state visit has no scene for any partner but DEU and ITA.** `data/summits/` holds two scene pools; for any other partner the day resolves to a note ("KEPT: STATE VISIT", `main.gd`'s `card_appointment`) with no scene and no hold, so a visit to Spain booked at speed 3 did not stop the game. By design today, not a bug. **Owner:** Content and Gameplay; V5.2 (people who talk, audiences).
- **N7, a summit offers few choices.** "tres peu de choix se sont offert a moi": the Germany summit has two choices and Continue (`data/summits/DEU_ruhr_dinner.json`). **Owner:** Content and Gameplay; V5.2.
- **N8, "the game lack soul".** **Owner:** Gameplay; V5.2 (people who talk).
- **N9, "some panels are really monolithic and uneasy to read".** The Legislature is the one named. **Owner:** Interface; taken by V5.2's sub-block 0b (split monolithic panels into sections, a test pinning each panel's prose budget); the rest of G14 stays with V5.3b.
- **N11, "i need graph, diagrams, to make data more digest".** A feature, not planned in V5.1. **Owner:** Interface and Systems; the V5.2 brief's sub-block 0a, the chart kit, takes the first charts (Overview, Economy, Budget, Opinion, Legislature), fed from the history the game already keeps; V5.3b's statistics service is the later, fuller version.
- **N12, a hydro plant can be placed anywhere in France, with no river check.** Unverified in code (`src/sim/energy.gd` placement). **Owner:** Gameplay and Systems; V5.3c's construction register and siting (`docs/tiers/v5.md`, V5.3 c).

## Carried from QA's PRE-GATE 2 (2026-10-23)

QA's MCP pass on 89dddf4a, before the author's closing gate, scored A=0, B=3, C=11. The three B items were fixed in #87 (the focus-release ERROR on every inbox answer, the tall person card, "Failed" for a bill the second chamber holds). The eleven C items were recorded and not fixed; each was re-read against `origin/main` at 5c8e5d7b (after #87 to #91) and **all eleven are still in the tree**: none of the files they cite changed after 89dddf4a. QA's numbering (C1 to C11) is kept; the measurements are in its report (`qa-report.md`, section "PRE-GATE 2", gitignored). They sit below the V5.1 bar, but the gate's author met several of them.

- **C1, "This month you decided: ..." keeps its title for months.** In Feb 2027 it heads November 2026's decisions, and the Jan 2026 programme card still says "this month" in Nov 2026 (`src/ui/effects_ledger.gd:60`). **Owner:** Interface.
- **C2, the hold reason with a sentence-shaped event title.** "Paused: The sea takes the front row needs an answer." (`src/ui/hold_reason.gd:43` formats the event's name into a sentence; the names are written as sentences). **Owner:** Interface (a verb-led reason) or Content (names).
- **C3, three date formats.** The Diary reads "05 FEB 2027", its refusals "05/02/2027" (`Calendar._date_text`, `src/sim/calendar.gd:583`, a raw `%02d/%02d/%d`), Dispatches "2028-01". The sim helper cannot reach `DateText` (`src/ui/date_text.gd`, rule 2); the refusal reason would have to carry a date, not a string. **Owner:** Interface, with Systems for the refusal text.
- **C4, "Away 4 FEB - 6 FEB (1 days' travel each way)".** The plural is not chosen at `src/ui/visit_booking.gd:140` (`Strings.t`, not `Strings.tn`), while its two neighbours (`nation_panel.gd:481`, `campaign_panel.gd:301`) use `tr_n`. **Owner:** Interface.
- **C5, the Germany summit's speaker is not Germany's leader.** `data/summits/DEU_ruhr_dinner.dialogue` has "Chancellor Vogel" throughout; `data/people/DEU.json` has "Matthias Vogler". Line 6 says "a toll Bonn cannot be blamed for" and the capital shown everywhere is Berlin. **Owner:** Content (V5.2 b's summit scenes are rewritten anyway; fix the names in the same pass).
- **C6, after a load the inbox is empty.** "No news yet": no term note, no year's visits note, no consequence card, although `recent_effects` is saved (QA read 5). QA's question stands: by design or not. **Owner:** Interface, and a call from the parent.
- **C7, two identical notes side by side, undated.** "A LEAK -- Clarisse Turcy briefs against the government." (`src/ui/world_news.gd:261`); not traced to the source of the double push. **Owner:** Interface or Systems.
- **C8, a panel opens in one ~140 ms frame.** The Legislature and Energy opening or rebuilding, and Commit at 55 ms, measured embedded in the editor; see "An OPEN panel's own refresh" above. **Owner:** Interface; taken by V5.2's sub-block 0c.
- **C9, "NEXT VOTE 60 mo" while POLLS CLOSED and the count are on screen.** The strip's "election" reading (`src/ui/strip_readings.gd`) is the one that says it; why it still reads 60 months at that moment was not traced. Low. **Owner:** Interface.
- **C10, the two-round presidential system shows no second round.** "Renouveau Civique holds the office, first in the vote with 23.9%." (`src/ui/election_panel.gd:362`); gate 1's C7 in new words. **Owner:** Gameplay and Systems.
- **C11, a click on a term in the hint note falls through to the note.** It opens Presidency > Dispatches, while the note says "Click it to keep the note open"; correct by `src/ui/term_text.gd`'s `_gui_input` but surprising when the hover did not register. Low. **Owner:** Interface.

**Closing-gate items the V5.2 brief does not cover** (the brief is `.superpowers/sdd/v5.2-brief.md`, gitignored; everything else in the gate report either has a sub-block there or is fixed):

- **N12, a hydro plant can be placed anywhere in France.** No river check, though the author's Q3 answer named it as strange; unverified in code (`src/sim/energy.gd`). **Owner:** Gameplay and Systems; V5.3c (the construction register and siting).
- **G5, grand plan decisions** and the rest of **G14** (badly presented info beyond the text diet). **Owner:** V5.3 (`docs/design/v5.1-gate-triage.md`).
- **N6's second half: a booked visit with no scene should still say so on the day.** The brief's sub-block b adds scenes, but a partner without one (every partner but DEU and ITA today) still resolves to a note, "KEPT: STATE VISIT" (`main.gd`'s `card_appointment`), no hold and no mention that no meeting happened; the author was not told at the booking. **Owner:** Interface (the booking's text) with Content (the scenes).
- **QA's call 2 is answered, not open:** a no-deadline programme item is judged at the end of the term and then ends (the author, 2026-10-23, in the V5.2 brief); the work is V5.2 a's programme rule.

## Carried from V5.1-c (2026-10-22)

- **`main.gd` keeps its total-lines exception** (2 124 lines, 1 090 code): the decision and programme holds and the desk cards (~130 lines) still live there; moving them out (a `clock_holds.gd`, the plan's) removes the `TOTAL_EXCEPTIONS` entry in `tools/check_size.py`. **Owner:** V5.1d.
- **The panels' fit at text size 130 %** is unchecked: the chrome fits (`test_shell_fit`), the 22 panels were not swept. Text size also leaves the map labels and code-drawn sizes alone. **Owner:** V5.1d, which re-homes every window.
- **The accent casing on the map ramps** (a ramp drawn in the player's accent): a G2 risk. **Owner:** V5.4.
- **`src/sim/` and `src/core/` comments still name `src/ui/message_stack.gd` and its "six card slots"** (diplomacy, foreign_policy_constants, unrest, unrest_constants, nation_state); the inbox keeps every decision and 40 notes. Systems' files.
- **Interface scale is gone**, replaced by Text size; a settings file's old `ui_scale_index` is ignored and the content scale reset to 1. Say so at the play gate.
- **A load keeps the open tab** (c3.2b): the plan's "the stack resets to the map" was not done; the rows and the Decisions lane are rebuilt. One `close_all()` in the load path if a play gate minds.
- **The shell's frame cost**, outside G2: +32 draw calls a frame, 0.2–0.3 ms on the no-map rows; boot's "enter" stage +~106 ms (the shell's `_ready`), the stage sum flat.
- **Glossary tooltips, left for later:** the keyboard path (a `glossary_next` action; RichTextLabel has no per-tag focus) and the 309 `PanelKit.line()` sites go to V5.1d (the parent's call Q4); the six live values that need a context (a partner, a firm, a budget line, a tax, a portfolio, a bloc) and the rest of the closed table read nothing yet (Q2); P1's second half (every entry marked somewhere or in a see_also) waits for Content's markup step; N2 is enforced per block (3), not per paragraph (2); a long body clamps rather than scrolls (the longest locked plate is ~260 px); `TermText` passes the mouse (a card's body stays clickable), so an ancestor with `tooltip_text` would show its tip over a term -- none of c's sinks has one, d's must be checked; the event record's "what it meant" line is still a Label; the French glossary is parked.
- **`tools/screenshot.gd --open summit` frames an empty summit window**; `--summit` stages one.
- **QA's record on #54, routed to V5.1d by the parent:** the programme plate's "—", the history cursor drift, the Legislature window's scroll, and the Commit button's focus. The details are in QA's #54 verdict.

## Carried from V5.1-0d (2026-10-21)

The embassies, the capitals and the runner's verdict; two items measured and left.

- ~~**The hands-off AI aims ~95% of its state visits at the player.**~~ The 0d attribution
  (scratch act counter, hands-off FRA, 168 months through WorldMonth): base 338 of 354
  state visits target France, tip 353 of 375. **The cadence is answered at the V5.1 play
  gate (author's call, 2026-10-22):** a host receives a state visit at most once every six
  months ([[diplomacy-model]], "The host's cadence"); the player now gets 2 a year and the
  AIs visit each other. **Still open, owner V5.4 (the real network):** the cause it
  starves but does not remove -- third-party judgement credits the ACTOR of every friendly
  act with every observer holding a stake in the target, so AI-AI amity saturates (0.5-1.0
  within two years) and an idle player, who never collects that credit, stays the one
  partner with room. Also why the test audit found no AI-to-AI agreement in 168 months.
- **`Capital.city()` refolds the nation's city list on every call.** Microseconds today:
  its callers are a booking, the campaign panel's rows and the campaign's factor. **When a
  per-month caller appears,** the right shape is a fold table the loader builds once
  (folded name -> city, per nation), NOT a static memo -- static memos read by pool workers
  are G2's hazard class.

## Carried from V5.1-a2 (2026-10-21)

Below the V5.1 bar, from `code-review 33 high` (none met it):

- **`message_stack.clear()` runs the `card_dismissed` handler for every card**, plain ones included, before the load resets `_paused_for_decision` and `_unseen_events`: a load from a decision-paused game can briefly set `_clock.paused = false` until the load's own `paused = true` a few lines on. No tick runs between, and the old event-card loop had the same order; moving the flag resets above the clear would remove the ordering.
- **`test_load_hygiene` asserts the ribbon's title only**, not its cells (same dirty flag), and reads `message_stack._cards` and `ribbon._title` (private), as `test_statute_surfaces` already does.
- **A loaded game never gets the "Your term" card** (by the existing comment: "a loaded save never receives it"); an in-game load used to keep, and refresh, the discarded game's card by accident. Not a regression, but the one-line "win the vote by MAY 2027" reminder is gone for loaded games.

## Carried from V5.1-b (2026-10-21)

Localisation plumbing's edge, from the build and `code-review high`; see [[localisation]].

- **A live language switch in game is not done.** `tr()` text is the language a Control was built in; the Settings screen rebuilds itself and says windows opened afterwards follow. Making every open window follow is the shell's work (V5.1c re-homes the windows and can rebuild them on a change). **Trigger:** V5.1c's plan. **Not done in c** (French parked, author 2026-10-21); the trigger is now French un-parked.
- **V5.1b2 wrapped the rest** (about 550 prose literals the b lint could not see: the lint now reads prose anywhere, see [[localisation]]). What stays: single lowercase words away from a sink, fragments of sentences joined at runtime (the French word order of `"%s the %s stance"` will be English-shaped until a whole sentence per case), plurals as two msgids instead of `tr_n`. **Trigger:** the content child reading French in game.
- **Un-wrapped dynamic text that equals a msgid is translated anyway** (Godot auto-translates a Control's text): an issue name "Unemployment" shows French because the top bar's caption is a msgid. Harmless, and a homonym (one English word, two French ones) needs `tr(msg, context)` first.
- **`tools/screenshot.gd -- --menu` ignores `--lang`:** the menu applies the saved language when it comes up. A frame of the French menu needs the setting written to the (isolated) user dir.
- **The default language is English, not the OS locale** (deterministic suites). Defaulting to a French OS's language is the author's call.
- **`Law.law_name` / `summary` have no accessor of their own:** every display site goes through `Strings.law_name(law, fallback)`, one preload line per file against the size ratchet (three files were shrunk to pay for it). A `display_name()` on `Law` (src/core, the Systems child's) would remove the preload.

## Carried from V5.1-a (2026-10-21)

- **The at-icons files are orphaned.** After the Material Symbols swap nothing in `src/` reads `addons/at-icons`; the 24 committed SVGs, the `.gitignore` exception, the REUSE/ATTRIBUTION entries and the docs/tooling.md "committing rule" are dead weight. Delete them in c or d (they touch docs, not code). **Done in V5.1-c (`2f025178`).**
- **Plates are wider with Archivo.** The map-layer legend and the portrait card went from 506 to 628 px, covering more map; c's re-layout (the docked workspace, no minimap) is where it gets absorbed, not a font tweak.
- **The map's data colours stay brass.** Trade and dependency ramps, road/ferry spines, project arcs and the legend's key rows are data colours on the map's own scale, not the interface accent, and are untouched. "No layer reads by colour alone" landed at V5.1-d2 as a lightness rule (every data ramp rises in luminance, each legend stop 1.4:1 over the last; tests/test_map_layers.gd), which retuned the relations, coercion-top and dependency ramps; a wider retune of the map's palette is still V5.4's map work.
- **`events_panel.gd`'s header plate is graded but not unit-tested** (the portrait, the scene backdrop and the arrival card are, in `test_grade.gd`): building the panel needs a state. A silent regression there looks like an ungraded plate.
- **Sliders still wear the engine default** (the budget levers): the theme never styled `HSlider`. A Bureau slider (graphite track, accent fill) is d's, with the dense-table kit.
- **The accent rule shifts hues, and a shift can read as a different colour than the flag.** Resolved in V5.1-a3 for the pick (the band whose hue moves least wins, ties to file order: DEU gold `#e4ff00`, ITA raspberry, IRL turquoise), but the shift itself stays: ITA's green nearest edge is a yellow-green (125), not the turquoise the author's option text promised, and ITA now takes its red as a raspberry like POL and TUR. Forcing the cool edge for greens would be a rule change.
- **The home outline (and every accent stroke) can vanish on the map's data ramps.** Contrast of an accent against the ramp mid-tones is 1.2-1.4:1 for blue, raspberry, green and teal accents on the trade, dependency, relations-warm, production and coercion mids (the accent was lifted to read on graphite, so it has the same luminance as a mid-tone fill); a yellow-green accent (BEL) is low on the trade/production highs. A dark casing under the stroke is the fix; it needs a second line pass over `_roster_line_mesh` with a width-plus-2 variant of `map_line.gdshader` and a G2 re-measure, so it is c's, not a patch.


Below the V5.1 bar, from `code-review 32 high` (the two that met it -- the accent judged on SLATE not HULL, the cluster icons keeping the old accent after a load -- were fixed test-first, the latter by making the pending mark a fixed WARN status tone in pass 2):

- **`Icon.load_icon` injects the fill at `find("<svg ") + 5`**: an SVG whose root tag is followed by a newline or tab returns -1 and corrupts the document. The committed Material files all use a space.
- **`map_face()`'s six callers keep `if font == null` guards that cannot fire** (it falls back to `ThemeDB.fallback_font`), and a missing Archivo re-attempts the load on every call (only a non-null face is cached).

Recorded from QA's pass on PR #32 (`.superpowers/sdd/qa-report.md`), not fixed:

- **The load-path accent re-apply has no test** (`main.gd`'s `_on_load_requested` calls `UiTheme.apply_for` after a load; QA saw it re-theme DEU -> FRA on screen). A test needs a second nation's save through the real load path.
- **Hover readouts and labels draw in the width-62 map face** (`map_view.gd` outline readout plate, tip text) as well as the place names; they were not part of the label-packing problem that needed it.
- **Every load rebuilds the whole theme even for the same nation** (`apply_for` always builds). A cache keyed on the accent colour would skip it.
- **A flag whose bands are all dull but chromatic would fall back** (the rule's fallback is "no band qualifies", not "no chroma"). None does today and `test_accent_rule`'s 0-fallback check turns the suite red on a new one.

## Carried from V5.1-0c (2026-10-21)

- **A programme can only be chosen on the first day of a term.** V5.1-0c stops one keypress from forfeiting it and says when the next opens, but a player who loads a mid-term save still has no programme until the vote. A grace window (the first months of a term) or a "choose later at a cost" is a V5.3 decision-model call, not a UI one.
- **The minimap leaving its frame when menus open, and the UI shifting on a category click** (P5, P6) did not reproduce at 1920x1080 or 1280x1024 with the State drawer, a window and cards open. Ask the author for the window size and the click; V5.1c rebuilds the shell either way. **Gone with the minimap and the action bar (V5.1-c2.3).**
- **A window dragged left still goes under the message column** (an overlay above windows). New windows open to its right (`WindowManager.LEFT_RESERVE`); the author's drag is theirs. Measured by the parent in 0a: six cards covered the budget window's lever column until dismissed -- fixed for placement, not for a drag. V5.1d (windows).
- **Which foreign cards a month pushes now depends on the machine's settings file** (the "News of other countries" switch). Tests that read cards are fine while runs stay isolated (a fresh user dir reads Off); a non-isolated run with the switch On would see more cards.
- **`AgendaPanel.offer_seen` is per panel instance and per `terms_served`**: loading a different save mid-session at the same `terms_served` inherits the seen mark, so the first Space after that load runs without the nudge. Reset it on load if that ever matters.
- **The Settings screen's resolution row is disabled while fullscreen** with no word why; F11 and the Window row are the way out.

Below the V5.1 bar, from `code-review 30 high` (the four that met it -- the Settings rows resetting a dragged window, the panel's stale rows after F11, the un-maximizing mode write, the unguarded Agenda date -- were fixed test-first):

- **The overlay message column has no bound.** Five or six tall decision cards from y=54 cover the legend and portrait and, at the extreme, run their last buttons off the bottom; before this PR the same column pushed the HUD down instead. A ScrollContainer or a max height belongs to V5.1c's shell. **Done in V5.1-c: the inbox's lanes scroll inside the dock (`ae802108`).**
- **The dev console's `pause off` goes through the Agenda guard** (`_toggle_pause_by_hand`) and answers "clock paused" at an unchosen term start; an agent sends it twice. The guard is a player nag; `set_paused` could set `Clock.paused` itself. Cheap, but the console file belongs to 0b's surface.
- **The maximized-window case is not unit-tested** (the headless root has no OS window); the fix is one condition in `SettingsPanel._apply`.

## Carried from V5.1-0b (2026-10-21)

Below the V5.1 bar, from `code-review 28 high` (the two that met it were fixed test-first in `7cd07ad9`):

- **The dev scripts ship in a release export.** `main.gd`'s preload keeps `dev_console.gd` and what it preloads in the PCK; `install()` builds nothing there (and `--dev-console` turns it on), so it is inert, not absent. Fully absent means a `load()` behind the build check and an export filter -- V5.1c, when `main.gd` is rebuilt anyway. **Half done in V5.1-c (`254254f9`): a guarded `load()`, no preload; the export filter waits for an export preset.**
- **`skip 120` is one synchronous call**: ~0.3 s a month, so ~40 s of an unresponsive window (and an MCP call that may time out). A frame-sliced skip would reuse `month_runner.gd`'s cursor; the cap is 120 until someone needs a year-long skip that does not freeze.
- **Clicking the console's log takes focus off the input**, so a key typed next reaches `main.gd`'s hotkeys (S opens the save dialog). Fixing it costs text selection in the log; click the input first.
- **The overlay's per-system month cost includes the step hooks' UI work** (cards built in a step's before/after, inside the timed unit).

Pass 2 (`code-review 28 xhigh`, the parent's), recorded and not fixed:

- **`tests/test_dev_console_game.gd` writes `user://saves` with no `## suite-exclusive:` tag** (the test audit's S11 class). Harmless under isolation, which every run is; tag it if a run ever shares a user dir.
- **The Logger installs in the console's `_ready`, late in `main._ready`, and `menu.tscn` has no console**, so errors raised at boot (the data load, the menu) never reach the counter. Installing it from the menu too, or earlier, is a V5.1c shell decision. **First concrete case (V5.1-0c, found by the parent's smoke run):** the menu's `_ready` called `WindowMode.install()`, whose `add_child()` on the still-busy root window failed with "Parent node is busy setting up children" -- F11 was dead and no counter showed it, because the menu has no console. Fixed by a deferred add; the error was only in the game log. **V5.1-c left it:** it needs `DevLog` to outlive the menu-to-game scene change (a static shared log), a design change to `dev_log.gd`.

## Carried from V5.1-0a (2026-10-21)

The month across frames and the forecast off the frame took the play gate's freezes;
these were measured and left.

- **A test can print "all checks passed" over a subject that never compiled.** Mid-build,
  a parse error in `budget_panel.gd` left `tests/test_budget_panel.gd` reporting all checks
  passed (exit 0) over six SCRIPT ERRORs: its panel was Nil, every check's guard
  short-circuited. A sibling test that
  `preload`s the broken file hangs instead (the SceneTree never quits) until the runner's
  timeout. **Corrected by the test audit (2026-10-21), closed in part at V5.1-0d:** the
  runner never judged by exit code alone -- its verdict has failed on `SCRIPT ERROR` /
  `Parse Error` since V2.1c, and the audit's repro went red through it; the lie is a test
  run by hand with `godot --script`. Since V5.1-0d (S7) the runner also fails a test on
  any `ERROR:` line it did not declare (`## expects-error: <regex>`), the engine's exit
  leak report excepted. **Still open:** the hang -- a frame-driven test should
  `_finish()` when its scene failed to load (test_shell's guard) rather than read through
  a Nil scene until the 1 800 s timeout.
- **An OPEN panel's own refresh is still a frame at the month's end.** The visible-only
  gate makes a closed window free; an open one redraws on the month's sweep, and some
  are slow: law 174 ms, commodities ~60, city ~57, people ~52 (the fix pass's figures).
  With the Legislature window open, every month end is one ~174 ms frame. **Owner:**
  V5.1c/d (the windows rebuilt); the panels' own builds, not the sim.
- **The longest month unit left is Commodities, whole: 33 ms mean, 45 ms worst** (then
  Migration 29/39, Industry 17/24). Inside the ~50 ms target with the draw on top; the
  next slice (per good or per nation, `month_units()` like Economy's) if the target
  tightens.
- **At speed 3 with the budget window open the forecast never settles**: a projection
  (~5 s of work, ~7 s at the frame budget) outlasts a month (~4.5 s), so the rows show
  the last finished forecast, marked "...", a month or two behind. By design, stated in
  `budget_forecast.gd`; a cheaper forecast model (D14's other option) would close it.
- **One unexplained 63 ms frame** in the second tip run of `tools/month_frame_probe.gd`,
  mid-month, 102 frames before the first boundary, not in the first run. Not the month.
- **Below the review bar (the code-review pass), recorded rather than fixed:**
  - a hand-driven `Clock.advance_one_day()` while a sliced month is held runs a second
    month over the half-run cursor (`month_runner.run()` has no guard). Only a tool or a
    test can do it: in play every input waits for the month.
  - an embedded popup (a dropdown left open across the boundary) may take its input
    ahead of the runner's `_input` (subwindow forwarding). Unverified at runtime; the
    open popups today choose UI selections, not commands.
  - mouse events replayed after a window resize during the ~0.4 s hold land at the old
    canvas coordinates.
  - Revert re-projects "now" on an unchanged state (~5 s of background work, rows
    marked "..."), the price of the panel's own commit path calling `mark_dirty()`.
  - a projection dropped mid-Diplomacy leaves `Org`'s static memo on the dropped copy
    until the next Diplomacy settle (one copy, bounded; values unaffected).
  - the visible-only gate is twenty copies of one line; the window manager could stop
    a closed frame's processing once (V5.1c, the shell), and the clock cluster polls
    `held` where a signal would do.

## Carried from the V5.0 fix pass (2026-10-20)

The play gate scored 1/5 and earned one bounded fix pass: the load crash (P1) and the
11-second month end (P2) were fixed; these were measured and left for their blocks.
Numbers are the author's save (FRA, 41 nations, November 2027), headless.

- **PAID at V5.1-0a** (the forecast runs off the frame, `src/ui/budget_forecast.gd`; a
  lever drag ~10 s → 37 ms a frame). **The budget forecast costs ~10 s per redraw with its window open.** Two 24-month
  `Budget.project()` runs of the real model (each ~5 s at 41 nations; D14 recorded
  ~4.5 s for the pair at 29). Since the fix pass the panel draws only while its window
  is showing, so a closed window costs nothing -- but OPEN, every month end and every
  lever move pays ~10 s, and a slider drag pays it per changed frame. The levers are
  NOT broken: a moved lever and Commit apply (health 11.0 -> 12.0 measured); they
  freeze. **Owner:** V5.1d (the forecast's cost, D14). **Fix shape, measured first:**
  the "now" projection once per state change rather than per lever move, the proposed
  one on drag end, then a cheaper model for the forecast than the full month.
- **PAID at V5.1-0a** (every panel gates on `is_visible_in_tree()`). **The other hidden panels still redraw every month: ~0.4 s.** The same `visible`
  gate in every panel (law 174 ms, commodities ~60, city ~57, people ~52, orgs ~31...),
  each refreshing inside a closed window on the month's `mark_all_dirty()` sweep. The
  budget panel's gate was the 12-second share; the rest is a hitch, not a freeze.
  **Owner:** V5.1c (the shell: the window manager can gate every panel at once).

- **`tools/foreign_policy_probe.gd` no longer parses.** The editor reports `Identifier
  "Bloc" not declared` (lines 961, 997, 1012, 1014; 929 calls it too): V3.2a
  (`9a8994f2`) deleted `bloc.gd` and the probe's preload but not its calls -- and
  nothing noticed, because no suite test loads a probe.
  **Owner:** the next block that touches `tools/`. **Fix shape:** the rename in the probe,
  and a parse check over `tools/*.gd` in CI's checks job (load each with
  `--check-only`), which catches the whole class.

## Carried from V5.0d (2026-10-20)

The pre-review hotspot pass (the eight oldest, most-touched `src/` files) fixed what
it could without moving a number; these it recorded instead.

- **`Budget.project()` never ticks Discipline.** It runs `Statute.tick_month`, so the
  projection holds parliament's divisions, but `ns.party_discipline` only falls
  (rebellions) and never drifts toward `Discipline.target()` -- which drops by up to
  0.20 in the twelve months before a legislative election. A close backbench bill with
  a fiscal effect can carry in the forecast and fail in play, or the reverse, and the
  panel's month-24 deficit and debt diverge. Not a probe number (the probe never
  projects); adding the tick adds cost to the projection V5.1d is cutting.
  **Owner:** V5.1d (the budget forecast's cost, D14). **Fix shape:**
  `Discipline.tick_month(sim, loader)` before `Statute.tick_month` in `project()` and
  in `tests/test_budget.gd`'s mirror, priced against D14's budget.
- **A held referendum-route amendment is released without its referendum.** A bill
  carried on route B (a chamber majority, then the country) that a suspensive upper
  house holds is released by `_tick_held_bills()` through `_review_and_apply()`, so it
  takes effect and the referendum is never called. The hold entry does not record the
  route. Only ROU has both a suspensive upper house for amendments and an optional
  referendum, and ROU is not playable; the probe never reaches it. **Owner:** V5.3b (the
  decision grammar over `resolve_vote()` and its callers -- the same pass found two
  more Legislature defects, fixed in V5.0d: the `ordinary_law` bar at exactly half,
  and a held amendment released under a system it was not written for). **Fix shape:**
  carry `"route": true` on the hold entry (absent reads false, correct for older saves),
  and on release call `Referendum.announce()` -- or lapse if one is already in flight.
- **An orphan firm entry keeps its subsidy bill.** `Companies.subsidy_bill_pct_gdp()`
  (and the two counts) walk the register, not the loader's majors, so an entry whose
  firm a content edit removed or renamed without a `SAVE_VERSION` bump bills forever and
  nothing can withdraw it (`available()` refuses the id). It needs a content edit to a
  playable nation's majors -- `2bb07d3f` removed 222 ids at one version, none of them
  subsidised. Walking `majors_of()` instead is byte-identical in a fresh run (same
  order) and also removes a one-ulp difference between a fresh and a loaded register
  (the save sorts keys). **Owner:** V5.4e (firms sited at depth). **Trigger:** any edit
  that removes or renames a playable nation's major.

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

## Carried from the V5.0 replay audit (2026-10-21)

- **Andorra, Monaco and the other micro-states are not in the roster** (the V5.0 play
  gate's P9). The roster is 41 nation files, none for AND, MCO, LIE, SMR or VAT. Parked
  by the author's call (2026-10-21): five near-empty states would add load to every
  system for little play. See [[v5.0-replay]]. **Trigger:** a roster expansion.

---

Related: [[index]] · [[legislature-model]] · [[companies-model]] · [[tax-model]]
