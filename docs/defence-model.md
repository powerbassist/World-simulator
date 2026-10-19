---
title: Defence Model
tags:
  - model
  - sim
  - diplomacy
---

# Defence Model

Military capability, deployments, defensive pacts, and the obligation that bills you at home. Built at V1.3g, the seventh and last session of the V1.3 block.

Files: `src/sim/defence.gd` (the rules) · `src/sim/defence_constants.gd` (the numbers) · `data/diplomatic-actions/defence.json` (the content) · `GameState.pacts` and `GameState.deployments` (the registers) · `tools/defence_probe.gd` (the measurement).

> [!important] The obligation is the point, and the rest is what prices it
> [[v1|The tier page]] committed years of sessions ago that defence lands last and lands thin, because "the player's real interaction with defence in a nation-management game is budgetary and political — what it costs, who it upsets, what an alliance obliges you to". Everything here serves the third of those. **Capability is not a stat and a deployment is not a unit**: capability exists to price a commitment, and a commitment exists to arrive on the budget without having been asked for.

## 0. What was already built, and what this session adds

More of this session existed before it started than in any other in the block, and that is the reason it can be thin:

| Already there | Since |
|---|---|
| `defence` in `SPENDING_KEYS` — the spending line, its lever, its multiplier | S4 |
| `defence` in `ISSUE_KEYS`, fed by a delta-from-start term, split six ways by `BLOC_SALIENCE_BASE` | S5 |
| `defence` in `PORTFOLIO_KEYS`, so a minister's competence scales delivery | [[cabinet-model|V1.1d]] |
| `spending_defence` as a bloc constraint field, with `common_defence_floor` authored against it | [[bloc-model|V1.3d]] |

**V1.3g adds no spending line, no issue key and no portfolio.** It adds a derived stock, two registers, one effect channel and four verbs.

## 1. Capability is a stock, derived and never authored

```
target(N)   = N.spending_pct_gdp["defence"]
capability += CAPABILITY_CONVERGENCE × (target − capability)     [monthly]
```

The same treatment [[cabinet-model|competence]] gets, and for the same reason: an authored per-nation `military_strength` is a number somebody has to keep in step with the spending line, and it would disagree with it the first time a player moved the lever.

### Why this needs no `has_budget` lift

All ten nations author `spending_pct_gdp.defence` in `data/nations/*.json` — 1.1 to 2.0 points of GDP. So the stock is well defined for the whole roster with no new per-nation data, which is what the tier bullet asked for.

The nine have no budget model, so their spending never moves and their capability sits at its authored equilibrium forever. **That is correct rather than a stopgap**: a nation whose budget the game does not simulate has a defence posture that does not change, and saying so is more honest than mirroring a budget onto it. Lifting `has_budget` is a separate session [[trade-model]] books, and this session does not spend it. (V4.4's AI event answers deliberately skip the spending, tax, company and other-revenue channels, so this invariant holds: see [[events-model]] §5.)

> [!warning] Both bounds on `CAPABILITY_CONVERGENCE` are failures, not just one
> Too slow, and a stock that has not visibly moved inside a five-year term is a lever the player cannot pull — [[scenario-model|V1.2e]]'s decorative-axis failure. Too fast, and capability tracks spending closely enough that **it is the spending line under a second name**, and every function reading it could have read `spending_pct_gdp["defence"]` instead. The constant has to sit comfortably inside both, and the midpoint is not automatically that place.

### What reads it

Two readers, and a derived quantity with none would not have shipped:

1. **The deployment cost divides by it.** A nation that has funded its military commits cheaply; one that has not pays through the nose for the same commitment. This is what makes sustained spending *pay*, which a spending line on its own never does.
2. **The interest model prefers a capable pact partner.** `ForeignPolicy.would_accept_pact()` reads `ns.military_capability` directly.

**No economy reader.** Capability does *not* reduce the damage a tariff or a sanction does to you. That would be a new term inside [[coercion-model|V1.3c]]'s measured growth channel, and it would re-open the Laffer curve and the strictly-dominated finding both — a whole session's measurement spent for a thematic gain.

## 2. A pact is a pair; a deployment is a directed pair

`GameState.pacts` is keyed by `Relations.key()` — `"DEU|FRA"`, symmetric, because a mutual defence commitment has one shared value the way a relationship and a contract do.

`GameState.deployments` is keyed by `Relations.directed_key()` — `"FRA>DEU"`, because *France committing forces in support of Germany* and the reverse are two separate acts with two separate bills.

**No fifth kind of state.** [[bloc-model|V1.3d]] added the fourth — one object binding eight nations — and the temptation here was to add a fifth for "an alliance is a set". It is not needed: the set is a **derived read**, `Defence.allies(state, id)`, over the symmetric register, and the genuinely multilateral case already exists as the bloc, which already carries `common_defence_floor`. This is the first session since [[diplomacy-model|V1.3a]] to add two registers and no new shape.

## 3. The obligation, and the correction that shaped it

A measure landing on a nation you have a pact with opens a deployment **on its own**, with a running budget cost and a running opinion cost, and the player is not asked. That is the whole design: an obligation the player consented to *once*, arriving as a bill they did not consent to *this month*.

There is no accept/refuse surface, and the exclusion is deliberate. An offer with an expiry that the player answers is pending state, a decision and a UI — a second machine, and precisely the one [[foreign-policy-model|V1.3f]] cut when it kept agreements AI-to-AI. Letting it back in here is what would split this session.

> [!warning] The design pass's correction: an edge-triggered obligation is unbounded
> The obligation was first written **edge-triggered** — it opens when the measure lands, and only the abandon verb closes it. That cannot be bounded. `Diplomacy._tick_retaliation()` writes its mirror with `retaliated: true`, which stops the mirror recurring, but **nothing in the project ever lifts a measure except a `lift` verb, and no AI carries one on its agenda**. Over fourteen years every retaliation landing on a pact partner becomes a permanent, monotone line on the player's budget, and `DEPLOYMENT_BILL_MAX_PCT_GDP` stops being a guard rail and becomes the thing setting the number — [[economy-model|`IMPULSE_MAX`]]'s failure in its fifth place.
>
> Obliged deployments are therefore a **level read**, reconciled every month against (pacts × measures in force). The design's point survives untouched: the player still cannot close an obligation. Only the aggressor lifting the measure, or abandoning the pact, can.

This also gives the register a property worth asserting rather than describing: **an obliged deployment is derived and a chosen one is not**, which is what `tests/test_save_load.gd` pins in §6.

## 4. The two prices

```
cost_one(N)  = DEPLOYMENT_COST_PCT_GDP ÷ clamp(capability ÷ CAPABILITY_REFERENCE, MIN_RATIO, MAX_RATIO)
bill(N)      = cost_one(N) × deployment_count(N),  clamped to DEPLOYMENT_BILL_MAX_PCT_GDP
opinion(N)   = Σ over deployments of DEPLOYMENT_OPINION_CHOSEN × (obliged ? DEPLOYMENT_OBLIGED_MULT : 1.0)
```

The bill is a spending figure of its own on the budget panel, beside [[coercion-model|the tariff revenue line]] and [[bloc-model|the bloc transfer]] — not a fourth entry in `SPENDING_KEYS`, for the reason V1.3c gives for keeping tariff revenue out of `TAX_KEYS`.

The opinion load is subtracted from the `defence` issue's satisfaction, and its six-way split needs no new machinery: `BLOC_SALIENCE_BASE` already weights `defence` differently for every bloc, which is what the tier bullet's "differs by bloc" asked for.

> [!important] Subtracted *after* `Cabinet.effectiveness()`, not through it
> `Opinion.issue_satisfaction()` multiplies the `defence` spending delta by `Cabinet.effectiveness(ns, "defence")`, and applying the same multiplier to the deployment load would let a competent defence minister quietly cancel this session. Effectiveness is a claim about how well a **change of policy** is delivered; a deployment is a fact on the ground. The load goes on after.

**The cost is never stored on the deployment entry.** It is derived from live capability every month. Storing it would be one intensity written twice — the redundancy `tools/coercion_probe.gd` cut when it deleted the authored `tariff_rate_pct`.

## 5. The channel and the verbs

`effects.pact` is the **fifth** effect channel on the existing diplomatic action, after `relations`, `bloc_offset`, `agreement` ([[trade-model|V1.3b]]) and `measure` ([[coercion-model|V1.3c]]). No new content type and no `data/pacts/`, for the sixth session running and the same reason each time.

Four ops rather than a sixth channel: `sign`, `abandon`, `deploy`, `withdraw`. A chosen deployment needs a verb, and giving it a channel of its own would be a parallel vocabulary for a mechanism that already exists. `deploy` requires `pact_active == 1`, so both registers share one domain and abandoning a pact closes both kinds of deployment through one rule.

The mutual exclusion in `src/core/diplomatic_action.gd` was a single pairwise test and becomes **at most one of {agreement, measure, pact}**. `agreement` + `pact` is technically harmless — different registers, no erase ordering — but it would give one action two counterparty gates, and `execute()`'s single `blocked_by_partner` would have to become an OR that a later session would have to unpick.

`_is_pact_verb()` tests `op == "sign"`, **not** "the channel is non-empty", which is where `is_agreement_verb()` sits (both in `src/sim/diplomacy_verbs.gd` since V5.0c). Only signing needs the counterparty's consent, and testing non-emptiness would mean an AI can never *abandon* a pact with the player — locking a human into an alliance the AI hates, permanently, with no exit on its side.

> [!note] An existing consequence this uncovered, recorded and not fixed here
> `is_agreement_verb()` (`src/sim/diplomacy_verbs.gd`, `Diplomacy._is_agreement_verb()` before V5.0c) has exactly the non-empty shape today, so `withdraw_from_compact` is skipped when the target is the player: **an AI can never withdraw from a trade agreement with the player.** It is out of this session's scope and is written down rather than quietly repaired inside it.

## 6. `SAVE_VERSION` 12 → 13

The rule is unchanged — *would a missing field read as something wrong?* — and applied per field it comes out four ways, which is why the test asserts four things rather than one.

| Field | An absent one reads as | Verdict |
|---|---|---|
| `military_capability` | `0.0`, against a France that has spent 2.0 % of GDP on defence since before the game started | **Loud. This is the bump.** The cost divides by capability, so every deployment jumps to `MAX_RATIO`, and `would_accept_pact()` reads the whole roster as militarily worthless. A reloaded game runs a **different model** from the one that saved it — `eu_member`/`neighbours`' case in its strongest form |
| `pacts` | `{}` — nothing signed | Quiet, and correct for every version-12 save, because those games could not sign one. `measures` at V1.3c |
| `deployments`, the **obliged** half | re-derived next tick from `pacts` × `measures`, both of which the save carries | Fails soft, for one month. `trade_baseline_by_partner`'s case, which V1.3b ruled not-a-bump |
| `deployments`, the **chosen** half | a silent withdrawal of the player's own forces, and their bill vanishing with them | Loud. `bloc_base_transfer_pct_gdp`'s case |

The split on `deployments` is the assertion worth having, because it pins the property rather than describing it: **obliged deployments are derived, chosen ones are not.** A later session that makes obligations stateful turns that test red and has to come and say why.

## 7. Measured tables

Every constant was set from `tools/defence_probe.gd` before a verb was authored.
**The probe corrected the model three times**, which is seven sessions running.

### (a) The ten separate — trigger 2's first half did not fire

```
  id     def%GDP    capab    ratio   cost%GDP
  AUT       1.90    1.900    1.145     0.2621
  CHE       1.10    1.100    0.663     0.4527
  DEU       1.70    1.700    1.024     0.2929
  FRA       2.00    2.000    1.205     0.2490
  GBR       1.50    1.500    0.904     0.3320
  LUX       1.60    1.600    0.964     0.3112

  cost span 0.2490 .. 0.4527  =  1.82x
```

The 1.8× spread in authored spending survives the cost function intact. Capability
is not one number written ten times, so the `GRAVITY_EXPONENT = 1.0` clustering
failure does not recur here.

### (b) `CAPABILITY_CONVERGENCE`, both bounds named

France moved 2.0 → 4.0 points of GDP and held there:

```
      conv     half    @12mo    @60mo   @168mo
     0.005      139     2.12     2.52     3.14
     0.010       69     2.23     2.91     3.63
     0.020       35     2.43     3.40     3.93
     0.040       17     2.77     3.83     4.00
     0.080        9     3.26     3.99     4.00
```

0.005 and 0.01 have half-lives past a full 60-month term — a lever the player
cannot pull. 0.08 is 63 % of the way inside one year and is the spending line
renamed. **0.02**: half the gap in 35 months, a fifth of it at twelve.

### (c) One deployment ≈ one point of VAT

```
  id       capab   cost%GDP    vat pts  1 deploy bn  4 deploy bn
  FRA      2.000     0.2490       1.00          7.2         29.0
  DEU      1.700     0.2929       1.17         12.6         50.5
  LUX      1.600     0.3112       1.24          0.3          1.1
```

### (d) The obliged stack — trigger 1 did not fire, and the first correction

> [!warning] The probe's first correction: **the nine never coerce each other**
> Over 168 months with the agenda running and no player, `state.measures` stays
> **empty** and all 24 recorded acts are `state_visit`. V1.3f's agenda is friendly
> by revealed preference. The only AI-driven source of a measure anywhere in the
> project is the council's `common_external_tariff` — the [[bloc-model|V1.3d]]
> feature V1.3d's own re-run never fired and V1.3f's did. `Bloc.tick_month()` is
> therefore load-bearing for this table, and the first run reported zero
> obligations **for the wrong reason**.

```
  id    who       pacts   maxDep   endDep    maxBill    endBill   meas  retals
  FRA   top2          2        0        0      0.000      0.000     16      16
  FRA   top5          5        1        1      0.249      0.249     16      16
  FRA   outside       2        2        2      0.498      0.498     16      16
  DEU   outside       2        2        2      0.586      0.586     16      16
  GBR   top5          5        0        0      0.000      0.000     16      16
  GBR   outside       1        1        1      0.332      0.332     16      16
```

The worst reachable bill is **0.586 against a clamp of 2.00**, so the clamp is a
guard rail doing a guard rail's job — the first time in this block a clamp has been
measured and found *slack* rather than found binding.

**What the shape says is better than the number.** The 16 live measures are 8
members × 2 non-members of one adopted external tariff, all flagged `retaliated` by
`bloc.gd` so they are not answered 16 times. An obligation therefore fires when the
player is allied **outside the bloc** — your pact with Britain bills you when
Brussels turns on Britain. Nothing authored that: it is V1.3d's council meeting
V1.3g's pact, and it is why a pact with your largest trade partners (`top2`, all
members) costs nothing while `outside` costs every time.

### (e) The opinion cost — the second and third corrections

```
  authored `defence` salience per bloc (BLOC_SALIENCE_BASE):
    work 0.00  pens 0.00  urba 0.00  rura 0.12  busi 0.00  stud 0.00
```

> [!warning] The probe's second correction: the headline is the wrong statistic
> `defence` is weighted **0.00 by five blocs of six**. No value of
> `DEPLOYMENT_OPINION_CHOSEN` can move `overall_approval_pct` past the ±3.0 noise
> floor, so raising it until one did would be tuning against an arithmetic
> impossibility. This is [[diplomacy-model|V1.3a]]'s own measured finding — *a
> domestic price hitting fewer than all six blocs is legible on the polling panel
> and never in the headline* — reached a second time from the other direction.

> [!warning] The probe's third correction: the first table measured half the price
> It set the opinion load and never the **bill**. The bill widens the deficit, and
> `public_finances` is weighted by all six blocs where `defence` is weighted by one.
> Both prices are written before Budget reads them, which is the order the real
> chain produces.

```
  deploys      kind    bill  deficit  headline  d(head)    rural  d(rural)
  0               -   0.000     5.20     49.80     0.00    49.81      0.00
  1          chosen   0.249     5.46     49.24    -0.56    48.49     -1.32
  1         obliged   0.249     5.46     49.09    -0.71    47.35     -2.46
  2          chosen   0.498     5.73     48.52    -1.28    46.55     -3.26  CLEARS
  2         obliged   0.498     5.73     48.10    -1.70    43.31     -6.51  CLEARS
  4         obliged   0.996     6.25     45.68    -4.12    33.50    -16.31  headline
```

Saturation arrives at four obliged deployments (`load` 1.05 against a term that
clamps at 1.00); the reachable stack is **two**, so trigger 3's second half does not
fire.

### (f) `DEPLOYMENT_OBLIGED_MULT`, raised from 1.50 because it was decorative

```
   deploys  rur chos   rur obl      gap   reach
         1     48.49     47.35     1.14     yes
         2     46.55     43.31     3.25     yes   <-- CLEARS
         4     41.40     33.50     7.90      no   <-- CLEARS
```

At 1.50 the gap at the counts the game actually produces was 0.72 and 2.05 — a
distinction that existed in the register and nowhere a player could read it. Solved
off the measured slope of 13.7 rural points per unit of load: 1.73 puts the
two-deployment gap on the floor, and **1.75** is the round number above it.

**One deployment stays below the floor either way, and that is a structural bound
rather than a number left untuned.** Making one chosen deployment legible needs
`DEPLOYMENT_OPINION_CHOSEN = 0.316`, and at 0.316 two obliged deployments carry a
load of 1.11 against a satisfaction term that clamps at 1.00 — the third would be
free. No value of the pair makes one legible without saturating two, and two is the
top of the reachable stack.

### (g) Pact acceptance — trigger 2's second half fired, and the bar moved

`PACT_ACCEPT_MIN` was set at 1.60 on the argument that a permanent contingent
liability is a bigger ask than a trade agreement. **The sweep said otherwise**, and
it is [[foreign-policy-model|V1.3e]]'s Britain finding for the sixth time in this
block:

```
       bar    accepts   GBR-in   GBR asks
      0.80         51       13          5
      1.00         35        9          4
      1.20         24        4          1
      1.60         13        1          0
```

At 1.60 Britain could not ask **any** of the nine and appeared in exactly one
accepting pair of ninety — structurally unable to have an alliance policy, while
three of the ten nations are playable. **1.00**: it can ask four and appears in
nine, and 61 % of ordered pairs still refuse, so the register keeps its information.

That lands *below* `ACCEPT_MIN`'s 1.20 and inverts the original argument, which is
worth stating rather than hiding. A trade agreement carries a third term the asker
can move — a generous `weight_multiplier` pushes a marginal pair over. A pact has no
such lever, so the same number would not be the same difficulty.

### (h) The agenda never signs a pact, and the cause is not this session's

```
  verb                  max       mean   over bar     wins
  defence_pact       0.0486    -0.1162          2        0
  deploy_forces      0.0383    -0.0794          2        0

  Which verb actually wins each of the 90 pairs, and its authored price:
    state_visit        wins  90   relations +5.0   domestic price 0.000
```

After fourteen years the register holds **0 pacts and 0 deployments** from AI
action. The cause was measured rather than guessed at, and it is one line of the
table above: **`state_visit` wins 90 pairs of 90 because it is the only verb in
`data/diplomatic-actions/` with a domestic price of exactly 0.000, and nothing
priced can beat free.** Its 12-month cooldown is per *pair*, so with nine targets
an unpriced act is always available against somebody.

This is a **[[foreign-policy-model|V1.3f]] property that V1.3g surfaces, not one
V1.3g creates** — V1.3f's own correction ("free concessions get spent freely") fixed
the *ranking among priced verbs* by making the agenda read `bloc_offset`, and left
the unpriced verb dominating all of them. Pricing `defence_pact` lower would not fix
it and would be dishonest content: at 0.215 its price already sits between
`bilateral_treaty`'s 0.2 and `settle_dispute`'s 0.54.

**The consequence is stated rather than worked around: the four verbs here are
player content.** AI-to-AI pacts are reachable by the model and unreachable by the
agenda, so the obligation the session is about arrives through the *council's*
external tariff (table d) rather than through nine nations allying with each other.
`is_pact_signing_verb()`'s player exclusion is therefore correct and currently
untriggered. The fix is a security term in `_desire_parts()` — a real addition to an
interest model two sessions measured, which is a session and not a constant.

## 8. Escalation triggers, named before the measurement

1. **The obliged bill is unbounded in reachable play** — if fourteen years with the agenda live puts the stack over `DEPLOYMENT_BILL_MAX_PCT_GDP`, the clamp and not the model is setting the number. The fix is not a larger clamp; if it needs obligation tenure or a per-deployment drawdown, that is a second machine and a later session.
2. **The ten do not separate on capability, or GBR can never ally.** A 1.8× spread in authored spending has to survive the cost function above rounding, and a capability term anchored absolutely would read Britain's structural detachment as weakness — [[foreign-policy-model|V1.3e]]'s finding, which has now fired five times.
3. **The opinion cost never clears ±3.0, or saturates before the reachable stack does.** `_scaled()` clamps to ±1, so past some count further deployments are free — `DEFICIT_SCALE_PP`'s S10 failure in a new place.

### What actually fired

| Trigger | Fired? | Response |
|---|---|---|
| 1 — the obliged bill is unbounded | **No.** Worst reachable stack 0.586 against a clamp of 2.00 | None. The first clamp in this block to be measured and found *slack* |
| 2a — the ten do not separate on capability | **No.** 1.82× cost span | None |
| 2b — GBR can never ally | **Yes**, for the sixth time in the block | `PACT_ACCEPT_MIN` 1.60 → **1.00**, off the sweep |
| 3a — the opinion cost never clears the floor | **Partly.** Two deployments clear on rural; one does not, and *cannot* | Recorded as a structural bound; `DEPLOYMENT_OBLIGED_MULT` 1.50 → **1.75** so the two-deployment gap clears |
| 3b — saturation before the reachable stack | **No.** Saturates at four; the reachable stack is two | None |

Plus one the list did not anticipate, in the shape V1.3f's fourth correction had:
**the agenda never reaches the new content**, because an unpriced verb dominates
every priced one. Cause measured, consequence stated, fix booked to a later
session — §7 (h).
