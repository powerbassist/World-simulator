---
title: Events Model
tags:
  - decision
  - sim
  - balance
---

# Events Model

Occasions, choices and deadlines, as built at V1.8 — **the last session of
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

> **V1.8 RECORD — REWRITTEN AT THE RULE AT V4.4 (the field list and the "no category,
> no cooldown" paragraph below describe the V1.8 event, not the shipped one).** V4.4's
> event also carries `category`, `weight`, `severity`, `on_action` and
> `cooldown_months`, and a choice carries `arms` (`src/core/event.gd` is the
> authority). The reasoning below for why V1.8 left them out stands as history; §5 and
> §7 hold the machine and the book that replaced it.

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

**The subject is an OFFICE — and since V4.3 a person may stand behind one.** The
office resolution itself STAYS: a law names an office, the nation's own
`government` block names who holds it, `src/ui/events_panel.gd` remains the only
resolver, and the frame still reads **"Cécile Aumont — Prime Minister"** without
a word of content saying so. It is also why the same scandal reads correctly in
a republic and in a monarchy. What the original rule forbade — *nothing in
`src/sim/` ever touches a person id* — is **overturned deliberately at V4.3**
([[v4]] §V4.3, *People who want things*): the character register
(`src/sim/characters.gd`, [[people-model]] §14) is that tier's signed exception,
a person now carries wants, and the office-never-a-person wall it defended is
rewritten here rather than left contradicting the code beneath it. The events
SCHEMA does not change in that block: `subject_office` stays an office field,
no event ships a person subject, and the day one wants to it will extend this
same table with the reference named.

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

> **REWRITTEN AT THE RULE AT V4.4** (the events-at-scale block). The one-slot form
> below is kept as the V1.8 record; what it argued held at nine events and died with
> the slot at a hundred and two — the tier doc's own sentence. The V4.4 machine:

```
Events.tick_month(state, loader):          # every nation now, player AND the 28
  quiet down (per CATEGORY, sparse; BEFORE the draw reads it) + cooldown release
  player: expire entries whose months_left hit zero (each on its own default)
  armed chains due this month -> deliver first (a consequence outranks a draw)
  hooks: for each ON_ACTIONS with a live emitter read this month
      -> one hook event per happening (likelihood = spawn chance, gates still apply)
      -> the player's door skips an event already on the desk, so a sibling hook
         event on the same happening can draw (pass 17; before it the desk-held
         event passed its draw, hit the dedupe and took the one-per-happening break)
  standing hazard: group the month's draws by category
      -> one WEIGHTED winner per pulsing category (Cycle.unit over the roster)
      -> player: land on the desk (severity-ordered, QUEUE_MAX 4, dedup by id)
      -> AI nation: resolve IN THE SAME TICK through the situational chooser
```

**The desk replaced the slot**, severity-ordered and bounded at `QUEUE_MAX` 4 (the
message column holds six cards — the old ceiling argument, one size up) — the bound
lives at DELIVERY, where all three doors pass, and a chain that finds the desk full
waits a month while a hook or a draw skips (next happening, next month). `answer()`
answers a NAMED entry; `choose()` remains the head-answering read kept for harnesses. The
quiet moved DOWN a level: a delivery or resolution quiets its own CATEGORY, and
`CATEGORY_QUIET_MONTHS` 3 is the gap to the next draw, not the count of silent months —
the countdown runs before the hazard reads it, so a stamp at month M blocks M+1 and M+2
(two blocked months) and the category draws again AT M+3 (pinned in `tests/test_events.gd`;
E4's cadence bands were swept on exactly this) — one resolution in fiscal silencing scandal forever was
the global quiet's defect at nine categories. The per-event cooldown V1.8 designed
and cut came back: the cut's argument ("the slot already bounds it") died with the
slot.

**The register's third shape** (obligation-not-opened, below) is unchanged; what
changed is that several obligations can stand at once, each carrying its own clock.
`event_pending` became `event_queue` — SAVE_VERSION 39, argued per register in
`game_state.gd`'s documentation block.

**`once`, cooldowns and the category quiet are marked at DELIVERY** — V1.8 marked
`once` at announcement for the player, and the V4.4 machine first kept that shape,
which the review caught binding NOTHING for the 28 AI nations (they resolve without
ever announcing). Delivery is the one write site every nation passes through; the
staging primitive `announce()` writes the queue and nothing else (the mark registers
stay unwritten), so the sited sweep can drive it 48 times without stamping a single
`once`, cooldown or quiet. The V1.8 reason survives the move intact: the
mark exists the moment the occasion is in front of somebody, not when they answer it.
**The cooldown has a floor of one month**, stamped at delivery
(`month + max(cooldown_months, 1)`) and raised again at resolution (`_resolve` lifts
the event's until-month to at least the month after): an authored 0 still means one
occasion per event per month. The AI branch resolves on the spot, so a double delivery
would apply its choice twice, and the UI's desk-diff keys on the event id, so an entry
that defaults and is re-delivered in one tick would show neither card nor ledger line.
The floor itself leaves the shipped book unaffected — every cooldown-0 event is `once`,
which already binds. This floor is also why a chain MAY arm a hook event: the chain door
delivers first and every door checks the cooldown, so the hook door cannot deliver the
same event again in that tick (the loader refused the shape until pass 18).

**The hook door's desk skip is a shipped-behaviour change (pass 17), separate from the
floor**: the player's hook loop now skips an event the desk already holds, as the hazard
pool does, so a sibling hook event on the same happening can draw where it never could
while the desk-held event used up the happening's one slot. AI nations have no desk and
are untouched.

**Only the hazard door checks the category quiet.** The chain and hook doors run no
quiet check: a consequence or a happening-triggered event is delivered inside a quieted category (delivery then re-stamps the quiet). The
quiet throttles the standing draw, not the world's reactions to what the player did.
(The hook door runs `_gates_pass` and `_cooldown_ok`; the chain door runs the `once`
mark and `_cooldown_ok` only — see Chains below.)

**An armed chain entry whose target is cooling down in its due month is erased** — the
existing "cooling down dies silently" rule (the target's preconditions are not checked at
this door). The one-month floor makes that reachable for
a chain that collides with a same-tick resolution of a cooldown-0 target (the resolution
raises the target's until-month to the month after, and the armed entry finds it cooling).
No shipped content reaches it: every cooldown-0 event is `once`, and no chain targets one
that can resolve in its own due month.

**The weighted draw is a second pure function**: `Cycle.unit` over (nation,
category, roster-sorted-ids, month) against cumulative authored weights — same
inputs, same winner, no stored draw (the absence pins stand). The roster salt re-keys
the stream whenever the eligible set changes (the category was already in the key);
authored `weight` is content (bounds [0.2, 5.0]),
and `LIKELIHOOD_MIN` moved 0.005 → 0.002 at integration: the V1.8 floor was
calibrated when the book had nine events and per-event PLAYER visibility was the
point — at 102 events the floor's job is WORLD visibility (0.002 × 29 nations × 168
months ≈ 10 firings somewhere per run), and the [6, 18]/term cadence band is
arithmetically unreachable above it (measured: all-94-events-at-0.005 gives 22/term;
the ×0.2 proportional rescale lands 12.0/term, dead interior).

**Hooks are the block's "the game watches you" change**: an event fires BECAUSE a
law passed (`ns.law_ledger`'s own months list), a repeal landed (the V4.4
`ns.repealed_at` stamp beside the ledger's silent erase), a private member's bill
became law (`ns.assembly_bill_passed_month`, written only where the bill comes into force), a minister resigned (`ns.last_resignation`,
one-month lag — Cabinet ticks after Events), a takeover bid stood or a firm failed
(two industry stamps on the register the machine already writes), a commodity price
crossed up through 1.25× base (an EDGE — `Commodities` stamps `ns.commodity_high_month` in the month a good goes from below the line to at or above it, because a level read on a vector that drifts to its clamp within months fired nearly every month and flooded the desk; pass 22), or the Union's
accession flipped (the `ns.last_accession` stamp inside `_flip_membership` is
written for every org; `accession_won` fires only when its `org` is `eu`). **Two vocabulary names have no shipped consumer:** `law_passed` (never had one) and `commodity_price_high` — the two commodity events that rode it, `com_price_high_desk` and `com_industry_bills`, are ordinary HAZARD events in the `commodity` category since pass 23 (median likelihood of the category's other six, 0.0033), because the V4.6 price drift crosses goods one after another in months 1–5 of every new game for all 29 nations and never again, so the edge fired only inside that artefact. The hook stays in the vocabulary and its emitter stays witnessed (test sweep, events_probe E6); re-bind the two events once the drift is fixed (docs/someday.md). One vocabulary,
closed at `events_constants.ON_ACTIONS`, refused loudly at load; `election_lost` is
refused WITH ITS REASON (a lost election ends the game — nothing could answer the
event).

**Chains**: a choice carrying `arms {event_id, delay_months}` schedules the
follow-up at an absolute due month; due entries deliver FIRST (a consequence
outranks a draw), and the loader refuses unknown targets and cycles at load. **A chain
delivers its target regardless of the target's preconditions** — the arming IS the
occasion (the player's own choice promised the consequence), so a government below the
target's gate still receives it; the target's `once` mark and cooldown still bind (a
once-fired target, or one cooling down in the due month, kills the chain), and a full
desk makes it wait a month. The preconditions gate the hazard and hook doors only.
The machine V4.1 refused, built once, here.

**The register is a third shape, and the handoff offered two.** A **deferred command**
([[calendar-model|U6a]]) is something the player scheduled and can cancel for free; a
**commitment in flight** ([[projects-model|V1.6f]]) is something billing that can be
abandoned at a price. An event is neither: it is an **obligation the player did not open
and cannot decline**, which is [[defence-model|V1.3g]]'s alliance obligation and V1.7c's
`referendum_pending`.

> **V1.8 RECORD, CLOSED AT V4.4.** The paragraph below survives unedited because
> the reasoning is the reasoning; the SITE moved. The marks are made at DELIVERY
> now -- the corrected rule the V4.4 paragraph above states -- because at
> announcement they bound nothing for the 28 AI nations, which resolve without
> ever announcing.
>
> **`once` is marked at ANNOUNCEMENT**, which is the one place this differs from
> `passed_law_ids`. An event has happened the moment it arrives; the choice is the response
> to it, not the event. Marking at resolution would also let a save reloaded mid-crisis see
> the same revelation announced twice.

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
> **CLOSED AT V4.4.** The paragraph above is the V1.8 record, kept because the
> reasoning is still the reasoning — the player needs a decider, and the council
> example still holds for that. What changed: the OTHER 28 nations now have one too.
> A minimal situational chooser (`Events._choose`) scores each choice against the
> nation's own position — size-weighted bloc response, a fiscal term above a
> deficit floor, a corruption term, an unrest term — and resolves the occasion
> IN THE SAME TICK through the one applier — **minus four channels**: for an AI
> nation `Events._resolve` hands the applier a COPY of the choice's effects without
> `tax_rates_pct`, `spending_pct_gdp`, `company` and `other_revenue_pct_gdp`
> (pass 23). Nothing ticks the other 28 governments' rates, spending lines, firm
> burdens or other-revenue line back toward anything, so an event answer written
> there only ratchets (measured: AI infrastructure +1.45 points of GDP on average,
> an industry burden at its clamp). The chooser still SCORES every effect, and
> `bloc_offset`, `society`, `structural_unemployment_pct`, `potential_growth_pct`
> still land. Deterministic (two identical states
> answer identically, test-pinned), never defaulted (an AI nation that says
> nothing is an occasion that never happened), and its queue is structurally
> empty because it has no desk. The sixth recorded instance is this one, and
> the record ends here.

## 6. The tables, and E1b is where the session turned

> **V4.4'S OWN TABLES LIVE IN `tools/events_probe.gd`'s E4–E7** (driving the real
> machine): E4 cadence/overfull swept over `CATEGORY_QUIET_MONTHS` [1..6] and the
> `QUEUE_MAX` bound; E5 arrival share per category (≤ 30 % band — E1b's finding
> one level up, no category a monoculture); E6 every `ON_ACTIONS` hook witnessed
> landing a likelihood-1.0 fixture; E7 the chooser over a term (≥ 10 nations
> answering, zero defaults, non-constant choice distributions). The verdicts at
> integration: 12.0 answered/term dead interior, all nine categories 2.7–18.9 %,
> 8/8 hooks, 28/28 nations. `tools/event_lint.py` (law_lint's pattern) carries
> E1b's per-choice arithmetic as a standing content gate — mean within ±0.008 of
> zero, business-strict-worst ≤ 30 % — which FAILED the five pre-band carried
> choices on first run, exactly as an instrument should. The machine's cost,
> measured at integration: the events tick runs ~14–17 ms/month over the full
> book (102 events × 29 nations), the projection path carries its events share
> at +~0.5 s per 2×24-month projection, and the scale probe PASSES at 4.68 s
> mean against its 7.0 s band. The hazard-memo idea (PR-46 finding 6's
> projection-work shape) is recorded beside that work rather than built.

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

`EVENT_COOLDOWN_MONTHS` was the V1.8 session's **only** tuned constant. V4.4 deleted it
with the single slot it governed; its dial is now `CATEGORY_QUIET_MONTHS`, swept in §6.
The record below is V1.8's, kept because the E1b clause it found still binds.

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

Final: **0 dominated alternatives, 0 toothless defaults** — the V1.8 six-event book's
record. The 102-event book measures differently on the same instrument (35 dominated
non-default pairs, 4 toothless defaults, 2026-10-11): E2/E3 declare their bands but do
not fail the run, and re-tuning grown content to the V1.8 standard is an author call,
recorded in [[someday]].

## 7. The content — six events, eighteen choices

> **V4.4: six → 102 events, 307 choices, nine category files** (scandals 16,
> personal 10, fiscal 13, unrest 11, industrial 14, european 10, foreign 10,
> commodity 8, disaster 10 — the four legacy crises and two climate events moved
> in and re-tuned (every likelihood ×0.2, five carried choices re-authored to
> the band), `crises.json` and `climate.json` retired). The table below is the
> V1.8 record; the E1b paragraph beneath it is the one that GREW TEETH: the
> ±0.008 mean and the business-worst ≤ 30 % share are now `tools/event_lint.py`,
> a standing content gate that failed the five pre-band carried choices on first
> run and passes at 0. Eight of the 102 carry `on_action` hooks (§5), one carries
> a chain (`audit_finding.bury_it` arms `deficit_ceiling_vote` at 6 months), and
> the likelihood book is ×0.2-proportional under the moved floor (§5).

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

> **V4.4 bumps 38 → 39 on SIX registers, argued apart in
> `src/core/game_state.gd`'s documentation block**: `event_queue` (the slot
> became the desk — a dropped queue is the V1.8 free escape times four),
> `event_category_quiet` and `event_cooldowns` (sparse until-registers whose
> absent value means *may draw now*, the `event_quiet_months` case one level
> down), `event_armed` (a chain the player paid for must not evaporate), and
> the two stamps other machines write (`repealed_at`, `last_accession`; the
> pure-function absence pins below survive and stay red). A seventh,
> `event_hook_fired`, was removed at pass 18 as dead state: its guard could
> only trip on a second tick of one month, which no caller does, and the
> cooldown floor refuses the second delivery regardless. The table below is
> the V1.8 record for the fields that became the queue.

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

> **V4.4's own re-baseline (2026-10-07, both sides from worktrees, 51 regimes):
> 0 identical, 24 outcome-sequence flips of 51 — 20 of them HELD→LOST at the
> 2032 second election, ONE-DIRECTIONAL, and the prediction's 1–4 was a
> magnitude miss written before E4's cadence landed.** The mechanism is the
> declared default-drain channel and nothing else: the queue-era idle president
> answers ~12 occasions a term against the slot-era ~4, the unanswered share of
> them defaults, and the defaults' small negative mean accumulates to
> hands_off −2.0 approval by 2032 — flipping every second election that sat
> inside that margin. Invariants 50/50 both sides; zero stray lines after the
> last `invariants: OK` on either side (V1.7c's check); every regime's first
> divergence at the 2027 row, the AI nations acting in year one as predicted.
> **Recorded as the block's OPEN AUTHOR CALL, not tuned**: whether silence
> should cost a governing president the second election THIS often is a design
> question (the honest levers: the defaults' authored means,
> `CATEGORY_QUIET_MONTHS`, or accepting the bound) — the numbers frame it
> precisely in [reports/v44-rerun-prediction.md](../reports/v44-rerun-prediction.md)'s
> verdict block. The V1.8 record follows.

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

**One diary row per desk entry** (V4.4: the desk is a queue, so one `FIXED_EVENT` row
for each), and `src/sim/calendar.gd` still preloads nothing —
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

- **No AI chooser** *(V1.8–V4.3; closed at V4.4 — see §5's closure note)*. Events fired
  for the player alone; the other 28 nations answer through the same chooser now.
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
