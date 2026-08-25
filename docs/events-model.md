---
title: Events Model
tags:
  - decision
  - sim
  - balance
---

# Events Model

Occasions, choices and deadlines, as built at [[ROADMAP|V1.8]] — **the last session of
the V1 tier**, and the one [[v1]] §8 has been deferring to since the scope was written.

Same standard as [[pledge-model]], [[unrest-model]] and [[media-model]]: a **game
model**, judged on whether the player's decisions produce a legible, attributable
political outcome. Where realism and legibility conflict, legibility wins, and the trade
is noted.

## 1. The row is tiered nowhere, and that is what the section turned out to be about

[[v1]] §8 carries two bullets — *data-defined events with preconditions, choices and
consequences* and *crisis events that force a response under time pressure* — plus the
**Scandals** bullet §5 handed here at [[media-model|V1.5d]].

Counted against `docs/brainstorm/mechanics-*.md` one last time, **§8's own two bullets
are tiered nowhere at all**. Every other V1 section's bullets trace to a row in one of
those four tables with tier V1; these have no row. And every event-shaped mechanic that
*is* in those tables is **Someday**:

| mechanic | file | tier |
|---|---|---|
| Terrorism | [[mechanics-foreign-policy]] | Someday |
| Pandemics and global crises | [[mechanics-foreign-policy]] | Someday |
| Emergency powers | [[mechanics-governance]] | Someday |
| Housing market ("its own crisis generator") | [[mechanics-economy]] | Someday |
| **Scandals** | [[mechanics-society]] | **V1** |

**Instance forty-four**, and it is the largest gap between a section and its own backing
that the count has found. The consequence is not cosmetic. There is no crisis left to
author that is not either a machine this project already built — a strike is
[[unrest-model|V1.5c]], a downgrade is [[credit-model|V1.6c]], a foreign act is
[[foreign-policy-model|V1.3f]] — or tiered out of V1 entirely. So the session cannot be
an authoring exercise, and the design had to answer what is left.

What is left is the **moment**:

> **An event does not add a consequence the game did not have. It adds an occasion on
> which the player must pick one, a menu of them, and a deadline.**

Every consequence a choice carries lands on a register some earlier session owns and is
written by the function that owns it. That is what keeps this from being "a generic event
engine under another name", which §8's warning box forbids outright — and it is why the
box's third outcome, taken at V1.5d, was the right one: scandals arrive here with a
framing channel already built, so a revelation has somewhere to land.

## 2. Three more instances, and one of them is an orphan nobody had counted

**Instance forty-five: "scripted and SEMI-RANDOM events".** [[economy-model]] forbids
`randf()` outright, because determinism is what makes `Budget.project()` exactly equal to
what subsequently happens — an MVP done-when condition. [[cycle-model|V1.6a]] hit the
identical collision in nearly identical words (*"arriving whether or not deserved"*) and
its answer transfers whole: the draw is a **hash of (nation id, event id, absolute
month)**, so an event's arrival is fixed before the game starts and reproducible from
state alone. Surprise was never the mechanic; the deadline is.

**Instance forty-six: "the event schema is the union of the channels §3–7 create" is
right about the TIMING and wrong about the SHAPE.** Counted, there are ten channels. Four
are pair state (`relations`, `agreement`, `measure`, `pact`) and four are commitments in
flight (`investment`, `project`, `campaign`, `pledge`). Every one of the eight has exactly
one writer with an **actor or a bill** behind it — a directed measure with no nation
imposing it is a nation acting with nobody behind it, and a build with no bill is a second
writer of a register `tests/test_projects.gd` pins to one. **The union is not writable.**

The timing argument survives on what *is* writable, which is the LAW channel:
`effects.society` grew from one term to four across V1.5a–d, `effects.company` and the
sector burden arrived at [[companies-model|V1.4b]], and `ORDINARY_INSTITUTIONAL_KEYS` split
at [[referendum-model|V1.7c]]. A schema written at V1.5d would have carried a quarter of
what this carries. **Written before them it gets written twice — true; written as the
union it cannot be written at all.**

**Instance forty-seven: `effects.institutional` on an event choice IS "Emergency
powers".** The refusal has a citation rather than only an argument —
[[mechanics-governance]], *"suspend normal process during crisis. Addictive and
corrosive"*, tiered **Someday**. `src/core/event.gd` refuses the channel by that name
rather than as an unrecognised key, because a key refused as a typo is one a later session
re-adds. The two keys V1.7c made reachable by an ordinary Act are refused with the six
entrenched ones: an electoral system rewritten as an executive response to a crisis is
worse than one entrenched at the amendment bar, not better.

**Instance forty-eight: "Decree / executive order" is tiered V1 and appears in NO row of
any tier doc.** *"Bypass the assembly on a narrow set of matters, at a legitimacy cost."*
Forty-three prior stale-row instances never caught it. A choice that moves
`tax_rates_pct` or `spending_pct_gdp` with no assembly division **is** that mechanic: the
narrow set of matters is what the event's content names, and the legitimacy cost is the
choice's own `bloc_offset`. Discharged here rather than booked, and cross-referenced into
§8 **and** §1.

**Instance forty-nine, and not this session's.** The same sweep found two more V1-tiered
orphans in [[mechanics-foreign-policy]] — **Embassies** and **Foreign aid** — in no row of
[[v1]] and not among `data/diplomatic-actions/`'s fourteen verbs. Recorded rather than
built. This is the last V1 block, so sweeping the whole tier column one final time is this
session's job even where the answer is *not here*.

## 3. An event is nine fields, and what it does NOT carry is the design

`data/events/*.json`, a **global flat list** on `data/pledges/`' shape — the SEVENTH
directory to take `data/diplomatic-actions/`'s form and the last content type the V1 tier
adds.

| field | note |
|---|---|
| `id`, `name` | `event_name` internally — `name` is a `Node` property, the dodge seven value types now make |
| `summary` | the card body and the panel's own paragraph |
| `subject_office` | **optional**, one of `head_of_government` / `head_of_state` / `largest_party_leader` |
| `likelihood` | monthly hazard once every precondition holds |
| `respond_months` | the deadline |
| `once` | as a law's |
| `preconditions` | `legislature_constants.PRECONDITION_FIELDS`, minus one refusal, and **often empty** |
| `choices` | 2–4, each `{id, label, summary, effects, default}` |

**There is no `weight`, no `severity`, no `category` and no `cooldown`.** Duration, price
and payoff being three independent facts is [[projects-model|V1.6f]]'s finding, and it
holds here for hazard, deadline and effects: none is derivable from the others, so each is
authored and each is only *bounded* by `src/sim/events_constants.gd`. A per-event cooldown
was designed and cut — with one pending slot and a global quiet period, an event's own
cooldown is a second bound on a thing already bounded, and
`src/core/investment_action.gd`'s refusal of a second authored strength applies.

**The subject is an OFFICE and never a person.** [[people-model|U6b]]'s rule verbatim — a
law names an office, the nation's own `government` block names who holds it — so nothing
in `src/sim/` ever touches a person id and *no mechanism on a person* stays true by
construction. `src/ui/events_panel.gd` is the only thing in the project that resolves it,
and the frame reads **"Cécile Aumont — Prime Minister"** without a word of content saying
so. It is also why the same scandal reads correctly in a republic and in a monarchy.

**`preconditions` is often empty, and that is the honest split between §8's two bullets.**
Not two machines: a scandal is the pure-hazard case (bullet 2, arriving whether or not
deserved) and a fiscal ultimatum is the preconditioned one (bullet 1, data-defined with
preconditions). One schema, one field, both bullets.

## 4. The choice channel, and the one refusal that is not about a channel

A choice's `effects` is `Law.extract_shared_effects()` — extracted at this session so a
law and an event choice cannot drift apart — **minus `institutional`**:
`tax_rates_pct`, `spending_pct_gdp`, the three `SCALAR_EFFECT_KEYS`, `bloc_offset`,
`company` (sector + burden) and `society` (all four terms). The three anti-double-count
refusals `law.gd` already carries came with it, because they are properties of the channel
pair and not of laws.

`Legislature.apply_effects()` is the single applier. A second one in `src/sim/events.gd`
would have been a second writer of `bloc_offset`, `regulation_burden`, `corruption`,
`migration_stance`, `settlement_stance` and `press_freedom` at once, with six clamps
agreeing by inspection rather than by being the same line of code. **The approval path is
what separates the two callers** — a law reaches these channels through a vote and an
event choice through a decision made under a deadline — which is V1.4a/V1.4b's a/b line
one block later.

**`overall_approval_pct` is refused as an event precondition**, and it is the one refusal
that is about the *loop* rather than the channel. Every choice's core price is
`bloc_offset`, a clamped permanent accumulator that reaches approval directly; an event
gated on low approval and priced in approval is positive feedback with nothing damping it,
so a president who slips once is handed a crisis, pays for it in approval, and is handed
another. [[credit-model]] deleted its own deficit term for exactly that reason.
[[pledge-model]] refused the same field on a *different* argument — a promise about your
own approval is circular — and **two refusals agreeing about one field for two reasons is
worth more than either**.

Expressed as a **refusal set** beside the one list rather than as a second list:
`legislature.gd` already records that its whitelist and its `read_field()` match are the
same list in two places and that V1.5c added half of it. A third copy would be that
failure again with the same excuse.

**V1.5c's `>=`-only invariant on `unrest_pct` does NOT transfer**, and the reason is in
its own words: it exists because `available()` only ever *opens* laws, so a `<=` would
make unrest an uncontestable gate on player action. An event is not a lever the player
reaches for; a precondition on one opens a *problem*. Recorded rather than copied.

## 5. The machine

```
Events.tick_month(state, loader):
  ns = state.player()                      # player only: the nine have no decider
  count the quiet period down
  if pending:
      months_left -= 1
      if months_left <= 0:  apply the DEFAULT choice, record, clear, open the quiet period
      return                               # ONE slot
  if quiet: return
  the first event, in content order, that is off cooldown, whose preconditions hold,
  and whose hazard draws this month -> announce
```

**One pending slot**, `referendum_pending`'s rule and `GameState.bloc["pending"]`'s shape
one block on. The register IS the rule: one is not a bound, it is what *the matter on your
desk* means — and the message column holds six cards, so an event buried under the next
one is not an occasion.

**The register is a third shape, and the handoff offered two.** A **deferred command**
([[calendar-model|U6a]]) is something the player scheduled and can cancel for free; a
**commitment in flight** ([[projects-model|V1.6f]]) is something billing that can be
abandoned at a price. An event is neither: it is an **obligation the player did not open
and cannot decline**, which is [[defence-model|V1.3g]]'s alliance obligation and V1.7c's
`referendum_pending`.

**`once` is marked at ANNOUNCEMENT**, which is the one place this differs from
`passed_law_ids`. An event has happened the moment it arrives; the choice is the response
to it, not the event. Marking at resolution would also let a save reloaded mid-crisis see
the same revelation announced twice.

**`events.gd` is not a leaf, and that is deliberate.** It preloads `legislature.gd`. The
leaf alternative — returning the resolved choice as data for somebody else to apply, which
is `Calendar.due()`'s and `Referendum.resolve_due()`'s shape — fails because there is no
single somebody: `src/ui/main.gd`, `tools/balance_probe.gd`, `tests/test_balance.gd`,
`Budget.project()` and eight probes would each have to apply, which is
[[media-model|V1.5d]]'s forgotten-tick failure multiplied by ten rather than avoided.
V1.6a's rule governs: **a system that cannot be forgotten is worth more than one that is
remembered.** `tests/test_events.gd` pins the direction, and checks the tick in **four**
files where `tests/test_referendum.gd` checks two.

**Player only.** `Bloc._tick_council()` already gates on `state.player_nation_id` because
the council's proposal waits for the player's vote and nobody else's; this is the second
place in `src/sim/` to read the player id rather than `has_budget`, for the same reason.
There is no AI chooser, which is [[defence-model]]'s honest limitation recorded a **sixth**
time and pinned by a test rather than left as an absence.

## 6. The tables, and E1b is where the session turned

`tools/events_probe.gd`. **E0 runs before a single threshold is authored**, which is
V1.7c's R0/R6 correction applied to CONTENT rather than to a constant.

### E0 — the reachable range, and it corrected the plan before any content existed

A precondition written outside the reachable range of its field is a crisis that never
happens, and nothing in the suite would catch it: the content loads, the machine works,
and nothing fires.

**The plan had `deficit_pct_gdp` as a `<=` field.** It is not: `Budget.tick_month()` sets
it to `total_spending_pct_gdp - total_revenue_pct_gdp`, so **a shortfall is POSITIVE** and
`austerity` reads −9.41 because it runs a surplus. `balance_probe.gd`'s `_print_row()`
negates it for display, which is why every deficit quoted in [[CLAUDE]] and in the model
docs carries the opposite sign from the field. **An event authored on the plan's sign
would have fired only on a surplus.**

Reachable range over 168 months of FRA, and the run **stops when the player leaves
office** — `hands_off` and `managed` both last 136 months, everything harsher 16 to 76:

| field | hands_off | managed | authored threshold | occupancy (hands_off / managed) |
|---|---|---|---|---|
| `deficit_pct_gdp` | 4.99 … 7.19 | 2.47 … 2.87 | **>= 5.5** | 74 % / **0 %** |
| `unemployment_pct` | 6.78 … 7.83 | 6.67 … 8.08 | **>= 7.5** | 40 % / 43 % |
| `unrest_pct` | 0.00 … 14.52 | 0.78 … 8.79 | **>= 10.0** | 9 % / **0 %** |

Each row **separates the regimes**, which is what a precondition is for. A threshold at
0 % everywhere is unreachable content; one at 100 % everywhere is not a precondition, it
is a decoration.

### E1 + E1b — the two-part selector, because the band it was designed with was one-sided

`EVENT_COOLDOWN_MONTHS` is the session's **only** tuned constant.

Clause (i), cadence, between 2 and 6 events per five-year term in the median reachable
regime, **passed every candidate from 3 to 20**. That is the one-sided-band failure
[[society-model]] and [[demography-model]] each recorded, and V1.5a's two-part selector is
the only thing on this project's record that has ever answered it.

**Clause (ii) is E1b, and finding it is the session's sharpest correction.**

`bloc_offset` is a permanent clamped accumulator. Every previous writer of it either
charges once for an act the player chose (a referendum, a law) or charges while a
condition holds and stops when the player fixes it (a pledge breach). **An event is
neither** — it arrives whether or not it is wanted, it recurs, and its default charges
without a decision. The first authored ladder satisfied the per-decision band and **failed
this one by a factor of four**: ten defaults reached `BLOC_OFFSET_MAX`, and once the clamp
saturates **every regime converges on the same floor**.

`tests/test_balance.gd` caught it in the sharpest possible words — *managing the budget
did not beat ignoring it on approval: 38.4 managed vs 38.6 ignored* — which is the harness
saying that a well-run country and an ignored one had become indistinguishable. That is
[[projects-model]]'s ***a bill is not a cost*** one block on: a per-decision price is not a
lifetime charge. And it is the plan's own **escalation trigger 4**, fired and honoured by
the response the plan named — the per-event magnitude came down, the clamp did not move.

Together the two clauses pass **[4, 20]** and fail 3 (saturating) and 24 (cadence), so the
interval is closed at both ends by a measured failure rather than by the edge of the grid.
Midpoint **12**.

**V1.5b's refinement diagnostic fired on the way**: on a coarse grid the answer was 10, and
adding the missing integers moved it to 12. The spacing was choosing the constant, exactly
as `unrest_probe.gd` found for its own convergence rate.

At the shipped value the worst reachable career accumulation is **0.423 of a 1.00 clamp**,
so the guard rail is **measured and slack** by 0.577 — [[defence-model]]'s discipline.

### E2 — the band's AXIS was wrong, and its own first run said so

Written as *best choice minus default on the headline approval figure, past ±3.0*. Five
events of six came back under the floor and the sixth came back **negative**: on
`emergency_budget_demand` the default — refusing to fix the deficit — is the most popular
thing a president can do, which is not a defect in the content but the fiscal dilemma the
event exists to pose.

Two things are wrong with it and both are recorded failures of this project's own. It
measures an observable the channel does not reach in one step — an event moves **a few
blocs hard**, and [[defence-model]] moved its price to the rural row after finding five
blocs of six weight `defence` at 0.00, [[demography-model]] DELETED a term that could not
clear the headline floor at any value, and [[unrest-model]] measured on the workers row for
the same reason. A headline figure is a size-weighted mean, and a decision that moves
winners and losers in opposite directions is quietest exactly there. And *best minus
default* presumes the best choice is the popular one, which for a fiscal decision it must
not be.

So the band is the **widest per-bloc spread across the whole choice set**, twelve months
on, and **both edges are measured rather than invented**: floor 3.0, the poll-noise floor
since S10; ceiling 5.8, what [[pledge-model]] measured a full-term promise breach to cost.
[[campaign-model]]'s correction is what forces that — its own first band clause was a
number picked because it sounded like a margin.

| event | spread | on bloc | headline |
|---|---|---|---|
| `sector_shock` | 5.145 | business | 0.288 |
| `emergency_budget_demand` | 4.990 | students | 2.117 |
| `union_ultimatum` | 4.716 | business | 0.494 |
| `broadcast_charter` | 3.666 | urban | 0.305 |
| `honours_scandal` | 3.336 | urban | 0.190 |
| `procurement_scandal` | 3.314 | urban | 0.365 |

All six pass. **The headline column fails for all six and is recorded rather than tuned
against** — V1.6a's legibility floor a third time. An event is a decision about *who* pays,
and the national average is the one number that cannot see it.

### E3 — the kill switch, and its RULE was corrected by its own first run

*No choice may weakly dominate another on all axes, and every default must be beaten on at
least one.* The first run reported five violations of which **four are the design**: in
every one an active choice dominated the **default**. A default is not taken, it is
suffered, and an active choice beating it is the pressure rather than a trap. The failure
this project has killed eleven times is an option that is never worth **taking**.

So dominance is counted **between alternatives only**. One real violation survived — `cut`
dominated `raise` on the fiscal event — and it was fixed in the **content**, by making the
tax rise collect more than the spending cut, so the two trade against each other.

Two further corrections to the test itself:

- **A tolerance.** The first run decided a verdict on a difference in the ninth decimal
  place and therefore stayed **silent** about two options identical in every readable
  sense. A dominance test with no tolerance is a test of float noise, and it fails in the
  dangerous direction.
- **A fourth axis, `corruption`**, and which registers belong is an argument rather than a
  list. A choice may be measured on a register only where that register has an
  **unambiguous better direction**. `corruption` has one, and without it `inquiry`
  dominated `dismiss` while being the choice that leaves the state dirtier.
  `press_freedom` has none (it buys legitimacy through the grievance and costs approval
  through the framing gain — which way a president wants it *is* the decision);
  `settlement_stance` has none, and refusing it is what keeps `settle` against `partial` a
  real choice, because a settlement is **bought**; `regulation_burden` has been signed by
  design since V1.4b.

Final: **0 dominated alternatives, 0 toothless defaults.**

## 7. The content — six events, eighteen choices

Three pure-hazard (`data/events/scandals.json`) and three preconditioned
(`data/events/crises.json`).

| id | gate | subject | reaches |
|---|---|---|---|
| `procurement_scandal` | hazard 0.030 | head of government | `society.corruption`, `bloc_offset` |
| `honours_scandal` | hazard 0.020 | head of state | `society.corruption`, `society.press_freedom`, `bloc_offset` |
| `broadcast_charter` | hazard 0.035, `once` | — | `society.press_freedom`, `bloc_offset` |
| `emergency_budget_demand` | `deficit_pct_gdp >= 5.5` | — | `spending_pct_gdp`, `tax_rates_pct`, `bloc_offset` |
| `union_ultimatum` | `unrest_pct >= 10.0` | — | `society.settlement`, `spending_pct_gdp`, `bloc_offset` |
| `sector_shock` | `unemployment_pct >= 7.5` | — | `company` (sector burden), `spending_pct_gdp`, `bloc_offset` |

**`union_ultimatum` reaches `society.settlement` DIRECTLY**, where V1.5c's settlement
reaches it through an assembly division. That is V1.4a/V1.4b's a/b split in a third
register, not a double count: the approval path differs and the mechanism does not.

**Every choice's size-weighted mean `bloc_offset` is held near zero** — actives within
±0.008, defaults at about −0.006 — with the size in the **per-bloc spread**. That is what
E1b forces, and it has a consequence nobody authored: holding the mean at zero pushes the
cost onto the **smallest** blocs, so `business` (size 0.10) is the natural loser far more
often than its share, and the content had to be spread deliberately to stop one bloc
carrying every crisis.

## 8. `SAVE_VERSION` 25 → 26, on three fields of four

They fail the rule by **three different failures**, so `tests/test_save_load.gd` asserts
them apart — the pattern V1.5c set and V1.6b extended, because a combined check lets any
one of them be quietly wrong while the other two carry it.

| field | verdict |
|---|---|
| `event_pending` | **Earns it.** Absent, a crisis the country is already facing vanishes — a free escape from the one act this session made un-escapable. `referendum_pending` at V1.7c, `campaign_started` one commit earlier |
| `event_fired` | **Earns it, differently.** Absent, a resolved `once` event happens again and the player pays its price twice for something settled. `passed_law_ids`' case |
| `event_quiet_months` | **Earns it, a third way.** Absent it reads 0, and 0 means *may fire now* — U6a's `diplo_months_to_act`, whose absent value fired nine acts in one month |
| `event_history` | **Earns nothing.** A display record nothing in `src/sim/` reads back, `unrest_acts`' case. Serialised anyway, because the ledger is half of what the panel exists to be and a session-only ledger is one the player loses by saving |

**What was NOT added is the half worth pinning**: no stored hazard, no stored draw, no RNG
state, because `Events.hazard_passes()` is a pure function. V1.6c pinned the credit
module's statelessness the same way, so the day a session gives an event's arrival an
accumulator the test turns red and has to come and say why. It is also what makes a save
reloaded on the month a crisis arrived receive **the same crisis**.

## 9. The re-run is a re-baseline, and 30 of 43 keep every figure

Predicted in advance, and E0c named the movers before the run. **All 43 shared regimes
differ** — every regime fires the three hazard-only events, which have no precondition to
fail — but:

- **30 of 43 keep GDP, growth, trend, unemployment, debt and deficit bit-identical.** Only
  13 move, and those are exactly the runs where a choice touched a budget line: the fiscal
  event, `sector_shock`'s underwriting, `union_ultimatum`'s settlement, or a run that
  diverged after the one outcome change.
- Worst approval move **5.80**; **one outcome change of 78** (`tinkering`'s second
  election, HELD → LOST).
- `managed` is the cleanest single row: 2032 GDP **3084**, growth **+1.27**, trend
  **+1.31**, unemployment **7.67**, debt **125.2**, deficit **−2.86** — *identical to the
  digit* — against approval **49.3 → 48.6**. The budget is untouched and the standing is
  not, because `managed` never sees the fiscal event and only ever takes scandal defaults.

**Two new regimes**, and the only thing that varies across the three is whether the player
opens the window: the budget is identical, the events are identical, and **the arrival
month of every one of them is identical**, because the hazard is deterministic. That is
[[pledge-model]]'s own confounded regime pair avoided rather than repeated — it differed in
two things at once and needed a third regime to separate them.

### The legibility evidence, and it refuted the regimes' own names

Same budget, same crises, same dates:

| 2032 | approval | deficit | worst bloc | 2037 approval |
|---|---|---|---|---|
| `managed` (answers nothing) | **48.6** | −2.86 | students 44 | 44.9 |
| `managed_answers_softly` | **49.3** | −3.19 | students 46 | 46.5 |
| `managed_answers_hard` | **49.8** | −2.86 | rural 44 | 46.9 |

Answering beats ignoring by 0.7 to 2.0 points, which is the property the deadline needs.
But the two regimes were first called `best` and `worst`, **and the run refuted the
names**: the soft run — always the choice with the largest immediate size-weighted
`bloc_offset` — ends *below* the hard one on both approval and the deficit, because the
choices that buy the most approval on the day are the ones that concede money, and the
books are something the electorate weighs too. That is [[campaign-model]]'s own finding in
a new place: **maximising the thing you can see at the moment of the decision is not the
same as being better off a term later.**

## 10. The surfaces

**The card is `message_stack.gd`'s fifth caller and the FIRST EVER CONSUMER of its
`card_activated` signal**, emitted since U5a and connected to nothing. U5a's call 3 said
the column ships as furniture because the thing that fills it is events, and that *"V1.8
adds calls rather than a layout"*. It held: nothing on screen moved to make room, and the
one piece of machinery this needed — a card the player can click through to the decision —
was already there.

Two cards, opposite in kind. An **arrival** is a question and clicking it opens the window.
A **default** is a thing that already happened to the player's government with no button
pressed — `_card_appointment()`'s class, and the sharper case, because with an appointment
the player at least booked it.

**Dispatches** is a window in the State cluster, **not modal**: a crisis the player can
ignore and pay for is the whole of *forces a response under time pressure*, and a modal
removes the choice by removing the option of not making it. Pending block at the top, the
**ledger** below it.

**One diary row**, `FIXED_EVENT`, and `src/sim/calendar.gd` still preloads nothing —
V1.6f's and V1.7c's reason a third time. The register carries the event's own **name**,
copied in at announcement, so this is the one row on that list needing no lookup at all.

### The screenshot pass earned its keep for the twentieth session running — four bugs

- **The tool's.** `--event` announced the register directly and then ticked a month, which
  put a correct panel on screen and left **the message card unexercised**: `main.gd` cards
  an event that was absent before the tick and present after it, so a pre-announced one is
  already pending when `_card_events()` looks. The frame showed an empty column beside a
  live crisis. It ticks until one arrives now, which is affordable precisely because the
  hazard is deterministic — the loop is not a search.
- **The tool's again, and it is V1.4a's failure a fourth time.** `_mark_panels_dirty()` was
  missing `_projects_panel` and `_campaign_panel` as well as this session's, so `--build`
  and `--campaign` had each been photographing a panel that refreshed once on frame 1.
- **The readout's.** *"2 months to answer, then: Say nothing"* rendered in **green** — the
  colour this interface uses for a delta that is good news. A deadline is not good news at
  any distance; it is only more or less urgent. Neutral until the last month.
- **The readout's, and it is [[pledge-model]]'s own lesson.** The ledger named the button
  and not the consequence — *a live promise that never said what it had cost*. The choice's
  authored sentence is printed under each resolved row, **derived from the content** rather
  than stored with the record, so the save-format assertion that an entry carries three
  keys and nothing else survives intact.

## 11. What is deliberately not here

- **No AI chooser.** Events fire for the player alone.
- **No map layer.** The nine never have one, so a fifth `LAYERS` entry would read exactly
  0.0 for nine of ten forever — U6c's own argument.
- **No corruption-scaled hazard.** Designed and cut: one tuned constant buying a coupling a
  precondition already expresses, and E1 measures frequency directly.
- **No new `PRECONDITION_FIELDS` entry.** The seven cover every authored event.
- **No `renounce` verb.** There is nothing to renounce: an event resolves by being answered
  or by the clock answering.

---

Related: [[v1]] · [[legislature-model]] · [[media-model]] · [[pledge-model]] ·
[[projects-model]] · [[calendar-model]] · [[people-model]] · [[cycle-model]]
