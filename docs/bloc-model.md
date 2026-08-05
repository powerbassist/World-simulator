---
title: Bloc Model
tags:
  - model
  - sim
  - diplomacy
---

# Bloc Model

The supranational bloc: what the council votes on, what a rule in force requires, what defying it costs, and what membership charges. Built at [[ROADMAP|V1.3d]], the fourth session of the V1.3 block.

Files: `src/sim/bloc.gd` (the rules) · `src/sim/bloc_constants.gd` (the numbers) · `src/core/bloc_proposal.gd` (the content type) · `data/bloc-proposals/*.json` (the content) · `GameState.bloc` (the register) · `tools/bloc_probe.gd` (the measurement).

> [!important] Comply and you pay in policy; defy and you pay in politics
> This is the session's central call and everything below follows from it. A rule in force does **not** refuse a budget — the player is head of state and sovereignty means they *can* break it. Complying costs the spending they could not run, which lands on the issues that were already there. Defying costs a penalty on the budget line and a share of the national agenda under a new issue. Both directions cost, which is what makes it a decision rather than a wall.

## The fourth kind of state

Per-nation state is on `NationState`. [[diplomacy-model|Relations]] and [[trade-model|agreements]] are symmetric pair state. [[coercion-model|Measures]] are directed pair state. A bloc rule is none of those: it is **one object binding eight nations at once**, and mirroring it onto each member would be the divergence the symmetric pair key was chosen to make impossible, committed at a wider scale.

`GameState.bloc` holds it — rules, the proposal before the council, the last division, and a two-integer scheduler. The scheduler is a countdown and an index, so the council survives a save with no generator state to serialise, the same property [[opinion-model|polling noise]] gets for free.

## 1. The `ISSUE_KEYS` question, and why it was answered yes

[[ROADMAP|V1.3a]], [[trade-model|V1.3b]] and [[coercion-model|V1.3c]] each priced their domestic cost through `bloc_offset` and each deferred this call here by name. The cost was named in advance: six new `BLOC_SALIENCE_BASE` rows, against which [[declined]] records that *every* tuned opinion constant was measured.

**Three structural reasons, none of them thematic:**

1. **`bloc_offset` never enters `issue_salience`.** `opinion.gd` builds the national agenda from the salience weights alone, so a Europe priced on the offset channel could never be named by the polling panel's *what the country is thinking about* list, nor by `elections.gd`'s `attribution()` — the two surfaces that exist to tell the player **why**. The session's headline mechanic would have been unnameable by the game's own readouts.
2. **A split price is invisible in the headline figure.** [[diplomacy-model]] measured it: an effect hitting fewer than all six blocs never clears the ±3.0 poll-noise floor in `overall_approval_pct`, because the roll-up is size-weighted. Europe divides the country by nature, so the one channel a–c used is the one channel this mechanic cannot use.
3. **`bloc_offset` cannot become more salient.** It is a flat additive on the target. A rule biting hard should raise how much the country *argues* about Europe, and `SALIENCE_GAIN` is the only mechanism that does that. It operates on issues only.

### The dilution, measured before it was taken

Every row summed to 1.0, so the normalised weight *was* the base weight at rest. Adding `europe` at weight `w` makes the row sum `1+w`, and `salience_weights()` renormalises — so every existing weight in that row is scaled by `1/(1+w)`.

S10's finding was a **ratio**: `public_finances` against the five spending lines. `tools/bloc_probe.gd` table (a) measures what happens to it.

| bloc | size | `europe` w | scale on the rest |
|---|---|---|---|
| workers | 0.30 | 0.10 | 0.909 |
| pensioners | 0.24 | 0.10 | 0.909 |
| urban | 0.15 | 0.06 | 0.943 |
| **rural** | 0.13 | **0.14** | 0.877 |
| business | 0.10 | 0.06 | 0.943 |
| students | 0.08 | 0.05 | 0.952 |

| | `public_finances` | five spending lines | ratio |
|---|---|---|---|
| before | 0.1961 | 0.3819 | 0.5135 |
| after | 0.1801 | 0.3493 | 0.5155 |
| | | | **+0.39 %** |

**The ratio moves by four tenths of a percent, and in the safe direction** — fiscal discipline is fractionally *better* rewarded, not worse. Per-bloc dilution is not uniform, so this is not preserved exactly and the table is measuring how far off exact it lands rather than asserting it.

`europe` takes **0.083** of the national agenda: fifth-largest of the twelve, above education (0.054), infrastructure (0.047) and defence (0.014), below jobs, public finances, health and pensions. For an issue that is a whole session's headline, being above defence was the floor to clear.

### The split falls out of a table written at S5 for other reasons

**The opinion model has no signed split.** Every satisfaction enters every bloc's score with the same sign; blocs differ only in *weight*. [[opinion-model]]'s tax split — *"income tax 20 → 30 %: workers 50 → 37, business to 57"* — is not one issue signing two ways, it is `tax_income` falling while `public_finances` rises.

So `europe` had to be **one-signed** — everyone dislikes being overruled — and the political split had to come from membership's economic upside landing on issues the blocs already weight unevenly. It does:

| bloc | `growth` | `public_finances` | net |
|---|---|---|---|
| business | 0.19 | 0.34 | strongly pro-bloc |
| urban | 0.10 | 0.17 | pro-bloc |
| workers / students | 0.08 | 0.18 / 0.14 | mixed |
| **rural** | — | 0.18 | sovereignty cost, thin upside |
| **pensioners** | — | 0.20 | sovereignty cost, no growth upside |

Pensioners and rural carry **no `growth` entry at all**: 37 % of the electorate structurally receives the constraint and none of the single market. A eurosceptic countryside and a pro-European boardroom, derived rather than authored.

### `EUROPE_SCALE` was swept, not reasoned to

`SALIENCE_GAIN` makes the response sharply non-linear, so the scale could not be argued from the burden's range. Measured against one rule defied outright:

| `EUROPE_SCALE` | peak approval move, FRA | verdict |
|---|---|---|
| 1.00 | −3.24 | clears ±3.0 by almost exactly nothing — [[scenario-model|`deu_grand_coalition`'s mistake]] |
| **0.80** | **−7.41** | matches [[coercion-model|a full embargo by the largest partner]] at −4.9 to −7.4 |
| 0.60 | −12.98 | defying one bloc rule twice as bad as being embargoed |

0.80, because defying a rule and being embargoed by Germany should cost about the same and the anchor is a figure this project already measured.

## 2. The rules, and the ceiling the severities sum to

```
burden(A) = Σ_rules severity_r × clamp(breach_r / tolerance_r, 0, 1)
            clamped to BURDEN_MAX
sat["europe"] = −(burden − start_burden) / EUROPE_SCALE
```

`tolerance` is the breach at which a rule counts in full, floored at load — a tolerance near zero turns a continuous quantity into a step, and the panel would show a cliff where the model claims a slope.

> [!warning] The probe's correction: the severities must sum to exactly the ceiling
> They were authored at 0.45 / 0.35 / 0.30 / 0.25 — **1.35 against a `BURDEN_MAX` of 1.0**. The clamp then removed 0.35 of real burden, so a player already defying three rules got **nothing** from breaching the fourth: the strictly-dominated shape [[coercion-model|the coercion probe caught]] for high tariff severity, in a new place. Rescaled to 0.33 / 0.26 / 0.22 / 0.19, summing to exactly 1.0, so the clamp *touches* at total defiance and never bites before. `tests/test_bloc.gd` asserts the sum, which is what stops a fifth rule reintroducing it silently.

**Zero for a member that complies**, and that is the point rather than an omission: a complying player pays in the policy they could not run, and that shows up on the spending lines they had to cut.

France begins in real breach of a 3 % deficit rule, and `start_bloc_burden` is captured at new-game like `start_deficit_pct_gdp` — so an inherited breach is politically free until the player moves it, exactly as its real 4.7 %-of-GDP starting deficit already is.

### What it costs, measured

Rules adopted at month 0 and held sixty months against a control on the same budget.

| actor | budget | rules | burden | peak approval | legible? |
|---|---|---|---|---|---|
| FRA | starting | 1 | 0.132 | −0.93 | no |
| FRA | starting | 2 | 0.327 | **−3.36** | yes |
| DEU | starting | 2 | 0.076 | −0.46 | no |
| FRA | defiant | 1 | 0.330 | **−7.41** | yes |
| DEU | defiant | 1 | 0.330 | **−11.45** | yes |
| FRA | defiant | 4 | 0.826 | −18.79 | yes |

**The escalation trigger did not fire**: one defied rule clears the ±3.0 floor with 2.47× to spare on the weaker of the two members.

The row worth reading is FRA/starting/2 against DEU/starting/2. France carries 116 % debt and a 4.7 % deficit and is in breach of *both* fiscal rules the moment they pass; Germany at 62.9 % debt is compliant with one of them. The same two rules cost France 3.4 points and Germany half a point, and nothing in the content says so — it is the nations' own starting books.

## 3. Transfers

```
net(A) = CONTRIBUTION_BASE + CONTRIBUTION_SPAN × (gdp_per_capita_A / bloc_mean − 1)
```

Derived from starting prosperity rather than authored — the treatment resting relations, [[cabinet-model|competence]] and the trade weight all get, and for the same reason: an authored table of ten net positions is frozen. Copied once onto `NationState` as a **static fact**, like `eu_member` and `neighbours`, which is what puts it inside `start_deficit_pct_gdp` where an inherited drag belongs.

| nation | GDP/capita (EUR k) | vs bloc mean | net % GDP | tax points |
|---|---|---|---|---|
| LUX | 122.6 | 2.759 | 1.179 | 2.36 |
| NLD | 62.2 | 1.401 | 0.500 | 1.00 |
| AUT | 53.5 | 1.204 | 0.402 | 0.80 |
| DEU | 51.6 | 1.162 | 0.381 | 0.76 |
| **FRA** | 42.4 | 0.955 | **0.277** | 0.55 |
| ITA | 37.1 | 0.835 | 0.218 | 0.44 |
| ESP | 32.6 | 0.733 | 0.167 | 0.33 |
| GBR / CHE | — | — | **0.000** | — |

France's 0.277 % lands on its real net contribution of roughly 0.25–0.30 % of GNI without being authored to. A non-member reads **exactly** 0.000, by construction rather than rounding.

It is a **line of its own on the spending side**, not a sixth `SPENDING_KEYS` entry: [[v1]] §6 keys the five spending lines 1:1 to cabinet portfolios, so a sixth line would be a sixth minister — and the player does not set this one with a slider. The tariff line's argument, in the other direction.

> [!note] Nobody in this roster receives, and that is the roster rather than the model
> Every member is a net contributor, because the ten nations are all rich Western European ones and the real cohesion flows go to members this game does not simulate. The field is signed and the sign is reachable through content: `recovery_facility` is −0.30 % of GDP, which takes France net-negative. Stated so it is a known consequence rather than a discovered one.

## 4. The council

A proposal reaches the council every `PROPOSAL_INTERVAL_MONTHS`, divides `VOTE_DELAY_MONTHS` later, and binds every member if it carries. The agenda is a rotating index over the loaded list in authored order — deterministic, no RNG, so a proposal already in force is skipped and one that *failed* can come back.

**The threshold is a share of the seats actually cast**, not of the council's whole strength, and that is the one thing making abstention a third option.

> [!warning] Under a whole-council denominator, abstaining and opposing are the same act
> `seats_for` is identical either way, so the outcome is identical, always — abstention would be a slower way of voting no. `tests/test_bloc.gd` caught it before it shipped. Against cast seats the three genuinely differ: backing it adds to the numerator, opposing it adds to the denominator and blocks, abstaining removes the player from both and lets it through on a smaller base. That is constructive abstention, and it is what the real Council does.

### The sweep that set `SUPPORT_SIGMA`, and the fix that was content

The first run had **six of seven proposals decided by France's own vote** — the *second legislature they happen to control* failure rather than *one member among many*.

| sigma | carried without the player | player decides | lost even with the player |
|---|---|---|---|
| 0.45 | 0 | 1 | 6 |
| 0.65 | 0 | 4 | 3 |
| 0.75 | 0 | 5 | 2 |
| **0.90** | **1** | **5** | **1** |
| 1.10 | 4 | 3 | 0 |

**The fix was content, not the constant.** The member-position list the probe prints is why: the other eight are clustered, so no sigma alone spreads the tallies. Moving `common_defence_floor` to where a defence commitment actually sits in ideology space — right and traditional — is what put a proposal out of France's reach. 0.90 is then the only value swept with all three columns non-zero.

France holds 81 of 393 member seats. `recovery_facility` carries on the other eight alone, so a France voting against it is **outvoted and bound** — which is the done-when condition, asserted rather than claimed. `common_defence_floor` fails even with France voting for it. Neither is dead content: member governments change at their own elections over a fourteen-year run, and the council's arithmetic moves with them.

## 5. The first reader of the directed register

[[coercion-model]] parked this here by name. A `common_external_tariff` writes `GameState.measures` for every (member, non-member) ordered pair through `Relations.directed_key()` — **the same key a player's own tariff uses**, so nothing in `src/sim/coercion.gd` or `src/sim/trade.gd` needed a line changed to read it. A pair already carrying a measure is left alone, because one measure per directed pair is a bound [[coercion-model]] states.

This is also what GBR and CHE get. They are not members, carry no burden and pay nothing — but a bloc acting as one is the only thing in this game that imposes from eight directions at once, and it is aimed at them. The [[transition-model|V1.2d cold read]] that found a session shipping to zero playable nations is the failure this avoids.

## 6. The council is the fourth declared stopgap

> [!success] Discharged at V1.3e
> ~~The other eight members vote on their `coalition_position` and **nothing else**.~~ They now appraise a proposal against their **own books**: what the rule would cost them given their current deficit, what the transfer would cost or pay them, what an external measure would cost their own trade, with ideology retained as one weak term among four. `cohesion_fund` is now voted down by every member and `recovery_facility` carried by every member -- the two proposals the old rule could not tell apart. They still never propose, which is V1.3f's.
>
> `tests/test_bloc.gd` asserted the old rule by mutation and **died at parse time**, because `support()` grew a `state` parameter. See [[foreign-policy-model]].

Fourth on V1.3e's checklist, behind [[diplomacy-model|V1.3a's no-reaction]], [[trade-model|V1.3b's accept-gate]] and [[coercion-model|V1.3c's fixed retaliation]]. The four compose rather than conflict: the others say the target does not react, does not decide, and reacts by a fixed rule — this one says the council votes its priors.

`tests/test_bloc.gd` asserts it **by mutation** — the member's GDP cut 100×, unemployment at 39 %, growth at −11 %, sectors gutted, two relations pairs moved and a full sanction imposed on it — and the answer must not move. **That test must fail and be rewritten at V1.3e.**

## The balance re-run

Ten regimes × three playable nations = **thirty fourteen-year runs**, captured from a worktree at the V1.3c commit and diffed against the rebuilt tree, `^ERROR:` and `^   at: ` stripped from both sides.

**Not bit-identical, and this session said in advance it could not be** — [[trade-model|V1.3b's]] and [[coercion-model|V1.3c's]] both were, because an agreement and a measure each need a player command and no regime issues one. A bloc rule needs no command at all: the council meets whether or not the player engages. **That is the difference between a verb and an institution, and it is why V1.3d needed no eleventh regime** where b and c each did.

What moved, over all 168 year-rows:

| quantity | max abs change | where |
|---|---|---|
| GDP | **0.0000** | — |
| growth | **0.0000** | — |
| trend | **0.0000** | — |
| unemployment | **0.0000** | — |
| debt ratio | 4.90 pp | FRA `tinkering` 2037 |
| deficit | 0.79 pp | FRA `tinkering` 2034 |
| approval | 20.4 | GBR `spend_max` 2032 |

**The real economy is untouched.** GDP, growth, trend and unemployment are bit-identical in every run — so every economy constant measured through those is unchanged and unargued, which is the property the re-run exists to establish.

GBR is not a member, so its runs isolate the **dilution alone**: debt and deficit move by exactly 0.0000 there too, and only approval moves. The member runs' deficit shift is the standing contribution, arriving exactly at 0.277 pp for France.

### One run of thirty changed outcome, and it was decided by two seats

`GBR spend_max`. In the V1.3c tree a censure carries in 2029 at **328 against a threshold of 326**, the government collapses to a rump, approval falls to 12.6 and the incumbent loses in 2034. In the new tree the ~0.1-point approval shift moves discipline enough that one fewer member rebels, the censure falls nine seats short, and the government survives all fourteen years — running a 90 %-of-GDP deficit to a debt ratio of 1280 %.

Recorded as what it is: a knife-edge result that was never robust, flipped by a tenth of a point. `tests/test_balance.gd`'s three S10 assertions — fiscal discipline not dominated, a ruinous budget losing, defeat being attributable — **all still pass**, and they are what the property actually rests on.

## `SAVE_VERSION` 10 → 11

[[coercion-model|V1.3c]] left an assertion that the version was *still* 10 so a later session raising it had to come and say why. This is that session.

Checked against the rule `game_state.gd` states — *would a missing field read as something wrong?* — rather than assumed. Three fields fail it, and the loud one is not the register:

- absent `bloc_base_transfer_pct_gdp`: a France that has **never paid** into a budget it has always paid into, silently moving the starting deficit every economy constant is measured against.
- absent `start_bloc_burden`: reads as 0.0 against a **live** burden, so a game reloaded while in breach scores the breach as brand new and the `europe` issue is mis-signed for the rest of the run.
- absent `bloc`: no council and no rules, which for a bloc whose premise is that its rules are always in force is wrong rather than empty.

All three are `eu_member`/`neighbours`' case, not `agreements`' case. `tests/test_save_load.gd` asserts each directly.

## Bounds

| Quantity | Bound |
|---|---|
| One rule's severity | `MAX_RULE_SEVERITY` = 1.0, and the authored four sum to exactly `BURDEN_MAX`. |
| A nation's burden | `BURDEN_MAX` = 1.0, reached exactly at total maximal breach and never before. |
| A constraint's tolerance | `MIN_CONSTRAINT_TOLERANCE` = 0.10, floored at load. |
| One proposal's transfer | `MAX_PROPOSAL_TRANSFER_PCT_GDP` = 0.60 % of GDP. |
| The standing net position | `[−0.60, +1.20]` % of GDP. Luxembourg's 1.179 is the closest to a bound in the roster and `tests/test_bloc.gd` asserts nothing sits **on** one. |
| A collective external measure | `MAX_PROPOSAL_EXTERNAL_SEVERITY` = 0.50, below `MAX_MEASURE_SEVERITY` — a bloc acting as one is slower and more compromised than a nation acting alone. |
| Rules binding policy at once | `MAX_RULES_IN_FORCE` = 4. Transfer-only and external-measure proposals are not capped, or the council falls silent with content unused. |

## Deliberately absent

- **No structural single-market trend uplift.** The obvious move is to stop `EU_TRADE_BONUS` cancelling in `openness_index()`'s counterfactual, giving members a permanent trend gain. It would take the index off exactly 1.0 at new-game — the property that made [[trade-model|V1.3b's]] and [[coercion-model|V1.3c's]] re-runs provable — and move France's starting trend, which every economy constant was measured against. Membership's upside is carried by content instead. **Named trigger:** a session that is willing to re-tune the economy's trend constants.
- **No accession and no exit.** `eu_member` stays a static fact copied at new-game. A bloc you can leave is a different mechanic and needs a referendum, which is [[v1|V1.1f/V1.7]].
- **No repeal.** A rule in force stays in force. The player's answer to a rule they hate is to defy it and pay, which is the mechanic.
- **The bloc's own books are not modelled.** Contributions do not have to net to zero across members; only the player's budget line is real.
- **A scenario cannot author a rule already in force.** [[scenario-model|The three axes]] are unchanged, stated so it is a decision rather than an assumption.
- **No `bloc_offset` writer.** Everything the bloc does to opinion goes through the `europe` issue or through the deficit, which is the whole point of §1.

---

Related: [[ROADMAP]] · [[coercion-model]] · [[trade-model]] · [[diplomacy-model]] · [[opinion-model]] · [[economy-model]] · [[declined]]
