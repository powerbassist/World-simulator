---
title: Decision Log
tags:
  - decision
  - process
---

# Decision Log

Corrections made *during* a session that changed what the [[ROADMAP]] said before
it. Kept out of the roadmap itself so that document stays forward-looking, and
kept at all because the pattern is the useful part: it shows which kinds of
estimate this project gets wrong, and in which direction.

Each entry names what the plan said, what was built instead, and where the full
argument lives. The models themselves are in the model notes — this is a record
of the *changes of mind*, not a second copy of the design.

## S4 — three economic sectors, not four

The roadmap said four sectors, the fourth being energy split out of industry.
[[data-sources]] then established that no open dataset provides the split, and no
MVP mechanic distinguishes energy from industry — energy mix is [[someday]] tier.

Corrected rather than honoured. If a later model wants an energy lever it splits
industry as a hand-tuned constant, against a concrete model instead of a
placeholder invented before one existed. Model: [[economy-model]].

## S6 — real per-nation election timing, not a five-year timer

Added on instruction partway through S6's plan. Each nation's term length,
election date and electoral system are real and authored, and European Parliament
elections exist alongside national ones.

This invalidated the roadmap's own reasoning for the session. "Light plan… seat
allocation is bookkeeping" assumed one term length and one allocation rule. Ten
real systems plus the EP made the schedule-and-system shape an S1-class **schema**
decision instead, since S7 laws, V1.1 coalitions and V1.2 political systems all
read it. Full argument: [[electoral-systems]]; the vote-share model is
[[election-model]].

## S7 — effort revised up, and two design calls

Effort was written High → Low. Planning at High held; the build was corrected to
**Medium**. It was not only the fifteen law templates: it was vote resolution,
four effect channels wired into three existing tick formulas, a third UI surface,
and two new headless tests — the same class of work S6 got Medium for.

Two calls made in the same session:

- Per-ideology-slot law support reads the **same two-axis space**
  [[election-model]] already puts every party on, rather than inventing a second
  vocabulary.
- The vote forecast is deliberately **blurred**, not exact. A party inside a band
  wider than the real vote's own threshold shows as Undecided — a display-layer
  trick with no sim-side randomness, the same shape [[opinion-model|polling noise]]
  and [[election-model|no election-day noise]] both argue for in their own cases.

Full argument: [[legislature-model]].

## V1.1a — two findings from planning government formation

- **The player's term was modelled as the Assembly's**, which made the first
  playable term 41 months instead of 16. Corrected in [[electoral-systems]].
- **A France-honest formation model necessarily contains the motion de censure**,
  because there is no investiture vote in France. So government formation and half
  of the confidence-vote work could not be separated into different sessions.

Full model: [[government-model]], including the honest note that the current
balance produces majorities stable enough that neither cohabitation nor censure
fires in a played game.

## U1 — the roadmap had no UI track at all

Found in the post-V1.1a audit. `ROADMAP.md` contained zero UI or UX work across
the entire MVP and V1 — presentation was assumed to fall out of each feature
session. What that produced by V1.1a: no main menu, no pause menu, no route out
of a running game, seven floating overlays each bound to a single keypress, a
five-line `Label` for a HUD, and no theme.

Two consequences, both acted on:

- The roadmap now runs **two interleaved tracks**, S (simulation) and U (UI), so
  presentation is schedulable rather than invisible.
- Four U blocks were scheduled ahead of the remaining V1.1 sub-projects, on the
  argument that every system session currently ends by bolting on one more
  overlay and one more keybind, so the rework only gets more expensive.

The same audit found two defects worth recording because both had been shipped
and neither was noticed: `SaveManager.save_game()` wrote straight to the live save
file, and the banned-names check had been failing since S2 on two substring false
positives caused by a missing `-w`. An always-red check is one nobody reads.

## U2 — effort corrected High → High at plan time, not mid-session

The roadmap wrote U2 as High → Medium. Corrected before any code was written,
by counting surfaces instead of the headline artefact: top bar, rail, dock host,
seven tab hosts, two new panels (Overview, Economy), a map re-host, a nation-panel
re-host, a modal layer that stays for four panels, seven keybinds retargeted plus
three added, focus order, and a new shell test. Eleven surfaces behind one line
in the roadmap table.

Same tell [[ROADMAP|the roadmap's own effort note]] already names for S7: the
estimate counted the thing the session is named after and not the wiring around
it. This is the second time the same pattern has produced a wrong effort call —
worth watching for at every future plan-first session, not just re-deriving from
scratch each time.

## U3 — the surface count that held, and three calls it forced

The roadmap wrote U3 as Light / Opus / Medium. Counted at plan time, as U2's
entry says to: two panel rewrites, one theme at two scene roots plus a top-bar
variation and a rail-button variation, four modals losing their hand-built
`StyleBoxFlat`, a new trend helper reading `history`, and three test files.
Roughly nine surfaces — the first plan-first session in three where the roadmap's
own estimate survived the count. **Medium was right.** The counting is still
worth doing; what it caught this time is that the estimate was fine.

It only held because of a scope call taken with it. The done-when line reads "no
tab is a flat list of every field its system owns", which literally means seven
tabs. Politics, Society, Legislature and Budget already group their content under
headings and grids — they are dense, not flat — so U3 rewrote **Overview and
Economy only**. Reading the line as "all seven" would have tripled the surfaces
and reproduced the S7 and U2 mistake from the opposite direction: not
underestimating the wiring, but inflating the scope to match a sentence.

Two smaller calls:

- **The theme is `src/ui/ui_theme.gd`, not a `.tres`.** A Theme resource is the
  engine-idiomatic answer and was rejected: it diffs badly, can only really be
  edited through the editor, and the repo has no other `.tres`. Built in code it
  matches the rule that panels are built in code, and a palette change is a
  one-line diff. What actually mattered was not the format but that a `Theme`
  assigned to a Control propagates to every descendant — that propagation is why
  one assignment per scene root replaces three hand-built styles.
- **Approval deltas are poll-against-poll.** `history` stores the true
  `overall_approval_pct`, so the obvious six-month delta would have quietly
  contradicted the polled figure printed beside it and leaked the real number's
  movement. `Trends.approval_delta()` runs both ends through `PollNoise`, and
  `tests/test_overview_panel.gd` advances months until the two round differently
  before asserting, so the check cannot pass by coincidence.

One thing found and **not** fixed, because it is a simulation question and U3
changed no simulation: on a fresh French game `ns.term_months` says 60 while
`next_election_*` is 41 months out, so an honest Overview would print "month 0 of
60" next to "41 months until the vote". The term-progress line was dropped rather
than shown. Whichever of the two figures is wrong belongs to a V1.1 session.

## V1.1b — the effort column held, and a term the plan did not contain

The roadmap wrote V1.1b as Plan / Opus / High. Counted at plan time as U2's entry
says to: two new `src/sim/` files, one `NationState` field across three
serialisation sites, a `SAVE_VERSION` bump, two readers plus a censure split in
`government.gd`, a support extraction plus a vote split plus two erosion sites in
`legislature.gd`, three readings in `law_panel.gd`, a column and two lines in
`government_panel.gd`, effective-majority reporting in the balance probe, one new
test and five updated, one new doc and six updated. Eleven surfaces. **High was
right** — the second plan-first session running where the estimate survived the
count, which is worth recording as much as the misses were.

The change of mind was inside the model, not the estimate.

**`hostility()` needed a term nobody had noticed was missing.** The session was
scoped to make discipline live and divisions seat-level, and the balance goal
agreed at plan time was to make the censure branch [[government-model]] records
as unreachable actually fire. Building it revealed that it could not: measured on
the authored French roster, the three governing parties sit 0.26, 0.32 and 0.36
from the coalition's agreed position, so their raw hostility is near −0.8 apiece,
and subtracting discipline only pushes it further down. **Eroding discipline from
0.85 to the floor moved the censure tally by zero seats** — 259 of 289 at every
value. The formation search builds coalitions out of parties that agree with the
government, so distance can never turn one against it.

Discipline had no route into the censure arithmetic at all. The fix is
`DISAFFECTION`: cohesion asks whether a party likes the *policy*, disaffection
asks whether its members want to be standing next to this government at the next
election, and only the second explains why coalitions collapse under unpopular
leaders. Gated on `(1 − discipline)` so it stays a discipline term rather than a
second parallel channel, and zero at or above neutral approval so the V1.1a
balance is untouched. Full argument, and the probe table it was tuned against,
in [[discipline-model]].

Worth generalising: **the tell was that a number refused to move, and the probe
was the thing that said so.** The plan's balance goal was written from a reading
of the model rather than from a measurement of it, and the reading was wrong. A
balance goal in a future plan should name the measurement that would confirm it.

One scope call taken with it: **no whip or concession command.** Rebellion's
counterplay is the lever set that already exists — which bills you propose, who
is in the coalition, and whether you force. Adding a costed command to suppress a
rebellion in the same session that invented rebellion would have been tuning two
things against each other with neither yet measured.

## V1.1c — the effort row was flagged wrong in advance, and it was

ROADMAP wrote V1.1c's row as **Light / Sonnet 5 / Medium**, and flagged that
reasoning as known wrong before the session started: it read "reads the
schedule schema [[electoral-systems]] already settled", but the dissolution
rule was not in that schema. Counted cold at plan time: a ten-nation schema
addition plus `nation.gd` validation, six `NationState` fields across three
serialisation sites plus a `SAVE_VERSION` bump, a new `src/sim/` module and its
constants file, a change to `elections.gd`'s tick, two panels, tick wiring in
two files, one new test file plus four edited, two new balance-probe regimes,
and eight documentation edits. **Corrected to Plan first Yes, High → Medium** —
the third correction on this roadmap's own accounting, and the second one
caught by the receiving session reading the row cold rather than the one that
wrote it, which is the pattern [[ROADMAP|the roadmap's own handoff section]]
now names directly.

**The structural finding: a scheduled election is worth roughly +65 seats no
regime earns.** `tools/balance_probe.gd`, unchanged, shows every legislative
election that survives to fire returning the government 368–385 of 577,
against a starting 318 — at every approval a surviving regime reaches (44–50).
Traced to `Elections.init_nation()` allocating the authored `seat_share`
roster with `pr_national` while every election after it runs the same shares
through `two_round`'s squaring: five points of approval move the result by
eleven seats, the allocation step alone moves it by sixty-five. A dissolution
called in month two of a fresh game would have been worth that whole step for
free, regardless of governance — the same "free action, unbounded upside"
defect class [[government-model|Article 49.3]] already had to be given a cost
against.

**The fix the finding suggests is rejected, and the rejection is on record so
it is not tried again.** Re-seeding the starting assembly through each
nation's own electoral system — one line in `Elections.init_nation()` — was
checked and found to break something else: under `two_round`, the authored
French roster gives the top two parties roughly 355 seats between them,
destroying [[government-model|the no-two-parties-reach-289 property]] that
makes every French majority government a three-party coalition and that
`tests/test_government.gd` asserts directly. The roster would need
re-authoring to fix this without breaking that, which is [[ROADMAP|S2]]
content work, not a V1.1 session's.

**The gamble was measured before it was built, and it did not need
`INCUMBENT_SWING` touched.** The session's plan pre-committed a branch: sweep
a snap election's result across the approval range a player can hold while
still in office (27–50), and if the spread came in under 40 seats, extend the
incumbent's electoral swing to the whole governing coalition and re-measure
every balance table that depends on it. It measured at 57. `INCUMBENT_SWING`
was left exactly as [[government-model]] and [[discipline-model]] already
describe it — the two-round system's own amplification does the work, the
same mechanism that produces the authored 318-seat starting majority in the
first place. Recorded because the branch not firing is itself a finding: the
model was closer to a resolving gamble than the "free +65 seats" structural
finding above made it look.

## V1.1d — corrected by cutting scope, not raising effort, for the first time

ROADMAP wrote V1.1d's row as **Plan first Yes / Opus to plan, Sonnet to build
/ High → Medium**, on "ministers are a schema that departments, opinion and
events all read — S1 class." Counted cold at plan time against the roadmap's
own one-line description, three forks each carried real surface cost:
named individuals instead of a party field (a whole content roster, exposed
to `check_names.sh`), loyalty as a second `hostility()` term instead of
resignation, and a new dashboard tab instead of a Government panel section.
Taken together, roughly fourteen surfaces — V1.1c's own thirteen plus two
V1.1c did not have.

**Every prior correction on this table moved a session to a higher plan/model
tier. This one moved the other way: three decisions taken with the user
before planning cut the scope back to eleven surfaces, and Sonnet 5 / Medium
held at that scope.** Portfolio → party rather than named individuals;
resignation rather than a second hostility equation; the existing Government
panel rather than a new tab (deferred to **U5**, the roadmap's own trigger
for it — "until a system session ends by needing a surface the shell does
not have"). None of the three closed off future depth: named ministers and a
dedicated tab are both recorded as deliberately-not-built rather than
foreclosed. Full argument: [[cabinet-model]].

**Section 1's own test needed correcting before it could answer the
question it was built to ask.** The pre-committed probe budget was
`balance_probe.gd`'s `managed` regime — S10-tuned to be near-frictionless
governance, so it moves only `defence` away from
`policy_defaults.json` and leaves the other four spending lines exactly at
their starting values. Effectiveness multiplies a line's *delta from start*,
so the first run multiplied zero on four of five lines and the measured
spread came back **negative** — a more competent cabinet reading as worse,
because the one line that did move was a cut and a bigger multiplier on a
cut is a bigger cut. Corrected to a representative governing budget with
deltas on all five lines; the channel then measured a genuine 2.21-point
spread at `COMPETENCE_SPAN = 0.75` (0.6 fell short at 1.77). The lesson
generalises past this session: a pre-committed measurement is only as sound
as the scenario it runs against, and a scenario chosen for a different
reason (S10 tuned `managed` to be *low-friction*, not *representative*) can
silently defeat the question a later session asks of it.

**A plan-time architectural assumption did not survive contact with the
file it named.** The design called for `Government.form()` to call
`Cabinet.seat()` directly. Writing `cabinet.gd` surfaced that `Cabinet`
needs `Government.cohesion()` and `Government.penalise_blocs()` — so the
planned direction would have made a `preload()` cycle out of two files each
depending on the other, which GDScript does not support. Fixed by moving
`seat()` to the orchestrator (`game_state.gd`, `elections.gd`,
`legislature.gd` — every external call site of `Government.form()`/`fall()`)
rather than calling it from inside `government.gd`. Cabinet depends on
Government; Government never depends on Cabinet. Caught during
implementation, not planning — worth naming because it is the kind of
one-directional-dependency check a plan can assert in prose without the
author actually tracing which file would need to `preload()` which.

Full model, both measurements, and the balance-probe regimes that confirmed
section 1(b) under the real full pipeline rather than the probe's isolated
formula: [[cabinet-model]].

## Scope alignment — four gaps found by a competitor comparison, and what each got

The first entry here that came from **no build session at all**. A comparison of
the planning docs against Geopolitical Simulator's 2025/2026 store-page feature
list found four things absent from every doc in the repo: military, tourism, the
leader's personal wealth, and difficulty settings. A fifth question came with
them — whether three economic sectors is enough — and a sixth was already open in
[[ROADMAP]]: what follows V1.1d.

The premise the pass worked from, and did not treat the store page as
overriding: **this project's differentiator is not feature parity.** It is fewer
systems that work reliably, against a competitor with a documented reliability
problem. Copying the surface area copies the failure mode. So the output is
decisions with reasons — two scheduled thin, two declined, one folded into an
existing line — rather than a longer backlog.

**Military is scheduled, thin, inside V1.3, and is not warfare.** The genre
argument for scheduling it is real: a geopolitics game with defence as a
non-pillar is arguably out of genre. The argument against building the
competitor's version is equally real: units, theatres and war resolution are a
second game, and the lose condition here is an election. The split that resolves
both is that the player's actual interaction with defence in a
nation-management game is **budgetary and political** — what it costs, who it
upsets, what an alliance obliges you to — and all three run on machinery that
already exists: the `defence` spending line, its opinion issue with per-bloc
weights, the Defence portfolio in [[cabinet-model]], and
[[legislature-model|the law effect channels]]. Capability is *derived* from
sustained spending rather than authored, the same treatment competence gets, so
it costs no new per-nation data. It cannot land before V1.3, because a
deployment with no counterparty and no relations score is a spending line with a
different label.

One premise in the framing was checked and **found wrong**: EU defence
integration does not land on existing structure. `src/core/eu.gd` is a
membership table, an EP seat count and an election date — there is no bloc
policy and no bloc-level voting to attach anything to. Those are themselves V1.3
scope, which is a second, independent reason the defence layer belongs there.

**Three sectors is the answer, permanently; five taxes is V1.6's target.** The
asymmetry that decides it had never been written down: **sector count scales
with the nation roster, tax count scales with nothing.** Sector shares are
per-nation content seeded from World Bank value-added indicators, [[data-sources]]
establishes there is no fourth series, and [[scope]] commits to every nation
eventually being playable — so a fourth sector is a hand-authored guess
multiplied by the whole roster, forever. Tax parameters live in
`economy_constants.gd`, are authored once, and are not per-nation at all. This
generalises S4's energy rejection from one decision into a rule, which is why
tourism could be declined by the same argument without a fresh investigation.
Spending lines stay at five plus `other` because [[cabinet-model|the cabinet]] is
keyed 1:1 to them and a sixth line is a sixth minister. V1.6's "sectoral
investment" is resolved as a lever pointed at a sector, not more sectors.

**Events stays last, for a better reason than the one written.** The original
reason — events paper over a loop that is not working — is right but does not
answer the strongest objection, which is that a consequences layer is the direct
vehicle for the visible-cause-and-effect goal. It does not answer it because
**that goal already shipped its vehicle, and it was not events**: U4's decision
deltas capture a baseline at commit and measure it against the next history
entry. Events add *authored* consequences on top of systemic ones, and authored
consequences are only legible if the systemic ones already are. Second reason,
purely practical: the event schema's shape is the union of the effect channels
V1.3–V1.7 create, so writing it early means writing it twice. A falsifier was
attached, in the discipline V1.1b arrived at for balance goals — if playtesting
finds the loop legible but **inert**, that is the signal to move it, and nothing
weaker is.

**The three silent omissions, one line each.** Tourism → [[declined]]: a services
sub-sector with no dataset split and no mechanic that would read it (no visa
policy, no exchange rate). Leader personal wealth → [[someday]], folded into the
existing personal-corruption line rather than added beside it, because a
personal-money pool that is not corrupt is a second currency with no lose
condition attached. Difficulty → [[declined]] **as a global multiplier**,
accepted as **start scenarios** under V1.2: every balance number in this project
is measured, so a slider scaling tuned constants invalidates every measurement
and multiplies every future probe run by the number of settings, while varying
the *starting* state changes data and no constant.

**A fourth tier doc exists now: [[declined]].** [[someday]] says "not
scheduled", which is a weaker claim than "decided against", and
[[out-of-scope-mvp]] is phase-specific with its own deadline long past. Each
entry names what would reopen it, because a decision with no route back is a
prohibition.

**Next block: V1.2a, a second playable nation** — the breadth move, confirmed
with the user, replacing the open question this document's own [[ROADMAP]] entry
had parked. What made it the cheapest option is that the content already exists
for ten nations and `GameState.new_game()` is already parameterised on
`player_id`; the only hardcoded player nation under `src/` is one const in
`main.gd`. The real cost is the two **shared** things a second player nation
makes wrong — `policy_defaults.json` is one file for every nation, by an explicit
MVP-era note that is now due, and `opinion_constants.gd`'s bloc weights are one
global table, so every electorate in Europe currently has identical priorities.
Which of those two moves into data is the call that decides the block's size, and
it belongs to that block's plan step.

## V1.2a shipped: Germany playable, per-nation starting fiscal policy, bloc weights stay global

**The plan-step call:** `opinion_constants.gd`'s bloc weights stay one shared
table. `policy_defaults.json` — the other shared thing this document's own
V1.2a entry flagged — did move into data: each nation's `fiscal` block now
carries `tax_rates_pct`, `spending_pct_gdp` and `other_spending_pct_gdp`,
sourced per nation (VAT directly, income and corporate scaled from France's by
OECD Revenue Statistics tax-to-GDP shares, spending scaled by general
government expenditure), with France as the unchanged anchor. Full sourcing
in each nation's `fiscal._note`; the model argument in [[economy-model]].

The bloc-weight call replaced an assumption with a measurement.
`tools/balance_probe.gd`, parameterised by nation, ran the identical relative
`managed` budget against France and Germany: Germany's government lost its
majority at its February 2029 legislative election, France held one through
the whole fourteen-year run — from institutions and party rosters alone, bloc
table untouched. Recorded with the full argument in [[declined]].

**The roadmap row was challenged, not accepted.** It read "roughly ten
surfaces". A cold count at plan time found sixteen, but two of the row's own
assumed surfaces turned out not to apply — no `SAVE_VERSION` bump (no
`NationState` field moved), and most `"FRA"` literals in `tests/` turned out
to be intentional assertions about France's own authored numbers, not things
that needed parameterising. `High → Medium` held.

**One exception to "no nation id under `src/`" survives, by design, not
oversight.** `main.gd` still carries a single default player id, read only
when a scene is built directly rather than through the menu — the shape
`tests/test_game_loop.gd` and every `tools/*.gd` probe already depend on.
That is a default value for an entry point, not the `if nation_id == "FRA"`
branch [[engine-decision|Rule 1]] forbids; the two are different enough that
the distinction is worth stating rather than assumed.

**One correction found mid-build, not mid-plan.** `balance_probe.gd`'s
extreme regimes (`tax_max`, `tax_zero`, `spend_max`, `spend_zero`, `ruinous`)
were first rewritten as ±100pp deltas on the reasoning that clamping to the
schema's 0/100 range would reproduce the old absolute figures. It did not —
the old absolute figures (30/20/20/30/20 for `spend_max`, for instance) were
nowhere near that ceiling, so every nation was pinned to the identical
extreme regardless of its own starting point, and Germany's `spend_max`
tripped a debt-ratio-runaway invariant France's identical-looking run did
not. Corrected to the same France-relative deltas the moderate regimes
already used (e.g. `spend_max`'s defence delta is `+18.0`, landing at
France's old 20.0), re-verified against France's pre-change trajectory
before moving on.

## V1.2b shipped: political system templates, head of state, term limits

**The plan-step calls, both settled before the build began.** Whether the
template should be a defaults table nations could override, or a constraint
on fields they already carry flat — settled as a **constraint**: no
inheritance, no override-resolution order, so there is nowhere for a
half-understood institutional state to come from, the same standard a version
mismatch or a dangling exclusion already gets refused rather than patched
around. And how many templates to author against §2's five named ones —
settled as **four**, matching the roster (`semi_presidential_republic` corrects
§2's "presidential republic": France is semi-presidential): absolute monarchy
and one-party state have no nation in a ten-nation Western European roster to
attach to, deferred with a named trigger — the first start scenario or system
transition that produces one — rather than authored as content with no reader.

**A collision the plan named in advance, and caught nothing wrong.** The plan
flagged the lose-condition rename (`elections.gd`'s run-ending branch,
dispatched on `has_executive` before this block, on `ns.lose_condition` after)
as the one place a mechanical refactor could turn out to be a behaviour
change, and named escalation to Opus as the response if a balance number
moved. None did — `test_elections.gd` and `test_censure.gd`'s existing
assertions on `in_government` passed unmodified, and France's and Germany's
existing `tools/balance_probe.gd` regimes are unchanged.

**A different collision the plan got wrong, caught by running it rather than
reading it.** The plan assumed enforcing France's two-term limit could simply
move `tests/test_balance.gd`'s long-horizon three-election survival check to
Germany, "unchanged from V1.2a's numbers," since Germany has no chancellor
term limit. Running the moved check found a do-nothing German budget does not
survive three elections either: `tools/balance_probe.gd -- hands_off DEU`
shows the chancellor's party sliding under 50% approval and losing "largest
party" status at the second legislative election, 2033-02 — the same
France/Germany divergence [[declined|V1.2a's bloc-weight measurement]] already
found, surfacing again in a horizon nobody had run an automated check against
before. Not a bug in this block's refactor: `_validate_political_system()`
made no change to how Germany's elections resolve. The check was rewritten to
assert what its own name promises — no softlock, no non-finite value, across
however many elections a 168-month run actually resolves — rather than a win
streak Germany's own measured behaviour does not support. France's own
three-election check became `_check_france_terms_out_at_the_limit()`,
asserting the term limit fires on schedule rather than early, late, or
indistinguishably from an actual defeat; `_check_managing_beats_ignoring`
needed a matching adjustment since both its regimes now hit the same
term-limit stop for the same non-political reason. Full account:
[[political-systems]].

**The seventeen-surface count held Medium.** No new tuned constant, no new
model needing a number decided — only a fifth instance of the
dispatch-on-a-data-string pattern electoral system, formation, censure and
dissolution had already established. The two collisions above were both
caught and resolved inside the build session rather than requiring escalation
or a second planning pass.

## V1.2c — Spain's real amendment threshold, and Germany's measured to be unreachable

Two corrections, both caught before any content was authored against the
wrong number, not after.

**Spain's plan-time table entry was wrong.** The plan grouped Spain with
Germany/Italy/Austria at `two_thirds`. Writing the real citation rather than
copying a rough cohort found Spain's Constitution Art. 167 sets the
*ordinary* amendment procedure at 3/5 of each chamber — only Art. 168's rare
total-revision path is 2/3, and no amendment content in this game invokes it.
Corrected to `three_fifths` at data-authoring time, before Spain's
`data/nations/ESP.json` entry was written.

**Luxembourg's real bypass bar (3/4) was nearly rounded down to an existing
tier (2/3) rather than added as its own rule.** Caught mid-authoring: this
project's own standard is that amendment thresholds are real constitutional
numbers, not detuned to fit a convenient existing tier — the same standard
that kept France's term limit at the literal figure through V1.2b. A fifth
`AMENDMENT_RULE_FRACTIONS` entry, `three_quarters` at 0.75, was added instead
of rounding.

**The plan's own named measurement fired, and sharpened rather than merely
confirmed the rough estimate.** The plan-time sweep (authored `seat_share`
only, full-strength coalition bonus) found France marginal under `two_thirds`
and Germany "probably unreachable... once discipline erodes." The build
session's live-state re-measurement — real starting `seats_by_party`, real
cohesion, real discipline — found Germany's ceiling **already below 2/3 at
term start**, before any erosion: the unmodelled Bundesrat co-requirement
stacked on six-party fragmentation, not a discipline-erosion story at all.
The response, matching what the plan named in advance rather than requiring
an escalation: Germany keeps its real `two_thirds`, and no amendment content
this session names `parliamentary_republic` in its `systems` list — the same
honesty `referendum_required` already gives Switzerland, rather than a
detuned number invented to make the mechanic playable everywhere. Full
account: [[amendment-model]].

**docs/political-systems.md's own named trigger for the deferred absolute-
monarchy/one-party-state templates was dead as written**, caught while
writing this block's own plan rather than left for a later session to trip
over: "the first start scenario or system transition that produces one"
cannot fire, because a transition inside the ten-nation Western European
roster never produces either, and a start scenario per [docs/tiers/v1.md](tiers/v1.md)
§2 varies starting state, never the institutional system. Corrected to name
the honest trigger — a roster addition outside Western Europe, or an
explicitly counterfactual scenario.

**The ~eighteen-surface count held Medium.** No new tuned constant (the
fractions are real, not model parameters), no new model, only a sixth
instance of the dispatch-on-a-data-string pattern. The one condition that
could have forced an escalation to Opus — the reachability measurement coming
back bad — did come back bad, but the response it required (leave the real
number, don't author against it) was already the plan's own stated response,
not a design decision made fresh mid-build.

## V1.2d — a third playable nation added to the scope, at plan time

[docs/tiers/v1.md](tiers/v1.md) §2 scoped system transition as a mechanism
only. Cold-reading the plan found it would have shipped to **zero** playable
nations: FRA and DEU both prohibit a change to the form of the state
outright (Art. 89 §5, Art. 79(3)), and every nation a monarchy↔republic
transition is actually about — GBR, ESP, BEL, NLD, LUX — was `playable:
false`. Corrected before any code was written, not discovered mid-build: the
session became transition **and** a third playable nation, GBR, picked
because its `ordinary_law` amendment bar settles reachability by
construction rather than requiring a sweep that could come back
"unshippable" the way Germany's did at V1.2c.

**The restoration-direction reachability sweep needed widening mid-measurement,
the same way V1.2c's own sweep needed sharpening.** The plan's Step 0 swept
only GBR's *actually formed* government against a hypothetical bill position,
and found a ceiling of exactly that coalition's own seat share (0.560) —
below `parliamentary_republic`'s real `two_thirds` (0.667). Re-run against
every 1–3-party coalition combination, matching
[[amendment-model|the Germany sweep's own method]] rather than a narrower
reading of it, the true ceiling is 0.680 — reachable, with a 1.3pp margin.
`restore_the_monarchy` shipped on the strength of the wider sweep;
authoring it against the narrower one would have wrongly left restoration
unshipped. Full account: [[transition-model]].

**`ROADMAP.md`'s own stated reason for keeping transition a separate session
from amendment didn't hold for the content actually authored.** The roadmap
said a transition "changes `lose_condition` and the head of state at the
same time, not one field" — true in principle, but
`constitutional_monarchy` and `parliamentary_republic` both declare
`lose_condition: "party_not_largest"`, so for the one transition pair this
block ships, `lose_condition` never changes. The real reason transition
earned its own session — a completeness rule on the institutional bundle,
and a cross-check that has to validate against the *target* system rather
than the systems a law is proposed under — is a real, different
justification, corrected in [[transition-model]] rather than left standing
on the roadmap's original framing.

---

Related: [[index]] · [[ROADMAP]]
