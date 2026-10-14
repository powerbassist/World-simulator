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

## Carried from V4.2's close-out (2026-10-05)

Found during the version-close ultra's eight-pass review of PR #48, refuted as
*not this PR's defect* or *not yet reachable* — recorded here so the refutation
is not the last anyone hears of them.

### Negative pending rates through `Budget.apply_pending()` (general case)

`Budget.apply_pending()` floors every pending write at zero and refuses unknown
keys, but beyond that trusts its callers; the repeal path floors its negation
at the register (`Legislature._budget_removal`). What remains open is
the general case: any *future* sim caller — the general compose window above
all — could send a negative pending rate, and the pre-existing corporate route
has the same shape today. **Trigger:** the general compose window shipping, or
any new `apply_pending()` caller. **Fix shape:** an apply_pending-side refusal (or floor) on
negative pending values closes the whole class at the one writer.

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

`_score_choice` divides the size-weighted bloc offset by the weight of the blocs a
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
value (0.0) and `deficit_pct_gdp` moves only when an event's own fiscal effect
recomputes it. Consequences for the events machine: the chooser's unrest term
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

### World prices drift to their clamp within months

Found while converting `commodity_price_high` to an edge (pass 22). The commodity
layer's premise (docs/commodities-model.md, V4.6) is that the world is born in balance
and only a shock moves the price vector; measured on a new game, it is not: at month 1
two goods already sit at or above 1.25x base, at month 3 fifteen do (cotton at 1.75x,
the clamp), and the level read stayed true in 168 of 168 months. The events hook no
longer depends on the level (it fires on a crossing), so nothing is broken, but any
future reader of the price vector inherits a world that is mostly at a clamp.
**Trigger:** a commodities tuning pass, or a feature that reads the price level.
**Fix shape:** find the recipe/supply imbalance that drives the early drift (V4.6
territory: the capacity and demand structure should agree, and the gap sign for the
rising goods says which side is short) before any price constant is touched. **Pass
23:** this drift is why the two hook-bound commodity events were unbound -- the drift
fix is the trigger to re-bind them (previous entry).

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

## Carried from earlier blocks (pointers, not duplicates)

- **The 25 generated nations' majors are generator-owned** — hand-curating
  them means narrowing `firms_generate.py --check` to the body tier first.
  The AUTHOR's call, open since V4.7a's A3 review.
- **The from_dict aliasing sweep** for `plants`/`projects`/`sector_investment`
  (companies itself is fixed, T5 rebuild) — V4.6 §6's record.
- **`PRICE_ELASTICITY` is unvalidated** — the sweep belongs to the first task
  that lets a player cause a shortage (V4.6's record).

---

Related: [[index]] · [[legislature-model]] · [[companies-model]] · [[tax-model]]
