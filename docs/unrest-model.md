---
title: Unrest Model
tags:
  - decision
  - sim
  - balance
---

# Unrest Model

Unions, protests and strikes, as built at [[ROADMAP|V1.5c]] — the third session of the
V1.5 block and **the block's one true acting agent**. A grievance stock built out of two
rows of the electorate, an inequality statistic nothing the player does can move, and a
deterministic agent that walks out when the country has had enough.

Same standard as [[society-model]], [[demography-model]] and [[companies-model]]: a
**game model**, judged on whether the player's decisions produce a legible, attributable
political outcome. Where realism and legibility conflict, legibility wins, and the trade
is noted.

## 1. The session where two rules that were pulling apart finally agree

[[diplomacy-model|V1.3a]]'s rule was that live state ships **with a verb** or it decays
into a number nobody reads. [[ROADMAP]]'s decomposition inverted it for this block —
*every session ships a statistic and the price it charges* — because §5's nine bullets
contain at most two player verbs and both belong to (d).

V1.5c is where the two agree, and the reconciliation is not a compromise: the statistic
is the grievance, and **the verb is the union's**. A rule about live state needing
something to act on it never said the actor had to be the player.

## 2. The row's own warning is the design constraint

[[v1]] §5, about this bullet specifically:

> unrest driven by nothing the average voter does not already feel is a second approval
> number with a different label.

That is a real risk and the model has to defeat it **mechanically** rather than by
asserting it has. There are two ways it could fail:

**A national anger index already exists.** `Discipline.unpopularity()` is a `[0, 1]` read
off `overall_approval_pct`, and it is consumed by `discipline.gd`, `government.gd` and
`cabinet.gd`; `ns.party_discipline` is already a hardship-driven stock with an inertia
term. A grievance target built the same way would be `military_capability` /
`potential_shift_pct` a **fifth** time — one quantity, two answers. So the hardship term
reads **two rows of the electorate, not six** (§3).

**And two rows are still a re-weighting.** So the target carries two further terms that
**no opinion issue reads at all**: the inequality drift (§5) and the settlement stance
(§6). A country can be angry for reasons its approval figure does not contain, which is
what §5's own bullet asks for when it says inequality drives unrest *independently of
average prosperity*. The row is internally coherent, and the coherence is load-bearing.

## 3. Two rows, and the division falls out of a table written at S5

```
sat      = Opinion.issue_satisfaction(ns)
for bloc in UNREST_BLOCS:                       # ["workers", "students"]
    w    = Opinion.salience_weights(BLOC_SALIENCE_BASE[bloc], sat)
    row  = Σ w[issue] · sat[issue]
    total += BLOC_SIZE[bloc] · row              # renormalised over the set
hardship = −total / Σ BLOC_SIZE[bloc]
```

**Zero new weights and zero new saturation scales.** `BLOC_SALIENCE_BASE`,
`salience_weights()` and `BLOC_SIZE` all already exist, so the political map of who
strikes is a table written at S5 for reasons that had nothing to do with strikes —
[[bloc-model|V1.3d]]'s finding a second time. Workers weight `defence` at **0.00** and
`tax_vat` at **0.08**, which is exactly what `balance_probe`'s `managed` regime moves, so
a well-governed France is structurally quiet and nothing authored that.

Run through `salience_weights()` rather than the base row, so `SALIENCE_GAIN` amplifies
the issue the mobilised blocs are actually suffering on — the same amplification the
polling panel and the result screen already show the player, reused rather than
re-derived.

`UNREST_BLOCS` is a **registry, not a mode flag** ([[society-model|`QUALITY_KEYS`]],
`map_layers.gd`'s `LAYERS`), and `tests/test_unrest.gd` fails if `business` appears in
it. The test that pins the whole §2 argument is sharper than the list, though: moving
`tax_corporate` twenty points — an issue **only** `business` weights — must move national
approval and leave the grievance **exactly** unchanged.

## 4. The price: the design was refuted by its own probe

The session was designed with an **output-only** price. A strike writes a decaying
impulse into `economy.gd`'s growth sum; approval falls through `growth` and `jobs`, which
already exist and which `elections.gd` already attributes; no thirteenth `ISSUE_KEYS`
entry has to be argued. It is the cheapest design that satisfies the block's rule, and
the plan committed to it.

**Table (d) refuted it, at every candidate and for a structural reason.** On the isolated
path — grievance held at the ceiling, every other issue identical between the runs — over
fourteen years:

| scale | Δ workers approval | Δ GDP | Δ unemployment | peak impulse | clamp |
|---|---|---|---|---|---|
| 0.50 | −0.08 | **−1.24 %** | +0.02 | 0.670 | slack |
| 1.00 | −0.18 | **−2.47 %** | +0.04 | 1.341 | slack |
| **2.00** | **−0.42** | **−4.94 %** | **+0.08** | **2.682** | **slack** |
| 3.00 | −0.72 | −7.37 % | +0.12 | 4.000 | BINDS |
| 6.00 | −0.66 | −7.39 % | +0.11 | 4.000 | BINDS |

**The country ends five per cent poorer and the workers row moves four tenths of a
point.** The whole opinion model is written in **rates and ratios**: `growth` reads
`growth_annual_pct − trend` and returns to zero once a shock is steady, unemployment
mean-reverts to a structural level a strike never writes, and every fiscal figure is a
share of GDP — so a GDP five per cent smaller changes almost none of them. A permanent
**level** loss is invisible to a model that prices **changes**, which is `opinion.gd`'s
own deficit-not-debt argument read from the other side.

No value clears the floor, so raising the scale would be tuning against an arithmetic
impossibility — exactly what V1.5b refused to do for `DEPENDENCY_ELASTICITY["health"]`.
But V1.5b's answer there was to **delete the term**, and that answer is not available
here: the impulse is this session's price, and a block whose rule is *ship a statistic
and the price it charges* cannot ship a price nobody can feel.

So the model takes the direct term it was designed without. `UNREST_OPINION_SCALE`, read
off the **stock and not off the act** — a country at grievance 44 has not struck and is
still angry, and the row's noun is *organised opposition*, not *work stoppages*.

Three placement calls, and the middle one is the one to be careful about:

| | |
|---|---|
| **At `opinion.gd`'s `bloc_offset` site** | Not subtracted from `jobs`, which is `deployment_opinion_load`'s shape and the obvious move. `jobs` lives inside `issue_satisfaction()`, which `Unrest.hardship()` **reads** — so that placement closes a same-quantity loop through the salience simplex that no clamp bounds. This site is outside that read by construction. |
| **Uniform across the six blocs** | A general strike inconveniences everybody, and an authored per-bloc row would be a table with no measurement behind it. Which blocs *generate* the grievance is a different question and `UNREST_BLOCS` answers it. A split belongs to [[v1]] §7's campaign phase. |
| **No thirteenth `ISSUE_KEYS` entry** | §7. |

The output impulse **stays**, and it is not decoration: −4.94 % of GDP is the largest
single economic effect any session in this project has added. It is simply not how the
player finds out.

## 5. Inequality: the row said it cannot be derived, and it was right

[[v1]] §6, which owns the instruments:

> There is no distribution in the model today: no brackets, no deciles, no capital/labour
> split, so §5's index cannot be *derived* and ships at V1.5c as a **declared stopgap
> read**.

Every word of that is true. **It does not follow that the index has to be invented.** The
World Bank publishes `SI.POV.GINI` for all ten nations, on the same provider, the same
licence and the same download loop as every other figure in `imported`:

| | 2015 | latest | slope |
|---|---|---|---|
| NLD | 28.2 | 25.7 (2021) | **−0.417** |
| ESP | 36.2 | 33.4 (2023) | −0.350 |
| GBR | 33.3 | 32.4 (2021) | −0.150 |
| ITA | 35.4 | 34.3 (2023) | −0.138 |
| FRA | 32.7 | 31.8 (2023) | −0.113 |
| BEL | 27.7 | 26.8 (2023) | −0.112 |
| AUT | 30.5 | 31.2 (2023) | +0.087 |
| LUX | 32.9 | 33.6 (2023) | +0.088 |
| CHE | 32.3 | 33.8 (2022) | +0.214 |
| DEU | 31.4 | 33.7 (2022) | **+0.329** |

Levels span **1.33×** and **the signs differ** — six falling, four rising. Nothing
clusters, which is the [[foreign-policy-model|clustered `coalition_position`]] risk a
stopgap would otherwise run. That is the **twenty-fourth** stale-row instance and it is
[[demography-model|V1.5b]]'s headline repeating one session later.

**The cost, booked rather than discovered.** Coverage stops at 2021, 2022 or 2023 per
nation and nothing exists at `YEAR`, so `load_wb_indicator_for_year()`'s exact-year match
plus `build_imported_block()`'s `sys.exit` would refuse the whole import. `import_data.py`
gained a **nearest-year fallback scoped to this one series** — deliberately not folded
into the shared loader, because a silent fallback on GDP would turn a broken download
into a quietly stale figure — and the year actually used is written into the block beside
`_year` and `_trend_from_year`.

**Where the drift lives is a split, not an oversight.** `Demography.tick_month()` owns it:
this layer already owns measured facts about the population that drift on their own, and
the session that prices a fact owns the price rather than the fact. Demography owns the
dependency ratio and Society owns the denominator it becomes; Demography owns the Gini
drift and Unrest owns what it costs. It also keeps `unrest.gd` free of any accumulator,
which its own test asserts.

**The stateless version was designed and cut.** `inequality_deviation()` was to be a pure
read of the slope times elapsed months — no field, no save entry, `Defence.allies()`'s
shape. There is no elapsed-time source that survives the harness: `balance_probe.gd` and
`tests/test_balance.gd` both set `state.year` **after** `GameState.new_game()`, so a
reference captured at init reads year 0 and every derived elapsed time is wrong by two
thousand years. Recorded because the reasoning looked right and the harness decided it.

### What makes "declared stopgap" mechanical

`tests/test_unrest.gd` mutates the three distributional instruments the model actually
has — the corporate rate to 60 %, `state_share` to 1.0 on every firm, `regulation_burden`
to 1.0 on every sector — runs 168 months, and requires the index to be **bit-identical**.
That test is written to go **red the day §6 lands**, which is the point of it: the stopgap
is discharged by a visible test change rather than by someone remembering.

**Deliberately not built:** the Gini *level* as a term. In a France-only alpha a constant
is absorbable into the strike threshold, so it would be a number that looks alive and is
not. It becomes meaningful when other nations are playable.

## 6. `settlement` is the third `effects.society` term, and it is what makes unrest closable

[[society-model]] §3 declared the sixth channel *"schema two later sessions read rather
than one session's private field"*. V1.5b was the first and widened it by one key; this
is the second, and a channel that carries a **third** register is schema rather than
luck.

Without it the only lever pointed at a strike is a spending increase, and
`society_probe.gd` table (c) established that raising a line necessarily widens the
deficit — so the player could buy industrial peace only by opening `public_finances`, and
unrest would be the **permanent monotone charge** [[defence-model]] names.

Signed both ways: an imposed settlement — a service minimum, a pay freeze — is the
negative direction on the same accumulator, not a repeal verb. It is not
strictly dominated, because its **authored `bloc_offset` is immediate and positive**
(business, pensioners, rural and urban all resent the people who can strike) against a
grievance cost that is slow. Fast in, slow out, in the other direction.

### V1.5a's refusal was narrowed from the channel to the pair

`law.gd` refused `society` + `spending_pct_gdp` outright. The reason V1.5a gave is about
**corruption** reaching the spending issues through the quality stock — it was never true
of the channel, only of that one term, and V1.5a scoped it to the channel because
`corruption` was the only term there was. A settlement law is naturally a spending law
(public-sector pay, a pension restoration), so under the wide scope every one was a load
error. Narrowed to the pair, which is exactly what V1.5b did to its own refusal for
`labour.json`'s sake. **This turns an existing red green and is argued rather than
slipped in.**

### V1.8 gave the stance a SECOND ROUTE, and it is a split rather than a second writer

`data/events/`'s `union_ultimatum` reaches `society.settlement` **directly**, through an
event choice made under a deadline, where a settlement law reaches the same register
through an assembly division. That is V1.4a/V1.4b's a/b line in a third register: the
approval path differs and the mechanism does not, and there is still exactly one writer —
`Legislature.apply_effects()`, which both callers go through.

It also closes something this section left open. A settlement law is what makes unrest
*closable*, but it is only available once the grievance has already crossed
`PRECONDITION_FIELDS`' bar, and it has to be proposed and carried. The event is the
grievance asking the question directly, with a **default that makes it worse** — the
`hold_firm` choice carries a negative stance — so a president who ignores the union's
deadline is not merely failing to settle, they are hardening. See [[events-model]] §7.

### And there is no fourth anti-double-count, which is the more interesting half

`society.settlement` + `structural_unemployment_pct` was written and then deleted, once it
was checked against the criterion the three existing refusals actually use rather than
against the pattern they make. The first refusal states it in full: *the same act, the
same landing site **and the same units***. A settlement is in units of stance and lands on
the unrest target directly; structural unemployment is in points and lands on
`Economy._update_unemployment()`, reaching unrest only afterwards through `jobs`. **Two of
the three criteria fail.**

The distinction is **one mechanism priced twice** against **two mechanisms landing on one
number**. All three existing refusals are the first kind — a regulation's burden *is*
headcount, corruption's degradation *is* the spending issue, and
`immigration_tightening`'s structural offset was literally a stand-in for a migration flow
that did not exist. But *"a minimum wage rise makes hiring harder"* and *"a minimum wage
rise buys industrial peace"* are two true sentences about two mechanisms, and a rule that
forbade them would forbid `bloc_offset` beside anything.

Recorded in `law.gd` itself, because the next session to add a term on this channel will
reach for a fifth refusal by symmetry, and **symmetry is not the test**.

### Content

`labour.json`'s four laws each gained a settlement term, which is the block's **third
booked retro-fit** — [[ROADMAP]] booked the corruption line to (a) and the migration line
to (b), and this is the same sentence one session on. Before it, the model was perverse:
`minimum_wage_rise` and `working_time_reduction` both *raised* unrest through
`structural_unemployment_pct` while `labour_market_flexibilisation` *lowered* it, so
conceding inflamed and breaking the unions calmed.

`social.json` gains two, both gated on `unrest_pct >= 35`: `public_sector_pay_settlement`
and `essential_services_minimum`.

## 7. `unrest_pct` in `PRECONDITION_FIELDS`, and only ever with `>=`

The first entry in that whitelist that names something **the player did not do**. That is
the whole of *"protests forcing a response"*: a settlement law is unavailable until the
country is actually angry, so the response is forced by the situation rather than offered
from a menu.

**`>=` only, asserted over the whole law list.** `available()` only ever *opens* laws, so
a `>=` precondition is a lever unrest hands the player — while a `<=` one would take a
lever away, making unrest an uncontestable gate on player action. [[ROADMAP]]'s call 4
says two of those is one machine claimed twice, and [[v1]] §1's judiciary is the other.

### The `ISSUE_KEYS` question is answered NO, and the reason is prior to V1.3d's four tests

There is **no direct opinion term to key**. Unrest's approval price is an offset at the
`bloc_offset` site, and its economic price reaches `growth` and `jobs`, which are keys
that already exist. The question does not reach test 4. Recorded beside `ISSUE_KEYS` —
fourth time, [[companies-model|V1.4c]]'s precedent — with **that** reason rather than
V1.5a's collinearity one, because the reasons differ and a reader would otherwise assume
they are the same.

## 8. This scheduler is explicitly non-generic

[[v1]] §8 says the two legal outcomes for anything event-shaped are to **be** §8's first
instance or to say plainly that it is not one, and that silence is not among them.

It is not one. There is no preconditions table, no authored choice list and no content
directory: one float crosses one threshold, one cooldown gates it, and the labels are
chosen by dividing the span above the threshold evenly. §8's event schema is not being
written here under another name.

**Not honeymoon-and-fatigue either.** That orphan — deferred *in code* at
`APPROVAL_NEUTRAL` since S5 and named in no row — is time in office as its own drag.
Unrest is closable by `settlement_stance` and mean-reverting through `UNEMP_REVERT`, so
it is not that machine. Refused explicitly rather than left adjacent.

## 9. Where it sits

```
Economy.tick_month()
Budget.tick_month()
Opinion.tick_month()        <- reads LAST month's stock
Demography.tick_month()
Society.tick_month()
Unrest.tick_month()         <- V1.5c
Cabinet.tick_month()
```

After Society, because the hardship term reads the `health` and `pensions` satisfactions,
which read V1.5a's quality stock through V1.5b's dependency denominator. After Opinion for
`society.gd`'s reason inherited whole — and the loop it breaks here is a **second** one:
`unrest_pct` is itself a `PRECONDITION_FIELDS` entry, so unrest → which laws are available
→ a settlement law → the stance → unrest closes twice over. The one-month lag breaks both
structurally rather than by being careful.

`unrest.gd` preloads `opinion.gd`, its own constants and `economy_constants.gd`. It is
**not** a leaf, and the one preload that must never appear is `economy.gd`: this file
*writes* an impulse Economy reads next month, and a reverse edge would make that lag a
convention instead of a fact. `opinion.gd` does not preload `unrest.gd` either — it reads
`ns.unrest_opinion_load` off `NationState`, `deployment_opinion_load`'s arrangement, which
is what keeps the pair out of a cycle.

`Budget.project()` runs it in the same slot, the **sixth** instance of V1.3b's repair and
the sharpest: the other five report a standing cost the player has already chosen, and
this one reports an act nobody has chosen at all. `tests/test_budget.gd` gained a
**third displaced** projection check to go with it, and the displacement is the whole
point: from an undisplaced state the grievance is exactly 0.0, the agent never fires
inside the window, and the projection agrees with reality for the boring reason. That is
the same blind spot at a smaller scale that made all twenty-five balance regimes report
zero acts.

## 10. The probe corrected the session six times, fourteen sessions running

`tools/unrest_probe.gd`. Bands, tiebreakers and isolation paths were fixed before any
sweep ran. **Four of the six corrections are about the measurement discipline itself**,
and they are recorded here because they generalise past unrest.

### (a) `UNREST_CONVERGENCE` — a nearest-to-X tiebreaker is only as good as the grid's resolution

Band, two-sided by construction: the half-life must be shorter than `service_quality`'s
34.31 months (a grievance is not a hospital) and longer than `INERTIA_RATE`'s 2.41 (else
this is approval with a delay, which `opinion_constants.gd` forbids as *two lags in
series*). Tiebreaker: nearest the geometric mean, **9.09 months**.

| rate | half-life | band | dist |
|---|---|---|---|
| 0.02 | 34.31 | fail | 25.22 |
| 0.06 | 11.20 | PASS | 2.11 |
| **0.07** | **9.55** | **PASS** | **0.46** |
| 0.08 | 8.31 | PASS | 0.78 |
| 0.12 | 5.42 | PASS | 3.67 |
| 0.32 | 1.80 | fail | 7.29 |

The first grid was a doubling ladder — `[0.02, 0.04, 0.06, 0.08, 0.12, 0.16, 0.24]` — and
it chose **0.08**. Refining to 0.01 moved the answer to **0.07**. V1.5b's diagnostic is
about *widening* the grid; this is the same failure under **refinement**, and it is
checkable the same way.

### (b) `UNREST_THRESHOLD_PCT` — a band whose ceiling is one regime's peak

Band (i): fires at least once under `austerity`. Band (ii): **exactly zero** times under
`hands_off` and `managed` — added in advance because (i) alone is a one-sided minimum.
Tiebreaker: the largest passing candidate still clearing (i) with at least two acts.

Against `austerity` alone the tiebreaker chose **52.0**, which passes V1.5a's ordering
check and V1.5b's widening check and is **still wrong**: the interval's ceiling is set by
that one regime's measured peak of 52.82, so *largest passing* means *that peak, minus
0.8*. And at 52.0 a budget that **zeroes every spending line** produces no industrial
action at all, which is not a model anyone would defend.

That is a criterion the bands should have contained and did not — [[foreign-policy-model|V1.3f]]'s
`AGENDA_ACT_MIN`, where a pre-committed sweep measured a state that could not answer the
question. Band (i) gained `spend_zero`; the selector is unchanged.

| threshold | austerity | spend_zero | hands_off | managed | band |
|---|---|---|---|---|---|
| 35.0 | 12 | 12 | 0 | 0 | PASS |
| 40.0 | 12 | 12 | 0 | 0 | PASS |
| **45.0** | **12** | **11** | **0** | **0** | **PASS** |
| 50.0 | 11 | 0 | 0 | 0 | fail |
| 55.0 | 0 | 0 | 0 | 0 | fail |

### (c) `UNREST_COOLDOWN_MONTHS` — every candidate passed, so the band was a bound

Third time in three sessions, after V1.4c's and V1.5a's `CORRUPTION_DELIVERY_BETA`. Every
value from 3 to 36 months clears both clauses — 36 still gives 1.43 acts a term, and even
a 3-month cooldown adds only 0.12 points of unemployment — so the sweep ordered nothing.

**Set by argument instead, and it says so.** Twelve months is one bargaining round a year,
and `IMPULSE_DECAY^12 = 0.28`: each act has decayed to under a third of itself before the
next can fire. A cooldown short enough for the impulses to overlap would make industrial
action a standing condition, and the decaying-not-sustained distinction the whole channel
rests on would be false.

### (d) `UNREST_IMPULSE_SCALE` — a band applied to an observable the channel does not reach

§4. The pre-committed band failed at every candidate and the **constant was right**; the
band was measuring the wrong thing. What selects instead is the half of the tiebreaker
that discriminated — the saturated impulse must leave `UNREST_IMPULSE_MAX_PCT` strictly
slack, which excludes 3.0 and above — plus the argument the clamp already makes: the peak
must sit between `FIRM_IMPULSE_MAX_PCT` (2.00) and `COERCION_IMPULSE_MAX` (6.00), because
a strike is a bigger shock than a subsidy programme and a smaller one than an embargo.
**2.0**, peak 2.682.

### (d2) `UNREST_OPINION_SCALE` — the constant the refutation forced into existence

Band: the workers row past ±3.0 at a **reachable** grievance (~52), not at the ceiling.

| scale | workers row | delta | worst score | clamp | band |
|---|---|---|---|---|---|
| 0.10 | 26.33 | −2.11 | 0.596 | slack | fail |
| 0.14 | 25.49 | −2.95 | 0.615 | slack | fail |
| **0.15** | **25.28** | **−3.16** | **0.620** | **slack** | **PASS** |
| 0.20 | 19.44 | −9.01 | 0.766 | slack | PASS |
| 0.50 | 10.00 | −18.44 | 1.084 | **BINDS** | fail |

Three rows pass, so the two-part selector is a bound again. **Smallest passing ships**,
and the reason it is *smallest* rather than the midpoint is (e): the interval's upper edge
here is a **guard rail** (`opinion.gd`'s own ±1.0 clamp), not a model criterion, and a
guard rail does not select. The jump from −3.16 to −9.01 between 0.15 and 0.20 is a
discrete outcome flipping inside the run, which is a second reason to take the floor.

### (e) `UNREST_SETTLEMENT_BETA` — V1.5b's own correction, inverted

Band (i) was lifted **verbatim** from `demography_probe.gd` — *holds unrest at or below
where it started* — and it did not transfer. A dependency ratio rises forever, so holding
it flat is the only interesting question; unrest converges on a **bounded** target. Under
the borrowed wording (i) demanded a beta near 60 and (ii) one under 29, and the interval
was **empty** — an artefact of the borrowed band, not a fact about settlements. For a
bounded stock, closable means **stops the strikes**.

| beta | saturated | closable | one law | not immune | band |
|---|---|---|---|---|---|
| 7.0 | 45.94 | no | 49.77 | yes | fail |
| 8.0 | 44.99 | yes | 49.30 | yes | PASS |
| **12.0** | **41.04** | **yes** | **47.50** | **yes** | **PASS** |
| 17.0 | 36.11 | yes | 45.31 | yes | PASS |
| 20.0 | 33.15 | yes | 44.00 | **NO** | fail |

**And then the pre-committed selector was wrong, which is the fourth distinct failure
mode.** V1.5b's correction was that when both bands are one-sided minimums the *smallest*
passing candidate ships, because *largest* just returns the top of the grid. That was
pre-committed here — and once (i) was corrected the interval became genuinely two-sided,
`[7.3, 16.3]`, at which point *smallest passing* lands **back on an edge** and is
grid-dependent all over again: 7.0 leaves unrest at 45.24 against a threshold of 45.0, so
a 0.5 % model change flips it.

**The rule, extended:** when the passing interval is bounded by **two model criteria**,
take the value nearest its **midpoint** — interior by construction, and it moves only if
the interval moves. When one edge is a **guard rail**, the guard rail does not select and
the model edge governs (see (d2), which is that case). Midpoint of `[7.3, 16.3]` is 11.8;
**12.0** is the nearest candidate, clear of the threshold by 11 % at a saturated stance
and above it by 4 % at one law.

### (f) `INEQUALITY_BETA` — the kill switch cleared, and the surviving term is small

Band: the measured drift must move the date of the first act. Measured on **Germany**,
whose +0.329 pt/yr is the roster's widest rise among the playable three — France's own
slope is negative, so for the default nation this term *calms*.

| beta | first act | vs flat Gini |
|---|---|---|
| 0.30 | 36 | same |
| **0.40** | **35** | **MOVED** |
| 1.00 | 34 | MOVED |
| 2.00 | 33 | MOVED |
| 8.00 | 29 | MOVED |

Smallest passing ships. **One month in thirty-six**, and the size is recorded rather than
tuned away: a stopgap that dominated the target would be the opposite failure, because §6
owns the instruments and an index nothing the player can move should not decide the run.

### (g) Loop B is bounded, and it is the loop nobody would have named

```
strike → approval ↓ → Discipline.unpopularity() ↑ → cabinet.gd's resignation
       → VACANT_EFFECTIVENESS → Society.quality_target() ↓
       → health/pensions satisfaction ↓ → hardship ↑ → unrest ↑
```

Nothing closes it without a player reshuffle, and it runs straight through the model
widening V1.5a **recorded and kept** on the evidence that zero outcomes moved. V1.5c is
the session that supplies the push, so it was measured rather than commented: under
`austerity` with no reshuffle over 168 months, peak unrest **53.30** against a ceiling of
100.0, **zero months pinned**, four degraded portfolios, unpopularity 0.682. Bounded.

Loop A — unemployment → grievance → strike → output ↓ → unemployment ↑ — is bounded by
`UNEMP_REVERT`: a strike moves only the **cyclical** term, and the structural level it
reverts to is one a strike never writes.

### (h) Saturation, and the label that was cut

`JOBS_SCALE_PP = 3.0` clamps the `jobs` satisfaction at −1, so a hardship term reading it
could not tell bad from catastrophic. Measured, it does not saturate in the states that
matter (−0.154 under `austerity`), and the labels read the **stock** rather than the
instantaneous term in any case.

But the stock's own reachable range cut a label. Peak grievance over 168 months:
`austerity` 53.3, `spend_zero` 49.6, `tax_max` 80.6, everything else under 34. A
three-way split of `[45, 100]` puts the third tier at 81.7, which **no budget in the
harness reaches** — a label the model cannot produce is
[[trade-model|`refused_by_partner`]] a fifth time. `general_strike` is **deleted**, and at
two labels both are reachable: `protest` under austerity, `strike` under `tax_max`.

### (i) Every clamp measured

| quantity | reached | clamp |
|---|---|---|
| `unrest_pct` | 93.92 | 100.00 |
| `unrest_impulse_pct` | 2.589 | 4.00 |
| `settlement_stance` | 1.000 | 1.00 |

`unrest_pct`'s ceiling is **definitional** rather than a guard rail — 100 is maximum
grievance by construction — and it is approached only under a saturated hostile settlement
plus austerity, which is a player deliberately maximising it. `settlement_stance` reaches
its bound the way `corruption` reaches `CORRUPTION_MAX`: a repeatable law on a cooldown,
four passes inside fourteen years.

## 11. `SAVE_VERSION` 17 → 18, on two fields of eight

| Field | Earns the bump? |
|---|---|
| `unrest_pct` | **YES.** Absent it reads 0.0 — a perfectly calm France — so a save reloaded mid-crisis silently ends the crisis. `service_quality`'s case at V1.5a: re-deriving on load cannot rescue it, because the accumulation **is** the state. |
| `unrest_cooldown_months` | **YES, and separately.** Absent it reads 0, 0 means *act now*, so a reloaded save fires a strike in its first month whatever the player was doing. [[calendar-model|U6a]]'s `diplo_months_to_act` exactly. |
| `gini_index` | Would have earned it a third time on `young_share`'s reasoning — absent, the live index reads 0.0 against a France at 31.8 — and is folded into the same bump. |
| `start_gini_index`, `gini_index_per_yr` | No. Recomputed at init from `imported.inequality`, so they round-trip through `data/nations/`. |
| `settlement_stance` | No. Absent it reads 0.0 — no standing settlement — the truth about every version-17 save. `migration_stance`'s case, serialised anyway for its reason. |
| `unrest_impulse_pct`, `unrest_opinion_load` | No. Both recomputed on the next tick, failing soft for exactly one month — `trade_baseline_by_partner`'s case. |
| `unrest_acts` | No. A display record `src/sim/` never reads back. |

**The first bump on this list resting on two fields**, and `tests/test_save_load.gd`
asserts them **separately**, because they fail the rule by different failures — one erases
accumulated state, the other resets a schedule to *now*. The test also pins the *absence*
of any stored inequality index, so a later session storing one turns it red and has to say
why.

## 12. Why nothing diverges

| Quantity | Bound |
|---|---|
| `unrest_pct` | `[UNREST_MIN, UNREST_MAX]`, converging on a target that is itself clamped and built from terms each bounded — satisfactions by `_scaled()`, the stance in `Legislature.apply()`, the Gini drift by the target's own clamp. A first-order lag on a bounded target cannot overshoot it. |
| `unrest_impulse_pct` | `[−UNREST_IMPULSE_MAX_PCT, +…]`, and it **decays** at `IMPULSE_DECAY` toward zero, so a bounded per-act addition on a cooldown has a bounded sum. Measured slack. |
| `settlement_stance` | `[−SETTLEMENT_STANCE_MAX, +…]`, clamped on the accumulated value in `Legislature.apply()`. One writer, no tick. |
| `unrest_opinion_load` | A bounded fraction of a bounded stock, combined at a site `opinion.gd` re-clamps to `[−1, +1]`. |
| `gini_index` | `[GINI_MIN, GINI_MAX]`, definitional, and drifting linearly at a rate no lever moves. |
| Loop A | Mean-reverting, and the reversion target is one a strike cannot write. §10 (g). |
| Loop B | Measured, not argued. §10 (g). |

## 13. What is deliberately not built

**A per-bloc split of the approval load.** §4. Uniform, and a split belongs to [[v1]] §7.

**A thirteenth `ISSUE_KEYS` entry.** §7.

**A generic event scheduler.** §8.

**Honeymoon and fatigue.** §8.

**A Gini *level* term.** §5.

**A grievance ledger.** The stock **is** the memory, which is
[[foreign-policy-model|V1.3e]]'s property arriving in the one session that could have
built the ledger literally. `tests/test_unrest.gd` asserts that nothing in `src/sim/`
reads `GameState.unrest_acts` back.

---

Related: [[index]] · [[society-model]] · [[demography-model]] · [[opinion-model]] ·
[[economy-model]] · [[legislature-model]] · [[companies-model]] · [[v1]] · [[ROADMAP]]
