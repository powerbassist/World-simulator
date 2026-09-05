# BALANCE_PLAN — V2.9b agency probe

Written before any simulation, per the monte-carlo skill's Phase 0. This is a
MEASUREMENT session: no constant changes, no tuning — the fix for any dead
channel is its own session with its own bands.

## Abstract model

| Abstraction | This game |
|---|---|
| Session | One presidential term (16 months, FRA Standard) |
| Threat | Unemployment, debt, grievance — the election attribution's own drivers |
| Defense / agency | Budget levers, laws, diplomacy acts, campaign, projects |
| Faults | Unanswered events (V2.9 now pauses for them), cooldowns, the 49.3 arithmetic |
| Resources | Deficit headroom, assembly arithmetic |
| In-run economy | Spend now vs the debt path |
| Meta economy | Re-election → next term (out of scope: one term) |
| Grade | Final vote share + the "What decided it" attribution |

## Primary metric and band (pre-declared)

**Metric:** true overall approval (`ns.overall_approval_pct`), read at months 6
and 16, as the delta against the idle style at the same month; plus final
incumbent vote share from the executive election the term ends on.

**Agency band:** at least one policy family moves approval **≥ 1.0 point by
month 6** (the polling panel's own readable floor, V2.6b1's clause (i)).
Secondary read: final vote share idle vs active — the playtest's F6 (idle won
26.2 %, active lost 23.4 %) is about whether play moves the outcome at all.

## Determinism correction (supersedes the plan's "30 seeds")

The plan assumed a harness seed grid. The sim has none: it is fully
deterministic (every re-run this project has ever recorded is bit-identical by
design), so N seeds are N identical runs and a CI spread is zero by
construction. The stability read instead comes from **policy variants inside
each family's own free parameter** (a tax-led and a spend-led budget), which
is what the seeds were standing in for. One trajectory per run; runs are
reproducible.

## Styles

| Style | Governing verbs |
|---|---|
| `idle` | none (events still answered — see policy below) |
| `budget-tax` | quarterly budget, tax-led consolidation (income +4, corporate +2, VAT +2; pensions −1.5, health −1.0) |
| `budget-spend` | quarterly budget, spend-led (infrastructure +2.0, education +1.5, health +1.0; income +2.0, corporate −2.0) |
| `full-tax` | budget-tax + best-forecast law each quarter + one agreement act per quarter + one project + one campaign window (month 8) |
| `campaign-only` | no governing verbs; campaign efforts at months 8 and 12 |

Shared policy, so it never confounds the family comparison: events are
answered ON ARRIVAL in every style with the harness's "soft" rule (the
non-default choice best for bloc-weighted approval); campaign sites are the
largest live-population region (a deterministic answer, not an opinion);
law choice is pass-forecast-guided via the sim's own `Legislature.support`
(the same quantity the law panel's blurred forecast prints).

## Verdict rule

`agency PASS` iff any family's month-6 approval delta vs idle is ≥ +1.0
points. Otherwise `agency FAIL`, and per dead family the finding names the
missing term with its measured number beside it.
