---
title: Climate Model
tags:
  - model
  - sim
  - events
---

# The climate model — one measured line per head, and the politics of it

V3.5. The block is three things and no fourth: an emissions read over V2.8's
mix, two sited disasters on the event schema, and a fifth org on the V3.2
register. Everything here is a pure read, content, or machinery reused whole —
the re-run prediction in §6 is the claim that nothing else moved, and it held.
Model neighbours: [docs/energy-model.md](docs/energy-model.md) (the mix these
numbers are read off), [docs/orgs-model.md](docs/orgs-model.md) (the council
machinery), [docs/events-model.md](docs/events-model.md) (the schema `sited`
extends).

## 1. The partition — a measured baseline and a share displacement

Emissions are **a read off the mix, not a stock**. The baseline is the nation's
measured per-capita footprint (`imported.emissions.co2e_per_capita_t`, World
Bank `EN.GHG.CO2.PC.CE.AR5`, 29 of 29 at 2024 — the provenance is
[docs/data-sources.md](docs/data-sources.md), which also records why the AR4
code is gone); the fleet is the lever:

```
emissions_tonnes       = start_co2e_per_capita_t * population + deviation
deviation              = sum_b (mix[b] - start_mix[b]) * intensity[b] * national_twh
co2e_per_capita_t      = emissions_tonnes / population
```

The deviation is **share displacement**: a renewable TWh displaces the fossil
share it erodes, weighted by each branch's own emission intensity — the same
shape `dependency_deviation_pct()` prices on the import side, one quantity
over. With an empty register every term is exactly 0.0, and that is the
property the re-run rests on — but the property is **asserted empirically, not
claimed from the algebra**: `tests/test_energy.gd`'s inert check runs FRA, DEU,
CHE, LUX and GBR and compares against float equality, because an exactness
argument written in prose proves nothing a re-run could contradict (the T2
review's correction, kept as the check's own shape).

The per-capita form rides the **live** population, so a growing country drifts
up on its own — correct, and no constant expresses it. The per-capita figure is
also the one the accord's ceiling constrains, which is why the energy panel's
delta row rides it and not the national total.

**`SAVE_VERSION` is 34 on ONE field**: `start_co2e_per_capita_t` is
content-derived static state `NationState.from_dict()` cannot re-derive — the
loader never reaches a save — and absent the field a reloaded France reads
0.0 t against a live 4.0 (V1.6a's check, a fourth content-derived static beside
V2.8's three). The tick-rewritten reading beside it earns nothing by the same
argument's inverse: it is recomputed from the mix on the first tick, and it is
serialised so an unticked save reports the figure it was saved with.

## 2. The intensities — physical constants, not a dial

`emission_t_per_twh` on each source in `data/energy-sources.json`, in tonnes
CO2e per TWh **lifecycle (mine-to-grid)**. The basis is the IPCC AR5 lifecycle
medians — nuclear 12, onshore wind 11 rounded to 12, utility PV 48, hydro 24 —
with the two thermal stations on their fuel figures instead of a technology
median: hard coal ~0.95 Mt/TWh, gas ~0.40 including methane slip. The branch
level is **output-weighted** over its sources (`_branch_intensity()`'s exact
idiom over the emission key), so a branch holding a 6 TWh coal station and a
5 TWh gas one is described by neither alone. These are physical constants,
content and not a swept dial — the probes measure what the model does with
them, never the numbers themselves.

**The hydro note.** The plan's intensity table listed offshore wind in its
sixth row; the catalogue's sixth source is `hydro_scheme`, which carries
**24000** — AR5's hydro median directly, because hydro was the one technology
the planning table had no row for. Offshore wind is a row with no source, added
the day a source is; the file's own `_emission_note` is the rule that covers
every future source, so this paragraph records the mismatch rather than
patching it.

## 3. The ceiling — derived, and the placement rule

The accord's first proposal constrains per-capita emissions at **5.5 t**, and
the number is not authored: it is the EU-27 **population-weighted mean** of the
nations' measured baselines, **5.4687 t**, rounded to 0.5 — the placement
discipline `CONTRIBUTION_MAX_PCT_GDP`'s re-derivation set. **15 of 27 members
are inside at start**, so the division is real before anyone builds anything.
`tools/climate_probe.gd` table (a) recomputes the mean from the committed files
and prints MATCH or MISMATCH against the loaded proposal — a re-import that
moves the numbers turns red here instead of silently re-pricing the council.

**The tolerance was swept, and the sweep's finding is the load-bearing one.**
Below about 5 the pivotal band is EMPTY: every over-ceiling member's cost term
holds the whole 180-seat high-emitter bloc against the rule at every position
on the grid, others-for pins at 203–210, and no authoring of the position can
put France's 69 seats inside the decision. At tolerance **6.0** (severity
0.33) the small-over members — IRL, SVN, AUT, half a tonne to eight-tenths over
— become affordable to their own governments' ideology term and the 219-seat
plateau opens; the position sits at its centre.

**The player is pivotal, and that is the design.** France holds 69 of 452
seats; the ceiling passes 288–452 with her for, carries 219–383 on her
abstention, and fails 219–452 with her against (probe table (b), the real vote
machinery on the live register). The **solidarity clause** (+0.04 % GDP,
standing) is authored OUTSIDE that band on purpose: 306 others-for carries it
whichever way France casts — a coalition's question, and the contrast that
makes the ceiling's pivotal band mean something rather than everything.

## 4. The sited draw — the hazard's own purity

`"sited": true` on the event schema is the whole content-side contract. Where
the crisis lands is drawn at announcement, `Cycle.unit("%s|%s|site", month)`
uniform over the nation's sorted region ids — **pure in (nation, event,
absolute month)**, the same discipline as the hazard itself, so a save reloaded
on the month a flood arrived puts it in the same valley. The register carries
the place **both ways** (`region_id` and `region_name`) because the calendar
draws its diary row off the register and preloads nothing, and `months_left`
only counts down — a save reloaded mid-crisis could not reconstruct which month
drew which place. A non-sited event gains NO keys, so an old save's register
reads exactly as it did.

**Not population-weighted, on purpose.** A weighted draw is Île-de-France for
ever — V2.6b1's static-site finding, measured there at a 73.9 % winner-over-
runner-up margin — and a disaster that cannot move is a decoration. The flip
side is the **single-region bound**: CYP, EST, LTU, LVA and MLT take index 0,
because a nation of one region cannot differ from itself and a hash there would
be a second answer to a question with one response.

The UI names the place and nothing else learns it exists: the card title and
the Dispatches question read `region_name` off the register, the calendar stays
a leaf. The shipped content is two events: **`river_flood`** (no gate,
likelihood 0.06 — rain is not deserved, the scandals' own argument) and
**`heat_wave`**, gated on `co2e_per_capita_t >= 6.5`, measured before it was
authored: the gate opens for **7 of 29** (LUX, EST, BEL, CZE, DEU, POL, NLD),
never for France at 4.0. The plan-time description said roughly the dirtier
half; the roster says the dirtier quarter, and the count is recorded rather
than the threshold tuned to the sentence. The field is live, so the gate
follows the grid a government actually builds — which is the event's point.

## 5. The clamp contact — the measurement V3.2 owed

orgs-model named the bound: a nation defying every eu rule gains no opinion
price from defying a second org's rule, **and the session that authors a second
rule-carrying org owes the re-measurement**. The accord is that org, and
`tools/climate_probe.gd` tables (d) and (d2) are the committed instrument.

One real rule per org, France breaching all three past tolerance: raw burden
**0.88** (eu 0.33 + nato 0.22 + accord 0.33) — **the clamp does not contact**,
0.12 under `BURDEN_MAX` 1.0. Total defiance of every authored rule in force is
where the finding is: the pre-existing set filled the clamp **exactly** — eu's
three rules at 0.78 plus nato's 0.22 — so the ceiling's 0.33 reads a raw total
of **1.33 against `BURDEN_MAX` 1.0, a 24.8 % overhang**. A defier of the whole
register loses a quarter of the opinion price to the ceiling — the clamp is now
a real ceiling rather than a formality, which is what the bound owed a number
for.

## 6. The re-run

**Prediction, written first** (BALANCE_PLAN.md's V3.5 section): two channels
only — the solidarity transfer entering France's spending total after the
tick-42 division (2029-07; +0.04 % GDP), and the flood's displacement of the
one pending slot (whole authored effects at moved months, not last digits) —
zero outcome changes, and every excluded channel bit-identical. The block
shipped no tuned constant, so no band is pre-declared; that absence is the
entry.

**Held.** Both sides from worktrees, 51 regimes both sides, **43 moved** (the
8 still ones all stop at tick 17, before the division — stillness by timing,
not immunity), **869 moved line-positions**, **1498 column-moves** across the
423 paired annual rows, **zero outcome changes**. Of 280 deficit column-moves,
**259 sit at exactly the three transfer magnitudes**; GBR, not a member, carries
no +0.04 anywhere — non-membership immunity confirmed rather than assumed. The
ceiling's adoption left **no fingerprint on any printed line** (the handoff's
"< 62 %" pass-fraction note was corrected at prediction time and the run
confirmed the correction), and `heat_wave` drew nowhere, as predicted. The
prediction missed twice, both recorded beside the verdict: it inherited the
62 % note, and it undersold the event channel's magnitude — ten floods plus
displaced crises' re-rolled months compound to whole points of bloc spread in
the two regimes that answer them.

## 7. The refusals

- **No temperature, no carbon stock.** Emissions are a flow read off the mix;
  nothing integrates it into a climate state, and no field anywhere carries a
  national tonne-stock. The event gate reads the per-capita flow directly. A
  stock is a design a future block can argue for; a stock nobody reads would be
  V2.2a's inert register with the serial numbers filed off.
- **No regional price channel — the author accepted the gap at the plan gate,
  2026-09-10.** The flood names a region and its price lands on the nation; no
  grievance accrues where the water was. The precedent is V2.6b1's siting
  record: a regional opinion channel there was refused as *a second approval
  number with a different label*, V1.5c's reason, and the same shape argues
  here — an unrest term keyed to the struck region would be the unrest channel
  wearing a postcode.
- **No fund yet.** The accord's own summary promises "the fund that pays for
  the transition"; what ships is the solidarity clause's standing +0.04 % GDP —
  the trigger the org file names. The first adopted proposal that prices a
  co-member bonus gets its own measured band, eurozone's and schengen's
  zero-priced precedent with the named trigger carried whole.
- **No AI desire for membership.** Accession and withdrawal are
  player-initiated only, V3.2's refusal at one more org: the EU-27 founders are
  content, GBR and CHE's questions exist for the player to ask, and inventing
  an unmeasured appetite for either is the synthetic-appetite shape.
- **No tuned constant.** The disasters' magnitudes are authored effects on the
  two channels every event already rides; the ceiling's value is derived; its
  tolerance and the accession positions were swept with the evidence in the
  content's `_note` lines. A `climate_constants.gd` would have been
  `siting_constants.gd`'s unused-0.0 ending again.

Related: [[energy-model]] · [[events-model]] · [[orgs-model]] ·
[[data-sources]] · [[ROADMAP]]
