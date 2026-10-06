---
title: Referendum Model
tags:
  - decision
  - government
  - simulation
---

# Referendum Model

V1.7c, the last session of the V1.7 block. Two things that turn out to be one shape: a
constitutional amendment ratified by **the country** instead of by a supermajority of
the assembly, and the electoral system becoming something a player can change. Both are
edits to `effects.institutional`; they differ in what bar they clear, and that
difference is the session's correction to its own row.

Two stopgaps are discharged, both declared in advance and both pointing here by name:
`src/core/nation.gd`'s `KNOWN_AMENDMENT_RULES` carried `referendum_required` with *"no
referendum mechanic exists yet (V1.1f/V1.7)"* beside it, and
`legislature_constants.AMENDMENT_RULE_FRACTIONS` deliberately had no entry for it. Three
other places pointed here: [[v1|§1]]'s own bullet list, the re-parked **V1.1f** row, and
[[bloc-model]]'s "a bloc you can leave needs a referendum".

## 1. Instance forty-three: the row is right about the channel and wrong about the bar

[[v1|§7]] asks for electoral-system choice as *"a seventh `effects.institutional` key"*.
`law.gd` refuses that channel on any law that is not `constitutional: true`, and
`constitutional` forces `majority: "amendment"` — so the row's own wording **entrenches
the electoral system at each nation's amendment threshold**.

That is wrong for the nations that matter. Electoral law is **ordinary legislation** in
essentially all ten: France's code électoral (changed by ordinary law in 1985 and again
in 1986), Germany's Bundeswahlgesetz (2023), Italy's Rosatellum, Britain's ordinary Act.
It is right for GBR alone, and only by accident — GBR's `amendment_rule` *is*
`ordinary_law`. Wrong for two of the three playable nations.

So `law.gd`'s institutional whitelist **splits**. `ORDINARY_INSTITUTIONAL_KEYS` holds
`election_system`, `ORDINARY_INSTITUTIONAL_FLOAT_KEYS` holds `election_threshold_pct`,
and every entrenched key still requires `constitutional: true` — with an error string
that names the rule rather than reporting an unrecognised field. That is V1.4a/V1.4b's
own split written into the schema rather than only into the docs — a subsidy reaches
`effects.company` directly and a regulation reaches it through an assembly division —
one block later and in the other direction.

**No template constrains either key and none could.** `constitutional_monarchy` alone
covers `fptp`, `pr_dhondt` and `pr_national` across GBR, ESP, BEL, NLD and LUX, so an
`allowed_election_systems` field would be a constraint with nothing to say.
`term_months` is the precedent: bounded by its own range check and by no template.

## 2. A referendum is a second ratification stage, not a bypass

The design that suggests itself is *put it to the people instead of the assembly*, and
**not one of the ten constitutions works that way**. Every citation was already sitting
in the nation files' own `government.amendment._note`, authored at V1.2c for a mechanic
that did not exist:

| Nation | What its own note says | Mode |
|---|---|---|
| FRA | Art. 89: both chambers pass the bill, then **either** a popular referendum **or** — the President's choice — Congress at 3/5 | `optional` |
| ITA | Art. 138: a second vote at absolute majority is open to a confirmatory referendum; only 2/3 is referendum-proof | `optional` |
| ESP | Art. 167: a referendum is held if one tenth of either chamber's members ask | `optional` |
| LUX | Art. 114: two simple-majority votes then a binding referendum, unless 3/4 waives it | `optional` |
| CHE | Art. 195: a mandatory popular vote, with no seats-only path at all | `mandatory` |
| DEU | Art. 79 provides no referendum at any stage | `none` |
| GBR | Parliament amends by ordinary Act; UK referendums are ad hoc and statutory | `none` |
| BEL, NLD | entrench through a dissolution and re-election, not a popular vote | `none` |
| AUT | Art. 44(3), referendum only for a **total** revision, which no content here writes | `none` |

All the live ones are the **same shape**: the referendum replaces the **supermajority**
with an ordinary majority plus a popular vote. So route A (the assembly at the nation's
own `amendment_rule`) is untouched, and route B is a majority of votes cast in the
chamber and then `REFERENDUM_MAJORITY` at the ballot box. Neither is a subset of the
other — route B is easier inside the chamber and harder outside it.

`government.amendment.referendum` is the **seventh** instance of the
dispatch-on-a-data-string pattern `formation_method`, `censure_rule`,
`dissolution_rule`, `lose_condition`, `head_of_state_kind` and `amendment_rule` already
use, and it is per-nation and not per-template for `permits_system_change`'s reason: one
template covers nations with a route and nations without.

**`referendum_required` gains a seat fraction**, which is the literal discharge. Art. 195
does not remove the Federal Assembly's vote, it adds a popular one on top, so the
chamber's bar is an ordinary majority and what makes the rule *mandatory* is the
nation's own mode. `resolve_vote()`'s `push_error()` arm becomes unreachable rather than
being deleted.

**The chamber's bar is `simple` and not `absolute`, and the probe settled it.** Art. 89's
first stage is the ordinary legislative procedure, a majority of votes **cast**. Read as
an absolute majority of members, abstentions count against and route B came back at 270
of the 289 seats it needed in **every one of 168 months** — unreachable in a played run.
Luxembourg and Switzerland read the same way; **Italy is the outlier**, whose Art. 138
second vote is explicitly absolute, and that divergence is recorded here rather than
modelled per nation, the way [[electoral-systems]] records a per-method reduction.

## 3. The popular vote is `vote_share()` with two options

Not a new model. Per bloc, exactly the structure `Elections.vote_share()` already uses
for parties, with two "parties":

- **YES** at the law's own authored `position`, on the same two-axis space
  `election_constants.SLOT_POSITION` uses. Every amendment has carried one since V1.2c.
- **NO** at `status_quo_position()`, the **size-weighted mean of `BLOC_IDEAL`** —
  measured at **(−0.230, +0.084)**, derived from a table written at S5 for unrelated
  reasons rather than authored. [[media-model|V1.5d]]'s mean anchor, one block on. A
  per-nation authored status quo would have been ten numbers with no dataset behind
  them, in the one place where a dataset could never exist because the quantity is
  invented.
- Both weighted by affinity at the existing `AFFINITY_SIGMA` and renormalised per bloc;
  the bloc's weight is `BLOC_SIZE × Campaign.turnout_of()`.
- **YES carries the incumbent's per-bloc approval pull** on the existing
  `INCUMBENT_SWING`, because a referendum called by an unpopular president is a vote on
  the president. De Gaulle resigned on one in 1969 and the arithmetic says so with no
  term authored for it.

**Two properties nobody authored fall out.** A referendum held inside [[campaign-model|
V1.7a]]'s presidential run-up reads whatever mobilisation the campaign bought, for free
and with no edge anywhere — so *when* to hold it is a real decision. And one held
outside the run-up reads `BLOC_TURNOUT` **bit-for-bit**, because `Campaign.turnout_of()`
returns the authored constant exactly at mobilisation 0.0. `tests/test_referendum.gd`
asserts that with exact equality, and it is what let the whole layer go live with the
balance harness bit-identical across every existing regime.

The plan-time arithmetic predicted `abolish_term_limits` at **45.8 %** yes, spanning
business 67.4 % to students 24.6 %. Measured against live state: **0.458**, business
**0.674**, students **0.246**. Recorded because the agreement is the evidence that the
construction is arithmetic rather than a tuning.

## 4. Scheduled, and what the register is

`ns.referendum_pending` is `{law_id, months_left, position}`, on `NationState` for all
ten and inert for the nine. [[projects-model|V1.6f]]'s commitment-in-flight rather than
[[calendar-model|U6a]]'s deferred command: it bills nothing and it cannot be undone for
free. The **position is copied in at announcement** rather than re-read at resolution,
so the country answers the question it was asked; content cannot change under a live
vote.

**No new tick anywhere.** `Legislature.tick_month()` already existed, already counted
cooldowns down, and is already called by `src/ui/main.gd`, `tools/balance_probe.gd`,
`tests/test_balance.gd` and eight probes. The countdown and the settlement go there,
beside the cooldown tick — `diplomacy.gd`'s `_tick_agenda()` precedent. Its signature
widens to `tick_month(state, loader)` because settlement calls `apply()`; **required and
not defaulted**, on the reason `legislature.gd` already gives about `apply()`'s own
loader. That is [[cycle-model|V1.6a]]'s argument taken deliberately: [[media-model|
V1.5d]] shipped with neither balance harness calling `Media.tick_month()`, so both ran
the pre-session model and their agreement about a bit-identical re-run was about
nothing. A referendum reached through a call they all already make cannot repeat it, and
`tests/test_referendum.gd` reads **both harnesses** and fails if either omits the
widened call.

`src/sim/referendum.gd` is a **leaf**. `resolve_due()` returns the verdict as **data**
and `legislature.gd` applies the law — [[calendar-model|U6a]]'s `due()` one block on,
and the reason that file could preload nothing. The test reads the source and fails if
`legislature.gd` or `elections.gd` appears in it: the popular vote reuses the *formula*,
not the module.

## 5. The price, and why withdrawal needs no second constant

Route B is otherwise free, and the effective amendment bar becomes
min(supermajority, popular majority) — the strictly-dominated shape this project has
killed ten times. One signed constant, `REFERENDUM_RESULT_OFFSET`, on `ns.bloc_offset`:
[[pledge-model|V1.7b]]'s landing site, because trust in a promise and the standing of a
president who called a vote and lost it are both squarely **at** the ballot box rather
than outside it. Won, it is a mandate; lost, a rebuke. Signed both ways for V1.4b's and
V1.5b's reason: a one-way charge makes calling one strictly worse than not calling one,
which is the same failure mirrored.

**Withdrawing costs exactly what losing costs, and that is a proof rather than a fitted
second constant.** A withdrawal charges the same offset *and* sets the same cooldown, so
holding the vote **weakly dominates** withdrawing by construction: the two outcomes are
identical except that holding it might carry. A withdrawal priced below a loss is
strictly better than governing through a referendum you might lose — the free-hedge
shape — and one priced above needs a number solved against the first, which is what
`investment_action.gd` refuses as one strength written twice. What withdrawal buys is
the register slot back this month rather than in `REFERENDUM_DELAY_MONTHS`. Small, real,
never free. `tests/test_referendum.gd` proves it by withdrawing from one state, losing
from an identical one, and requiring the same `bloc_offset` on every bloc.

## 6. The probe corrected the session four times, twenty sessions running

**(i) The verb was unreachable, twice, for two different reasons.** First the chamber
bar (§2), which was the model's. Then the content: France's only amendment,
`abolish_term_limits`, is rejected **270–307** by its own assembly, so with the bar
fixed the verb was still never offered. A position sweep over the ideology grid against
France's live assembly found a real window — economic −0.4…−0.2, social −0.1…0.0, where
the yes-seat fraction is 0.534–0.551, **above an ordinary majority and below 3/5**. That
window *is* the referendum: the only route to a bill the chamber will carry and the
supermajority will not. `single_term_reform` is authored into it at (−0.3, 0.0) — the
Jospin commission's *mandat unique*, a real French proposal — and V1.4b's discipline
holds: the fix was **content**, not a constant.

**(ii) The kill switch was measuring a state the player cannot reach**, and it is the
session's sharpest correction. Table R1 swept approval from 30 to 65 and **cleared** —
four of seven amendments winnable "somewhere". Table R6 then measured what a French
president actually holds under a budget they can stay in office on: **40.0 to 50.3** over
fourteen years, against a crossover at ~52. The verb was winnable only at approvals no
reachable government has. [[foreign-policy-model|V1.3f]]'s measuring-the-wrong-state
error, a fifth time, in the file written to avoid it — and the lesson generalises: **a
kill switch that sweeps a range the player cannot reach is not a kill switch.** The
probe now measures the reachable range **first**, in table R0, and every approval band
below is written inside it.

**(iii) The escalation fired and was honoured.** `STATUS_QUO_PULL` was declared in
`referendum_constants.gd` before the sweep ran — status-quo bias made explicit — with
the alternative (raising `INCUMBENT_SWING`) refused in advance because that constant is
measured for the election and moving it re-baselines every election this project has
ever run. Selected by putting the crossover **nearest the middle** of the reachable
range, the only tiebreaker that does not privilege one outcome: a crossover at either
end makes one result the default.

**(iv) The probe's own player was nobody.** The first reachability table called a
referendum every month it was legal, lost **24 of 25**, and drove its own approval down
with each loss. That measures a player who does not exist. A *rational* player calls one
only when the yes share is already over the bar — and against that player the verb is
reachable, both outcomes occur, and the dominance in §5 is strict rather than vacuous.
V1.3f's error in its other costume: the state was reachable and the **behaviour** was
not.

## 7. Constants

`src/sim/referendum_constants.gd`. **The popular vote itself ships nothing** — every
number in §3 already existed and was measured for something else.

| Constant | Value | How it was chosen |
|---|---|---|
| `STATUS_QUO_PULL` | 0.90 | Band: the crossover approval must lie strictly inside the reachable range [40.0, 50.3]. Passing 0.80–0.95; nearest the middle (45.1) is 0.90, at a crossover of **46.42**. Interior to the passing set and to the grid. Fixed point |
| `REFERENDUM_DELAY_MONTHS` | 11 | Band (i): median drift in yes share over N months must exceed one point of approval (0.4387 pts) — fails to 6, passes from 8. Band (ii): ≤ 16, the first playable term; swept to 24 so the upper edge is proved to be the model's. Maximin slack picks 11 at 0.313. Fixed point |
| `REFERENDUM_RESULT_OFFSET` | 0.175 | **Closed form.** The approval response is exactly linear at 10.0000 points per point of offset, so band (i) solves to [0.1000, 0.3000] and band (ii) — four results reachable in fourteen years — to below 0.2500. Midpoint of [0.1000, 0.2500]. Band (ii) binds above, so the clamp is a guard rail |
| `REFERENDUM_MAJORITY` | 0.5 | Not swept and not tunable: a referendum carries on a majority of votes cast |

**Switzerland's real double majority of the people *and the cantons* is not modelled** —
this game has no cantons — and that is a named reduction of the same class as
[[electoral-systems]]'s per-method caveats, not an oversight.

## 8. What Germany does not get

The ROADMAP's decomposition argued that referendums join this session because *"a
referendum exists precisely because a supermajority is sometimes unreachable, and this
block measured exactly that for Germany"*. True in the abstract, and **it does not
resolve for the nation it was named about**: Art. 79 provides no referendum at any stage
of a Basic Law amendment, and the Basic Law has no national referendum at all. Germany's
`two_thirds` stays measurably unreachable and `restore_the_monarchy`, which targets
`parliamentary_republic`, stays unpassable content. Recorded rather than fixed —
inventing a German referendum to rescue a mechanic would be the detuned number
[[amendment-model]] refused for the same nation three blocks earlier.

## 9. Save format

`SAVE_VERSION` **24 → 25**, on three fields of four, and they fail the rule by three
different failures, so `tests/test_save_load.gd` asserts them separately.

- `election_system` / `election_threshold_pct` — **lifted** from `Nation`, and the
  sharpest case since `military_capability`. Absent they read `""` and `0.0`;
  `ElectoralSystems.allocate()` falls through its match and **every seat allocation
  collapses to zero**. `NationState.from_dict()` never sees the loader — V1.6a's finding
  that statelessness is a property of the *module* and not of the save file — so a
  content-derived static fact cannot be re-derived on load.
- `referendum_mode` — static content, earning the bump for `eu_member`'s reason rather
  than its own: absent it reads `""`, a legal state for six of the ten and a silently
  different constitution for France.
- `referendum_pending` — absent, a referendum the country has already been called to
  **vanishes**, which is a free withdrawal of the one act this session deliberately made
  un-free. `campaign_started`'s case one commit earlier, and `diplo_months_to_act` at
  U6a.
- `last_referendum_result` — **not serialised at all**, `last_project_result`'s case.
  The *absence* is pinned, so a later session storing it turns the test red and has to
  say why.

The register carries a law id, a countdown and the question's own position, and nothing
else — V1.4a's discipline, and the position is there because the country must answer the
question it was asked.

## 10. Files

- `data/nations/*.json` (10) — `government.amendment.referendum`, each with its own citation
- `data/laws/amendments.json` — `single_term_reform`
- `data/laws/institutional.json` — `proportional_representation_act`, `two_round_voting_act`
- `src/core/nation.gd` — `referendum_mode`, the two-way consistency check, the rewritten `KNOWN_AMENDMENT_RULES` comment
- `src/core/nation_state.gd` — four fields; `src/core/game_state.gd` — 25
- `src/core/law.gd` — the institutional split
- `src/sim/referendum.gd`, `src/sim/referendum_constants.gd` — new
- `src/sim/legislature.gd` — the widened tick, route B, `can_put_to_referendum()`, `_already_in_force()`
- `src/sim/legislature_constants.gd` — `referendum_required`'s fraction
- `src/sim/elections.gd`, `src/sim/government.gd` — the lifts
- `src/sim/calendar.gd`, `calendar_constants.gd`, `src/ui/calendar_panel.gd` — the diary row
- `src/ui/law_panel.gd`, `src/ui/government_panel.gd`
- `tools/referendum_probe.gd` — new; `tools/balance_probe.gd`, `tools/screenshot.gd`, `tools/run_tests.sh`
- `tests/test_referendum.gd` — new; edits to `test_save_load.gd` and every harness calling `Legislature.tick_month`

---

Related: [[index]] · [[amendment-model]] · [[electoral-systems]] · [[election-model]] ·
[[political-systems]] · [[campaign-model]] · [[pledge-model]] · [[legislature-model]] ·
[[v1]]
