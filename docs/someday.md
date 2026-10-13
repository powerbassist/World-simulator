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

### The projection prices no goods, and `law_passed` has no consumer

`Budget.project()` ticks Events but not Commodities, so the `commodity_price_high` hook
reads a frozen price vector inside the forecast: if prices sit at or above 1.25x base
when the panel opens the hook looks true in every projected month, and a shortage that
develops in the window never appears. `test_budget`'s 1e-9 projection-equals-reality
check cannot see it because its mirror omits Commodities too. **Trigger:** the budget
panel's projection work, or a commodity event that moves the deficit. **Fix shape:**
tick Commodities in `project()` and in the mirror together.

The `law_passed` hook reads `ns.law_ledger`, which records only laws that moved a
ledgered register by a non-zero amount and ignores the institutional channel, so a
constitutional amendment or electoral-reform Act never stamps a month; and no shipped
event uses `law_passed` (7 of 8 vocabulary entries have a consumer). **Trigger:** the
first authored `law_passed` event. **Fix shape:** stamp passage in `Legislature.apply`
itself rather than reading it back off the ledger.

### Flavour text that assumes the Union

`river_flood` mentions "the Union's solidarity fund" and reads oddly for a non-member
player; it is not gated (a flood is a flood) and the copy would need a membership-aware
variant. **Trigger:** the first non-EU playthrough note. **Fix shape:** drop the clause
or split the summary.

### Same-month category collisions favour the early alphabet

The pulsing categories deliver in sorted-name order and the loop stops at a full
desk, so on a nearly-full desk `disaster` beats `unrest` every time. A fixed bias,
swept into E5's spread (all <= 18.9 % against 30) rather than introduced after it.
**Trigger:** a category whose measured share runs below its authored weight, or
QUEUE_MAX shrinking. **Fix shape:** rotate the order by the month or choose among the
pulsing categories by their authored weight.

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
