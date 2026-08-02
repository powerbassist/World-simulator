---
title: Trade Model
tags:
  - model
  - sim
  - economy
---

# Trade Model

Who each nation trades with, how much, what an agreement changes, and the two channels that reach the economy. Built at [[ROADMAP|V1.3b]], the second session of the V1.3 block.

Files: `src/sim/trade.gd` (the rules) · `src/sim/trade_constants.gd` (the numbers) · `data/diplomatic-actions/agreements.json` (the content) · `GameState.agreements` (the register) · `tools/trade_probe.gd` (the measurement).

> [!important] Relations are permission; agreements are economics
> This is the session's central call and everything below follows from it. Relations move the **mix** — which partners matter to you — and never the **level**. Only a signed agreement moves the level. The alternative was measured and rejected, and the rejection is what kept an exploit out of the build. See [Openness](#openness--why-it-is-a-ratio).

## What replaced what

`external_impulse_pct` has been wired since [[ROADMAP|S4]] and deliberately quiet: one GDP-weighted average of the nine nations the player does not govern, the same number for every viewer, and exactly zero at new-game. Every tuned constant in `economy_constants.gd` was measured with it at zero.

V1.3b replaces that scalar with a **directed weight table** — ninety entries, one per ordered pair — read from live GDP, live relations and the agreement register. `Economy.neighbour_weighted_growth()` is retired rather than kept alongside: two answers to "how much does B matter to A" is exactly the divergence [[diplomacy-model|the symmetric pair key]] was chosen to make impossible.

## 1. The weight, and why it is derived

```
raw(A,B) = gdp_B ^ GRAVITY_EXPONENT
         × (1 + EU_TRADE_BONUS      if both eu_member)
         × (1 + BORDER_TRADE_BONUS  if A borders B)
         × (1 + INTENSITY_SPAN × (relations(A,B) − REST_BASE)/100)
         × agreement weight_multiplier, if one is in force
w(A,B)   = raw(A,B) / Σ_C raw(A,C)
```

**Derived, not authored — and not for the reason the plan first gave.** The plan asserted that [[data-sources]] cannot supply bilateral trade. It does not say that, and it is not true: Comext and BACI both cover this roster under compatible licences. The real reasons, which are better:

- An authored ninety-entry table is **frozen**. The whole point of this session is that trade responds to relations and to agreements; a static matrix makes both decorative, which is the failure [[scenario-model|V1.2e]] caught for an authored starting approval.
- The precedent is derived: resting relations, [[cabinet-model|competence]], and V1.3f capability.
- A weight is a **model output**, not content. [[engine-decision|Rule 1]] puts content in data — the things a designer adds more of. There is exactly one weight function, forever.

### The measurement that set the exponent, and the escalation it caught

`tools/trade_probe.gd` swept `GRAVITY_EXPONENT × INTENSITY_SPAN × EU_TRADE_BONUS × BORDER_TRADE_BONUS` **before `src/sim/trade.gd` existed**, judging each parameterisation on two L1 distances: each playable nation's vector against the GDP-only aggregate it replaces, and the nations' vectors against each other.

> [!warning] At the obvious constants, the headline feature is a no-op for GBR — measured at exactly 0.000
> GBR is in no EU pair and its `neighbours` list is empty. Both tie bonuses are therefore **constant across all nine of its partners**, and both **cancel under normalisation**. At `GRAVITY_EXPONENT = 1.0` its derived vector is *identically* the old aggregate. One playable nation in three would have received a per-partner model that was arithmetically the thing it replaced.

The exponent is the only lever that moves GBR at all, because it is the only term that is not constant across its partners:

| exponent | FRA | DEU | **GBR** | cross-nation |
|---|---|---|---|---|
| 1.00 | 0.459 | 0.531 | **0.000** | 0.398 |
| 0.85 | 0.435 | 0.548 | **0.084** | 0.404 |
| **0.70** | **0.410** | **0.575** | **0.174** | **0.406** |
| 0.60 | 0.397 | 0.599 | 0.238 | 0.406 |

0.70 rather than 0.85 because GBR's distance is a pure function of this one number, and 0.084 is too close to the 0.05 line the probe calls a no-op to rest a playable nation on.

**The bonuses were nearly cut, and the measurement is what kept them.** Since a pair's resting relations are *themselves* derived from EU co-membership and a shared border, the gravity bonuses and the relations term encode the same two facts at new-game — they decouple only once a pair moves. Carrying the ties once, through relations, was a real candidate. It fails: with both bonuses at zero the cross-nation L1 is **0.02–0.07**, meaning all three playable nations trade almost identically. That is a different way of shipping nothing, and it is why they stayed.

`BORDER_TRADE_BONUS` (1.20) is larger than `EU_TRADE_BONUS` (0.50), **inverting [[diplomacy-model|the same two facts' ordering for relations]]**, and deliberately: adjacency dominates real bilateral trade far more than co-membership, whereas for a *relationship* an institution whose whole purpose is alignment outweighs a border that cuts both ways.

### The shipped table

```
actor     AUT    BEL    CHE    DEU    ESP    FRA    GBR    ITA    LUX    NLD
AUT         .  0.037  0.063  0.361  0.073  0.111  0.063  0.225  0.009  0.057
BEL     0.030      .  0.023  0.333  0.067  0.253  0.059  0.084  0.021  0.130
CHE     0.064  0.030      .  0.294  0.057  0.223  0.097  0.183  0.007  0.045
DEU     0.088  0.103  0.071      .  0.081  0.305  0.070  0.101  0.026  0.156
ESP     0.043  0.051  0.034  0.199      .  0.373  0.086  0.124  0.013  0.077
FRA     0.029  0.084  0.058  0.329  0.164      .  0.058  0.205  0.021  0.052
GBR     0.053  0.062  0.080  0.241  0.120  0.183      .  0.150  0.016  0.094
ITA     0.098  0.047  0.079  0.182  0.091  0.342  0.079      .  0.012  0.071
LUX     0.030  0.087  0.023  0.338  0.068  0.257  0.059  0.085      .  0.053
NLD     0.037  0.108  0.029  0.421  0.085  0.129  0.074  0.106  0.011      .
```

### This is where V1.3a's dropped third input landed

[[diplomacy-model|V1.3a]] cut size asymmetry from the relations derivation as a direct consequence of the symmetry call: a pair's single number has no side to attach a disparity to. It was handed here rather than quietly omitted, and a **normalised directed weight has two sides**, so the disparity is simply the ratio between them:

| pair | A→B | B→A | ratio |
|---|---|---|---|
| LUX → DEU | 0.338 | 0.026 | **13.1×** |
| LUX → FRA | 0.257 | 0.021 | **12.1×** |
| AUT → DEU | 0.361 | 0.088 | 4.1× |
| BEL → DEU | 0.333 | 0.103 | 3.2× |
| FRA → DEU | 0.329 | 0.305 | 1.1× |

Luxembourg's trade is mostly with Germany; Germany's is barely with Luxembourg. France and Germany matter to each other about equally. Neither statement is expressible on a symmetric key, and both fall out of this one for free.

## 2. Transmission — the impulse

```
external_impulse_pct(A) = TRADE_BETA × Σ_B w(A,B) × (growth_B − baseline_B)
```

`TRADE_BETA` is 0.25, moved from `economy_constants.gd` unchanged in value.

**The per-partner baseline is load-bearing, not bookkeeping.** `NationState.trade_baseline_by_partner` replaces a single scalar, and the reason is an exploit the scalar allowed: under one aggregate baseline, shifting weight toward whichever partner happens to have the highest trend produces an impulse **with nothing having changed abroad** — a free growth boost bought by clicking a diplomacy button. Measured against each partner's own baseline, the sum is identically zero whenever every partner sits at its baseline, *whatever the weights say*. `tests/test_trade.gd` pins that by setting relations to absurd, uneven extremes and asserting the impulse stays exactly zero.

### An ordering bug the synthetic probe caught

> [!warning] Snapshotting the weight table was not enough, and the gap was invisible
> `Economy.tick_month()` snapshots the ninety-entry table before the nation loop, for the reason the old aggregate was computed once. But the impulse *also* reads each partner's `growth_annual_pct`, and `_tick_nation()` overwrites that. Resolved inside the loop, France would have read **this** month's growth for the five partners sorted before it and **last** month's for the four after — an answer depending on `Dictionary` iteration order.
>
> Invisible today, because every partner sits at its baseline forever and both answers are zero. It would have surfaced at V1.3c as a mystery, in the session that first perturbs a partner. The fix is to resolve every nation's impulse before any nation ticks; `tests/test_trade.gd` asserts it by displacing one partner sorted before the player and one sorted after.

### What the channel does when something finally moves it

Declared synthetic: nothing in the shipped game produces this. DEU forced to −3.0 %/yr for 24 months.

| actor | w(DEU) | peak impulse | of `IMPULSE_MAX` | peak growth gap |
|---|---|---|---|---|
| FRA | 0.329 | −0.348 | 6 % | −0.354 |
| GBR | 0.241 | −0.254 | 4 % | −0.260 |

Both clamps stay far out of reach, and the two nations differ — which is the per-partner weighting doing visible work rather than a shared aggregate. The quiet-state residual, with no shock at all, is **0.008**: partners drift a hundredth of a point off their baselines as their sector shares move, and that is the honest size of the channel at rest.

### Why the other nine still have no impulse

Player-only, unchanged from S4. **Not a stability concern** — the coupled ten-nation system is provably stable. Linearising the common mode at `GAP_CLOSE = 0.30` and `TRADE_BETA = 0.25`:

```
λ² − 1.225λ + 0.25 = 0  →  λ = 0.966, 0.259     both inside the unit circle
```

Recorded here so V1.3c can lift the restriction knowingly rather than re-derive it. The reason to defer it is different and better: turning it on **replaces the 28-month output-gap half-life** (≈20 months for the coupled mode), which is the pacing constant [[economy-model]] argues the game's whole legibility from, and it adds a coupled-system row to *Why nothing diverges* where every existing row is per-quantity. That is a model rewrite, not a wiring change.

## 3. Openness — why it is a ratio

```
openness_index(A) = Σ_B raw(A,B) / Σ_B raw(A,B) with every agreement multiplier at 1.0
```

Then `_update_potential_shift()` gains a fourth term, `TRADE_OPENNESS_BETA × (openness_index − 1)`, sharing the existing `SHIFT_MAX_PCT` ±1.0 clamp — so trade openness and public investment compete for the same budget, which is the point rather than a compromise.

The obvious form — raw mass over own GDP — was rejected for three separate defects, and the ratio kills all three **structurally rather than by tuning**:

| Defect of `Σ raw / gdp_A` | Why the ratio does not have it |
|---|---|
| **A monotonic ratchet.** Partner GDP grows at trend forever, so the index rises ~20 % over the harness's fourteen years from time passing alone, driving `potential_shift` onto a clamp that then sets the growth rate — the `IMPULSE_MAX = ±50` failure [[economy-model]] already writes up, committed a second time. | Partner GDP appears identically above and below and **cancels exactly**. The index is dimensionless and has no time trend. |
| **Own GDP in the denominator** is an unmotivated negative feedback on the player's own success, and it makes trend a function of GDP *level* in every balance regime. | `gdp_A` never appears. |
| **An exploit.** `state_visit` is +5 relations, per-target cooldown, no preconditions and **no domestic price at all** — its own summary says "Costs nothing at home." Nine clicks a year on a 35-month relations half-life would buy most of a +32 % openness index for free: about two permanent points of GDP on infrastructure, for nothing. | Relations enter both passes and cancel too. They move the **mix**, which is zero-sum under normalisation. Only an agreement — which carries authored winners *and* losers at home — moves the level. There is nothing to farm. |

That third row is the same shape [[diplomacy-model|V1.3a's probe caught]] for a six-bloc gain applied against all nine neighbours, and it is the second correction on this project's record to come from a measurement finding an *exploit* rather than a wrong number.

**The consequence that made the session's defining cost cheap:** `openness_index ≡ 1.0` for every regime in the balance harness, because none of them signs anything. The re-run's question therefore sharpens from *"has anything moved materially?"* to *"has anything moved at all?"* — and the answer is no. See [The balance re-run](#the-balance-re-run).

## 4. Agreements — no new content type

`data/trade-agreements/` and `src/core/trade_agreement.gd` were both **cut at plan time**. The terms ride a third effect channel on the existing diplomatic action:

```json
"effects": {
  "relations": 6.0,
  "bloc_offset": {"business": 0.10, "workers": -0.10},
  "agreement": {
    "op": "enter",
    "weight_multiplier": 1.35,
    "sector_shift": {"agriculture": -0.15, "industry": 0.45, "services": -0.30}
  }
}
```

Availability is then **generic and costs three lines**: `"agreement_active"` joins `PRECONDITION_FIELDS`, and `Diplomacy._read_field()` gains one case returning 1.0 or 0.0 for the actor–target pair, beside the `"relations"` case that already special-cases pair state. An enter verb asks for 0, an exit verb asks for 1, and `Diplomacy.available()` gates both with **no trade knowledge in that module at all**.

The register stores the **terms**, not the action id:

```gdscript
GameState.agreements[Relations.key(a, b)] = {
    action_id, action_name, since_year, since_month, weight_multiplier, sector_shift
}
```

Two reasons, and the second is the one that shaped the session. An agreement is a **signed contract** — its terms are what was agreed, not what the content file says later. And storing them is what lets `src/sim/trade.gd` take no `loader`, which is what keeps `Economy.tick_month()`'s signature unchanged across its **twenty-eight call sites**. The same pressure put `eu_member` and `neighbours` onto `NationState`, as static facts copied once at new-game the way `assembly_seats` already is.

**Ownership.** `Diplomacy` owns the register — it is pair state written by a player command, exactly like relations. `Trade` reads it and never writes. The two modules talk through `GameState` and never preload each other, which is [[engine-decision|rule 3]].

### Winners and losers are compositional, and must sum to zero

`Economy._apply_growth_to_sectors()` runs each sector at `SECTOR_TREND[key] + potential_shift + trade_shift[key]` and then computes the cyclical part as a **residual against the GDP target**. So a per-sector trade shift moves composition only: GDP still lands exactly on target and the sectors-sum-to-GDP identity is untouched. It must go **inside** that trend loop — applied after it, the reconciliation breaks.

`src/core/diplomatic_action.gd` refuses a file whose three shifts do not sum to zero. Not because a surplus would be ignored — because it would be **silently converted into a different composition change than the author wrote**: the residual is redistributed by `share × SECTOR_CYCLE_BETA` (0.4 / 1.8 / 0.8), so a surplus comes back weighted toward industry and nothing tells the author. The same class of quiet lie a zero `effects.relations` is already refused for.

### An agreement is bilateral, and that is what makes the channel live

The register is keyed by the unordered pair, so the partner reads the same contract and both economies open up. This was found by a test asserting the opposite, and the test was wrong rather than the model: the declared stopgap is that the partner does not **decide**, not that a contract has one side.

It matters more than it looks. The partner's trend genuinely moves, so the bracket in the impulse sum is genuinely non-zero — **the transmission channel is live this session rather than dormant until V1.3c**. One hop and no loop: the player's own trend never feeds back to the partner.

### What one agreement is worth

FRA signs `industrial_compact` with DEU, against a control. Openness 1.1214; weight on DEU 0.329 → 0.417.

| month | Δ trend | Δ GDP % | Δ agri pp | Δ industry pp | Δ services pp |
|---|---|---|---|---|---|
| 12 | +0.022 | +0.013 | −0.00 | +0.14 | −0.14 |
| 36 | +0.053 | +0.097 | −0.00 | +0.42 | −0.41 |
| 60 | **+0.073** | **+0.231** | −0.01 | **+0.70** | −0.69 |

Three floors were named before the run and all three clear: the trend gain is readable at sixty months; it is far smaller than a budget commit of comparable domestic cost; and the composition move clears **0.5 pp**, which is the floor the economy panel's own `"%.0f%%"` sector rendering imposes. That last one is [[diplomacy-model|V1.3a's below-the-noise-floor finding]] repeated for sectors — an effect the player cannot read is a decorative effect however real it is in the state.

**The payoff scales with the partner.** The balance harness signs with whichever partner rests highest, which for France is Belgium, and openness reaches only 1.0318 against Germany's 1.1214 — because Belgium's raw weight is a quarter of Germany's, so multiplying it moves the total mass far less. The size asymmetry showing up again, this time in what a deal is worth.

## 5. The counterparty is a declared stopgap

> [!warning] Named, not approximated
> `Diplomacy.would_accept_agreement()` is a pair score against one threshold and **nothing else**. The target does not weigh its own economy, does not compare this partner against alternatives, never proposes an agreement, and never withdraws from one.

Implemented as a **gate**, not a post-hoc verdict, and that choice is load-bearing. `Diplomacy.execute()` has two outcomes — refused and applied. A verdict applied *after* the effects would be a third (available, executed, partner said no), and if the relations delta still applied the player would collect +6 relations for a treaty that was refused. As a gate there is no third outcome, no new result field and no UI branch; the existing `refused: true` shape carries it, with `refused_by_partner` naming the reason for the tooltip.

`tests/test_trade.gd` asserts it by **mutation**: the target's GDP is cut 100×, its unemployment set to 39 %, its growth to −11 %, its sectors gutted and an unrelated agreement added — and the verdict must not move. When V1.3e gives the target an interest function, **that test must fail and be rewritten**. That is the point of it, and it is the shape [[diplomacy-model|V1.3a's third-pair assertion]] established.

### `AGREEMENT_ACCEPT_MIN` was constrained from above, by GBR

The second named escalation trigger. Every GBR pair rests at exactly **45.0**, the floor of [[diplomacy-model|the four-tier table]], and the strongest positive verb reaches only **60.7** from there under sixty months of spam. Any relations-based gate must sit under 60.7 or the whole session is closed to one playable nation in three — [[amendment-model|Germany's two-thirds]] repeated.

**52.0.** Not 55: one `settle_dispute` takes a resting-45 pair to exactly 55, and clearing a bar by exactly nothing is the mistake [[scenario-model|`deu_grand_coalition`]] made at 0.667 against 0.667. 52 leaves three points.

> [!note] The trigger did not fire, but it forced a consequence worth recording
> At 52 the gate is **non-binding for eight of France's nine partners** and for all of Germany's EU ones, because their resting tiers are already 60 or 68. That is not a tuning choice — GBR's 60.7 ceiling caps *any* relations-based bar. The consequence: for an EU nation the difficulty of an agreement is carried by the action's **domestic price**, not by this gate. For GBR the gate *is* the difficulty, which is thematically right for a nation outside the bloc and is where the asymmetry belongs. `tests/test_trade.gd` asserts both halves — that GBR starts below the gate, and that one verb clears it.

## The balance re-run

The session's defining cost, and the reason V1.3b was marked plan-first. Ten regimes × three playable nations = **thirty fourteen-year runs**, captured from the V1.3a tree and diffed against the rebuilt one.

**All thirty are bit-identical.** Not "within tolerance" — byte-for-byte the same output. That is the invariant the model was shaped to make provable: the openness index is exactly 1.0 with nothing signed, and the impulse is exactly zero while partners sit at their baselines, both by construction rather than by tuning. Every economy constant measured through this channel before V1.3b is therefore still valid, unchanged and unargued.

An eleventh regime, `managed_signs_agreement`, is where the trade channel gets its own fourteen years. It runs clean for all three nations, with no clamp reached. GBR's run is the one worth reading: it is **refused at 45.0**, lifts the pair with one `settle_dispute` to 55, and then signs — the gate and the model behind it both exercised in the same run.

`_check()` gained one assertion, scoped deliberately: it bounds the **trade contribution** to `potential_shift`, not the total. The total already sits on its clamp under `ruinous` and `spend_max` through the infrastructure writer, and has since S10 — that is the guard rail doing its job on a budget no sane player commits, and it is not this session's to relabel as a failure.

## The projection had to be repaired

`Budget.project()` deep-copies the state and ran `Economy` + `Budget` and nothing else, because until V1.3b nothing else could reach a figure the projection reports. Relations now can: they set the weight, the weight sets the impulse, and `Diplomacy.tick_month()` is what drifts them.

Left alone, the projection held relations frozen while the real game drifted them, and the two disagreed at about **2e-9 relative** from a displaced state. Tiny, and still wrong: the budget panel is the one surface in the game that promises *this is what will happen*, and "the projection equals what happens" is an S4 done-when condition that held **by construction**. `project()` now takes a `loader` — required, not defaulted, because a defaulted null would make the divergence opt-in and silent at every call site that forgot — and ticks `Diplomacy` like `main.gd` does. `tests/test_budget.gd` runs the check from a diplomatically displaced state, because the undisplaced one cannot see it.

## `SAVE_VERSION` 9 → 10, and which field earned it

Two candidates were checked rather than assumed, and **neither was the one that earned it**:

- An absent `agreements` reads as `{}`, which is exactly right for every version-9 save — those games could not sign one. [[scenario-model|`scenario_id`'s case]] again; it would not have earned a bump alone.
- An absent `trade_baseline_by_partner` fails **soft**: `Trade.external_impulse()` re-bases a missing partner to its current growth, so the channel silently re-zeroes at the moment of loading and an in-flight external shock is erased. Real, worth saving for, recoverable.
- An absent `eu_member`/`neighbours` is the loud one. Every nation loads landlocked and outside the EU, both gravity bonuses vanish, and the weight silently collapses back to the GDP-only vector V1.3b replaced. **A reloaded game would run a different model from the one that saved it**, with nothing anywhere to say so.

All three are asserted directly in `tests/test_save_load.gd` rather than argued in a comment.

## Bounds

| Quantity | Bound |
|---|---|
| A weight vector | Normalised, so it sums to 1 by construction and no single partner can exceed it. |
| The relations multiplier | Floored at zero. `INTENSITY_SPAN = 2.0` leaves the floor unreached at any readable relations value, so the response stays smooth rather than hitting a cliff. |
| One agreement's weight multiplier | `MAX_AGREEMENT_WEIGHT_MULTIPLIER` = 2.5, checked at load. This is what bounds the openness index, **before** `SHIFT_MAX_PCT` ever sees the term — which is what keeps [[economy-model|the divergence argument]] a per-quantity one. |
| One agreement's sector shift | `MAX_AGREEMENT_SECTOR_SHIFT` = 1.0 per sector, and the three must sum to zero. |
| The trade share of `potential_shift` | Half the ±1.0 budget, asserted by `tools/balance_probe.gd`. Openness shares that budget with infrastructure, education and corporate tax; a treaty that could take most of it would out-earn every fiscal lever in the game. |

## Deliberately absent

- **No `Trade.tick_month()`.** The module is stateless — a weight recomputed from live GDP, live relations and the register has nothing to store — so there is no line in `main.gd`'s chain and no ordering question beyond the snapshot.
- **No agreement duration or expiry.** V1.3c owns it, via a sanction breaking one.
- **No effect on the partner beyond the contract itself.** The partner's economy opens because it is party to the agreement; nothing else about it is modelled, and it never acts.
- **A scenario cannot author a starting agreement.** [[scenario-model|The three axes]] are unchanged. Stated so it is a decision rather than an assumption.
- **No new `ISSUE_KEYS` entry**, and no trade colouring on the map. Both are still V1.3d's and both would reopen measurements this session did not touch.

---

Related: [[ROADMAP]] · [[economy-model]] · [[diplomacy-model]] · [[opinion-model]] · [[data-architecture]] · [[data-sources]]
