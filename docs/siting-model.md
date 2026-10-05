---
title: Siting Model
tags:
  - model
  - simulation
---

# A Place For What Happens

The contract by which a national quantity acquires a place. Built at
V2.6b1; [[tiers/v2|V2]] section 6. It reads
[[migration-model|V2.6a]]'s two live share registers and
[[region-economy-model|V2.5]]'s regional quantities, and it is the schema
[[tiers/v2|section 9]]'s sited disasters will read.

**This session shipped a contract and one price, and DELETED the other price it was
designed with.** The deletion is the result rather than a retreat from it, and the
numbers are in §5.

## 1. What changed

`src/sim/siting.gd` is a new leaf that preloads **nothing**: a caller hands it two
Dictionaries — weights and a signal — and gets back a region id. `src/sim/unrest.gd`
uses it to give the grievance a place, and prices that place into the **output**
channel alone. There is no new window, no new map layer, no new keyboard key, **no
verb**, and **no tuned constant anywhere in the session**.

The readouts are three, all derived and none stored: the economy panel names the
place under its existing unrest line, `src/ui/main.gd`'s message card names it on the
act, and `src/ui/map_cities.gd` draws a **ring around the city cross that is already
there**. `--site` is the one new screenshot flag.

## 2. THE ROW'S CENTRAL CLAIM IS FALSE, AND THE PROJECT HAD NO WAY TO ASK

's V2.6b row says both its halves *"decide **where** by reading V2.6a's
live shares"*. Measured before any code was written, that is wrong: the site is chosen
by **static content**, and the live shares are third-order behind it.

The instrument is `Siting.margin()` — the winner's score over the runner-up's, minus
one. Under the shipped scoring form, at month one:

| nation | site | margin | does the signal choose it? |
|---|---|---|---|
| FRA | Hauts-de-France | **+73.9 %** | **yes** |
| DEU | Nordrhein-Westfalen | **+0.4 %** | no |
| GBR | *(none)* | — | no |
| ITA | Campania | +23.6 % | no |
| ESP | Andalucía | +1027.6 % | no |
| BEL | Région wallonne | +37.8 % | no |
| CHE | Région lémanique | +504.8 % | no |
| NLD | Zuid-Holland | +143.4 % | no |
| AUT | Wien | *only one scores* | no |
| LUX | *(none)* | — | no |

Migration's entire fourteen-year budget is **0.0164 share points**, about **9 %
relative** on a large region ([[migration-model]] §6). A margin of 73.9 % is eight
times that; a margin of 1027.6 % is unreachable by any mechanism this game has. So for
nine nations of ten the place is decided at load time and never revisited.

**And the signal changes the answer for exactly ONE nation of ten.**
`Siting.signal_moves_site()` compares the arg-max under the signal against the arg-max
under a flat signal, and only France differs — everywhere else the population weights
alone would have named the same region. Britain is the sharpest case: its
`unemployment_rel` is exactly 1.0 across all twelve regions ([[region-economy-model]]
§8's ITL1 index proxy), so under the *level* form its "signal" is population share
wearing a signal's clothes, at a margin of +2.1 %.

**Nothing in this project could previously have asked that question**, which is why the
row could assert a live read that is arithmetically static and no check contradicted
it. `margin()` and `signal_moves_site()` are public surface for that reason, and **a
later session siting anything owes its own margin before claiming a place moves** —
U6c's *a lon/lat nothing reads carries no information*, one level up.

### The site DOES move twice, and the exceptions are the interesting half

Run over 168 months of austerity through the real tick:

| nation | distinct sites | @ month 1 | @ month 168 | margin @1 → @168 |
|---|---|---|---|---|
| FRA | **1** | Hauts-de-France | Hauts-de-France | +73.5 % → +57.0 % |
| DEU | **2** | Nordrhein-Westfalen | **Berlin** | +0.4 % → +0.2 % |
| GBR | **2** | *(none)* | *(none)* | — |

**Germany's demonstrations move from the Ruhr to Berlin**, and the knife edge was
named in advance rather than discovered: at +0.4 % the margin is inside the reach of a
0.0034 share drift. It is **deterministic** — both sides of a re-run see the same
crossing in the same month — so it is a story rather than noise.

**Britain acquires a site during the run and loses it again**, which corrects a claim
made at plan time. Britain's regional unemployment is flat, but `Regions.unemployment_pct()`
also carries `− OKUN × trend_deviation`, and the mean it is measured against is
**GDP-weighted** — so as V2.5's divergence moves the GDP weights, the mean trend shifts
and a region can cross its own nation's mean. Britain is therefore **unsited at month
one** and not permanently unsited, and `tests/test_siting.gd` asserts the first and
deliberately not the second: a test claiming Britain can never be sited would be
asserting something the model does not do.

Luxembourg is the one unconditional bound: one region cannot differ from itself, at any
rate, in any month — [[migration-model]] §5's bound a second time and unchanged.

## 3. THE SCORING FORM FLIPS THE SIGN OF THE PRICE

Two forms were available and the choice is not cosmetic.

**The level form** scores `share × unemployment` and puts the demonstration where the
most people are. **The deviation form** scores `share × max(0, unemployment − the
nation's own share-weighted mean)` and puts it where the *excess* unemployment is —
[[trade-model|`Trade.sector_shift()`]]'s zero-mean idiom, used here as a **selector**
rather than as a conservation law, and its fourth instance in the project.

They disagree about France, and the disagreement carries the whole price:

| | level form | deviation form (**shipped**) |
|---|---|---|
| FRA's site | Île-de-France | **Hauts-de-France** |
| output per head there | ~1.62 | **0.759** |
| concentration there | ~1.85 | **0.897** |

**A high-unemployment region is systematically a poor, small region**, so the shipped
form's multipliers come out **below one** for most of the roster — FRA 0.759, ITA
0.644, ESP 0.740, BEL 0.737, DEU 0.947, only AUT above at 1.147. **Siting makes unrest
CHEAPER, not dearer.** A strike sited where the grievance actually is costs the country
less output than the same strike in its capital would, and nothing authored that.

The deviation form ships on two grounds: it is truer — a demonstration happens where the
grievance is, not merely where the people are — and it is the project's own idiom. The
level form is recorded here with its figures rather than deleted silently, because a
later session reading only the code would see an `excess()` call and not know that the
obvious alternative was measured and rejected.

## 4. The output price, which needed no constant

`Unrest.act_impulse()` is multiplied by the site's output per head:

```
impulse = -UNREST_IMPULSE_SCALE * (unrest / UNREST_MAX) * output_index(site)
```

**This price ships no coefficient, and that is worth stating because a later session
will look for the missing one.** [[region-economy-model|V2.5]] already publishes
`Regions.gdp_per_head_index()` normalised to 1.0 at the national average; all V2.6b1
adds is `Siting.normalised()`, which makes the **share-weighted mean of the multiplier
exactly 1.0** rather than approximately so — the two partitions and the residual do not
sum alike. A coefficient in front of it would be one strength written twice, which is
`investment_action.gd`'s refusal.

The consequence is the one that matters: **the EXPECTED price is unchanged and only
the per-nation variation is new**, so `UNREST_IMPULSE_SCALE` keeps the calibration
V1.5c measured for it. Measured on the real register, the worst deviation from a
mean of one anywhere in the roster is **2.22e-16** against a 1e-12 tolerance — about a
4500× margin — and `tests/test_siting.gd` asserts it rather than trusting it, because
a multiplier whose mean is not one is a silent retune of a banded constant.

It is definitionally right as well as cheap: output lost is lost where it happened.

## 5. THE VISIBILITY PRICE WAS DESIGNED, BANDED, SWEPT AND DELETED

The second channel was to be a factor on `ns.unrest_opinion_load` — a demonstration in
a more concentrated place is more visible and costs the president more — with one tuned
constant, `SITE_VISIBILITY_BETA`, behind it.

Two clauses, both fixed before the sweep and **both model criteria**, so under
[[decision-log|V1.5d]]'s rule neither edge is a guard rail and the midpoint would have
shipped. Both are read on the same observable and in the same unit, points of the worst
bloc approval row, because a band whose clauses are in different units cannot be read
against itself:

- **(i) READABLE** — at least **1.0 point**, which is one digit of
  `src/ui/polling_panel.gd`'s own `"%.0f%%"`. Deliberately *not* the ±3.0 poll floor:
  V1.6a's cycle and V1.5c's own output channel were each measured against that floor
  and found structurally unable to reach it, and **a band an observable cannot reach is
  a bound rather than a selector**.
- **(ii) SITING MUST NOT OUTWEIGH GOVERNING** — below what settling the strike is worth
  on the same row.

**The passing interval is EMPTY on all three grids.** Measured on FRA austerity over
sixty months:

| quantity, worst bloc row | points |
|---|---|
| the **whole** unrest opinion price | **2.9825** |
| one saturated settlement | **0.4450** |
| clause (i) demands | ≥ 1.0 |
| clause (i) first crosses at | β ≈ 3.1 |
| clause (ii) is crossed at | β ≈ 1.3 |

A readable siting term must be **a third of the entire unrest opinion price** and
**2.25× what settling the strike is worth**. The two clauses are **inconsistent rather
than badly tuned**, and the reason is V1.5c's own finding read from the other side: the
opinion model prices rates and ratios, the whole unrest channel only just clears the
poll floor at three points, and a *modulation* of a three-point channel is a fraction of
a fraction. That is [[cycle-model|V1.6a]]'s legibility floor in a fourth place.

**The kill switch was declared before the sweep and it is honoured.**
`src/sim/siting_constants.gd` was **deleted, not left at an unused 0.0** — V1.3e's
treatment of `AGREEMENT_ACCEPT_MIN` and `SUPPORT_SIGMA`, because a tuned constant
nothing reads is a number a later session finds and reasons from. **V2.6b1 therefore
ships no tuned constant at all**, which is `projects_constants.gd`'s and
`pledges_constants.gd`'s position a third time.

`tests/test_siting.gd` pins the deletion: the file must not exist and `unrest.gd` must
not name the constant, so a session re-adding it turns the test red and **has to come
with a fresh measurement rather than a fresh opinion** — V1.3c's device, pointed
forward.

> **The concern the author raised and reaffirmed, recorded rather than buried.** The
> author chose both channels twice, once before §2's measurement existed and once after
> being shown it. What closed the second channel was not that call but the sweep: with
> the site constant, a visibility factor is a constant per nation, and the band written
> to test whether it was worth having came back empty. A later session under balance
> pressure that wants unrest sharper should read §5 before reaching for a constant, and
> should re-measure `margin()` before assuming the place moves.

## 6. An affine factor was written and replaced mid-build

The visibility factor was first `1 + β·(concentration − 1)`. It goes **negative** past
`β = 1/(1 − c)` — **3.47 for Belgium**, whose site is the roster's least concentrated at
0.712 — and a negative load is not a small price, it is **unrest raising approval**.
Guarding that with a clamp would have let the clamp set the number, the failure
`IMPULSE_MAX` was caught making in five places.

The replacement is `pow(concentration, β)`: positive for every β and every positive
concentration, so **there is no bound to set wrong** — V1.6a's argument that a bound
with no number beats a clamp, and `Campaign.turnout_of()`'s log-odds shape in a third
place. It is exactly 1.0 at β = 0 and exactly 1.0 at a concentration of 1.0, both by
construction.

The form is recorded although the constant it served is deleted, because it is the form
a later session will reach for first.

## 7. The contract V2.9 reads

```gdscript
normalised(values, weights)        # mean-one in the caller's weights, to 1e-12
excess(values, weights)            # positive deviation; {} is the NO-SITE answer
site(weights, signals)             # arg-max, ties by sorted id, "" when nothing scores
margin(weights, signals)           # the degeneracy detector; INF for one, 0.0 for none
signal_moves_site(weights, signals)# does the signal choose, or do the weights alone?
concentration(weights, site_id)    # the site's weight over the mean weight; 1.0 if none
pick(weights, signals, u)          # weighted pick, the draw supplied by the caller
```

Four properties, each asserted rather than commented:

1. **It preloads nothing**, so two callers that know nothing about each other can share
   it. `tests/test_unrest.gd` walks the transitive closure to prove the three names
   unrest.gd admits cannot reach `economy.gd`, which is the reverse edge the grievance's
   one-month lag depends on not existing.
2. **Derived, never stored.** No field, no tick, nothing in the save — §8.
3. **No randomness.** `site()` is arg-max and `pick()` takes its draw as an *argument*,
   so the one deterministic draw in the simulation stays in `cycle.gd`. A sited disaster
   passes `Cycle.unit()`'s own number rather than reaching for an RNG this file refuses
   to own.
4. **Walk order cannot reach the answer.** Ties break on the sorted id, asserted by
   building the same input twice in opposite orders.

`pick()` is unused today and is here on purpose: **a disaster is not always in the
biggest place, and arg-max structurally cannot express that.** It is the one part of
the contract written for section 9 rather than for this session.

## 8. `SAVE_VERSION` stays 29

The site is arg-max over two share registers the save already carries, so a stored site
would be a second answer to a question those already answer — `region_population`'s case
at V2.6a, one quantity over. `tests/test_save_load.gd` pins **five absences** (no stored
site, region, concentration, output index or per-region impulse), so a session making
siting stateful turns it red and has to say why.

The pin matters more than usual here: `Budget.project()` runs the real model on a
**duplicate**, and `GameState.duplicate_state()` does not carry `unrest_acts`. The whole
no-bump claim rests on the projection and the live tick **deriving the same place from
the same shares**, which they do because neither reads the record back.

The act record gains `region_id`, `region_name`, `city_id` and `city_name`, and earns
nothing: absent they read as *no place* and `main.gd`'s card falls back to the national
wording it has always had — `measures`' case at V1.3c, a seventh time. They are written
at the moment of the act because **a past act's place cannot be re-derived once the
shares have moved**, and they stay display-only: nothing in `src/sim/` reads them, which
`tests/test_unrest.gd`'s read-the-directory assertion already enforces.

`GameState.from_dict()` needed **no edit at all** — its `typed_strikes` rebuild casts
each whole Dictionary, so the new keys ride through. The plan booked that file and it
did not need touching.

## 9. The balance re-run

**Predicted before the build: not bit-identical, and the first session in three where
that is the honest prediction.** §1's concentration measurement says any priced siting
moves the aggregate from month one, and §3 says which direction.

**Measured, both sides from git worktrees** (`5089938` against `f0c6ac5`), so the
per-machine addon parse noise cancels rather than needing isolation — V2.6a's method
note applied rather than repeated. Both sides came back **1606 raw lines, 1582 content
lines**, the cut taken at the last `invariants: OK over 168 months`, and the 24-line
tails are **byte-identical**: V1.7c's third-stray-line check run and clean.

| | |
|---|---|
| regimes | **44 of 47 bit-identical** |
| movers | `managed_then_austerity`, `managed_breaks_its_word`, `managed_breaks_nothing` |
| changed lines | 18 |
| **approval column** | **identical in every printed row of every regime** |
| outcome changes | **zero** |

**The three movers are exactly the FRA regimes in which unrest fires** (two acts, one,
one). `managed` fires none and held identical — the control the prediction named.

**Every figure moved in the direction §3 measured**: GDP **2992 → 2995** and
**3007 → 3009**, growth **+1.18 → +1.23** and **+1.41 → +1.52**, unemployment
**8.14 → 8.11** and **8.38 → 8.35**, the grievance peak **48.38 → 48.29** and
**46.80 → 46.70**. The output multiplier at France's site is 0.759, so a strike costs
less output than it did, the country ends richer and slightly calmer, and the act count
is unchanged because no threshold crossing moved.

**Approval is untouched in every printed row, and that is the deletion showing up in
the harness.** With the visibility price gone, siting reaches approval only through
`growth` and `jobs` — the channel V1.5c measured as unable to reach a voter — so a
price that moves GDP by three billion moves the printed approval integer by nothing.
The re-run is the same finding as §5, arrived at from the other end.

**No new regime**, and none was needed: siting adds no verb, and every regime that
reaches unrest reaches the new code through `Unrest.tick_month()`. **No new tick call
anywhere** — the site is a pure read *inside* that tick, so both harnesses reach it
through calls they already make, which makes V1.5d's bug (both harnesses running the
pre-session model and agreeing about nothing) structurally impossible rather than
remembered.

## 9a. The screenshot pass found ONE bug, and it was older than this session

The twenty-third pass, three frames judged. The readout itself was clean; what the
frames caught was **V2.6a's own headline claim, untrue on screen since V2.6a shipped**.

`map_view.gd` built its city list **once in `setup()`**, under a comment that called it
*"static content, so once rather than per draw"*. That was true when V2.2b wrote it and
stopped being true at V2.6a, which made a city's population two live shares times a
live head count. So **the crosses never grew or shrank for a whole session** —
[[migration-model]] §1's *"the map's brass crosses grow and shrink for free"* was
describing a readout that did not refresh — and V2.6b1's demonstration ring, reading the
same list, drew nothing at all.

Rebuilt on the **monthly** hook U5c already added for the same class of staleness, not
per draw: this walks 581 cities and derives a site per nation, where `_refresh_markers()`
walks a handful of started projects. V2.3 put `Icon.load_icon()` on the path that
refreshes with the clock and rasterised an SVG on every call, and **a screenshot pass
structurally cannot see that class** — so the expensive rebuild goes on the clock and the
draw stays a draw.

**The proof is in two frames of the same flag.** Before the fix the hover label read
*"Lille — 240 k"*, the population Lille had at new game; after it, **"Lille — 245 k — where
the unions are out"**. Five thousand people the map had been refusing to admit had moved.

The flag's own correction was V1.6e's, applied to a zoom rather than to a scroll: at
`--city`'s zoom the ring is five pixels among several hundred crosses, so `--site` zooms
four times rather than twice — *scroll to where the flag's own claim is* has a direction
on a map too. One known tool limitation is recorded rather than fixed: a windowed run can
receive a mouse-motion event during the capture frames and overwrite `_hovered_city`, so
a hover label is present in some runs and absent in others. It affects `--city` and
`--hover-project` identically and predates this session.

The economy panel frame needed no fix and carries an unplanned corroboration: it reads
*"Unrest 46 of 100. Past the point where the unions organise. Concentrated in
Hauts-de-France (Lille)."* and, two lines below, the V2.5 line *"Hauts-de-France x0.78"*
— the panel independently reporting the poor-region finding this session's price is built
on.

## 10. What V2.6b1 did NOT build, and what passes on

- **The campaign half.** [[tiers/v2|§6]] books *campaign meetings sited* beside unrest
  and calls them **one shape**. They are not, and §11 records the measurement.
- **No visibility price.** §5.
- **No verb, no new regime, no map layer.** `LAYERS` stays at four; the demonstration is
  a ring on a glyph V2.2b already draws, so `_city_at_screen_point()` keeps answering
  for exactly one thing and the hit test is untouched.
- **No regional opinion number**, which V1.5c refused by name and V2.6a declined to add.
  There is still no per-region approval and no per-region bloc composition anywhere.

## 11. To V2.6b2 — campaign meetings sited

**The decomposition was wrong about the price and right about nothing else being
shared.** Unrest's place is a **derived report** whose failure mode is *constancy*; a
campaign meeting's place is a **verb** whose failure mode is *dominance*. One shape
cannot come out of two different failure modes, and V2.6b2 does not call
`Siting.site()` at all.

**The signals checked and refused, with numbers, so they are not re-proposed:**
`service_quality` is one figure per nation (zero variance — V2.6a's own deletion);
regional approval and regional bloc composition do not exist and are V1.5c's refusal;
**named payroll per head IS `Migration.city_pull()`** — one number with two names, the
failure `migration_constants.gd` documents twice — and is exactly zero for seven of the
ten nations; output per head is identically 1.0 for Britain and, pointed at turnout, *is*
a regional approval figure with a different label.

**What does vary honestly is distance, and V2.4a already built the currency.**
`Diplomacy.travel_days()` is haversine over the register's own city coordinates at
`TRAVEL_KM_PER_DAY = 280`, and `Calendar.make_entry()` already takes `travel_days` as a
plain int the caller computes. Measured from each capital: FRA 35 cities at 1 day, 17 at
2, 13 at 3, 1 at 4 (Ajaccio); DEU 25 / 92 / 5; GBR 103 / 26 / 3.

**But reach-per-day makes the capital strictly dominant** (Paris 0.0314 per day against
Marseille 0.0129 over three and Lyon 0.0076 over two), the shape this project has killed
twelve times. The only honest breaker is what `data/campaign-actions/campaign.json`
already says in prose — *whoever has already been spoken to has already been spoken to*
— which is a **per-region saturation counter**: a memory of the player's own acts, not an
opinion. That is a new accumulator with its own accrual and decay, so it bumps
`SAVE_VERSION`, needs one constant with a band, and **re-baselines V1.7a's harness**,
since `CAMPAIGN_WINDOW_MONTHS = 8` was chosen by maximin slack over a feasible set
[7, 10] and total reach falling moves that set.

A machine, and a **different conservation law** from this one's — which is exactly the
axis V2.6 split (a), (b) and (c) on in the first place.

---

Related: [[tiers/v2]] · [[migration-model]] · [[unrest-model]] · [[campaign-model]] ·
[[region-economy-model]] · [[geography-model]] · [[decision-log]]
