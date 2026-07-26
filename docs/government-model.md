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
bonus(p)    = COALITION_BONUS_MAX · cohesion(p) · p.discipline     for p ∈ C
            = 0                                                   otherwise
```

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
[[ROADMAP|S2]] for entirely different reasons.
`tests/test_government.gd` asserts the no-two-party property directly, so a
future roster edit cannot quietly remove it.

**Resolving a censure motion, Article 49.3, and government collapse are the next
session's work.** This block builds formation, the agreed position, the earned
bonus, and the threshold arithmetic the screen reads.

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
discipline as a *mechanism* — rebellions, whipping, defection on individual
votes — is [[v1|V1.1b]]; `discipline` here is only a scalar on the coalition
bonus.

## Why nothing diverges

| Quantity | Bound |
|---|---|
| `position(C)` | A seat-weighted mean of points inside the [−1, +1] square, so inside it by construction. Asserted every month of a 168-month run. |
| `coalition_bonus(p)` | `[0, COALITION_BONUS_MAX]`: a product of a Gaussian in `(0, 1]`, a discipline in `[0, 1]`, and the ceiling. |
| `support(p, law)` | Still clamped to `[−1, +1]`, unchanged from [[legislature-model]]. |
| `coalition_seats` | A sum of seat counts drawn from `seats_by_party`, so bounded by `assembly_seats`. |
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
cohabitation readings of the screen.

## Where it sits

```
clock.month_elapsed
  → Economy.tick_month(state)
  → Budget.tick_month(state)
  → Opinion.tick_month(state)
  → state.append_history()
  → Legislature.tick_month(state)        cooldowns; reads coalition_position
  → Elections.tick_month(state, loader)  legislative → Government.form()
                                         executive   → win/lose, then form()
```

`Government` has no tick of its own. Forming a government is not a monthly
event — it happens when the assembly changes, which is at a legislative
election, or when a re-elected executive appoints afresh. That is the same shape
`Budget.commit()` and `Legislature.propose()` already have: a command at a
boundary, not a per-month update.

---

Related: [[index]] · [[election-model]] · [[electoral-systems]] ·
[[legislature-model]] · [[opinion-model]] · [[data-architecture]] · [[v1]] ·
[[ROADMAP]]
