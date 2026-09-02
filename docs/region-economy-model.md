---
title: Region Economy Model
tags:
  - model
  - simulation
---

# The Economy From Below

National GDP is the sum of its regions. Built at [[ROADMAP|V2.5]];
[[tiers/v2|V2]] section 5. The register it reads is [[geography-model|V2.2a]]'s.

## 1. What changed

From the MVP to V2.4 `ns.gdp_eur_bn` was the sum of the three sectors, and
`Economy._apply_growth_to_sectors()` computed its own target as
`gdp × monthly_factor(growth)`. V2.5 swaps the definition in one move:
`Regions.tick_month()` grows every region and returns their sum, the tick
hands that sum to `_apply_growth_to_sectors()` as the target, and the
function's last line is now

```gdscript
ns.gdp_eur_bn = target_gdp
```

There is no reconciliation term, no fudge factor and no rescale-the-regions-
to-match pass — the partition **is** the model. The three sectors still
reconcile to GDP exactly (the cyclical residual is distributed by weights that
sum to 1.0), so the sector sum and GDP now agree to 1e-9 relative rather than
to the last bit — asserted at that precision in `tests/test_regions.gd`
alongside the partition closure itself, which holds to better than 1e-12
relative over 168 months for FRA, DEU and GBR (`tools/regions_probe.gd`
table (c)).

## 2. The refused alternative

Keep `ns.gdp_eur_bn` as the sector sum and normalise regional weights into
it. Exact by construction, bit-identical for free — and **top-down wearing
the partition's clothes**, one step from the ninth-addend version
[[tiers/v2|§5]]'s own warning box already declined. Recorded because a later
session under balance pressure will reach for it; the recorded refusal is the
reason not to.

## 3. The three authored fields

Written into `data/regions/*.json` by `tools/import_data.py`, all at 2022:

| field | source | range | normalisation |
|---|---|---|---|
| `gdp_share` | Eurostat `nama_10r_2gdp` (MIO_EUR) | (0, 1] | floored to 6 dp; named regions sum ≤ 1.0, the remainder is extra-regio |
| `unemployment_rel` | Eurostat `lfst_r_lfu3rt` (Y15-74, TOTAL) | (0, 5] | the region's rate over the nation's, renormalised so the **population-weighted mean over the named regions is exactly 1.0** |
| `sector_mix` | Eurostat `nama_10r_3gva` (CP_MEUR), six `nace_r2` branches folded to the game's three sectors | sums to exactly 1.0 | two floored, services the remainder — a mix is a partition of the region, so it closes with no unnamed rest |

Two joins the plan did not contain, both measured rather than invented:

- **The Dutch vintage sibling.** The register is the 2021 geometry, and the
  GDP and GVA series answer Utrecht and Zuid-Holland only under their 2024
  codes (`NL35`, `NL36`). That they are the same provinces is proven by the
  population series, which answers under both: NL31 = NL35 = 1 369 873 and
  NL33 = NL36 = 3 753 944, **equal to the person** — the same evidence
  V2.2a used to collapse the population file's two vintages, read in the
  other direction. `VINTAGE_SIBLING` in the importer is that join; no
  figure is authored.
- **Switzerland's mix-only fallback.** `nama_10r_3gva` carries a TOTAL
  branch for Switzerland and **no branches at all**, while its regional GDP
  and unemployment are fully measured. So `gdp_share` and
  `unemployment_rel` stay measured and every Swiss region carries the
  nation's own World Bank sector shares (already committed in
  `data/nations/CHE.json`). **Switzerland has no mix divergence** — a bound
  recorded, not a defect patched. The whole-nation proxy stays Britain's
  alone.

## 4. The zero-mean deviation

A region's trend is its own mix read through `economy_constants.SECTOR_TREND`
— the same expression `Economy.trend_pct()` applies to a nation:

```
trend_r = Σ_s sector_mix[r][s] × SECTOR_TREND[s]
mean    = Σ_r w_r × trend_r        (w_r = region's live GDP share)
dev_r   = trend_r − mean
```

so the GDP-weighted mean deviation is **exactly zero** — asserted, not
assumed. This is `Trade.sector_shift()`'s sum-to-zero rule one level up,
enforced by subtraction rather than by a load-time check. A region's mix
moves its share of the country and never the country's level. The residual
(entry under `RESIDUAL_KEY`) grows at exactly the national rate and carries
the named mean, contributing nothing to it.

**No tuned constant for the growth channel.** The honest coefficient is 1.0 —
a region's trend simply *is* its own mix's trend. A `MIX_BETA` in front of it
would be one strength written twice, `investment_action.gd`'s refusal.
`src/sim/region_constants.gd` holds a key and a bound, and
`tests/test_regions.gd` reads the file and fails if a third `const` appears.
All three candidate mutations were watched going red: an added constant, a
dropped register from a round trip, and a regional stock on `NationState`.

## 5. The residual gets a level, never a share

Extra-regio — offshore, embassies, ships — is what `<CC>ZZ` holds and why it
was never in the roster. Shares are still never stored
(`Region.national_gdp_residual()` derives one); the **level** needs a home or
the sum cannot close, so `region_gdp_eur_bn` carries one extra entry under
`region_constants.RESIDUAL_KEY = "_residual"`. An underscore cannot begin a
NUTS code, so the key cannot collide. It is seeded as `gdp − Σ named` so the
entries close on the national figure exactly at month zero.

## 6. Regional unemployment is a pure read

```gdscript
clampf(ns.unemployment_pct × unemployment_rel − OKUN × dev_r, UNEMP_MIN, UNEMP_MAX)
```

`src/sim/credit.gd`'s stateless shape: nothing accumulates, nothing is
serialised, and `Economy._update_unemployment()` keeps its single writer. A
regional stock would be a second answer to the Okun term the macro model
already owns — `companies.gd`'s argument at V1.4a. **This is the reason
`SAVE_VERSION` bumps on one field rather than two.**

The decomposition is asserted in its two exact halves, because the plan's
single-figure check was a **real red** and the reason is two weightings, not
bad arithmetic: the ratio part (`national × rel`) decomposes exactly in
**population** weights — that is what the import normalises — while the Okun
term is zero-mean in **GDP** weights, so its population-weighted mean is a
residual of **0.0037 points** at new game, three orders under the ±3.0 poll
floor. Bounded at 0.01 in the test, with the why beside it.

## 7. The divergence channel, measured

`tools/regions_probe.gd`, run over 168 months:

```
=== (a) starting spread: output per head against the national average ===
  FRA  richest Ile-de-France                  x1.624 | poorest Hauts-de-France                x0.769 | ratio 2.111
  DEU  richest Hamburg                        x1.774 | poorest Thüringen                      x0.712 | ratio 2.490
  GBR  richest Northern Ireland               x1.000 | poorest North West (England)           x1.000 | ratio 1.000

=== (b) divergence: the ratio at month 0, 60 and 168 ===
  FRA  2.111 -> 2.119 -> 2.132   moved 0.021   READABLE
  DEU  2.490 -> 2.502 -> 2.524   moved 0.034   READABLE
  GBR  1.000 -> 1.000 -> 1.000   moved 0.000   BELOW THE PANEL'S OWN PRECISION

=== (c) does the partition close? ===
  FRA  worst relative gap over 168 months: 0.000000000000
  DEU  worst relative gap over 168 months: 0.000000000000
  GBR  worst relative gap over 168 months: 0.000000000000

=== (d) SHARE_DRIFT_MAX 0.150 -- what is left over ===
  FRA  worst drift 0.0019, slack 0.1481
  DEU  worst drift 0.0007, slack 0.1493
  GBR  worst drift 0.0000, slack 0.1500
```

Table (b)'s pre-committed band was **at least 0.010** (one digit of the
panel's own %.3f) and **at most 0.500** (one region running away). FRA and
DEU clear the floor by 2× and 3×: the mix channel is **readable, not
decorative**, and no kill switch fired. `SHARE_DRIFT_MAX` is a bound with
**78× slack** — checked, never clamped, exactly the position
`projects_constants.gd` reached first.

The starting spread is the import's own evidence: nothing authored Île-de-
France at 1.62× the national output per head or Thüringen at 0.71× — the two
partitions divided by each other did.

## 8. Britain: the honest gap

All three Eurostat series carry zero `UK` geo codes at every year. The ONS
gate: `regional-gdp-by-year` publishes ITL1 `UKC`–`UKL` — **ten of twelve** —
plus England and extra-regio; **Scotland and Northern Ireland are published
by the devolved administrations and are not in the product**, and the product
is an annual **index** (cvm) rather than a monetary level besides. The gate
was all twelve; it failed; **the proxy was taken**: a British region's
`gdp_share` is its population share, `unemployment_rel` is exactly 1.0, the
mix is the national mix, and `data/regions/GBR.json`'s `_source` says so in
words.

**BRITAIN HAS NO REGIONAL DIVERGENCE AT ALL** — table (b) measures it at
`moved 0.000`, and that is a recorded bound with the number beside it, not a
bug. Handing it forward: closing the gap means an authored twelve-number
table (the devolved administrations' own products), and [[tiers/v2|§6]]'s
migration reads regional unemployment — which for Britain is the national
rate everywhere, so British internal migration would need the same authoring
first. **V2.6a shipped without it, exactly as this predicted**: the region
level is dead for Britain and the city level turned out to be a whole signal
on its own — Britain migrates on named employers alone, and the bound and its
number now live in [[migration-model]] §5.

## 9. The balance re-run

**Predicted before the build**: bit-identical in every printed figure, not
bit-identical at the bit level, zero outcome changes — because with
`Σ w_r dev_r = 0` exactly, `Σ_r w_r · f(g + dev_r)` differs from `G · f(g)`
only by the second-order Jensen term `½ f″ · Var(dev)`, on the order of 1e-9
relative per month at the measured spread.

**Measured** against a fresh 144-run baseline (48 regimes × FRA/DEU/GBR)
captured on this branch before the spine moved — both sides from worktrees,
so the worktree's missing-addon parse noise is identical on both sides and
cancels in the diff:

- **143 of 144 runs identical in every printed figure.**
- 1 of 144 (`tax_zero_DEU`) differs by **one digit in one year**: the 2027
  debt ratio prints 88.8 before and 88.9 after — a `%.1f` rounding boundary,
  which is the predicted not-bit-identical-at-the-bit-level half surfacing
  exactly where a value sat on an edge. Approval and every outcome line in
  that run are identical.
- **Zero outcome changes** across every HELD/LOST/DISSOLVED/amendment line
  in all 144 runs.

The escalation trigger ("a printed figure moves → find the normalisation
defect") was taken seriously and the answer is in the arithmetic, not a
widened tolerance: the zero-mean is exact (asserted), the spread is small
(table (b)), and a single last-digit flip on a rounding boundary is the
Jensen term reaching a print edge, not a trend.

**No new regime**, predicted in advance for the fourth session running
(U6c, V2.2b, V2.3, V2.4b's summit half): V2.5 ships **no verb**, no budget
regime can reach it, and every existing regime exercises the new code
because every one calls `Economy.tick_month()`.

## 10. `SAVE_VERSION` 28

One field earns it: `NationState.region_gdp_eur_bn`. Absent, every entry
reads 0.0, the sum is 0.0, and the definitional swap writes national GDP to
zero on the first tick — the country does not run a different model, it
ceases to have an economy (`military_capability`'s case at V1.3g in its
strongest form). Re-seeding on load does not rescue it: the authored
`gdp_share` is where a region **started**, and re-seeding would erase the
divergence the player watched happen (`service_quality`'s reason at V1.5a).
The two absences still pinned: the **shares** round-trip through
`data/regions/`, and **no regional unemployment stock** exists to store.
`tests/test_save_load.gd` asserts the presence, the two absences, the
stripped-register round trip, and all ten earlier version pins now name 28
with V2.5's reason.

## 11. What V2.5 did NOT build

- **No map layer.** `LAYERS` stays at four; `tests/test_map_layers.gd` pins
  it. A regional choropleth is a different draw pass and nobody has asked
  for one yet.
- **No verb.** §5 has none; V2.5 runs under V1.5's inverted block rule and
  ships a statistic, which §6 and §7 will charge for.
- **No city economy.** A city still holds a share of its region's
  population and nothing else; `city.gd`'s own unrecognised-field error now
  says §6 is what comes to change that.
- **No new window and no new keyboard key.** The readout is the existing
  Region (T) and Economy panels; `--diverge` is the one new screenshot flag.

## 12. The readout

The Region panel (T) carries both partitions side by side — named share of
population **and** named share of output — and a seven-column league table:
share of output, people, **output per head against the national average**
(the column nobody authored), live unemployment, dominant sector, named
jobs. The economy panel carries one line, never silent, leading with the
ratio because that is what moves. `tools/screenshot.gd --diverge` ticks ten
years and opens the panel at the top of its scroll; the three frames this
session captured (`--diverge`, `--region`, `--open economy`) all judged
clean — the twenty-first pass found **no bug**, V1.6c's precedent, reported
as such.

## 13. What passes to §6 and §7

Three hand-offs were written here at V2.5, and V2.6a collected them — recorded
how, so the next reader does not treat them as open:

- **A fixed geography of rates** — collected **unchanged**. `Migration.region_pull()`
  reads regional unemployment through the same pure read, and `unemployment_rel`
  is STILL static after import: nothing moves it, so migration's employment half
  differs between regions only where the mix deviation moves the deviation term.
  A mover of the ratio is still unwritten, and whoever writes one owes this
  section's two-weightings finding a second look.
- **A city with no economy** — **passed through whole**. V2.6a gave the city a
  head count that moves (two live shares, [[migration-model]]), not output, wages
  or jobs of its own. `city.gd`'s error string is unchanged from V2.5 and still
  defers the head count to §6 — *left the city a share of population, which is
  what docs/tiers/v2.md section 6 comes here to change* — a framing V2.6a has
  made stale in the humbler direction: the head count it defers now exists, and
  the economy is the part still owed. Updating the string is a `src/` edit no
  docs pass carries.
- **Britain's proxy** — **collected as exactly the bound it predicted**: every
  British region's expected income is identical by construction, so Britain's
  region column is 0.0000 at every rate and its people move on named employers
  alone ([[migration-model]] §5). The day the twelve ITL1 figures are authored,
  `tests/test_migration.gd`'s flat-pull assertion is the tripwire.
