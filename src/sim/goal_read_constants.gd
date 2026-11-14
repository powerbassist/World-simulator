extends RefCounted

## The goal read's standard steps (docs/design/finance-bill.md section 11, call 3 (a)):
## what one notch of a lever is when every lever is ranked side by side. A spending
## line moves half a point of GDP each way, a tax rate one point each way; a step that
## would leave the kind's rate_range_pct (or take a line below nothing) is not offered.
const SPENDING_STEP := 0.5
const RATE_STEP := 1.0

## Tier 2's horizon: the two years the screen promises, the budget forecast's own span.
const YEARS_MONTHS := 24
