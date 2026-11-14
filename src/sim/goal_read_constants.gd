extends RefCounted

## The goal read's standard steps (docs/design/finance-bill.md section 11, call 3 (a)):
## what one notch of a lever is when every lever is ranked side by side. A spending
## line moves half a point of GDP each way; a tax rate moves its kind's own step each way
## (TaxLibrary.step_pct, the parent's ruling of 2026-11-14 that replaced one point for
## every kind); a step that would leave the kind's rate_range_pct (or take a line below
## nothing) is not offered.
const SPENDING_STEP := 0.5

## Tier 2's horizon: the two years the screen promises, the budget forecast's own span.
const YEARS_MONTHS := 24
