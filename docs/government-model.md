---
title: Government Model
tags:
  - decision
  - government
  - simulation
---

# Government Model

The government-formation model, as built in [[v1|V1.1a]]. What a government
*is*, how each nation assembles one, how a coalition's agreed position is
derived, and what it takes to bring a government down.

Same standard as [[economy-model]], [[opinion-model]], [[election-model]] and
[[legislature-model]]: a **game model**, judged on whether the player's
decisions produce a legible, attributable political outcome — not on whether it
would survive a comparative-politics seminar. Where realism and legibility
conflict, legibility wins, and the trade is noted.

## What changed, and why it had to

Before this block a government was one string, `ns.incumbent_party_id`, and the
player survived by being the **largest party** after a national election. Two
things were wrong with that, and the second is the load-bearing one.

**A government is not a party.** No nation on the roster is governed by a single
party holding a plurality; nine of the ten are governed by coalitions. Laws
were resolved against a flat `GOVERNMENT_BONUS` given to one party, so the
assembly had no notion of who was actually in government.

**France's player term was the wrong term.** `data/nations/FRA.json` gave the
player the title *President of the Republic* but tied their term to
`government.election.next = 2029-06` — the **Assembly's** election. France runs
two clocks. The presidential election is **18 April / 2 May 2027**, five-year
term; the legislative election is **June 2029**, five-year term. Conflating them
meant the player's office was decided by a vote that, in the real constitution,
cannot remove them.

Correcting it makes the first playable term **16 months, not 41** — game start
is January 2026 — and it turns the 2029 legislative election into a mid-term
shock that reshapes the assembly without ending the presidency. That is a better
game as well as a truer one: the player gets a verdict fast, then has to govern
through an assembly they may no longer control.

## Two clocks

`government` in each `data/nations/*.json` now holds three blocks where it held
one.

| Block | Contents | Required |
|---|---|---|
| `legislative` | `chamber`, `assembly_seats`, `term_years`, and the `election` block [[electoral-systems]] already defined | Always |
| `executive` | `title`, `term_years`, `next: {year, month}` | **Only where the executive is elected separately from the assembly** |
| `formation` | `method`, `censure`, `head_of_government_title`, `head_of_government_name` | Always |

**`executive` absent means the executive is drawn from the chamber**, and its
term *is* the legislative term. Of the ten, only **France** has the block. That
presence/absence is what expresses the semi-presidential/parliamentary
distinction, reusing the "field exists, reader does nothing" shape
[[electoral-systems|EU membership]] already uses — so `Elections._tick_nation()`
has one code path, not two.

`ns.term_months`, `ns.months_in_term`, `ns.terms_served` and `ns.in_government`
all now refer to the **player's** term: the executive's where one exists, the
legislature's otherwise. Only an **executive** election can set
`in_government` false.

**Since V1.2b**, *why* it goes false is named rather than inferred
from `has_executive`: `ns.lose_condition` (`executive_election_defeat` for
France, `party_not_largest` for the other nine, `never` for CHE's collegial
executive) and a separate `ns.term_limit` check, which ends the run without
resolving a vote at all for an incumbent who is not on the ballot. Both are
copied onto `NationState` from the nation's declared political-system
template. Full argument: [[political-systems]].

## Formation as a method, not a branch

[[engine-decision|Rule 1]] still applies: no `if nation_id == "FRA"` anywhere.
Each nation's `government.formation` names a **method**, and
`src/sim/government.gd` dispatches on that string — the same pattern
`src/sim/electoral_systems.gd` set for seat allocation.

| Method | Used by | What it models |
|---|---|---|
| `presidential_appointment` | FRA | The President appoints a Prime Minister. **No investiture vote** — a government stands until it is censured. |
| `chancellor_election` | DEU | Head of government elected by the chamber on an absolute majority of its statutory membership (*Kanzlermehrheit*). |
| `investiture` | ESP, ITA | Confirmed by an investiture or confidence vote after appointment. |
| `coalition_negotiation` | BEL, NLD, AUT, LUX | Formed by bargaining between parties and appointed by the head of state. |
| `largest_party` | GBR | The largest party forms a government; no investiture vote. |
| `directorial` | CHE | The Federal Council is seated by formula and **cannot fall**. |

All authored, **only the player's resolved** — the same split
[[electoral-systems]] makes for the election schedule, and for the same reason:
there is no opinion model computed for the other nine, so there is nothing for
them to re-form against. Authoring all ten now costs one data field each and
means [[v1|V1.2]] giving a second nation a government is a data change.

Every rule and date was checked against a source at build time, not carried
over from training data. Sources are in each nation file's
`government.formation._note` and `government.executive._note`.

## A coalition is a point in ideology space

The spine of the model, and the reason it adds no new equation.

A coalition's **agreed position** is the **seat-weighted mean** of its members'
`SLOT_POSITION` — a point in the same two-axis space
(`src/sim/election_constants.gd`) that [[election-model]] already puts every
party on and [[legislature-model]] already puts every law in.

```
position(C) = Σ seats[p] · SLOT_POSITION[p.ideology_slot] / Σ seats[p],  p ∈ C
```

A parallel coalition-preference matrix was rejected for exactly the reason
[[legislature-model]] rejected a second ideology vocabulary for laws, and
[[election-model]] rejected a direct bloc-to-slot matrix: numbers nobody could
individually defend, retuned as a group at every balance pass. The one new
quantity here is a mean of numbers that already existed.

Because the position lives in that space, the flat `GOVERNMENT_BONUS` becomes an
**earned** bonus with no new plumbing:

```
cohesion(p) = exp(−(|SLOT_POSITION[p] − position(C)| / COALITION_SIGMA)²)
bonus(p)    = COALITION_BONUS_MAX · cohesion(p) · discipline(p)    for p ∈ C
            = 0                                                   otherwise
```

Since [[v1|V1.1b]] that discipline factor is the **live** one, not the authored
one — a coalition whose members have stopped listening to their whips delivers
less on the government's own bills. See [[discipline-model]].

A partner dragged a long way from its own ideology to join is a less dependable
vote on the government's bills than the party that wrote them. Opposition still
gets nothing, exactly as before.

## The formation search

Greedy, outward from an anchor, and **fully deterministic — no `rand()`
anywhere**, the same discipline `economy.gd`, `budget.gd`, `opinion.gd`,
`elections.gd` and `legislature.gd` all keep, and what
`tests/test_budget.gd`'s projection-equals-reality guarantee depends on.

1. **Anchor.** The executive's own party under `presidential_appointment`; the
   largest party under every other search method.
2. **Target.** More than `MAJORITY_FRACTION` of the chamber.
3. **Add** the compatible party closest to the coalition's *current* agreed
   position, then **recompute that position** and repeat. A third partner is
   judged against the government being built, not against the anchor alone.
4. **Stop** at a majority, or when no compatible candidate remains — which
   yields a **minority government**, a legal outcome and not a failure.

Ties break on `[distance, −seats, party_id]`, so the outcome never depends on
the order the roster happened to be authored in.

### Two things a party will refuse

**A cordon.** `excluded_partners` in `data/parties/*.json` names the parties a
party will not govern with. Read **symmetrically**, so a cordon is authored once
— on the party that draws it — and authoring order cannot change the outcome.
The authored cordons model real relationships against the invented roster:
Belgium's is the strictest, every federal party refusing the Flemish nationalist
right; Germany's firewall holds across all four mainstream parties; the Dutch
one is authored as broken, because it broke in 2024; Switzerland has none,
because the Federal Council seats everyone by formula.

**Too great a distance.** A party further than `MAX_PARTNER_DISTANCE` from the
agreed position refuses regardless of arithmetic. Without this the greedy search
buys any seat that closes a gap: on the authored Italian roster it seated a
left-populist party in a nationalist-right government, because the left's cordon
had excluded everyone else and nothing else reached 201. A minority government
is the honest answer, and Italy has had plenty.

## Censure

Four rules, dispatched the same way, matching how the ten actually differ.

| Rule | Used by | Threshold |
|---|---|---|
| `absolute_members` | FRA | An absolute majority of **all members** — 289 of 577. Abstentions and absences count as *against*. |
| `constructive_absolute` | DEU, ESP | An absolute majority that must simultaneously name a successor. |
| `simple_present` | ITA, BEL, NLD, LUX, AUT, GBR | A simple majority of those voting. |
| `none` | CHE | No censure motion exists. `censure_seats()` returns `assembly_seats + 1`, so any caller comparing against it fails safe. |

France's 289 is why the model produces drama without tuning. The authored roster
allocates to **162 / 115 / 104 / 92 / 52 / 52** on 577 seats, and **no two
parties reach 289** — so every majority government is at least three parties,
and a minority government falls only if the left and right opposition vote
together. That is the real French dynamic, and it emerges from data authored in
S2 for entirely different reasons.
`tests/test_government.gd` asserts the no-two-party property directly, so a
future roster edit cannot quietly remove it.

### How a party votes on a censure motion

**Hostility is the inverse of cohesion.** No new equation and no new constant —
the same Gaussian on distance from the agreed position that
`coalition_bonus()` uses, flipped:

```
hostility(p) = 1 − 2 · exp(−(|SLOT_POSITION[p] − position(C)| / COALITION_SIGMA)²)
             − discipline(p)                            if p ∈ C
             + DISAFFECTION · unpopularity · (1 − d)    if p ∈ C
             + FORCE_HOSTILITY_BONUS  if the motion follows a forced bill
             → clamped to [−1, +1]
```

Subtracting `discipline` means a disciplined partner does not vote down the
government it signed up to, while an ill-disciplined one that has **drifted** far
from the line might — and a partner that votes for censure is **expelled**,
barred from the replacement until the next legislative election clears the slate.
That is the mechanical cost of a censure the player survives.

The `DISAFFECTION` term is [[discipline-model|V1.1b's]], and it is the only term
here that can turn a partner against a government it agrees with. Cohesion asks
whether a party likes the policy; disaffection asks whether its members want to
be standing next to this government at the next election. It is exactly zero at
or above neutral approval, so nothing in the V1.1a balance below moves. That note
records the measurement which forced it: the formation search builds coalitions
out of parties *close* to the line, so without a term like this one, eroding
discipline could never move the censure tally by a single seat.

Since V1.1b a party is no longer one bloc either. Its line is `hostility()` and
its members unwhipped are `hostility(whipped = false)`; where those read as
different votes, a share of the party's seats set by [[discipline-model]] votes
the second. `party_votes` still names the party's line, and only that line
expels a partner — backbenchers who walk are not a defection.

`FORCE_HOSTILITY_BONUS` is the entire risk in Article 49.3. Without it, forcing
would be free: the seats that would censure a government are the seats that
would already have voted the bill down, so the motion could never reach a
threshold the bill itself did not.

### Article 49.3

`Legislature.propose(state, loader, law, force := true)`. The bill is **adopted
with no vote taken** — every seat tally in the result is zero because there was
no division — and the assembly may censure the government instead. If the motion
fails, the law stands and the government survives.

Gated on `formation_method == "presidential_appointment"`, not on the nation id:
49.3 belongs to one constitution. Every other method refuses the command
outright rather than silently adopting a bill without a vote.

**Forcing costs approval whether or not the motion carries.** This is the one
place the model asserts something the constitution does not. Without a cost on
use, 49.3 is **strictly dominant** — any government that covers the censure
threshold would force every bill it could not win, for nothing. That is the same
defect class [[opinion-model|`SALIENCE_GAIN`]] documents from the S10 balance
pass: a free action with an unbounded upside. The 2023 pension reform survived
censure by nine votes and cost the government heavily in the polls; surviving is
not getting away with it. Routed through the existing `bloc_offset`
accumulator, so inertia and every bound in [[opinion-model]] still apply.

### What is deliberately not built

**`constructive_absolute`'s successor requirement.** Germany and Spain can only
remove a head of government by simultaneously electing a replacement. The
threshold is authored and resolved correctly; the successor half is not
modelled, because **only the player's nation resolves a censure motion** and the
player is France, which uses `absolute_members`. Building it now would be code
with no caller. It lands with [[v1|V1.2]], the same session that gives a second
nation a budget and an opinion model.

**Opposition-initiated censure.** A motion is only ever triggered by the player
forcing a bill. Tabling one on the assembly's own initiative needs party AI with
its own agenda, which [[v1|V1.1b]] did not build either — it made discipline live
and divisions seat-level, not the assembly self-directing — so this remains
future work; [[v1|V1.1c]] built dissolution instead. In practice it is close to
the real distribution anyway: French censure motions are tabled often and almost
never carry, and the one that carried in December 2024 followed a 49.3.

### The second chamber and the court

[[v1|V1.1e]] adds the two checks this file's own clocks and rules had been citing
since V1.2c without modelling: `data/nations/DEU.json` carried *"there is no
Bundesrat in this game"* as a declared stopgap, and `FRA.json` cited Art. 89's "both
chambers" and Art. 12's "the presidents of both chambers" for a chamber that did not
exist. Nothing about coalition formation, cohesion or hostility changes: the second
chamber has no government in it, so `form()` never runs against it and it cannot be
censured. What it DOES read from this file is `coalition_bonus()`, at a reduced
strength — a government's own parties are its own parties in both chambers, but it
cannot fall in the second one. `src/sim/chambers.gd`, `src/sim/judiciary.gd`,
[[upper-house-model]] and [[judiciary-model]].

`Government.penalise_blocs()` gains a fifth caller: overriding the second chamber
after a suspensive refusal is charged on the same accumulator Article 49.3, a fallen
government, a reshuffle, a resignation and a dissolution all already use.

### Dissolution

[[v1|V1.1c]] adds the player's other lever against a hostile chamber: rather
than surviving a censure motion, the President can end the current assembly
early and gamble on a better one. `src/sim/dissolution.gd`,
[[dissolution-model]]. Section 1 of that session's plan measured the gamble
before building it — a 57-seat spread between the worst and best approval a
player can hold while still in office — and found it already resolves through
the existing election model, so **`INCUMBENT_SWING` was left exactly as this
document describes it**; the cohabitation and censure balance notes below are
unchanged by V1.1c.

### Cabinet

[[v1|V1.1d]] adds a decision inside the government itself, rather than only
levers against or around it: coalition parties hold portfolios, and how well
each governs its department depends on the same coalition position and
discipline this file already computes. `src/sim/cabinet.gd`,
[[cabinet-model]]. `Government.cohesion()` — the Gaussian on distance from
the agreed position `coalition_bonus()` and `hostility()` both already used
inline — is extracted as a public function there for `Cabinet.loyalty()` to
reuse; nothing about coalition formation, cohesion or hostility changes.
Cabinet depends on Government one-way, never the reverse, so `Cabinet.seat()`
is called by the orchestrator immediately after every `form()`/`fall()` call
site rather than from inside this file.

| Constant | Value | Why |
|---|---|---|
| `FORCE_COOLDOWN_MONTHS` | 12 | Real 49.3 allows one non-budget bill per parliamentary session. A twelve-month lockout is the same shape without modelling sessions. |
| `FORCE_HOSTILITY_BONUS` | 0.35 | Turns an abstainer into a censure vote. Without it, forcing is risk-free. |
| `FORCE_BLOC_PENALTY` | −0.08 | The cost of bypassing the assembly, paid on every use. Prevents 49.3 being strictly dominant. |
| `FALLEN_BLOC_PENALTY` | −0.12 | Paid when a government actually falls, on top of the forcing cost. Larger, because a collapse is the more visible failure. |

## What the balance currently does with all this

> [!tip] Censure fires now — V1.1b, through the model rather than a retune
> This box used to read "censure works, and no played game reaches it". France's
> starting government holds **318 of 577** against a threshold of **289**, the
> opposition musters only **259** even provoked by a 49.3, and every legislative
> election in `tools/balance_probe.gd`'s fourteen-year run returned a
> presidential majority of 368–385. Nothing could close that gap.
>
> [[discipline-model|Party discipline]] closed it. A government's nominal seats
> are no longer the seats it delivers: discipline erodes with unpopularity and
> with an approaching legislative election, members break ranks on a division,
> and an eroded partner becomes willing to bring the government down. The probe's
> full table is in that note. In short: the three competent regimes hold at zero
> rebels across all fourteen years, the two tax extremes sit seven seats from the
> line, and `austerity` collects **343 of 289** within a year — a forced bill
> under it brings the government down.
>
> One caveat survives, and it is not this model's. No regime that *wins* its
> presidential election ever becomes unpopular enough to reach those states, so
> the censure branch is live in the sixteen months before May 2027 and not after
> it. That is the same `INCUMBENT_SWING` question cohabitation raises above, and
> it is still left as found.

## Cohabitation, and what the balance currently does with it

Cohabitation is **not a grand coalition**. The question the model asks is whether
a bloc organised *against* the President commands the chamber, so the
President's own party is **barred** from the rival search rather than merely not
anchoring it.

That bar is load-bearing. Without it the greedy search hands a centrist
President's party straight back to the opposition as its nearest available
partner — on a test assembly with the President reduced to 40 of 577 seats, the
opposition anchor took it in to reach 290 and cohabitation never triggered.
France 1986, 1993 and 1997 were opposition majorities, not power-sharing deals.

> [!warning] The branch is reachable but the current balance never enters it
> `tests/test_government.gd` proves cohabitation forms from a hostile assembly,
> and that a President whose own bloc can still reach a majority is *not* put
> into it. But across `tools/balance_probe.gd`'s fourteen-year run, **every
> legislative election under every regime that survives its presidential
> election returns a presidential majority of 368–385 of 577.** No played game
> currently reaches cohabitation.
>
> That is a balance question, not a formation bug: the incumbent-swing term in
> [[election-model]] plus a centrist President's party sitting close to most of
> the roster means the President's bloc can nearly always assemble 289. If
> cohabitation should be a live threat rather than a modelled possibility, the
> numbers to look at are `INCUMBENT_SWING` and the President's party's own
> `seat_share`, not anything in this file. Left as found, and recorded here
> rather than discovered again later.

## Constants vs content

`src/sim/government_constants.gd` holds every tunable, next to the other four
`*_constants.gd` files and not in `data/`, per [[engine-decision|Rule 1]].

| Constant | Value | Why |
|---|---|---|
| `MAJORITY_FRACTION` | 0.5 | More than half the chamber. A government at or below is a minority government. |
| `COALITION_SIGMA` | 0.9 | **Looser** than [[legislature-model]]'s `LAW_SIGMA` (0.6), not tighter: a coalition partner has signed an agreement, so it tolerates more distance on an individual bill than a party judging that bill cold. At this sigma a partner one axis-width from the line still delivers roughly half the bonus. |
| `COALITION_BONUS_MAX` | 0.45 | Ceiling on the earned bonus. A little above the old flat 0.35 because it is now earned rather than given — a distant or ill-disciplined partner scores well below the old flat rate. |
| `MAX_PARTNER_DISTANCE` | 1.2 | A little beyond one full axis-width in a space whose axes each run [−1, +1]. Wide enough for a grand coalition across the economic axis, narrow enough to refuse the opposite corner. |
| `DIRECTORIAL_MIN_SEAT_SHARE` | 0.14 | Switzerland's magic formula seats the four largest parties; at the authored Swiss roster this cut-off selects exactly those four. |
| `CENSURE_ABSOLUTE_FRACTION` | 0.5 | Half the membership, exceeded — France's 289 of 577 is exactly this. |

`discipline` and `excluded_partners` are **content**, in `data/parties/*.json`,
because they describe particular invented parties rather than the model. Party
discipline as a *mechanism* — erosion, rebellions, defection on individual votes
— shipped in [[v1|V1.1b]] and is [[discipline-model]]; the authored figure is now
the **ceiling** on a live quantity rather than the quantity itself.

## Why nothing diverges

| Quantity | Bound |
|---|---|
| `position(C)` | A seat-weighted mean of points inside the [−1, +1] square, so inside it by construction. Asserted every month of a 168-month run. |
| `coalition_bonus(p)` | `[0, COALITION_BONUS_MAX]`: a product of a Gaussian in `(0, 1]`, a discipline in `[0, 1]`, and the ceiling. Live discipline is a subset of that interval, so V1.1b does not widen it. |
| `support(p, law)` | Still clamped to `[−1, +1]`, unchanged from [[legislature-model]]. |
| `coalition_seats` | A sum of seat counts drawn from `seats_by_party`, so bounded by `assembly_seats`. |
| `hostility(p)` | Clamped to `[−1, +1]` by construction; the disaffection term is bounded by `DISAFFECTION · 1 · 1`. |
| A censure tally | The three columns sum to `assembly_seats` exactly: a rebellion moves seats between them and never creates one — see [[discipline-model]]. |
| `bloc_offset[bloc]` | The censure and 49.3 penalties are clamped by the same `BLOC_OFFSET_MIN/MAX` a law's own offset is, and clamped again with the satisfaction score before reaching `APPROVAL_SPAN` — see [[legislature-model]]. Repeated forcing cannot walk approval down without bound. |
| `censure_barred_party_ids` | Grows to at most the roster size, and is emptied at every legislative election. |
| Formation itself | Terminates: each round adds one party from a finite roster and never removes one. |

No quantity here accumulates. A formation is computed fresh from
`seats_by_party` whenever the assembly changes, so there is no accumulator to
drift — the failure mode [[opinion-model|`SALIENCE_GAIN`]] documents cannot
arise in this module.

The argument is not the evidence. `tests/test_government.gd` forms a government
for all ten nations, asserts no cordon is ever crossed and no partner ever sits
past the distance cap, asserts the censure threshold matches each authored rule,
and runs 168 months through three presidential and three legislative elections
checking every month that the government is non-empty, headed, and inside its
bounds. `tests/test_government_panel.gd` covers the majority, minority and
cohabitation readings of the screen. `tests/test_censure.gd` covers hostility's
bounds and sign, a strong government surviving 49.3, the approval cost of
forcing measured against winning the same vote outright, the cooldown blocking
and then expiring, every non-French method refusing the article, a weak
government being censured and replaced, defectors being barred, the bar clearing
at a legislative election, Switzerland never falling, and a parliamentary head of
government losing the run to a carried motion.

## Where it sits

```
clock.month_elapsed
  → Economy.tick_month(state)
  → Budget.tick_month(state)
  → Opinion.tick_month(state)
  → state.append_history()
  → Discipline.tick_month(state, loader) erodes/recovers; reads approval
  → Legislature.tick_month(state)        cooldowns; reads coalition_position
  → Elections.tick_month(state, loader)  legislative → Government.form()
                                         executive   → win/lose, then form()
```

`Government` has no tick of its own. Forming a government is not a monthly
event — it happens when the assembly changes, which is at a legislative
election, when a re-elected executive appoints afresh, or when a censure motion
carries. That is the same shape `Budget.commit()` and `Legislature.propose()`
already have: a command at a boundary, not a per-month update.

The one per-month thing this model owns is the Article 49.3 cooldown, counted
down inside `Legislature.tick_month()` alongside the per-law cooldowns that were
already there rather than in a tick of its own.

---

Related: [[index]] · [[election-model]] · [[electoral-systems]] ·
[[legislature-model]] · [[discipline-model]] · [[dissolution-model]] ·
[[cabinet-model]] · [[opinion-model]] · [[data-architecture]] · [[v1]]
