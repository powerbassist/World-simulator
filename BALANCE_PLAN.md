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

---

# BALANCE_PLAN — V3.0 agency tuning

Written 2026-09-05, before any run of this block; not edited after a sweep
begins. The V2.9b probe's numbers are the band inputs and are quoted in
docs/superpowers/plans/2026-09-05-v3.0-agency-tuning.md.

| # | Band | Pass condition |
|---|---|---|
| B1 | Fiscal signature | budget-tax approval delta vs idle at month 6 in [+1.0, +4.0]; budget-spend month-6 delta ≥ −1.0 |
| B2 | Grievance | governing styles' month-16 grievance ≤ idle + 5.0 (today +15.5); idle within ±0.5 of 1.9 |
| B3 | Honeymoon/fatigue | idle approval month 2 ≥ idle-at-start + 3.0; idle month 16 within [48.0, 52.0]; a re-elected nation reads the honeymoon again |
| B4 | Campaign power | campaign-only final vote share ≥ idle + 1.0, OR the refusal recorded in campaign-model.md with the measured ceiling |
| B5 | Outcome monotonicity | across probe styles, approval ordering implies vote-share ordering; no flip between styles whose approval differs by ≥ 1.0 |
| GATE | Agency | `tools/agency_probe.gd` re-run: at least one family ≥ +1.0 approval at month 6 vs idle, AND the best active style's final vote ≥ idle's |

Anchor: the idle style's own path (m6 49.18, m16 49.52 at the V2.9b
constants) must not move more than ±0.3 except through the honeymoon term
itself (B3 owns months 1-6).

### V3.0 mid-block pre-declaration (before the style's first run)

The `budget-smart` style is added to tools/agency_probe.gd: a low-pain
consolidation (defence -1.5, infrastructure -0.5, income +4.0 only) whose cuts
land on lines the mobilised blocs weight at or near zero. It exists to
separate "the budget-tax style cannot reach B1" from "no fiscal stance can".
B1's spend-led clause is likewise amended before further sweeping: the
deficit-worsening side's grievance IS the amplified public_finances pain, and
a relief term that cancelled it would be a grievance blind to deficits — so
B2 reads: consolidating styles (budget-tax, full-tax) month-16 grievance <=
idle + 5.0; budget-spend is recorded as bounded, not swept against.
