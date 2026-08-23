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

## V1.2e — an axis measured decorative before it shipped, and a probe that lied once

Three corrections, and the interesting one is the earliest any correction on
this record has been caught.

**The coalition axis was cut at plan time.** [docs/tiers/v1.md](tiers/v1.md) §2
names four things a start scenario varies — debt, seats, approval, coalition —
and the plan shipped three. Seats plus `excluded_partners` already determine the
coalition through `Government.form()`, so authoring both authors a contradiction
that rule exists to resolve; and under GBR's `largest_party` the axis is
degenerate, the government being single-party by construction. Cutting scope at
plan time rather than discovering the collision mid-build is V1.1d's pattern,
not a new one.

**A third of the feature was decorative, and the constant said so before any
content existed.** The plan treated an authored `bloc_approval` as a single
write. It cannot be: every satisfaction term in [[opinion-model]] is a delta
against the nation's *own* starting figure, so a fresh game's approval target is
exactly `APPROVAL_NEUTRAL`, and `INERTIA_RATE = 0.25` pulls an authored 38 back
to 50 on a ~2.4-month half-life — gone inside a game year, while debt and seats
persist indefinitely. That is [[declined]]'s own falsifier firing on one axis.
Caught by reading the constant at implementation time rather than by running the
sweep afterwards, and fixed by holding the target through `bloc_offset`, the
channel `Government.penalise_blocs()` already uses for a fallen government. The
pattern worth keeping: **an axis can be measured dead from a tuning constant
alone, before there is any content to measure.**

**The probe's first answer was an artefact, and the fix was to split the
report.** `tools/scenario_probe.gd` initially showed the seats axis changing
*nothing* — identical approval, deficit, debt and election timing at every
extreme, for all three nations. The tempting read was "seats are not a
difficulty lever". The real cause was the regime: `hands_off` proposes no law,
and the legislature is the only channel seats have. Split into a legislative
table (month 0, through the real `resolve_vote()`) and an economic one, the axis
moves the amendment ceiling by ±0.06 and flips reachability in **both**
directions. Same lesson as V1.2c's Germany sweep and V1.2d's restoration sweep,
arrived at from the opposite side: those two needed *widening* to find a ceiling
that existed, this one needed *narrowing* to find an effect the aggregate hid.

The measurement then paid for itself twice on content that was already written:
`deu_grand_coalition` cleared two-thirds by exactly nothing (0.667 against
0.667, passing on a rounding boundary) and was widened; `gbr_hung_parliament`
made amendments *easier* than the standard start, the opposite of what the file
claims to be, and had its freed seats moved off the centre and onto the party
both large parties exclude. Neither would have been visible without running it.

`SAVE_VERSION` stayed at 8 — the first runtime-readable field since V1.2b not to
earn a bump, because a version-8 save's absent `scenario_id` reads as `""` and
that is *correct*, not silently wrong. Full account: [[scenario-model]].

## V1.3 — decomposed before any code, and four calls made while decomposing

Not a build session and not a correction to one: [[ROADMAP]] carried V1.3 as a
single table row — relations, diplomatic actions, trade agreements, tariffs,
sanctions, an EU-shaped bloc, nation AI foreign policy, defence — and a row is
not a session. Logged here for the same reason the **Scope alignment** entry
above is: a decision that changed the roadmap without shipping code is exactly
the kind that otherwise leaves no trace.

**The block's real schema decision is not any of its named features.**
Everything in this project's live state today hangs off a `NationState` or off
`GameState` itself. A relations score belongs to a *pair*, which nothing in the
codebase has a home for. That, not the verb count, is why V1.3a is the schema
session and why its tier is **High** while V1.2c–e each held Medium: those
three each held on "no new model, no new tuned constant, an nth instance of a
pattern built n−1 times", and all three are false here.

**Four calls made at decomposition time, each of which could have gone the
other way:**

- **Relations ship with a verb.** The obvious split — state layer first, actions
  second — reproduces exactly what [[scenario-model|V1.2e]] caught at design
  time: an axis with no persistent reader decays to neutral inside a game year
  and is decorative. So V1.3a is relations *and* a small set of player actions,
  and the elastic surface if it overruns is the action **content count**, never
  the schema.
- **AI is fifth, with named stopgaps rather than accidental ones.** The docs
  already commit to AI foreign policy being "the actual hard part". Building it
  early means building an agenda with no action space to score, then rescoring
  it at every later session. So V1.3b–d each ship a deterministic counterparty
  rule *declared* as a stopgap V1.3e replaces — the same declared-unresolved
  shape `lose_condition: "never"` and `referendum_required` already use — and
  V1.3e opens with the checklist rather than discovering the debt.
- **The foreign-policy opinion issue belongs to V1.3d.** Adding an `ISSUE_KEYS`
  entry means six new `BLOC_SALIENCE_BASE` rows, and [[declined]] records that
  every tuned opinion constant was measured against that one table. Assigning
  it to one named session keeps three sessions from each paying a share of a
  re-measurement; a–c use `bloc_offset` instead, the channel V1.2e already
  proved persistent.
- **LimboAI declined for V1.3e.** Installed, evaluated, and refused on four
  grounds — wrong problem shape, an engine-version bet, Nodes in `src/sim/`
  against Rule 2, and committed platform binaries against the `.gitignore`
  contract. It has a reopening condition, in [[declined]].

One thing the cold read changed on the spot: the roadmap's Military-tab row said
"blocked on V1.3's defence layer", a whole block away. It is now blocked on
**V1.3f** specifically, which is one named session with a dependency list.

## V1.3a — the symmetry call cost a third input, and the measurement caught an exploit

The plan/model/effort row was counted by the decomposition session, which by that
table's own record is the estimate most likely to be wrong. Counted cold at plan
time it came in at **~25 surfaces against the logged ~22**, and High held — on the
reversibility test the table's own preamble names, not on the count. Two logged
surfaces were wrong in opposite directions: `data/relations.json` does not exist,
because starting values are derived, and the `bloc_offset` rename logged as
"nearly free" was ~30 edit sites across five code files, four test files and eight
docs.

Three things the session found that the plan did not contain.

**The symmetry call took a third input with it.** The plan expected to derive a
pair's resting value from EU co-membership, a shared border, and size asymmetry.
Choosing one symmetric number per unordered pair made the third unusable *as a
matter of arithmetic* — the pair's single number has no side to attach "the
smaller partner has less leverage" to. Dropped and handed to V1.3b's read-time
trade weighting rather than quietly omitted, which is the same treatment
[[scenario-model|V1.2e]] gave the coalition axis it could not author without
authoring a contradiction.

**The probe's first table measured the wrong thing and looked like a finding.**
It swept sustained use and asked how many months a pair took to return within one
point of resting. From a twenty-point displacement that is four-plus half-lives
**by construction**, so nearly every row read "> 120 months" and the table appeared
to report that the drift does nothing. A second table was added rather than the
first reinterpreted — one action, then nothing — and it is the one that justifies
the constant: a 35-month half-life, 78% present after a year, 30% after a term.
Second time a probe on this project has produced an artefact rather than a result;
[[scenario-model|V1.2e's]] seats axis was the first, and the response both times
was to split the report rather than trust the first number.

**And the measurement caught an *exploit*, which is new on this record.** Every
correction here so far has come from a number that turned out unreachable. This
one came from a number that turned out too reachable. The plan's visible-cost slot
was going to be a six-bloc approval *gain* — condemning foreigners is popular, and
the probe had just shown that only a six-bloc effect clears poll noise in the
headline figure. But the cooldown is per (action, target), so nothing stopped the
player applying it against all nine neighbours in one month: +0.72 into a channel
clamped at +1.0, saturating approval outright. Shipped as a pure **cost** instead,
with the popular verb **split** across blocs so mass use is self-limiting. Found
before the content existed, which is the whole reason the measurement runs first.

Full account: [[diplomacy-model]].

## U5a — a request that was three sessions, and an accent chosen against the obvious one

The first U-track entry in this log, and the first session on the record whose
scope came from the user asking for something rather than from the roadmap's own
queue. Worth writing down for three reasons.

**The request decomposed into three before any code, and the split was not
arbitrary.** The ask was: reshape the shell to a geopolitical simulator's, put a
satellite map of the whole world behind it, and add a calendar of appointments
with leaders, politicians and celebrities. Two of those three are independent of
the shell, and one of them is not a UI feature at all — an appointment needs
*people*, and the game knows names but has no person entities, which is exactly
what [[cabinet-model|V1.1d]] deferred when it made a portfolio point at a party
rather than at a minister. Shipping the calendar as part of a layout session
would have smuggled an S-track schema in under a U-track heading. Split into U5a
(the shell), U5b (the map) and U6 (the calendar and the roster).

**The pin is what made deleting the tab rail defensible.** A rail guarantees the
player never has to tidy up: one thing is open, selecting another closes it.
Floating windows lose that guarantee by default, and a shell that makes the
player manage windows is worse than the tabs it replaced. `window_manager.gd`
keeps the guarantee as its one rule — opening a panel closes the open *unpinned*
one — so the default is exactly tab behaviour, and the pin buys the single case
tabs could never serve: reading the budget while proposing the law that changes
it. Without it this session would have been a reskin with a regression in it.

**Brass over cyan, and the reason is a rule about where the boldness goes.**
Every game HUD reaches for a cool accent on dark, and the reference the user
brought is no exception. Brass is the state's own material — seal, instrument
bezel, ministerial fitting — and picking it is the one deliberately bold move in
a palette that is otherwise disciplined navy. The corollary matters more than
the colour: the signature is *one rule applied everywhere* (a 1px brass hairline
along a plate's top edge and nowhere else, light falling on glass over a map
table), and nothing else in the interface gets a glow, a gradient or a shadow.
`tests/test_ui_theme.gd` asserts the other three edges stay bare, because a
later session tidying that into `set_border_width_all()` would cost the
interface its point of view without failing anything.

**Two bugs found by looking, which no test could have caught.** With the map
promoted from a tab to the background, its opening zoom of 1.0 left Europe as a
480×420 object in the middle of 1920×1080 — every test passed, because no test
asks what fraction of the screen the map fills. And the panels report combined
minimum heights up to 974px against a usable band of 886, so a window sized to
its content grew straight through the bottom furniture and its last row became
unreachable. Both needed a rendered frame: `--headless` draws nothing, so a
throwaway `tools/shot.gd` wrote the scene to a PNG. This is the third time on
this log's record that the U-track's characteristic failure is *silent* — the
thing renders, nothing errors, and it is simply wrong to look at.

**One plan claim that was wrong, corrected in the row rather than absorbed.**
The plan said U5a touched no `data/` and no `src/core/`. Drawing a flag without
a colour table keyed by nation id — [[engine-decision]] Rule 1 — meant a `flag`
block in all ten nation files, a field on `Nation`, and a validator. It earns no
`SAVE_VERSION` bump, since a flag is static content read at startup and never
written to a save.

## V1.5a — a pre-committed tiebreaker is not enough, and two ways it fails

[[companies-model|V1.4c]] added a rule to this project's measurement discipline: fix
the **tiebreaker** before the sweep as well as the band, because a band can pass three
rows and choose nothing. V1.5a is the first session to follow that rule, and it found
the rule incomplete in **two distinct ways** — recorded here rather than in the model
doc, because it is about how this project measures rather than about services.

**(1) A tiebreaker can be a test that cannot fail.** `QUALITY_SCALE_PP`'s said: if the
two satisfaction terms summed exceed what `SPEND_SCALE_PP` produced alone, re-measure
`SPEND_SCALE_PP` downward. Any positive stock term adds to a total, so the condition
fires for every candidate — it is not a discriminator, it is a tautology wearing one.
That is exactly [[foreign-policy-model|V1.3e]]'s criticism of its own split trigger
(*a plan-time count above V1.3a's ~25*, which had already fired on three sessions that
did not split), arrived at independently in a different part of the process.

**(2) A tiebreaker can be a bound rather than a selector.**
`CORRUPTION_DELIVERY_BETA`'s was a ratio against `VACANT_EFFECTIVENESS` — and every
candidate satisfied it, because it constrains the *range* without ordering the
candidates inside it. The kill-switch band then cleared at all four values too, so
band and tiebreaker together chose nothing. **This is V1.4c's failure repeating inside
the session written to prevent it**, which is the strongest available evidence that the
rule as V1.4c stated it was under-specified.

**The rule, restated:** a pre-committed tiebreaker must be a **strict ordering over
the candidates that survive the band**. "Nearest to constant X" is one
(`QUALITY_CONVERGENCE`'s, the only pair in this session that worked as designed —
band passed two rows, tiebreaker chose one). "Below constant X" is not. Check that the
tiebreaker discriminates *before* running the sweep, by asking what it would say if
every row passed the band.

**A third failure, and it is the older one.** `QUALITY_SCALE_PP`'s *band* was measured
through a path that could not observe the thing being banded: it asked whether the
quality channel **alone** moved the headline, via a spending increase — and raising a
spending line necessarily widens the deficit, so the channel was never isolated. The
headline came back **negative for a spending increase**. That is
[[foreign-policy-model|V1.3f]]'s measuring-the-wrong-state error for the third session
running, and the pattern across all three is the same: **the measurement was designed
before it was asked what state it would be taken in.**

**What the corrections cost and bought.** Nothing was tuned to a number already
picked, and there is checkable evidence: the replacement rule for `QUALITY_SCALE_PP`
chose **4.5** where the constant had been provisionally set to **6.0**. A rule that
moves the author's own guess is a rule that was not written backwards from it.

**One unplanned model widening, kept on the evidence.** The balance re-run's second
cause of divergence was not predicted: `quality_target()` multiplies by
`Cabinet.effectiveness()`, so a reshuffle or a resignation moves the quality stock with
every spending line untouched. [[cabinet-model|V1.1d]] had deliberately made
effectiveness multiply the *delta only*, so that a player who never moves a line is
untouched by the cabinet system; V1.5a un-chooses that through a different channel.
Kept rather than gated, because the alternative is a model in which a **corrupt** state
delivers less but an **incompetently run** one delivers the same — and the evidence for
keeping it is that zero outcomes moved across 182 outcome lines. Recorded because it
was not planned, not because it was wrong.

**And a check that silently covered less than it appeared to.**
`tools/run_tests.sh` never contained `tests/test_companies.gd`. It was authored at
V1.4a and omitted from the list, so V1.4a, V1.4b and V1.4c each shipped with their own
test file running only when invoked by hand — three sessions of green suites that were
not testing the thing those sessions built. Found by noticing that a *new* test file
was absent from a passing run and then reading the list. This is
[[people-model|U6b]]'s `check_names.sh` finding in a new place (that check iterates
`git ls-files`, so an untracked directory passes with zero files scanned), and the
generalisation is worth more than either instance: **a green check is evidence only
about what it enumerated.** Any session adding a test file must confirm the runner
names it.

## V1.5b — a tiebreaker can be a strict ordering and STILL let the range choose

[[society-model|V1.5a]] restated the rule above as: *a pre-committed tiebreaker must be a
strict ordering over the candidates that survive the band*, checked by asking what it
would say if every row passed. `MIGRATION_SHARE_BETA`'s tiebreaker **satisfied that rule
and still failed**, which is the third distinct failure mode in two sessions.

It said: strictly less legible on the pensions bloc row than a saturated corruption
register is on health's — their common landing site, and a genuinely measured quantity —
then take the **largest** passing candidate. That is a strict ordering by size. It orders
every row. It is not a tautology and not a bound.

**The defect is that both of its bands are one-sided minimums.** Band (i) asks the lever
to be *readable*, band (ii) asks it to be *closable*, and a bigger constant satisfies both
more easily. So every candidate above the threshold passes, "largest" returns the top row
of the grid, and the answer moves when the grid moves: the first sweep stopped at 0.010
and chose 0.010; widening it to 0.016 chose 0.016. **The candidate range was choosing the
constant, and no amount of ordering fixes that.**

**The rule, extended:** a pre-committed tiebreaker must strictly order the survivors
**and its answer must not move when the candidate range is widened.** The second clause
is the one with teeth, because it is checkable *before* trusting the result — widen the
grid and re-read — where "is this a strict ordering?" is answerable in the affirmative by
a tiebreaker that is nonetheless useless.

**The corrected selector was forced rather than chosen**, which is the useful part: when
every band is a minimum, the **smallest** passing candidate is the least-invasive value
that clears them, and it is stable under widening by construction. It chose **0.0090**,
which is *interior* to the widened grid — two candidates fail below it, three pass above
— and interiority is the observable that distinguishes a chosen number from a ceiling.

**A cheap diagnostic falls out of this.** If the selected value sits at an endpoint of
the swept range, the range is a suspect, not a result. That is true regardless of how the
tiebreaker is phrased, and it costs one glance at the table.

**And the kill switch fired in the same session, which is the counter-example worth
keeping beside it.** `DEPENDENCY_ELASTICITY["health"]` failed its band at *every*
candidate including the largest defensible one, so the entry was **deleted** rather than
shipped. A constant whose range cannot be trusted and a constant that cannot clear its
floor are different failures with different remedies — widen and re-select, versus
delete — and a session that meets both should not treat them alike.

## V1.5c — four more ways a pre-committed measurement fails, and the harness that could not see the thing it was measuring

[[society-model|V1.5a]] restated the tiebreaker rule; [[demography-model|V1.5b]] extended
it with the widening clause and the endpoint diagnostic. V1.5c ran six pre-committed
sweeps and **four of them failed in ways neither clause catches**. They are collected
here because they are about how this project measures rather than about strikes, and each
is checkable *before* the sweep.

**(1) A nearest-to-X tiebreaker is only as good as the grid's RESOLUTION.**
`UNREST_CONVERGENCE`'s band is two-sided by construction and its tiebreaker — nearest the
geometric mean of the two bracketing half-lives — is a genuine strict ordering with an
interior answer. It still gave the wrong number: on a doubling ladder it chose **0.08**,
0.78 months from the target, and refining the grid to 0.01 put **0.07** at 0.46. V1.5b's
diagnostic is about *widening* the range; this is the same failure under **refinement**,
and it is checkable the same way. **Refine as well as widen, and re-read.**

**(2) A band whose ceiling is one regime's measured peak makes "largest passing" mean
"that peak".** `UNREST_THRESHOLD_PCT`'s band was *fires under `austerity`, never under
`hands_off` or `managed`* — two-sided, so V1.5b's failure was avoided by design. The
tiebreaker chose **52.0** against `austerity`'s own peak of 52.82. It passes V1.5a's
ordering check and V1.5b's widening check and is still wrong twice over: the margin is
0.8 points on a 100-point range, and at 52.0 a budget that **zeroes every spending line**
produces no industrial action at all. The band's ceiling was a *measurement*, not a
criterion, so the selector had nothing to choose between. The fix is a criterion the band
should have contained — V1.3f's `AGENDA_ACT_MIN` again.

**(3) When the interval becomes two-sided, V1.5b's own correction INVERTS.** V1.5b forced
*smallest passing* because both bands were one-sided minimums and *largest* returned the
top of the grid. `UNREST_SETTLEMENT_BETA` pre-committed to that rule; then band (i) was
corrected and the interval became genuinely two-sided — at which point *smallest passing*
**lands back on an edge** and is grid-dependent all over again (7.0 left the stock at
45.24 against a threshold of 45.0, a 0.5 % margin).

> **The rule, extended:** when the passing interval is bounded by **two model criteria**,
> take the value nearest its **midpoint** — interior by construction, and it moves only if
> the interval moves. When one edge is a **guard rail** rather than a model criterion, the
> guard rail does not select and the model edge governs.

Both halves fired in the same session: `UNREST_SETTLEMENT_BETA` took the midpoint of
`[7.3, 16.3]`, and `UNREST_OPINION_SCALE` kept smallest-passing because its upper edge is
`opinion.gd`'s own ±1.0 clamp.

**(4) A band can be applied to an observable the channel does not reach.** V1.5a's
`QUALITY_SCALE_PP` was measured on a *path* that could not observe the channel. This is
the neighbouring error: `UNREST_IMPULSE_SCALE`'s band asked an **output** channel to move
an **approval** figure, and it failed at every candidate while the same channel moved GDP
by 4.94 %. The constant was right and the band was measuring something else. Distinguish
before deleting: *the band failed* and *the constant cannot clear its floor* look
identical in a table and have opposite remedies.

**And a fifth failure, the oldest one, a third time.** `UNREST_COOLDOWN_MONTHS`: every
candidate from 3 to 36 passed both clauses, so the band was a bound and not a selector —
V1.4c's failure and V1.5a's `CORRUPTION_DELIVERY_BETA`. Set by argument instead, and the
constants file says so rather than dressing the argument as a measurement. **A constant
set by argument is not a failure; a constant set by argument that claims to have been
swept is.**

## V1.5c — a probe can inherit the blind spot it was written to catch

Separate from the tiebreaker list, and the sharper finding of the two.

`tools/unrest_probe.gd`'s reachability table reported twelve strikes under `austerity`
over fourteen years. `tools/balance_probe.gd` then reported **zero acts in all
twenty-five shared regimes**. Both were right about their own harness: the balance harness
runs elections and stops on the lose condition, so a budget provocative enough to anger
the country loses the 2027 presidential election at month 16 and the run ends long before
a stock converging at 0.07 matures. The unrest probe's loop has no elections, so it ran a
government that had already been thrown out for fourteen more years.

**That is V1.3f's measuring-the-wrong-state error, in the probe written to avoid it, for
the third time in three sessions** — and the new part is that the *cross-check* is what
caught it, not either probe. Two harnesses disagreeing is information; one harness
agreeing with itself is not.

The consequence generalises past unrest: **a channel whose trigger no regime reaches makes
every bit-identical regime meaningless**, which is [[calendar-model|U6a]]'s day-loop
finding at a larger scale. `balance_probe.gd` now prints a reachability column for every
regime, and it gained a **mid-run budget switch** — the first regime shape in this project
that changes policy part-way through a run — because the reachable case is *govern well,
win, and then provoke*, and no month-1 regime could express it.

## V1.5d — the guard-rail rule assumes the model edge is a PLATEAU

[[society-model|V1.5a]] restated the tiebreaker rule; [[demography-model|V1.5b]] extended
it to widening; [[unrest-model|V1.5c]] added four more, the last of which reads: *when the
passing interval is bounded by two model criteria take the midpoint, and when one edge is a
guard rail the guard rail does not select and the model edge governs.*

`FRAMING_BETA` pre-committed to that rule and it failed, **twice over**, in ways that
happened to cancel.

**(1) One of its two declared model criteria never fired.** Band (i) asked for a readable
bloc row; band (ii) asked that a well-governed run's headline not move past ±3.0. Band (ii)
measures **0.44 at beta 7.0 and 1.02 at beta 20.0**. It orders nothing, so it is a bound and
not a selector — V1.5a's failure (2), in the session that inherited the warning. The
interval's real upper edge is the `FRAMING_GAIN_MIN` clamp, which is a **guard rail**.

**(2) So V1.5c's rule applies and prescribes the smallest passing value — and that is wrong
here for a reason the rule did not contemplate.** V1.5c's own table (d2), which the rule was
written against, reads −2.11, −2.95, −3.16, −9.01: a **lumpy** response, so its floor sat on
a shelf and refining the grid could not move it. `FRAMING_BETA`'s response is **linear** —
2.98, 3.01, 3.12, 4.52, 5.45, 6.53, 9.27 — so *smallest passing* means nothing more than
*wherever the band crosses*. 3.02 clears a 3.0 floor by 0.3 %, and every refinement of the
grid moves the answer. That is V1.5b's widening diagnostic and V1.5c's refinement
diagnostic arriving through the one rule that was supposed to be immune to both.

**The rule, extended:** the guard-rail clause assumes the model edge is a **plateau**. When
it is a smooth **crossing**, the model edge does not select either — and with neither edge
selecting, the only value stable under widening *and* refinement is the interior. Both edges
of `[3.02, 6.00]` are structural rather than grid artefacts (a band crossing and a clamp), so
the midpoint is structural too and is the value furthest from both failure modes.

**A cheap diagnostic falls out, and it costs one glance at the table:** before applying any
edge-selecting rule, ask whether the response near that edge is **lumpy or smooth**. Smallest
and largest passing are only meaningful on a shelf.

`PRESS_UNREST_BETA` failed in the older way — every candidate passed band (i) — and is **set
by argument**, as a ratio against `SETTLEMENT_BETA`. A ratio against a fixed constant is
stable under both widening and refinement, which is what neither band was, and that is the
general lesson rather than a fact about press freedom.

## V1.5d — a harness that never calls a system proves nothing by agreeing

The balance re-run was predicted **not** to be bit-identical, and came back with a diff of
**exactly zero lines**. The prediction being wrong is what caught the bug:
`tools/balance_probe.gd` and `tests/test_balance.gd` never called `Media.tick_month()`, so
both harnesses were running the pre-session model and their agreement was about nothing.

[[calendar-model|U6a]] found this for the day loop and V1.5c found it for reachability; this
is the same failure at its simplest, and the new part is the **detection method**. A
bit-identical re-run is normally the reassuring outcome, so nothing about it invites
suspicion — which is exactly why the prediction has to be written down **before** the run.
An unexplained agreement is as much a finding as an unexplained difference.

With both harnesses fixed, all 28 shared regimes are bit-identical in GDP, growth, trend,
unemployment, debt and deficit; approval moves in all 28 by at most 3.00 points; and there
are **zero outcome changes**.

## V1.6a - a legibility floor that cannot be met, and where a fit beats a band

[[society-model|V1.5a]] restated the tiebreaker rule; [[demography-model|V1.5b]] added
widening; [[unrest-model|V1.5c]] added four more; [[media-model|V1.5d]] added the
lumpy-or-smooth check. V1.6a pre-committed against all five, printed the check in its
own probe header, and **both of its bands still failed** - in the two ways that header
named. The new part is what happens next.

**(1) The failures were the known ones, and predicting them did not prevent them.**
Band (i) - *the cycle moves approval past the +-3.0 poll floor* - read the national
headline and passed at **every** candidate from 0.25 to 4.00, returning 6.271 where the
cycle is nearly switched off. A committed budget moves approval six points on its own,
so the band was measuring the budget: V1.5a's failure (2), in the session that wrote the
warning at the top of its own file. Band (ii) - a growth-clamp guard - was flat at 7.346
for seventeen candidates of nineteen, `ruinous` setting it rather than the cycle.

**The fix is to DIFFERENCE two runs alike in everything but the channel.** That is what
makes a band measure its own constant instead of the loudest thing in the same
observable, and it generalises past cycles: any band on a quantity the player can also
move needs a control.

**(2) Moving to a bloc row did not help, and that is worth recording because three
sessions said it would.** `society_probe.gd` table (c), `demography_probe.gd` and
`unrest_probe.gd`'s P3 all establish that a single issue cannot carry a national
headline. The workers row - 0.42 of growth-plus-jobs salience against business's 0.26 -
bought **8 %**. The cycle reaches every bloc through the same two issues, so bloc
selection cannot rescue a band this channel genuinely cannot clear.

**(3) The surviving bands had NO OVERLAP, and that is neither of V1.5c's two failure
modes.** *The band failed* and *the constant cannot clear its floor* look identical in a
table and have opposite remedies. Here both response columns are alive and smooth and
the two criteria simply disagree:

> Readable needs an amplitude of about 1.9. A France no more volatile than the real
> France allows at most about 1.7.

That is a fact about the model, and the remedy is neither widen-and-re-select nor
delete. It is to **record the bound and choose by something else** -
[[defence-model]]'s deployment that could not clear its own floor.

**(4) The rule this session adds: WHEN A BAND CANNOT CHOOSE, A FIT CAN - and a fit is
strictly better than a band edge under both existing diagnostics.**
`CYCLE_AMPLITUDE_PCT` is set to the candidate whose realised annual-growth standard
deviation is nearest France's own measured 1.262. At 1.70 the model returns 1.260.

> A band edge MOVES when the grid is widened or refined; a fit CONVERGES. Widening adds
> candidates further from the target and changes nothing; refining adds candidates
> nearer it and improves the answer toward a fixed point. V1.5b's and V1.5c's
> diagnostics are both really asking for stability under grid changes, and a fit has it
> by construction where an edge has it only by luck.

The precondition is that something outside the game measures the same quantity the model
produces. When it does - and for an economy simulator it often does - a fit should be
preferred to a band, not used as a fallback after one fails.

**(5) A sweep was DELETED because the data already answered it.** `CYCLE_COMMON_SHARE`
was pre-committed as the session's second swept constant. The World Bank series that
supplies the per-nation amplitude also says what the common share is: var(common
factor) / mean var(nation) = **0.619**, cross-checked against a mean pairwise
correlation of **0.633**. Two statistics of one dataset agreeing to 0.014 is V1.5c's
two-harness rule applied to a measurement rather than to a probe, and it is a stronger
result than any band would have produced. Its two bands survive as a **verification**,
and one of them then failed in a sixth way:

**(6) A band's NUMBER can fail to match its own stated REASON.** Band (ii) was written
as *the imported cycle must not BEAT the domestic one* and the number beside it was
0.25 - four times tighter, and never derived from the sentence. Measured 0.467, which
satisfies the reason and fails the number. Correcting it moved **no constant in either
direction**, which is what made the correction legitimate rather than a fit to a result;
had the constant been swept rather than measured, it would not have been. **Read the
number back against the sentence before the sweep runs.**

## V1.6a - the decomposition's own call, refuted by the session it booked work to

Separate from the tiebreaker list, and the sharper finding of the two.

V1.6's decomposition split V1.4c's inherited obligation - *inflation and the business
cycle own the risk a state-owned firm carries* - into a half V1.6a would discharge for
free and a half V1.6c owes. The free half was a one-line argument: a dividend is
`state_share x share x sector_output x yield`, `sector_output` already moves with the
cycle through `SECTOR_CYCLE_BETA`, therefore the dividend becomes procyclical the moment
a cycle exists.

It measured **1.07x** the flat-cycle variation, against a floor of 1.5x fixed before the
run. The mechanism is one line: `Companies.dividend_revenue_pct_gdp()` returns
`100.0 * paid / ns.gdp_eur_bn`, and the cycle moves the numerator and the denominator
together.

> **A quantity expressed as a share of GDP is not procyclical by construction.**

Two things generalise. First, **the decomposition is not exempt from the probe**: this
project has recorded fourteen instances of a *row* being wrong by counting, and this is
the first where the thing found wrong was written the same week by the same argument.
Second, **"X already moves, so anything built on X moves" is a claim about units**. It
holds for a level and fails for a ratio, and every fiscal line in this game is a ratio.

## V1.6a - a harness can be wrong in a way no test can see, for eleven sessions

[[media-model|V1.5d]] found that neither balance harness ever called
`Media.tick_month()`. This is the same failure one layer down and much older.

`Budget.project()` has **never advanced the clock on its copy**. It ran twelve ticks at
one date, and `tests/test_budget.gd`'s own comparison runner froze the clock too - so
the two agreed to 1e-9 while both were wrong, for eleven sessions. Nothing noticed
because nothing in either loop computed a figure from the date: `bloc.gd`, `defence.gd`
and `cabinet.gd` read `state.year` only to stamp a record, and `calendar.gd`, which
genuinely reads it, is not run there.

**The bug was invisible until a reader existed, and then it was caught on the first
run.** `tests/test_cycle.gd` asserts the projected cycle path equals the delivered one:
month 1 projected -0.903 and delivered -0.690.

The response that generalises is the structural one rather than the fix.
`src/sim/cycle.gd` has **no `tick_month()` at all** - `Economy.tick_month()` writes the
impulse from a pure read - so every harness in the project reaches it through a call
they all already make. **A system that cannot be forgotten is worth more than one that
is remembered**, and the claim was falsified before it was trusted rather than after.

## V1.6b — the row named an input the data does not support

**The plan said** the row's own words: inflation is *"a price pressure from the gap,
the impulse and (a)'s shock."*

**What was built** reads the **unemployment gap** and none of the three.

Two corrections, and only the first was available without measuring. The three named
inputs are **one quantity written three times** — the output gap is the accumulated
integral of the growth addends, so a target reading the gap *and* the impulses that
fill it double-counts, which is V1.3c's `tariff_rate_pct` error. Then the data refuted
the survivor: regressed on `FP.CPI.TOTL.ZG` over 1990–2024, the output gap's
correlation never leaves the noise **and its sign flips between sub-samples** (+0.204
pre-euro, +0.098 euro era, −0.140 pooled), while the unemployment gap is stable and
correctly signed in both disjoint halves.

The direction of the error is the useful part, and it is one this log has recorded
before in another form: **the row named the quantity the model computes rather than
the quantity the world relates.** `output_gap_pct()` is a public function and reads
like the obvious input; unemployment is a *result* two steps downstream and reads like
a symptom. The relationship runs the other way.

Full argument: [[inflation-model]] §2.

## V1.6b — the probe's table was not independent of the constant it chose

**The plan said** sweep `INFLATION_SCALE_PP` against a pre-committed band.

**What happened** is that the first table moved when the answer moved. A probe cannot
change a `const` at runtime, so the first version measured the headline response at
the *shipped* scale and rescaled linearly to each candidate — which is wrong twice:
approval is not linear in satisfaction (`SALIENCE_GAIN` amplifies bad news), and the
rescale was anchored on the shipped value, so **the passing interval changed when the
shipped constant changed**.

This is V1.5b's *the range was choosing the constant* in a new costume, and it was
caught only because the constant was set once and the probe re-run — a step that is
not obviously necessary and now is. The fix emulates a candidate **exactly** rather
than extrapolating: displace the stock to whatever produces the same satisfaction the
candidate would. Verified by re-running after the change, which now moves the table by
less than 0.003.

Full argument: [[inflation-model]] §8.

## V1.6b — a band that failed, and was neither raised nor deleted

**The plan said** a constant neither a band nor a fit can justify is deleted.

**What was built** keeps `INFLATION_OUTPUT_BETA` at an honest 0.30 with its visibility
band failing, and records the bound.

The reachable inflation deviation is **0.145 points**, so clearing a 0.25 %-of-GDP
visibility bar needs one point of inflation to cost two points of annual growth — more
per point than the whole business cycle. Raising it would be tuning a measured slope's
consequence until it is visible, which V1.5b refused for `DEPENDENCY_ELASTICITY` and
V1.6a refused for `CYCLE_AMPLITUDE_PCT`. Deleting it would remove the only term making
the inflation loop negative feedback.

**So the rule "delete what a band cannot justify" gains an exception, and the
exception is stated rather than left implicit: a term that is STRUCTURAL rather than
decorative survives a failed visibility band.** U6a's day budget and V1.3e's
`AGREEMENT_ACCEPT_MIN` were deleted because nothing read them. This one closes a loop.

Full argument: [[inflation-model]] §7.

## V1.6c — a band can pass a term the model's own boundary forbids

**The plan said** `YIELD_INFLATION_BETA` would fail its visibility band and be deleted,
and recorded in advance that V1.6b's structural exception must not be reached for to
keep it.

**What happened** is that the band **passed** it — 2 of 7 candidates — and it was
deleted anyway, on a ground the band could not see. `DEBT_REAL_RATE_PCT` is a **real**
rate and inflation raises a **nominal** one, so a term there is the Fisher effect:
precisely the nominal layer [[inflation-model]] §1 cut, smuggled back in through the
yield. What survives in real terms is an inflation *risk* premium, which is about
volatility rather than level — and this model's realised inflation sd is 0.040 against
a measured 1.14.

Every previous deletion on this list was a band failing. This is the first where the
band was the weaker instrument, and the rule it adds is short: **a band is a test of
size, not of legitimacy. Check the term against the model's own boundary first.**

Full argument: [[credit-model]] §3.

## V1.6c — three sets of bands for one constant, and the probe caught each

**The plan said** table (a) runs first and nothing is swept until it has been read.
It did, and it earned its place twice over.

The **first** band set measured a debt-widening regime and passed at every candidate
down to 0.005 — because a spendthrift budget does not widen the debt, it *spirals* to
the clamp and a ratio past 1400 % of GDP. **A band measured on a saturated run measures
the clamp.**

The **second** measured `hands_off` and passed at **0.0005**, because a debt ratio
walking 110 → 200 moves the service line by 1.8 points at the *anchor* rate with no
channel at all. **A band on a raw move measures the model that was already there.** The
fix is a control with the term zeroed — the control `tests/test_trade.gd` needed at
V1.6a, one session later.

The **third** ships, and the interval it found is interior, stable under refinement,
and iterated to a **fixed point**: the shipped value equals the midpoint measured at
it. That is stronger than V1.6b's check that the table moves by less than 0.003 when
the constant does, and it is the answer to a probe measuring a path its own constant
is on.

Full argument: [[credit-model]] §4.

## V1.6c — the row named two inputs and they were one

**The plan said** debt and deficit look like one quantity written twice, and that they
stay distinguishable only if the level and the trajectory are read at different lags.

**The sweep refused the term.** Three clauses, mutually inconsistent: isolated against
a control, the deficit term moves debt service 0.30 points of GDP over a term only
above a slope of 0.20, and by 0.145 it already outweighs twelve months of the debt term
it exists to lead. Everywhere it is legible it dominates the level; everywhere it does
not dominate it is under the floor. `corr(debt gap, deficit gap)` then measured
**0.9948** against an accepted standard of 0.3185.

Deleting it removed the session's **only** positive feedback loop with it, because
`debt_service_pct_gdp` is inside `deficit_pct_gdp`. What was going to be an argument
about a one-month lag is now a fact about the call order.

Full argument: [[credit-model]] §3.

## V1.6e — the row named a quantity that has no room for a second writer

**The plan said** the lever acts on `sector_output`, which is what [[v1]] §6 asks for in
those words.

**The measurement refused the site.** `Economy._apply_growth_to_sectors()` grows each
sector at its own rate, distributes the residual `target_gdp − after_trend` by cyclical
beta, and ends with `ns.gdp_eur_bn = total` — so the sector sum **is** the month's GDP
target by construction. 27.9 bn injected into French industry before a tick leaves GDP
**+0.024 bn** against a control and moves the industry share +0.006.

> A write to `sector_output` survives as **composition** and never as level.

The honest landing site is the per-sector trend **rate**, which is `Trade.sector_shift()`'s
slot — and the two are not the same kind of thing at all: **a trade shift must sum to zero
and an investment shift must not**. So the shift is read at *both* of `economy.gd`'s sites,
and adding it at `trend_pct()` share-weighted is precisely what stops the residual taking
the level effect back.

The general rule this leaves: **before banding a term, check that the quantity it writes
has room for another writer.** V1.6c's *a band is a test of size, not of legitimacy*, one
step earlier in the pipeline — there the term was legitimate and mis-sized, here the site
itself was unavailable.

Full argument: [[sector-model]] §2.

## V1.6e — the strictly-dominated shape appeared in a PRICE

This project has caught it six times and every one was in an **effect**: V1.3c's tariff
severities, V1.3d's rule burdens, V1.4a's rival floor, V1.4c's dividend yield, V1.6d's
Gini clamp.

Here the effect was proportionate and the **bill** was flat. Table (e), isolated: backing
French services moves growth **0.4865** points, backing French agriculture **0.0077** — a
spread of sixty-three to one against an identical price, plus a political price either way.

The fix moves the model rather than the number and adds **no constant**: the bill scales
with the sector's own share of GDP, so the return per euro is the same wherever it is spent
and *which sector* goes back to being a question about composition and politics.
`RIVAL_FLOOR_FRACTION`'s correction in a new place — there too the endpoint became content
and the rate went back to setting speed.

**It also deleted a constant.** The three shares sum to exactly 1.0 by the same
reconciliation the entry above is about, so the whole bill is bounded above by
`INVESTMENT_COST_PCT_GDP` itself. `INVESTMENT_BILL_MAX_PCT_GDP` was a guard rail guarding
arithmetic, and it went the way U6a's day budget went.

Full argument: [[sector-model]] §8.

## V1.6e — a closed-form band, reported off the grid

Two of this session's three constants are closed form, and the first run still printed the
interval as the **widest passing grid row**: 0.40 where the exact edge is 0.46, and t90
38.3–77.8 months where the band says 36–84.

That is [[demography-model|V1.5b]]'s *the range was choosing the constant* — in the one
place it should have been structurally impossible, since the whole claim of a closed-form
band is that no grid can move it. The edges are solved arithmetically now and the grid is
kept only as a legibility column.

A second correction in the same table set: the beta band's clause (ii) was **measuring the
clamp**, because the national shift is scaled down to `SECTOR_TREND_MAX_PCT` the moment it
would exceed `SHIFT_MAX_PCT`, so a grid wide enough to reach the clamp reports an interval
bounded by a guard rail. [[tax-model|V1.6d]]'s finding, in the session immediately after it.

Full argument: [[sector-model]] §7–8.

---

Related: [[index]] · [[ROADMAP]]
