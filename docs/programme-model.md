---
title: Programme Model
tags:
  - model
  - decision
  - simulation
  - opinion
  - balance
---

# Programme Model

*The government's programme*: an agenda register the player chooses at term start —
the first time this game asks *what are you for* rather than *what will you do this
month*. Designed and banded at [[tiers/v4|V4.1]], 2026-09-15, before any code or
sweep (V1.7c's discipline — the bands exist before the run, and every later task in
the block is judged against §6 exactly as written here).

The shape is Victoria 3's journal entry, named for this game. An entry is a live
goal with a condition, a clock and a progress reading; it concludes once, on one of
three outcomes, and its price lands through the one applier the law and the event
already share.

Files: `src/sim/programme.gd` (the leaf) ·
`src/sim/programme_constants.gd` (whitelists + `PROGRAMME_SPAN` + the two fixed
pulses) ·
`data/programme/*.json` (the content) · `src/ui/agenda_panel.gd` (the surface) ·
`tools/programme_probe.gd` (the sweep) · `tests/test_programme.gd` (the register
machine) · `tests/test_programme_channel.gd` (the channel and the tick-order
guarantee) · the credit site in `src/sim/opinion.gd` · this file (the argument).

## 1. The measured gap

Nothing tells the player what they are for. Every verb this game ships is reactive —
a budget to set, a law to pick from a menu, a crisis that arrives as a card — and the
resting screen probe (V2.1c, `tools/nav_probe.gd`) measured the consequence: 42 of 74
decision months said nothing at all to a president who never touched a card. The only
forward-looking commitment anywhere in the project is [[pledge-model]]'s campaign
promise — one file, made in a run-up window, priced on `bloc_offset` — and it is a
promise made *to voters at an election*, not a programme chosen *for a term*. The
V2.9 play report's headline ("a serious simulation wearing no game") and V4.0's
failed agency gate are the same finding from two sides: acting does not pay, and
nothing frames acting as a project rather than a month's chore.

## 2. The field contract

The tier doc's table, verbatim, is the contract; the loader refuses an entry that
does not carry it and refuses an entry that carries an unknown field beside it.

| field | note |
|---|---|
| `id`, `name`, `summary` | as an event's |
| `group` | economy / institutions / Europe / society / the office itself |
| `possible` | the trigger that makes it offerable — `PRECONDITION_FIELDS`' shape |
| `activation` | how it opens: authored, event-opened, player-chosen, or forced |
| `immediate` | effects on activation |
| `complete` / `fail` / `invalid` | the three conclusions, on [[referendum-model]]'s own three-outcome precedent |
| `timeout_months` | 0 = no deadline |
| `current_value`, `goal_value`, `progressbar` | the progress read, DERIVED from a live figure rather than stored |
| `on_complete` / `on_fail` / `on_timeout` | `Law.extract_shared_effects()` — the one applier events already use, not a second |
| `weight`, `pinned` | ordering, and whether it rides the outliner by default |

What each field is *for*, in one line each: `possible`/`activation` are the two halves
of the offer contract — what makes an entry offerable, and who opens it — because a
journal entry that is merely present is a task list, and a task list is not a
programme. `complete`/`fail`/`invalid` are three conclusions because three is what
the outcomes actually are: achieved, missed, and *overtaken by the world* (the
coalition fell, the office was lost, the war ended the goal) — `invalid` exists so a
world-changed entry stops ticking rather than failing a player who never got to
play it — and `invalid` prices at ZERO pulse for the same reason: the outcome was
outside the player's agency, and charging the full fail price for it is the same
punishment P3 refuses for abstaining. An `invalid` conclusion still concludes the
entry and applies its authored `on_invalid`-style effects through the ONE applier
(`Law.extract_shared_effects()` → `Legislature.apply_effects()`, the same route
complete and fail take); what it does not do is move the competence stock.
`timeout_months` 0 means no deadline, deliberately: some goals are the
term's character, not its clock. `current_value`/`goal_value`/`progressbar` are
**derived, never stored** (the region-share discipline — a cached progress field can
disagree with the live figure it reads, and then the panel lies); they earn no
`SAVE_VERSION` room of their own. `on_*` route through the ONE applier because a
second effect-writer is `legislature.gd`'s named failure.

## 3. Hard call 1 — the channel discharge

The V4.1 pitch ends: *"succeeding is the competence credit V4.0 may have just built
a channel for — the two blocks must agree on that channel or state why they do
not."* [[agency-model]] §4 wrote the agreement clause in advance; this is its
discharge, restated from the plan gate.

**The agreement holds on NAME and SITE; the FORM is upgraded to the decaying
bounded form, and the reason is V4.0's own measurement.**

- **NAME + SITE (agreed).** A programme entry's conclusion feeds `Opinion`'s
  per-bloc approval TARGET as an addend **beside `K.time_in_office_offset(...)`** —
  the site the honeymoon and V4.0's credit already ride, so `INERTIA_RATE` governs
  the path and nothing jumps. A programme's success is the natural competence
  credit: the two blocks name the same channel.
- **FORM (upgraded, with the reason).** V4.0's sweep ([[agency-model]] §5b/§5f)
  found the level-vs-inauguration form prices the *inherited business cycle*, not
  the policy record — the credit's three addends read a shared fresh-game world term
  of ~−0.37 record units at month 6 against a between-style differential of ~0.02,
  so C1 (+1.0 vs idle at month 6) is unreachable at ANY span (it would need span ≈
  45, past the ±1.0 clamp; C3 caps the span at ≈ 1.02). **`COMPETENCE_SPAN` ships
  0.0 and stays 0.0 — V4.1 does not re-open it.** But [[agency-model]] §2 named the
  **decaying bounded credit** the declared fallback, *"taken knowingly with its
  version bump"*, and a programme entry is exactly the instrument that makes the
  decaying form correct: it has a clock, a conclusion and a term-bounded meaning,
  so a bounded stock that accumulates on completion and decays on a half-life is
  the honest price of *what you delivered this term* — not a memory of an outcome
  level you inherited. This is V4.0's discharge option (b) — *drive the declared
  successor* — taken without the wait, because V4.1 is the block whose content
  justifies the stock. It is NOT option (a), a fourth addend on the level clamp,
  which the discharge forbids: pricing programme success on a channel measured not
  to reach a voter.

The shipped form, fixed here so Task 2/Task 4 implement it verbatim:

```
# per nation, per month, inside Opinion._tick_nation
stock = clampf(stock + programme_pulse(ns) - stock * DECAY_RATE, -1.0, 1.0)
credit = PROGRAMME_SPAN * stock
target = APPROVAL_NEUTRAL + time_in_office_offset(months_in_term)
       + competence_credit(ns)      # = 0.0 while COMPETENCE_SPAN is 0.0
       + credit                     # the programme's addend
       + APPROVAL_SPAN * clampf(score + law_offset - unrest_opinion_load, -1, 1)
```

`programme_pulse(ns)` is a pure read of the programme register: `+PULSE_COMPLETE`
for each entry that completed this month, `−PULSE_FAIL` for each that failed
this month, else 0. `DECAY_RATE` is a monthly decay. The stock is
bounded `[−1, 1]`, so `PROGRAMME_SPAN` is the whole price and no downstream clamp
can set the number — the reason V4.0's form failed was that the *form* set the
number, not the span; the bound removes that failure class at the source.

**The two pulses are fixed AUTHORED constants, not swept:
`PROGRAMME_PULSE_COMPLETE := 1.0` and `PROGRAMME_PULSE_FAIL := 1.0` — symmetric
by construction, which is what makes P2's symmetric price testable rather than
an aspiration.** The pulse is a unit step into the bounded stock; the SWEPT
constant `PROGRAMME_SPAN` scales the whole price, so sweeping the pulses too
would re-parametrise the same one dial twice. An `invalid` conclusion carries a
ZERO pulse — see §2's rationale; it concludes the entry without pricing it.

## 4. Hard call 2 — pledges: absorbed or kept apart

**Kept APART, with the boundary enforced by a shared read, not a shared schema.**
A campaign promise and a programme entry are *not* the same shape once you look at
the price:

| | Pledge (V1.7b) | Programme entry (V4.1) |
|---|---|---|
| Made | in the run-up, to voters | at term start, to yourself |
| Price | reward NOW + breach MONTHLY on `bloc_offset` | one bounded stock on the competence addend |
| Judged | every month live, binary breach | once, at conclusion (complete/fail/invalid) |
| Window | `Campaign.is_open()` gated | term-start modal |
| Register | `ns.pledges` (SAVE_VERSION 23) | `ns.programme` (SAVE_VERSION 35) |

Merging them forces one price model onto two different economic shapes — the
failure the project has caught six times (V2.9's *a second approval number with a
different label*; [[agency-model]] §4's two-machines-one-job rule). **But "apart"
must not rot into two lists the player reconciles by hand.** So the Campaign
panel's Promises section opens on the chosen programme — a read-only line through
`Programme.this_term()` → `progress_of()` → `PanelKit.progress_fraction()`, the
same trio the Agenda and the Overview read, printed as the pair plus a percentage
while the entry runs and as the verdict (Delivered/Missed/Overtaken) once it
concludes (a *read*, not a write; the choice happens on the Agenda or nowhere) —
and the Agenda panel is the single place a programme is chosen and tracked. The
scanner test pins that no surface hand-writes either list.

**Refused:** absorbing pledges into the programme register (two price models forced
into one), and a second approval register keyed to promises (two machines pointed
at one job — the single-applier argument).

## 5. The refusals

- **No chains, no branching quest trees.** An entry concludes; it does not unlock a
  sequel. Chains are V4.4's machine, and two machines pointed at one job is what
  `legislature.gd`'s single-applier argument exists to prevent. An entry that wants
  a sequel is an entry whose *content* should carry the next step as its own entry,
  gated by a `possible` that the first conclusion's effects make true — one machine,
  data describing the sequence, no second mechanism.
- **No second approval register.** The stock of §3 is ONE register on the ONE
  opinion target, shared shape with the honeymoon. A register keyed to promises
  beside `bloc_offset` beside the satisfactions is three approval numbers with
  three labels — V1.5c's reason, V2.9's reason, refused a third time here.
- **No AI programmes.** The nine AI nations have no reader for approval at all
(`Opinion._tick_nation` is gated on `has_budget` alone — `in_government` lives
in `elections.gd` and reaches `opinion.gd` only in comments — but the gate is
beside the point here), and a programme is a *player* instrument — an agenda the
electorate never sees is a journal nobody reads. `Programme.init_nation` seeds
the register for every nation (the Campaign/Projects `init_nation` precedent)
but only the player's is ever populated, and the pulse on an AI nation is
exactly zero because its programme register is empty. This is also the
load-bearing half of §7's re-run prediction.
- **No stored progress.** `current_value`/`goal_value`/`progressbar` are computed
  each read from the live figure the entry names; storing them is a second answer
  (the stored-city-population rule) and a panel that can disagree with the sim.
- **No new effect channels.** Every `on_*` conclusion prices only on the shared
  channels the one applier already carries — a conclusion needing a channel laws
  and events cannot use is content this model refuses at load, the summits'
  sidecar contract's loud refusal inherited.

## 6. The bands — pre-declared before any sweep

Written 2026-09-15, before `tools/programme_probe.gd` is touched. The probe
reuses `agency_probe.gd`'s harness shape; the poll-noise readable floor is
**±3.0** on a headline figure and the readability bar for a *family-vs-idle
margin* is **+1.0**, both carried from V3.0/V4.0 unchanged.

| # | Band | Pass condition |
|---|---|---|
| P1 | Readable | completing a programme entry moves month-6 approval vs idle past the poll-noise floor **≥ +1.0** at the shipped `PROGRAMME_SPAN` |
| P2 | No free lunch | failing an entry moves month-6 approval vs idle **≤ −1.0** (symmetric price — the decaying form is signed, and a failed programme is a record) |
| P3 | Idle inert | a term with NO programme chosen moves month-6 approval vs idle by **≤ ±0.3** (the choice to abstain is not punished by the channel existing) |
| P4 | Bounded | the stock never exceeds `[−1, 1]` under any reachable cadence; `PROGRAMME_SPAN` interior to its sweep crossing, midpoint stable across a refinement step (V1.5b/V1.5d) |
| P5 | Decay | a completed entry's credit decays to half within `ln(2)/DECAY_RATE` months ±1 (the decay is real, not a permanent monument; the tolerance also absorbs the discrete-tick half-life's deviation from the continuous form) |

**The sweep grid, declared before the run.** `PROGRAMME_SPAN` over
**[0.5, 8] step 0.5**, refined to **step 0.1 at any crossing the coarse pass
finds** — the V4.0 grid's shape (its [1, 8] step 1 coarse, 0.25 refinement)
widened downward, because the pulse is a step input per conclusion rather than a
continuous record and the working guess is that the readable span is *smaller*
than the level form's would have been. Each candidate is set live in
`src/sim/opinion_constants.gd`, then the probe runs headless and P1/P2/P3 are
read off the JSON; a span-0 control anchors the per-unit slopes as V4.0's did.
Midpoint stability is checked at both refinement steps (V1.5b's diagnostic);
if a band cannot select — a band an observable cannot reach is a bound, not a
selector (V1.5a) — it is recorded as a bound with its number, and the failure
is not tuned away. If P1 and P2 cannot both pass at any span, the bound is
recorded with its number and the verdict says so (V1.5c's inconsistent-clause
finding is the named risk: the symmetric price P2 wants may be louder than the
readability P1 can pay for at a pulse the content can fire once or twice a term).

`DECAY_RATE` is content-bounded by the cadence clause of P4:
the bounded stock means a spam cadence saturates at 1.0 and cannot buy more — the
energy model's saturation-is-a-bound posture, recorded with its number. The
sweep grid moves `PROGRAMME_SPAN` alone; the two pulses are fixed at ±1.0 by
construction (§3) and appear in no sweep dimension.

## 7. Predictions, written before the run

V1.7c's discipline: these live here so the sweep's report and the close-out
re-run can be checked against something other than their own output.

- **The idle baseline is bit-identical.** `PROGRAMME_SPAN` only pays on a chosen
  programme: no programme chosen means an empty register, `programme_pulse(ns)`
  reads 0 every month, the stock stays exactly 0.0, and the credit addend is
  exactly 0.0 — for the idle player AND for the nine AI nations, who never choose
  one (§5). The balance re-run therefore moves **only programme-active runs**;
  any moved figure on a run that never chose a programme is a DEFECT, not
  rounding. (The V4.0 lesson is inherited rather than repeated: §5g there
  corrected a prediction that called the credit zero on idle because the FORM
  read the world. This form reads the register, and the register is provably
  empty on every no-programme path — that is P3, asserted rather than assumed.)
- **P1 passes at a small span, and the sign is not an open question.** Unlike
  V4.0's level form — where every style shared a negative world term and the
  delta started at −2.04 — the programme pulse fires only when the player
  *delivers*, so the delta vs idle starts at 0.0 and the span that crosses +1.0
  is arithmetic against the pulse cadence, not a fight with an inherited cycle.
  The open question is the magnitude, not the mechanism.
- **P3 holds by construction and is tested anyway.** The empty register's pulse
  is 0 and the stock update is `0 + 0 − 0·DECAY_RATE = 0` at every month —
  but "by construction" is what V4.0 wrote about the honeymoon before a
  reachability check earned its keep, and the assertion is cheap.
- **P5's half-life is exact only in the stock, not the approval.** The stock
  halves on `ln(2)/DECAY_RATE` by construction; the approval addend follows it
  through `INERTIA_RATE`'s lag, so the ±1-month tolerance in the band is spent
  on the inertia path, and a measured half-life far from the nominal one is a
  defect in the wiring, not in the decay.
- **No new regime, no new content-shaped mover in the re-run.** The channel is
  the only live sim change; content (the 30–40 entries) ships with conclusions
  priced on shared channels, so a re-run diff shows movers only where a
  programme-active run's stock moved — approval, its downstream election digits,
  and nothing else. A moved GDP/unrest line outside a stock-threshold crossing
  is a defect (the unrest-stock `defc` print-boundary class of V4.0 §5e is the
  named exception to expect, at last digits only).

## 8. Deliberately absent

- **No branching chains.** §5; V4.4's machine, one register per entry, data
  describes any sequence.
- **No AI-facing behaviour.** §5; the nine never choose, and the pulse is zero on
  every path that has no register.
- **No second approval register.** §3/§5; the stock rides the competence addend's
  site, bounded, and nothing else in `Opinion` grows.
- **No `SAVE_VERSION` room for progress.** The bump to 35 is carried by the
  chosen register and the stock alone (a dropped register un-prices a term the
  player already lived; a dropped *progress* value is re-derived from the same
  live figure the panel reads).
- **No per-bloc programme row.** Uniform, like the honeymoon and
  `unrest_opinion_load` — a fact about the government, not about one row of the
  electorate; a per-bloc pulse is an authored table with no measurement behind it.
- **No timed "the programme is popular" pulse.** Making a programme entry pays
  nothing at choice time — the price is delivery's, on conclusion, and a choice
  pulse would be the pledge reward's shape grafted onto the wrong register
  ([[pledge-model]] §4's two-times rule is why the two stay apart).

---

## 9. The sweep, run 2026-09-15 — what Task 4 measured

The grid of §6 ran unchanged: `PROGRAMME_SPAN` over **[0.5, 8] step 0.5** (17
rows including the span-0 control), refined **step 0.1 across [3.6, 4.4]** —
the refinement window the coarse pass pointed at. One correction to §6's
recorded text, made here rather than silently: §6 says each candidate is "set
live in `src/sim/opinion_constants.gd`", and the span's home moved to
`src/sim/programme_constants.gd` beside the two pulses (the task brief allowed
either, and the pulses were already there). Twenty-five probe runs, each 22 s;
raw JSON in `reports/sweep_programme/` (gitignored, as reports/ always is).

**The harness half, declared before the run** (the bands were §6's half): the
probe ticks the term's own months 1..16 — not agency_probe's 2..17, because the
register's clock must run from term start — chooses at new game, and lands BOTH
conclusions in month 6. The completion is bought with ONE scripted write
(`growth_annual_pct := 2.5`, firing prog_industrial_renewal's `>= 2.0` goal) in
the slot between Media and Programme; no authored entry completes naturally on
the fresh-game cycle inside the window (unemployment starts 7.4 against a 7.0
goal, growth 0.08 against 2.0), and the conclusion path the write buys —
trigger judged, status stamped, `concluded_this_month`, pulse — is entirely the
sim's. Five arms: `idle` (nothing), `chosen` (chosen, never delivers — must
read exactly 0.0, and does, to the bit, at every span), `write-only` (the write
with no programme — the write's own approval path, +0.35 at month 6),
`complete` (concludes month 6), `fail` (prog_maastricht_letter's authored
6-month clock, no write). **P1 reads complete − write-only**, both arms
carrying the write; **P2 reads fail − idle**; **P3 reads chosen − idle**.

**One confound was measured and then designed out, and the number is recorded
because it is 40x what the first guess said.** The first pairing used
prog_jobs_first as the control arm and its authored `immediate` (+0.05 workers
`bloc_offset`) as "worth ~+0.004 headline points, negligible". Wrong:
`bloc_offset` rides the ×40 `APPROVAL_SPAN` inside the target, so the
immediate is worth +0.15 points at month 1, compounding through INERTIA_RATE
to +0.49 by month 6 — half the band, in the arm P1 subtracts. The shipped
pairing uses prog_industrial_renewal (no `immediate`, no `on_*`) in both
programme arms and gives the write its own programme-less control, so no arm
carries an authored effect the other lacks. A sweep whose control is off by
half its band prices the span, not the channel.

**The coarse table** (channel deltas at month 6, points of approval):

| span | P1 (complete − write-only) | P2 (fail − idle) | P3 (chosen − idle) | verdict |
|---|---|---|---|---|
| 0.0 | +0.000 | −0.050 | +0.000 | control: all channel deltas exactly 0 |
| 0.5 | +0.125 | −0.175 | +0.000 | |
| 1.0 | +0.250 | −0.300 | +0.000 | |
| 1.5 | +0.375 | −0.425 | +0.000 | |
| 2.0 | +0.500 | −0.550 | +0.000 | |
| 2.5 | +0.625 | −0.675 | +0.000 | |
| 3.0 | +0.750 | −0.800 | +0.000 | |
| 3.5 | +0.875 | −0.925 | +0.000 | |
| **4.0** | **+1.000** | −1.050 | +0.000 | P1 passes AT its edge |
| **4.5** | **+1.125** | **−1.175** | +0.000 | **shipped** |
| 5.0 | +1.250 | −1.300 | +0.000 | |
| 5.5 | +1.375 | −1.425 | +0.000 | |
| 6.0 | +1.500 | −1.550 | +0.000 | |
| 6.5 | +1.625 | −1.675 | +0.000 | |
| 7.0 | +1.750 | −1.800 | +0.000 | |
| 7.5 | +1.875 | −1.925 | +0.000 | |
| 8.0 | +2.000 | −2.050 | +0.000 | |

**The refinement table** (step 0.1): P1 reads +0.900 / +0.925 / +0.950 /
+0.975 at 3.6–3.9 and +1.025 / +1.050 / +1.075 / +1.100 at 4.1–4.4; P2 reads
−0.950 / −0.975 at 3.6–3.7, **−1.000 at 3.8** (its edge), −1.025 at 3.9, and
strictly past from 4.1. Both crossings are where the slope arithmetic put them
before the run.

**The reading, in five findings:**

- **The response is EXACTLY LINEAR at 0.25 points per span unit**, and it is
  float-exact, not fitted: a conclusion landing in the read month has exactly
  one month of inertia behind it, the credit enters the target as a single
  addend, and the S-term is one multiplication deep. This is §7's second
  prediction holding in its strongest form — the delta starts at 0.0, so the
  crossing is arithmetic against the pulse cadence and not a fight with an
  inherited cycle. P2's slope is the same 0.25 with a **−0.050 intercept**:
  maastricht's authored `on_timeout` (−0.05 business `bloc_offset`, −2 points
  on one bloc, −0.05 headline) rides every fail run, so P2 crosses at **3.8**
  where P1 crosses at **4.0**. The intercept is content, not the channel, and
  it moves if the content moves.
- **The band is ONE-SIDED-UP, and the crossing ships by V2.7's rule — but P4's
  own clause says interior, so the shipped candidate is the first coarse-grid
  candidate strictly past it.** No upper clause is declared: P4 bounds the
  STOCK, not the span, and nothing in §6 names a "too loud" failure. The
  passing set is [4.0, ∞); 4.0 holds P1 at exactly its edge — a span ON the
  crossing holds the band by the tolerance of the comparison, not by margin —
  so **`PROGRAMME_SPAN` ships 4.5**: interior to the crossing on both grids,
  +1.125 / −1.175 at month 6, 12.5 % over the bar, and the 0.1 refinement
  confirms no crossing between 4.0 and 4.5 for it to sit behind. V1.5b's
  midpoint diagnostic degenerates on a one-sided band and is recorded as such:
  what is stable across both grid steps is the CROSSING itself (4.0 exact,
  grid-independent by the single-term linearity), not a midpoint between two
  edges.
- **P3 holds to the bit, at every span, in two arms.** `chosen − idle` reads
  exactly +0.000 at month 6 and month 16 in all 25 runs, `idle`'s stock trace
  is exactly zero everywhere, and **the idle arm's month-6 approval is ONE
  distinct float across all 25 runs** — the §7 bit-identity prediction
  asserted rather than assumed, and the balance re-run's licence: any moved
  figure on a programme-free run is a defect.
- **P4 and P5 hold at every span and are span-independent, which is the form
  working as designed.** Max |stock| over every trace of every arm: 1.000000 —
  the clamp never visibly binds at the legal cadence and cannot be escaped at
  an illegal one (the channel test stamps a concluded completion every month
  for 30 months and the stock saturates at exactly 1.0). The decay half-life
  measures 14 months against a nominal 13.86 (ln 2 / 0.05), inside the ±1
  band, identically at span 0.5 and span 8.0 — the stock's clock does not know
  what the credit is worth, which is what makes the span the whole price.
- **P1 and P2 pass together, so §6's named risk did not bite** — the
  inconsistent-clause finding (V1.5c) was the declared danger: a symmetric
  price louder than the readability it must pay for. It cannot bite in this
  form because the pulses are symmetric by construction and the inertia is
  linear: both bands cross at 0.25 points per unit, 0.2 apart, and the
  intercept is the only thing that separates them.

**VERDICT: PASS.** P1 +1.125 ≥ +1.0, P2 −1.175 ≤ −1.0, P3 +0.000 ≤ ±0.3, P4
bounded with the span interior, P5 14 vs 13.86 ± 1 — all five at the shipped
`PROGRAMME_SPAN := 4.5`. A completed programme is worth up to +4.5 points of
target approval at full stock — three quarters of the honeymoon's 6.0, decaying
on a 14-month half-life instead of the honeymoon's 4 — and a failed one costs
the same shape in the other sign: delivery is the biggest single lever this
channel sells, which is the point of the block.

## 10. As built — the close-out

The block shipped across ten commits on `v4.1-the-programme` — the model and
bands (`fa097fc`), the pinned pulses (`9b1e307`), the register machine
(`1730f22`), `SAVE_VERSION` 35 (`d3a85e3`), the channel (`1c203a1`), the
content (`87a0edc`, fixes `6b92818`, `77f7c82`), the surfaces (`50d499b`, fix
`dc451e6`). What exists, with the why each piece carries:

**The machine** — `src/sim/programme.gd`, a leaf of 364 lines preloading only
its constants and `legislature.gd` (pinned by scan). Four statuses and no
flags: `active → complete | fail | invalid`, once, never back, precedence
**complete > fail > invalid > timeout** — the player DELIVERED, and a goal
achieved is not unmet because a world that also changed would have ended it;
timeout is not a trigger but the clock (the deadline month is the entry's
LAST month to land the goal, and the same tick concludes `fail` if it did
not). The term-start gate is a LEVEL READ of `months_in_term` (0 at new game
and again in the month a won election resets it) — defence-model's V1.3g
rule: an obligation that opens itself closes itself, so nothing lifts a flag
it must remember to clear. `_load_programme` refuses loudly off §2's
whitelist — no trigger and no deadline, a typo'd field, the `institutional`
slot, an unknown channel, an unknown trigger field are all load-time errors
(`test_programme.gd`'s five negative fixtures). `SAVE_VERSION` 35 on the
three serialised pieces — `ns.programme`, `programme_chosen_term`,
`programme_stock`: a dropped register un-prices a term the player lived and a
dropped stock is a clean slate over a record they watched; progress earns
nothing (§2's derived rule, pinned as an absence).

**The channel** — §3 verbatim. The stock advances once per nation per month
inside `Opinion._tick_nation` before the bloc loop;
`programme_credit() = PROGRAMME_SPAN × stock` on the per-bloc target beside
`time_in_office_offset`; `programme.gd` NEVER writes the stock (a second
writer is the two-machines failure one level up); the pulses are ±1.0
symmetric by construction; an `invalid` concludes at zero pulse; and
**`COMPETENCE_SPAN` stays 0.0, untouched** — V4.0's discharge option (b), the
decaying bounded form driven without the wait. **Gate verdict: PASSED** — P1
+1.125 ≥ +1.0, P2 −1.175 ≤ −1.0, P3 +0.000 exact, P4 bounded with the span
interior, P5 half-life 14 vs nominal 13.86 ± 1, all at `PROGRAMME_SPAN :=
4.5`. The response is exactly linear at 0.25 points per span unit
(float-exact, not fitted — §9), the band is one-sided-up with its crossing
4.0 grid-independent by that linearity, and V1.5b's midpoint diagnostic
degenerates on a one-sided band and is recorded as such: what is stable
across both grid steps is the CROSSING, not a midpoint between two edges.

**The tick order is a guarantee, not a convention.** Programme before Opinion
before Elections, the adjacent pair pinned at source
(`test_programme_channel.gd` reads `main.gd` and refuses anything but
comments between them): Elections is the ONLY writer of
`terms_served`/`months_in_term` in the loop and runs last, so a conclusion
stamped `(T, m)` in an election month is matched and paid by
`concluded_this_month()` before the vote resets the counter. If Elections
ever moved between the pair, a won election would stamp (T, m) and reset to
(T+1, 0) between stamp and read, and the pulse would go silently unpaid —
the class a suite cannot see and the pin exists for.

**The content** — 37 entries across the five groups (economy 9, institutions
7, europe 7, society 7, office 7), no starter touched, all data: every entry
carries `complete`, 29 carry `fail`, 8 `invalid`, 12 ride a 6/8/10/12-month
clock, `weight` authored on all 37, `pinned` on 12. **The review's CRITICAL
was the already-won/lost class**: two co2e entries carried a `fail` line
INSIDE their own `possible` band (five band-admitted nations were offered a
FAIL at tick one) and nine ungated entries were already-won or already-lost
at real start figures (playable POL insta-failing two deficit entries among
them). The fix is authored bands — the open interval between the entry's own
complete and fail lines on the trigger field — because a band strictly
inside (fail, complete) is unresolvable at the offer BY CONSTRUCTION; nine
bands closed the class with no schema change, and each edited summary names
its gate. **The triviality sweep is a suite gate**: no `complete`/`fail`
trigger already true at new game AND month 1, checked per banded entry
across the roster and per entry across every PLAYABLE nation (the flag read
off the loader, not off a list in the test), mutation-checked — stripping a
band turns the arm red. The one entry whose completion is
unachievable-by-effort and unavoidable-by-play (`prog_the_full_term`, by
calendar) is gated to the first term, so a second-term player is never
offered a goal already won.

**The surfaces** — the Agenda panel (K, in the State cluster after Overview:
the agenda is what the term is for), the offer and the register over one
body, groups iterated from `ProgrammeK.GROUPS`, entries weight-ordered,
conclusions printed Delivered/Missed/Overtaken, and a register entry whose
content no longer exists prints its id rather than a lying bar. The top-bar
strip names the nearest-deadline entry's progress and HIDES while nothing
runs — a permanent "no programme" slot says nothing in most games. The
Overview PROGRAMME section is NEVER silent: unset prints where the choice
lives, V2.1c's silence finding applied at birth rather than after a probe
found it. Cards fire on open, complete, fail and invalid; the term start is
an ARRIVAL PAUSE — idempotent, three callers (new game, load, post-election,
the reload re-raise reasoning verbatim), subordinated to the election
verdict's pause so the answerable card cannot eat it — and the blocking
plate is refused on test_shell's clean-boot pin plus events-model's
non-modal argument. The progress fraction lives in ONE place
(`PanelKit.progress_fraction`) after the found bug: Godot's `Range.step`
defaults 0.01 and SNAPPED every assignment, so the bar disagreed with the
read printed beside it — bars set `step = 0.0` and the why is at the site.

**The refusals held, and the two open calls closed.** §4: pledges kept APART
with the boundary a shared read, not a shared schema — the Campaign panel
surfaces the programme as a read-only line (shipped at the final review, below),
the Agenda is the only place a programme is chosen, and the scanner pins that no
surface hand-writes either list. §3: the channel discharge is the decaying bounded form, taken because
a programme entry is the instrument that makes the decaying form correct —
it has a clock, a conclusion and a term-bounded meaning — and
`COMPETENCE_SPAN` stays 0.0. §5 by construction: no chains, no AI programmes
(the register seeds for all ten nations and only the player's is ever
populated — the load-bearing half of §7's re-run prediction), no stored
progress, no second approval register, no new effect channels: every `on_*`
routes through the ONE applier, so a conclusion lands where a law lands.

### The balance re-run — bit-identical, the prediction held (2026-09-15)

Both sides ran from worktrees (merge base `0c379c3` at `../nswt-v41-base`,
head `dc451e6` at `../nswt-v41-head`), serially, each after a
`--headless --import`, so the per-machine addon parse noise cancels.
`tools/balance_probe.gd` over all 50 regimes; the MCP-port-line filter
found nothing to filter; V1.7c's third-stray-line check is clean — both
files END on their last `invariants: OK over 168 months` (line 1681),
nothing after.

**The prediction held to the bit: 1681 / 1681 printed lines identical,
zero diff.** The whole sim diff is strictly additive behind an empty
register — no balance regime ever calls `Programme.choose()`, so the
channel is inert: the pulse is exactly `0.0`, the stock advance is
`0.0 + 0.0 − 0.0 × rate = 0.0`, and the credit is `4.5 × 0.0 = 0.0`, a
float-exact no-op added into every target. §7's by-construction half
(idle bit-identity) is confirmed by measurement, not just asserted —
the same discipline `test_programme_channel.gd` pins over 8 months.
No verdict changed, no act count moved, no `SAVE_VERSION` consequence
beyond the register itself. A moved line would have been a defect;
there were none.

**Re-measured at the final-review fix `a71985f`**, which touched
`src/sim/programme.gd` (the already-failed offer gate and the
`this_term()` read) after this section was first written: same base
output, head re-run from the updated worktree, **1681 / 1681 identical
again, zero diff**. The gate is a filter on the offer list and the
helper a pure read — neither is on any path a balance regime takes, and
the measurement says so rather than the argument.

### The final review — three fixes and two recorded limitations (2026-09-15)

The whole-branch review found three Important gaps; all three shipped the same
day, with the reasoning each one owed:

- **The offer gates on not-already-failed.** `Programme.available()` skips an
  entry whose authored `fail` trigger is already true at the offer, read through
  the same `_trigger_met` the tick judges. This is the mid-game reopening of
  Task 5's already-won/lost class: the triviality sweep pins start figures, but
  `prog_settle_the_streets`' `possible` (unrest ≥ 5) and `fail` (unrest ≥ 20)
  overlap, so a term starting with unrest already past twenty was offered a
  programme that insta-fails on the next tick — a −1 pulse on a goal the player
  never got to play. No authored band can close this half, because the offer
  re-fires every term against drifted figures; the gate is the sim's, one skip
  in `available()`, not a content edit. **Deliberately one-sided**: an
  already-WON entry stays offerable — a goal already met is a different and far
  less harmful shape — and `test_programme.gd` pins both halves.
- **`REQUIRED_FIELDS` is enforced, not decorative.** The constant's docstring
  claimed a contract the loader did not run: `summary` defaulted to `""` on
  absence. `_extract_programme_entry` now refuses an entry missing any required
  key and requires a non-empty summary (the offer prints it under the name, so
  a blank summary is a field the entry does not carry). All 37 shipped entries
  already carried one — enforcement was checked safe before it was chosen over
  deleting the constant.
- **§4's shared read shipped.** The Campaign panel's Promises section opens on
  the term's programme — the read-only line this doc had claimed since the
  plan, built here. It rides a new `Programme.this_term(ns)` pure read, which
  is now the ONE `chosen_term == terms_served` filter: the review also flagged
  that filter as hand-written twice (agenda_panel, overview_panel), and the
  duplicate is deleted rather than copied a third time.

Recorded limitations, known and tolerated rather than fixed:

- **A zero-goal `down` bar draws 0 % until the figure moves.**
  `PanelKit.progress_fraction()` expresses progress as distance from the live
  figure toward the goal, and for `prog_in_the_black` the goal IS 0.0 — so the
  bar reads empty however small the standing deficit is, and only a surplus
  completes the entry. The printed pair beside the bar carries the real number,
  so nothing lies; the sim prices the trigger, not the bar. Display-only, and
  fixing it would mean a second fraction rule for one entry.
- **A decision event and a won election in the same month can eat the
  term-start pause.** The clock has three boolean pausers (decision arrival,
  programme term-start, election verdict) and each resume path unpauses
  unconditionally, so two arrivals in one month resolve to one pause and the
  first answer consumed it — the election's dismissal re-runs
  `_enforce_term_start_programme()`, but an event answered after that point
  resumes the clock with the programme card still on the desk. The offer stays
  answerable: the card and the pending mark persist, and `choose()` accepts
  until Elections next advances `months_in_term` — so the cost is a beat of
  pacing (or, if the player idles past a month boundary, a term that runs
  programme-less by their own clock), never a crashed or half-applied choice.
  The fix would be a reference-counted pause stack — a second pause mechanism,
  which is the flag-lifting class defence-model's V1.3g rule exists to
  prevent — refused for that reason.

Related: [[agency-model]] · [[pledge-model]] · [[tiers/v4]] · [[opinion-model]] ·
[[campaign-model]] · [[referendum-model]] · [[decision-log]]
