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

### Negative pending rates through `Budget.commit()` (general case)

`Budget.commit()` floors every pending write at zero and refuses unknown
keys, but beyond that trusts its callers; the repeal path floors its negation
at the register (`Legislature._budget_removal`). What remains open is
the general case: any *future* sim caller — the general compose window above
all — could send a negative pending rate, and the pre-existing corporate route
has the same shape today. **Trigger:** the general compose window shipping, or
any new `commit()` caller. **Fix shape:** a commit-side refusal (or floor) on
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
