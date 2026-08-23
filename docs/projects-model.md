---
title: Projects Model
tags:
  - decision
  - economy
  - simulation
---

# Projects Model

Infrastructure projects, as built at [[ROADMAP|V1.6f]] — the sixth session of the V1.6
block and **the last one in it**. A discrete, dated, expensive commitment that bills
every month it is under construction and pays once, permanently, when it finishes.

`src/sim/projects.gd` is the model, `src/sim/projects_constants.gd` is the bounds,
`data/project-actions/` is **where the numbers live**, `tools/projects_probe.gd` is the
evidence and `tests/test_projects.gd` is what stops a later session quietly breaking the
design.

**The row split again, and the count is why.** [[sector-model|V1.6e]] §1 put infrastructure
projects at three machines of five and named the third — *"visible on the map"* — a
**U-track surface**. Counted here the split holds and sharpens.

## 1. The count, and the map came one session later

| | machine | track | built |
|---|---|---|---|
| 1 | the project content type and the in-flight register, counted in **months remaining** | S | V1.6f |
| 2 | the completion payoff and the bill | S | V1.6f |
| 3 | ~~per-project~~ **per-nation** geography, a marker draw pass on `map_view.gd`, hit-testing and hover | **U** | **U6c** |

V1.6f is machines 1–2. Machine 3 was **U6c** — U5b→U5c, V1.6e→V1.6f, a third time.
*A difference in architectural shape is an argument; the two-track rule is a rule.*

The sim half counts **~24 surfaces**, between [[transition-model|V1.2d]]'s ~21 and
[[trade-model|V1.3b]]'s ~33, and the same band V1.6e counted at ~22.

> **No project names a place, and that is the deferral rather than a gap.** Authoring a
> lon/lat here that nothing reads would be a content field carrying no information —
> [[tax-model]] §3's refusal for the bracket index. The five are named generically and
> are true of any of the ten; the session that draws them owns naming them, the way U5a
> authored the `flag` block in the session that drew it.

### U6c: instance thirty-nine, and it is in the row's own wording

**Geography is not per-project, and the phrase above is what would have made it so.**
Every statement of machine 3 — this table, [[sector-model]] §5 and [[ROADMAP]]'s V1.6f
paragraph — called it *"per-project geography as content"*. Read literally that puts a
lon/lat inside `effects.project`, and `data/project-actions/` is a **global flat list**:
one `high_speed_rail` shared by all ten, so every nation's rail spine would stand at one
point on the planet. Fixing that means moving the directory per-nation, which reopens the
global-list call V1.6f made freely and which nothing else has asked to reopen.

**The site belongs to the nation.** `data/nations/*.json` grew an optional `project_sites`
block, `project id -> [lon, lat]`, parsed into `Nation.project_sites`. That is
[[people-model|U6b]]'s rule unchanged — *a law names an office; the nation's own
`government.pretender_person` names the person* — and it settles three things at once:

- `data/project-actions/` stays **global and unedited**. A rail spine is still true of any
  of the ten; only the ground it stands on is national.
- `src/core/project_action.gd` is **not touched at all**, so `PROJECT_OP_TERMS` keeps its
  three quantities and `project_name`'s exception is not widened. U6c was offered that
  exception as precedent — *a coordinate is not a strength, the way a name is not* — and
  did not need it, because no coordinate ever reaches `effects.project`.
- The consequence V1.6f left unrecorded is **avoided rather than paid**.

Coverage is FRA, DEU and GBR, exactly `data/companies/`'s and `data/outlets/`'s: an absent
block is legal and means no markers. `tests/test_map_markers.gd` holds the two claims no
loader could — every site names a project the content defines, and every site is inside
its own nation's polygon, which is what a mistyped digit fails.

### The marker is an OVERLAY, not a fifth map layer

`map_layers.gd` is a registry rather than a mode flag, which invites a fifth `LAYERS`
entry, and U5c's per-layer alpha argument does not settle it either way. What settles it
was already written, in `map_view.gd`'s own header: *"no map layer adds, removes or
reorders a draw layer"*. A `LAYERS` entry chooses a roster **fill**, one at a time, from a
per-nation scalar; a marker is a point, is additive, and is orthogonal to whatever fill is
up. As a layer it would also be **structurally dead content**: the nine never build, so its
value would read exactly 0.0 for nine of the ten forever — V1.6f's own *a frame of an
all-zero data layer proves nothing*, arriving as a design instead of as a frame. So markers
are the **fifth draw pass**, frontmost, and `tests/test_map_markers.gd` pins `LAYERS` at
four so a later session moving them has to come and say why.

### The hit test does not go through the roster, and the test reads the file to say so

U5b's *unclickable structurally* rests on one sentence: `_nation_at_lonlat()` iterates
`_polygons` alone, and `_world_polygons` is drawn by nothing. A marker hit test routed
through that function would make it answer for two things, and the property would die the
day someone widened it to answer markers over Poland. `_project_at_screen_point()` is
therefore a **radius test in screen space** over the marker list, reaching neither name;
screen space rather than lon/lat because the glyph is a fixed number of pixels at every
zoom, so a degree-radius target would shrink as the player zoomed out to find it. The test
extracts that function's body from the source and fails on either name —
`tests/test_projects.gd`'s idiom for *`calendar.gd` is still a leaf*.

A click on a marker opens **Public Works** and does not fall through to the nation
underneath, or one press would open two windows.

## 2. (B1) `GameState.appointments` is NOT this scheduler, and what IS reused is the surface

The session was told to check whether [[calendar-model|U6a]]'s register was already this
machine under another name before writing a second one. It is not:

| | `appointments` | `projects` |
|---|---|---|
| what it holds | a **deferred command** | a **commitment in flight** |
| firing | `due()` fires it once, `main.gd` runs a verb that already exists | the register itself is the state |
| cancelling | free, and **leaves no trace** | the money is already spent |
| identity | `verb_key()` — one in flight per verb | the project id |
| what it owns | nothing; `calendar.gd` preloads no system **by design** | a bill and a payoff |

**What is reused is the diary, and it cost nothing.** `Calendar.fixed_dates()` gains one
row per project under construction, so completion dates appear on the strip U6a built —
which is exactly what that session exists for. It needed **no preload**, because the
register counts **months remaining** rather than dates: `diplo_cooldown_months`,
`dissolution_lockout_remaining` and `bloc.months_to_next` all already do, and
`_fixed_in()` already converts one.

> `src/sim/projects.gd` does **no date arithmetic at all**, so it cannot disagree with the
> clock about when a thing lands.

`tests/test_projects.gd` asserts both halves: a build appears on the diary and a finished
project does not, and **`calendar.gd` still preloads only its own constants**.

## 3. (B2) The payoff is the SIXTH writer of an existing target, not a third trend term

§6's bullet never says what a project's payoff *is* — [[inflation-model|V1.6b]]'s instance
thirty in a new place. Against `src/core/law.gd`'s criterion for the three existing
anti-double-count pairs — *same act, same landing site **and** same units*:

| | `INFRA_BETA` | a completed project |
|---|---|---|
| act | a player-set **spending rate** | a **discrete dated commitment** |
| landing site | the target of `_update_potential_shift()` | the same target |
| units | points of GDP of annual spending | a completed lump, in points of trend |

One of three, so **not a pair**. And the shape already existed:
`ns.law_potential_target_pct` is a permanent accumulator with its own bound, added to that
same target, written by `Legislature.apply()` when a law passes. A completed project is
that shape exactly.

> So the payoff is `ns.project_potential_target_pct`, the **sixth writer** of
> `_update_potential_shift()`'s target, and V1.6f **adds no third quantity reaching
> trend**. `economy_constants.SHIFT_MAX_PCT`'s comment — which V1.6e had to amend — needs
> no second amendment, and `investment_constants.SECTOR_TREND_MAX_PCT`'s per-quantity rule
> is satisfied by the accumulator's own clamp rather than by a new one downstream.

## 4. (B3) "Slow" was already half spent, and it changed what the band is written on

`economy_constants.SHIFT_ADJUST` is **0.20/yr — a five-year lag** on that target. Measured:

| | months after completion |
|---|---|
| t50 | **41.2** |
| t90 | **137.0** |

So a build of N months followed by that lag is **two answers to
[[mechanics-economy]]'s one word**. A band on the build length alone would have measured
half the wait. The band is written on the **delivered fraction from commit** instead:

    f(t) = 0 for t < build, else 1 − (1 − SHIFT_ADJUST/12)^(t − build)

| clause | |
|---|---|
| (i) **collectable** | the shortest project delivers ≥ 0.30 of its payoff within **one** presidential term of commitment (60 months) |
| (ii) **a bequest** | the longest delivers **exactly 0.00** within one term and ≥ 0.25 within two |

Solved rather than read off a grid: (i) puts the shortest build at **≤ 38.8 months** and
(ii) puts the longest at **> 60 and ≤ 102.9**. The escalation trigger — *if no legal build
length can deliver 0.30 inside a term, `SHIFT_ADJUST`'s own lag is binding and the response
is to shorten the BUILD, never `SHIFT_ADJUST`* — **did not fire**.

## 5. (B4) No employment term, and V1.6e's consequence one landing site further out

The payoff raises **trend**; `Economy._update_unemployment()` reads Okun on
`growth − trend`, and `structural_unemployment_pct` reads only the income-tax wedge,
`law_structural_offset_pct` and `firm_jobs_offset_pct`. There is nothing to band.

Measured **bit-identically** over 150 months, and the source is read as well — because a
later session could add the channel and a measurement alone would then simply change. The
test checks the **write** forms (`unemployment_pct =`), not the names: `_read_field()`'s
precondition read is a lookup the content asked for, not a channel.

## 6. (B5) The cost is a FLOW, and it is the first computed line that STOPS

[[companies-model|V1.4c]] writes `debt_eur_bn` directly because buying equity swaps cash
for a **sellable asset**. Building a road is spending: there is nothing at the end of it
the treasury can sell. So `ns.project_bill_pct_gdp` is a computed spending line — the
**fifth**, after V1.3d's bloc transfer, V1.3g's deployment bill, V1.4a's subsidy bill and
V1.6e's investment bill — and it lags one month in `Investment.tick_month()`'s own slot,
because `deficit_pct_gdp` is one of this verb's precondition fields.

> **Every other computed line in this game is a standing rate. This one runs for a fixed
> term and ends.** That is the whole of what makes a project a commitment rather than a
> policy, and it is what turns the deficit into a bulge with a known end date.

`tick_month()` **advances, then completes, then prices**, so a project that finishes this
month stops billing this month.

## 7. The content is the lever, and the model ships no cost, speed or strength constant

`data/project-actions/`, `src/core/project_action.gd`, `effects.project` — the **eighth**
effect channel and the **fourth** directory on `data/diplomatic-actions/`'s shape.

V1.6e had one dial (`intensity`) and three constants turning it into a bill, a build rate
and a trend coefficient, so `investment_action.gd` refuses a second authored term as *one
strength written twice*. Here there is no such constant, so **duration, price and payoff
are three independent facts** about a named object, and `_extract_project()` requires all
three on `start`. That is the difference stated in the schema rather than only in prose.

`projects_constants.gd` therefore holds only **bounds**: the ops, the op-term table, the
content ceilings, and one guard rail. **A concurrency ceiling was considered and is not
there** — how many may run at once is set by the `project_count` precondition every
authored action carries, which makes it **content**, and a model constant duplicating a
content gate is the clamp-guarding-arithmetic failure V1.6e deleted
`INVESTMENT_BILL_MAX_PCT_GDP` for.

Ten actions, five projects, a `start` and an `abandon` each. **A programme you can stop; a
project you can only abandon**: V1.6e's withdrawal leaves 63 % of its capital standing a
year on, and an abandoned project leaves nothing, forgets the build ever happened, and can
be begun again from zero.

## 8. The shipped ladder

| project | build | cost %GDP/yr | payoff %/yr | total cost | cost per point | f(60) | f(120) |
|---|---|---|---|---|---|---|---|
| High-Speed Rail Spine | 96 | 0.19 | 0.300 | 1.520 | **5.07** | 0.000 | 0.332 |
| National Grid | 72 | 0.17 | 0.170 | 1.020 | 6.00 | 0.000 | 0.554 |
| Port and Freight Corridor | 54 | 0.14 | 0.100 | 0.630 | 6.30 | 0.096 | 0.670 |
| Fibre to Every Home | 42 | 0.12 | 0.055 | 0.420 | 7.64 | 0.261 | 0.730 |
| Coastal and Flood Defences | 30 | 0.11 | 0.027 | 0.275 | **10.19** | 0.396 | 0.780 |

**Cost per unit of payoff FALLS with size and what buys the discount is TIME.** That is
the only reason a big project is not strictly dominated by running three small ones — and
the largest cannot deliver anything at all inside the term that signs it. Probe table (f)
checks it rather than asserting it: **0 dominated pairs**, and the last column is monotone.

## 9. What the probe corrected — three times, seventeen sessions running

### (1) Clause (ii) was written on the BILL, and the bill is not the cost

The first run passed its own arithmetic and failed the model: the largest permitted stack
is **0.5200** against a headroom of **0.5639**, and the measured peak deficit gap was
**0.7615**.

> A build that runs for eight years **borrows** for eight years, so what reaches
> `public_finances` is the bill *plus* [[credit-model|V1.6c]]'s interest on everything
> borrowed so far.

Every previous computed line is a standing rate against a roughly standing debt, so bill
and deficit moved together and the distinction never mattered. **A line that runs for a
fixed term and stops is the first one where it does** — V1.6c's own finding arriving from
the other side. Clause (ii) is banded on the **measured peak** now, and the relation is
solved rather than read off the grid:

    peak deficit = 1.4626 × stack − 0.0029  →  the stack may reach 0.3875

**Every point of project bill costs 1.46 points of deficit at the peak.** Shipped stack
**0.3600**, inside it.

### (2) The uniform scale was the wrong parameter, and it declared an escalation trigger

The sweep that found (1) scaled the whole ladder rigidly, and on that evidence fired
escalation trigger 2: the largest uniform scale that fits is 0.700, which takes the
cheapest project to **0.084** against a floor of 0.10, so *"no scale is both legible and
inside the span"*.

True, and **a statement about the sweep rather than about the model**. Clause (i) binds
the **cheapest** project and clause (ii) binds the **dearest pair**, so one multiplier
cannot satisfy both by construction — the free variable is the ladder's **spread**.
[[demography-model|V1.5b]]'s *the range was choosing the constant*, with the range one
dimension short. The ladder was re-authored rather than rescaled, and the trigger did not
fire on the corrected test.

### (3) Table (h) measured a president who changed their mind inside thirty days

Every abandon row came back at **−0.77 on the same bloc across five projects that are not
alike**, which is what gave it away. The control was a quiet run, so each row was reading
the **net** of a start and a cancellation taken in the same month — about −0.02 of offset,
under the floor. An abandon is measured against a president who **started and carried on**
now, and every row clears.

**And a fourth was the probe reading its own prose**: the (B2) source check matched
`trend_pct` and `sector_output` in `projects.gd`'s *header*. A check a comment can fail is
a check the next comment will quietly break; it strips comment lines now.

## 10. The kill switch cleared, and the real path is printed beside the isolated one

Pre-committed: the largest reachable project must move `growth_annual_pct` by ≥ **0.15 %/yr**
sustained, on an **isolated path** — the accumulator displaced with every budget line
untouched, so the deficit and every tax satisfaction cancel between the rows.
[[society-model|V1.5a]]'s `QUALITY_SCALE_PP` failure.

| project | isolated, vs quiet | real path, 168 months | of isolated |
|---|---|---|---|
| High-Speed Rail Spine | **+0.2621** | +0.2121 | 75 % |
| National Grid | +0.1485 | +0.1368 | 86 % |
| Port and Freight Corridor | +0.0874 | +0.0856 | 91 % |
| Fibre to Every Home | +0.0481 | +0.0485 | 94 % |
| Coastal and Flood Defences | +0.0236 | +0.0244 | 96 % |

**Cleared at 0.2621.** The isolated path holds the payoff from month zero, which is a
project *already finished* — it measures what the payoff is worth and not what a player
gets — so the reachable column is printed beside it rather than left out.
[[foreign-policy-model|V1.3f]]'s measuring-the-wrong-state, guarded against inside the
table written to avoid it.

**Four of five sit below the floor**, and that is a structural bound recorded rather than
tuned around: this ladder's whole shape is that the small projects are small.

## 11. The guard rails are slack

| | reachable peak | bound | |
|---|---|---|---|
| `PROJECT_POTENTIAL_MAX_PCT` | 0.6520 | 1.00 | SLACK |
| `SHIFT_MAX_PCT`, everything built | 0.4145 | 1.00 | SLACK |
| peak project bill | 0.3600 | 0.5639 headroom | inside |

`PROJECT_POTENTIAL_MAX_PCT` is **1.0, equal to `legislature_constants.POTENTIAL_TARGET_MAX_PCT`**,
and the match is the argument rather than a coincidence: a law writing that target and a
completed project writing this one are the same act, so the two accumulators bound alike or
the model says a motorway is worth more than a statute for no reason anybody chose.

P3's two clauses both pass: the largest payoff **0.300** clears `INFRA_BETA`'s reachable
**0.15**, and the whole ladder **0.652** stays under **0.70**, leaving the infrastructure
slider its own 0.30 of the budget the two share.

## 12. The seventeenth `ISSUE_KEYS` question — answered NO, on test 1 alone

Recorded in `opinion_constants.gd` beside `ISSUE_KEYS` whatever the answer, so a later
session finds the reasons rather than the silence.

Every YES on that list — [[inflation-model|V1.6b]]'s `inflation`, [[tax-model|V1.6d]]'s two
tax keys — was paid because the price was **not nameable otherwise**. This ships a content
object with an authored `bloc_offset`, which is exactly what [[companies-model|V1.4c]]'s
`ownership` had and V1.6e's programmes had. The S10 ratio was **not swept**, on V1.5a's
ground.

What was measured instead is that the authored price is legible. Probe table (h), twelve
months after the act:

| action | headline | worst bloc |
|---|---|---|
| `start_high_speed_rail` | +0.52 | urban **+4.45** |
| `abandon_high_speed_rail` | −1.14 | urban **−5.23** |
| `start_flood_defence` | +1.08 | rural **+4.13** |
| `abandon_flood_defence` | −1.68 | rural **−4.90** |

All ten clear the ±3.0 floor on the per-bloc rows and none on the headline —
[[diplomacy-model|V1.3a]]'s finding used as designed. **Every abandonment is a net loss**:
whoever gained from the announcement loses more than they gained.

## 13. `SAVE_VERSION` is 23, on the HALF of one field

V1.6e re-armed V1.3c's device — *the version is still 22, so V1.6f has to come and say why
it moves*. It moves, and the **split** is the assertion worth more than the bump —
[[defence-model|V1.3g]]'s `deployments` in a new place.

`NationState.projects` is one dictionary carrying two things:

- the **building** half fails soft. Absent, "nothing under construction" is the truth about
  every version-22 save, because those games had no project verb — `measures` at V1.3c,
  `sector_investment` at V1.6e.
- the **done** half does not. A France that finished the rail spine has bought a permanent
  claim on its own trend, and an absent register erases the record of it. Nothing
  re-derives it: the accumulator is the only other trace and it is not content.

`tests/test_save_load.gd` asserts the two **separately**, and pins that a serialised entry
carries exactly `Projects.ENTRY_KEYS` — so a later session caching a cost, a payoff or a
start date turns it red. `project_potential_target_pct` earns nothing on its own (derivable
from the register plus the content, exactly as `law_potential_target_pct` is derivable from
the passed-law list plus `data/laws/`) and is serialised because
`_update_potential_shift()` takes no loader. `project_bill_pct_gdp` is recomputed on the
first tick. `last_project_result` is **not serialised at all**, and the test pins that
absence.

## 14. The readout

**Four** surfaces for one register as of U6c, and each says a different thing — which is
the only way four surfaces for one register works. The map says **where**, and says nothing
else: the marker is a way *into* Public Works rather than a second readout of it.

- **Public Works** (`src/ui/projects_panel.gd`), its own window. Three sections, because a
  project is in one of three states and each is a different question: what is being
  **built**, what is **finished**, what is **available**. It does **not** go on
  `companies_panel.gd`, where V1.6e hung its whole surface: that panel is grouped by sector
  and a project is pointed at no sector, and its body is already guaranteed to overflow.
- **The budget panel**, one indented row under Spending — the **sixth** to take that route.
  Its missing-key branch is separate from its zero branch, [[tax-model]] §11's
  `.get(key, 0.0)` failure guarded against rather than repeated.
- **The diary**, which needed no code beyond one row in `fixed_dates()` — see §2.
- **The map** (`src/ui/map_markers.gd`, U6c), a hollow ring while a project builds and a
  filled one once it is finished, at the nation's authored site. An **unstarted** project
  draws nothing, which is why Public Works' third section has no counterpart here: the map
  says where, and a road nobody has begun is nowhere. The name and the months are drawn on
  **hover alone** — the dots are the layer and stay at every zoom, and it is the names that
  would collide on a France sixty pixels wide at the world view.

### The fifteenth screenshot pass found two bugs and both were the readout's

**(1) One cell was wider than the panel.** The budget row shipped as
`0.19% (6 bn) (1 building)` — twenty-four characters against `46.10% (1473 bn)`'s
sixteen. Both value columns size to their widest row, so **one extra clause on one row
pushed the whole `proposed` column past the window edge** and put the budget on a
horizontal scroll bar it had never needed. Nothing was wrong with the number; the frame
simply showed a budget the player could not read without dragging. The count moved to
Public Works, which is where the row's own comment said it belonged — *three surfaces for
one register only works if each says a different thing* — and `Budget.snapshot()` lost the
two keys nothing then read, because a snapshot key nothing reads is
[[calendar-model|U6a]]'s day budget in a new place.

**(2) The diary read *"Opens: Build the High-Speed Rail Spine"*.** The only name in the
content was the **action's**, and an action name is an imperative: right on the button
that starts the work, wrong after a colon. Two surfaces genuinely need two strings, so
`effects.project` gained an authored **`project_name`** — the noun the diary and the
finished list print. It is deliberately **not** in `PROJECT_OP_TERMS`: that list is the
three quantities, and its whole argument is about strengths written twice. A name is not
a strength.

`--build` reads its horizon **off the content** — the shortest build plus a year — rather
than carrying a number of its own. [[inflation-model|V1.6b]]'s pass found a flag that ran
*past* what it existed to photograph and V1.6e's found one that could have stopped short;
a literal here would be a third copy of an authored figure and would go stale the first
time the ladder moved. The frame shows the rail spine at *12 of 96 months remaining*, the
grid **finished** at +0.170 %/yr, and three unstarted projects with their terms.

## 15. What is deliberately not built

- ~~**No map marker.**~~ **Built at U6c** — §1.
- **No employment term.** Structural, not a policy — §5.
- **No second scheduler.** `appointments` is not it, and neither is a date register — §2.
- **No third trend quantity.** §3.
- **No partial credit for a half-built project.** There is no half-built thing in this
  model, and inventing one would be a second stock beside V1.6e's capital.
- **No sixth spending line.** `SPENDING_KEYS` is keyed 1:1 to cabinet portfolios, so a
  sixth line is a sixth minister, and [[v1]] §6 rules it out.
- **No law channel.** A project is an executive verb, by the decomposition's call 2.
- **No AI use of the verb.** The nine have no agenda term for it, which is what keeps the
  re-run bit-identical and is the same honest limitation [[defence-model|V1.3g]] and V1.6e
  each recorded. `tests/test_projects.gd` pins it.
- **No per-nation project list, and U6c did not create one.** The action list is still
  global; what became per-nation is the **site**, on the nation file. See §1.

---

Related: [[index]] · [[sector-model]] · [[economy-model]] · [[calendar-model]] · [[credit-model]] · [[companies-model]] · [[tax-model]] · [[opinion-model]] · [[decision-log]] · [[ROADMAP]] · [[v1]]
