---
title: Foreign Policy Model
tags:
  - model
  - sim
  - diplomacy
---

# Foreign Policy Model

Why a nation the player does not govern answers one way rather than another. Built at [[ROADMAP|V1.3e]], the fifth session of the V1.3 block.

Files: `src/sim/foreign_policy.gd` (the rules) · `src/sim/foreign_policy_constants.gd` (the numbers) · `tools/foreign_policy_probe.gd` (the measurement) · `tests/test_foreign_policy.gd` (the invariants).

> [!important] Interest is material. Ideology is one weak term.
> This is the session's central call and everything below follows from it. `tools/bloc_probe.gd` table (d) prints the eight non-player members' `coalition_position` and they are **clustered** — economic spans −0.54..+0.33, social −0.50..+0.63. An interest function resting on that is [[trade-model|the `GRAVITY_EXPONENT = 1.0` finding]] in a new place: nine vectors that are arithmetically one vector. So the spine of every function here is the directed trade weight, which spans 0.007 to 0.421 with 13.1× asymmetries, plus the pair's own history, plus each nation's own books.

## The session that pays four debts at once

V1.3a, V1.3b, V1.3c and V1.3d each shipped a **declared stopgap** — a deterministic counterparty rule, named in advance as this session's to replace, each pinned by a test that mutates the thing the stopgap ignores and asserts the answer does not move.

**All four had to go red before anything here was written, and all four did.** Recorded because the discipline is worthless if the going-red is assumed rather than watched:

| session | the assertion that died | how it died |
|---|---|---|
| **a** | *"acting on DEU moved the unrelated pair DEU\|ITA"* | assertion |
| **b** | the verdict unmoved by the target's whole economy | parse — `AGREEMENT_ACCEPT_MIN` no longer exists |
| **c** | *"the retaliation answer MOVED under mutation (0.3750 vs 0.0000)"* | assertion, with its own message naming this session |
| **d** | `Bloc.support(DEU, proposal)` identical before and after mutation | parse — `support()` grew a `state` parameter |

> [!note] The ROADMAP row was wrong three ways, and this session corrected it
> The row read *"Replaces every stopgap rule **b–d** shipped"* — undercounting by one, because [[diplomacy-model|V1.3a's no-reaction]] is the **first** of four rather than a precursor to three. The split trigger was *"if its own plan-time count comes back above V1.3a's"*, which V1.3b (~33), V1.3c (~30) and V1.3d (~39) all cleared without splitting; a test that fires four times for four non-splits is not a test, and the real one is [[ROADMAP|U5b's]] machine count. And the tier table had no V1.3e row — the **sixth** instance of the missing-row failure V1.3b recorded, not the fifth.

## The split, and why it went the way it did

**V1.3e is the interest model. V1.3f is the acting agent. Defence runs to V1.3g.** The decomposition predicted this row was the most likely to split and it did, but on machines rather than on the surface count it named.

The interest model is **one** machine with four readers that all exist today. The acting agent is a second — a scheduler, a target selector, new serialised state, and a surface for reading what was done to you. Three further reasons:

- **It is not the "state layer with no verb" failure [[diplomacy-model|V1.3a]] warns about.** Four live readers on day one is what makes it shippable alone where a relations score was not.
- **It keeps the balance re-run answerable.** With no agent, only the council's votes and the eleventh regime's retaliation are perturbed. An agent acting from month 1 perturbs all thirty runs and the re-run becomes a full re-baseline.
- **It is what f scores against.** An agent built before an interest function is what the decomposition already refused at (b).

## 1. Stake — how much B weighs in A's foreign policy

```
raw(A→B) = DEPENDENCE × w(A→B)/EVEN_SHARE
         + HISTORY    × min(1, |rel(A,B) − resting(A,B)| / HISTORY_SPAN)
         + IDEOLOGY   × alignment(A,B)
stake(A→B) = raw(A→B) / Σ_C raw(A→C)
```

**Normalised per viewer**, and that is what stops the model reading GBR as a nation that cares about nobody. Britain is in no EU pair, borders nothing in the roster and rests at 45 with all nine, so every *absolute* term it has sits at the floor. Normalised, the question becomes **who matters to Britain** rather than **how much Britain cares**, and only the first has an answer for every nation. Every threshold in the model is then expressed against `EVEN_SHARE` (1/9), the anchor [[ROADMAP|U5c's]] trade ramp already uses.

**The history term reads displacement, not level**, and that is not a detail. The relations *level* is already inside `w(A→B)` — [[trade-model|V1.3b measured it there]] — so reading it again would be the *two numbers for one intensity* redundancy [[coercion-model|the coercion probe cut]] between severity and an authored tariff rate. What is **not** in the trade weight is that somebody acted.

Consequence, stated rather than discovered: at new-game the history term is zero for all forty-five pairs, so interests are purely material at the start of a game and become political as it is played. `tests/test_foreign_policy.gd` asserts the zero exactly.

### The measured spread — the escalation trigger did not fire

The named trigger: *if the cross-nation L1 distance sits below the 0.05 line `tools/trade_probe.gd` calls a no-op, the session shipped nothing, and the response is a model decision rather than a tuning one.*

| | value |
|---|---|
| cross-nation L1 over 45 actor pairs, **min** | **0.085** |
| mean | 0.331 |
| max | 0.570 |

The closest two nations sit at **1.7× the no-op line**. It did not fire.

## 2. Amity — how warm A is toward B, signed

```
amity(A,B) = clamp( (rel(A,B) − resting(A,B)) / AMITY_SPAN
                    + IDEOLOGY × (2·alignment − 1), −1, +1 )
```

Distinct from stake and not a normalisation of it: stake is how much A cares, amity is whether that caring is friendly. A pair can be high-stake and hostile, which is the interesting case and the one a single number could not express.

> [!warning] The probe's first correction: a global neutral double-counts structure and reads it as sentiment
> Amity was first anchored at 56.5, the midpoint of the measured resting tiers. Every GBR pair then sat at **−0.575 forever**, because all nine of Britain's pairs rest at the floor of 45. The model was saying *Britain hates everyone* when the data says *Britain is structurally unattached*.
>
> The measured consequence was total: **France signed 9 agreements of 9, Germany 9 of 9, and Britain 0 of 9**, with every score negative and no amount of play able to move it. [[trade-model|V1.3b's own GBR trigger]], fired a fourth time in a new place.
>
> It was also a double-count. EU co-membership and the shared border are already inside the trade weight and inside stake through it; reading them a third time through a resting-derived relations level is one fact written twice.

So **structure lives in the trade weight, sentiment lives in displacement from rest**. Every pair reads exactly 0.0 at new-game — the same property stake's history term has, from the same argument — which leaves the model with **one** notion of sentiment rather than two.

What this costs, stated rather than discovered: at new-game an agreement's difficulty is carried entirely by how much of the target's trade runs through the proposer. For Britain that is still hard — Germany's stake in Britain is 0.68× an even share — but it is hard because **nobody depends on Britain** rather than because Britain is disliked, which is the same statement [[coercion-model]] already makes about its leverage.

## 3. Whether a partner signs — V1.3b's stopgap

```
accept(B→A) = STAKE × (stake(B→A)/EVEN_SHARE − 1)
            + AMITY × amity(B→A)
            + DEAL  × (weight_multiplier − 1)
            ≥ ACCEPT_MIN
```

Every term reads **zero at neutral** — stake at exactly an even ninth, a pair exactly at rest, a multiplier of exactly 1.0 — so `ACCEPT_MIN` is interpretable on its own.

The deal term is what V1.3b could not have: a generous agreement is now genuinely easier to sell than a thin one, so an author moving `weight_multiplier` moves how hard the content is to land rather than only what it pays.

### `ACCEPT_MIN` was constrained from above by GBR, for the second time in this block

`rest` is partners signing at new-game; `+10` is after one `settle_dispute`, the strongest single positive verb in the content.

| bar | FRA rest/+10 | DEU rest/+10 | GBR rest/+10 |
|---|---|---|---|
| 0.60 | 9 / 9 | 9 / 9 | 0 / 9 |
| 0.90 | 7 / 9 | 9 / 9 | 0 / 9 |
| **1.20** | **7 / 9** | **9 / 9** | **0 / 4** |
| 1.50 | 6 / 8 | 7 / 9 | **0 / 0** — closed |

**1.20**, with a 0.30 margin against the value that shuts one playable nation in three out of the feature entirely. [[amendment-model|Germany's unreachable two-thirds]] is what that margin exists to avoid, and clearing a bar by exactly nothing is [[scenario-model|`deu_grand_coalition`'s]] mistake.

The consequence is V1.3b's, unchanged and still forced: **for Germany the gate is non-binding**, because everyone depends on the largest economy in the roster and no bar that leaves Britain a feature can bite there. An agreement's difficulty for an EU nation is carried by the action's domestic price; for Britain the gate **is** the difficulty.

## 4. How hard a target answers — V1.3c's stopgap

```
leverage = w_before(imposer→target) / EVEN_SHARE     how much my answer would hurt
exposure = w_before(target→imposer) / EVEN_SHARE     how much it would cost me
fraction = clamp( leverage / (1 + DAMPING × exposure) × grievance, 0, CEILING )
```

`RETALIATION_FRACTION` survives as the **ceiling** where it used to be the answer. Both weights read *before* measures, for the reason [[coercion-model]] gives at length: you hurt in proportion to the trade you destroy.

**What falls out of it rather than being authored** — a small nation heavily dependent on a large one answers barely at all, because answering costs it more than it collects:

| | answered at |
|---|---|
| FRA tariffs LUX → Luxembourg answers | **0.058** |
| LUX tariffs FRA → France answers | **0.600** (the ceiling) |

**10.4×**, against the weights' own 12.2×. This is the thing [[trade-model|V1.3b's directed table]] made *sayable* and no session until this one could act on.

A `RETALIATION_MIN_SEVERITY` floor is what lets the model say **no** rather than only **how much**: below it no register entry is opened at all, because an entry at severity 0.01 is a diplomatic incident on the nation panel and on the map's relations layer that costs everyone nothing.

### The clamp V1.3c predicted, and the prediction was wrong

[[coercion-model]] labels `9 × 1.00` *"V1.3e's worst case"* and says outright that `COERCION_IMPULSE_MAX` *"binds only once V1.3e gives the other nine agency"*. Measured, with every one of the nine deciding for itself:

| actor | answers | sum severity | impulse | on the clamp? |
|---|---|---|---|---|
| FRA | 9 | 2.397 | −3.222 | no |
| DEU | 9 | 2.348 | −2.820 | no |
| GBR | 9 | 4.052 | −4.287 | no |

**Giving the nine agency made the worst case milder, not harsher**, because the nations that used to mirror at a flat 0.60 are exactly the small dependent ones that now decline. The clamp stays at 6.0 with 1.7 points of headroom.

GBR takes the worst of it, and that is the mirror of [[coercion-model|its leverage finding]]: everyone can afford to answer Britain hard, so **Britain also lacks deterrence**.

## 5. What a third party makes of it — V1.3a's stopgap

One signed rule, applied to every nation X outside the acting pair, both halves scaled by `stake(X→B)`:

- X's pair with the **actor** moves *with* the sign of the act
- X's pair with the **target** moves *against* it

So sanctioning Germany costs France standing with everyone who trades with Germany and wins Germany sympathy from exactly those nations. **A sanctioned nation acquiring sympathisers** is the most legible thing an interest model can produce, and [[ROADMAP|U5c's relations map layer]] is already the readout for it.

V1.3a parked this on the grounds that third-party effects need an alliance model. That was right at the time and is not now: stake already carries EU co-membership and the shared border, so the channel exists **without an alliance in it**. Alliances at V1.3g make it stronger, not possible.

Two properties, both asserted rather than assumed:

- **A floor.** Without `THIRD_PARTY_MIN_STAKE_SHARE`, every act moves all eight remaining nations by some tiny amount and forty-five pairs drift on every click for reasons no readout could explain.
- **The whole list is resolved before any of it is applied.** Applying one adjustment moves the relations the next stake is scaled by, so a resolved-as-you-go version would depend on `Dictionary` iteration order — [[trade-model|the ordering bug the trade probe caught]] in the impulse, which was invisible until something finally perturbed a partner.

## 6. How a council member votes — V1.3d's stopgap

```
appraise(A, P) = IDEOLOGY × alignment(A, P)
               − RULE     × breach A would carry under P's constraint
               − TRANSFER × P.transfer_pct_gdp × fiscal stress
               − EXTERNAL × A's own trade outside the bloc × P's severity
```

Every term but the first is against the member's **own books**, and every one of them differs across the eight where `coalition_position` does not.

`Bloc.rule_breach()` was extracted for it — the same arithmetic was already written three times (in `burden()`, in `rules_in_force()` for the panel, and it would have been a fourth here). It takes a rule *dictionary*, so a rule in force and a proposal's `constraint` go through one function: a member prices a rule it is being asked to adopt against the same arithmetic that will bind it afterwards, and **a member already inside a proposed rule scores exactly 0.0 by construction**.

> [!warning] The probe's second correction: the weak term was not weak enough
> At `APPRAISE_RULE_WEIGHT = 1.00` a single rule's burden tops out at that rule's own severity, and [[bloc-model|V1.3d rescaled the four severities to sum to exactly `BURDEN_MAX`]] — so no one of them exceeds 0.33. Against an ideology term reaching 0.35 the two were **commensurate**, and the measured result was a council in which every member already in breach of the deficit rule voted **for** it: AUT +0.168, DEU +0.225, FRA +0.135, all carried by ideology over a cost they were going to pay. V1.3d's council-of-priors failure, in the other direction. At 3.00 a full breach reads about 1.0 and a rule that will bite decides the vote.

### `SUPPORT_THRESHOLD` was swept against four columns, where V1.3d swept three

| threshold | carried | FRA decides | lost anyway | abstention window |
|---|---|---|---|---|
| 0.00 | 6 | 0 | 1 | 0 |
| 0.05 | 5 | 1 | 1 | 1 |
| **0.15** | **3** | **2** | **2** | **1** |
| 0.20 | 3 | 1 | 3 | **0** |
| 0.25 | 1 | 2 | 4 | 2 |
| 0.40 | 1 | 0 | 6 | 0 |

> [!warning] The probe's third correction, and a test caught it: constructive abstention has a window nobody had measured
> Abstaining differs from opposing **only** when the other eight land in [172, 216) of 393 seats — a window 11 % of the range wide, because abstaining removes the player from the denominator and nothing else. V1.3d swept only the first three columns, so its own constructive-abstention property came out of the shipped content by luck. At threshold 0.20 that window is **empty**: three vote options, two outcomes, which is the decorative-verb failure with entirely correct arithmetic.
>
> `tests/test_bloc.gd` now **scans** the content for a proposal in the window rather than naming one — V1.3d hardcoded `stability_pact`, and a test naming a proposal is a test about the content rather than about the mechanism.

0.15 also has the better first three columns. At 0.00 France is pivotal on **nothing**, which is V1.3d's own failure mirrored: that session found six of seven proposals decided by France and called it a legislature the player controlled, and a council the player can never move is the same fault from the other side.

### What the council now says, that it could not before

The same proposal, priced by each member's own books:

- `cohesion_fund` (+0.28 % of GDP): **every member votes against**, reason `would_pay`.
- `recovery_facility` (−0.30 % of GDP): **every member votes for**, reason `draws_on_it`.

Under V1.3d's rule those two were indistinguishable if they sat at the same point in ideology space. `stability_pact` now divides the council 5–3, with the members in breach of it voting against.

## The readouts

**`refused_by_partner` shipped at V1.3b and nothing in `src/ui/` ever read it** — so a partner declining a treaty was, until this session, completely silent to the player. The model returns a **key**, not a sentence, because `src/sim/` does not know the UI exists and a test asserting a key survives a session that rewords a tooltip.

- `nation_panel.gd` names the weakest of the three accept terms: too little of their trade runs through you / relations are not close enough / these terms are not worth it.
- `bloc_panel.gd` groups the council by reason rather than listing eight nations, because the interesting object is the **camp**. Reasons are recorded at the moment of the division rather than recomputed on repaint — the books a member voted on were that month's, which is [[coercion-model|the stale-budget-panel bug V1.3c fixed]] avoided rather than repeated.
- Third-party drift needs no new surface: U5c's relations layer is already it.

## The balance re-run

Ten regimes × three playable nations = **thirty fourteen-year runs**, captured from a worktree at the V1.3d commit and diffed against the rebuilt tree, `^ERROR:` and `^   at: ` stripped from both sides.

**The question is *has anything moved materially?*, not *at all*.** [[trade-model|V1.3b's]] and [[coercion-model|V1.3c's]] re-runs could ask the sharper question because an agreement and a measure each need a player command and no regime issues one. [[bloc-model|V1.3d]] ended that, and this session cannot restore it: the council meets whether or not the player engages, and this session changes how it votes.

**15 of 30 runs changed. Exactly one changed outcome.**

| quantity | max abs change | where |
|---|---|---|
| GDP | 3.64 % | GBR `hands_off` 2040 |
| growth | 2.20 pp | GBR `managed` 2039 |
| trend | 0.07 pp | GBR `hands_off` 2040 |
| unemployment | 1.07 pp | GBR `ruinous` 2040 |
| debt ratio | 55.5 pp | GBR `ruinous` 2040 |
| deficit | 1.11 pp | GBR `ruinous` 2040 |
| approval | 20.2 pp | GBR `spend_max` 2040 |

**Every large mover is GBR, and the mechanism is a V1.3d feature that V1.3d's own re-run never fired.** Britain is not a council member, so nothing here should have touched it — the reason it did is `common_external_tariff`, the proposal [[bloc-model|V1.3d built to aim the bloc at non-members]]. Under the old ideology-only vote the council never adopted it inside fourteen years. Under an appraisal it does, and the signature is unambiguous: GBR's trend falls 1.32 → 1.25, which is the openness channel, while growth goes to −0.87, which is the coercion impulse. In the V1.3d tree both sat flat at 1.32 for all 168 months.

So the movement is not the interest model leaking into the economy. It is the bloc doing the thing it was built to do, to the nation it was built to do it to, for the first time in the harness.

### One run of thirty changed outcome, and it was decided by one seat

`DEU hands_off`. In the V1.3d tree the incumbent takes 29.8 % and 188 of 630 seats in 2029 and **holds**; in the new tree it takes 29.6 % and 187 seats and **loses**, ending the run. A one-seat margin — [[bloc-model|V1.3d's own two-seat censure]] one session on, and the same reading: a knife-edge result that was never robust.

`tests/test_balance.gd`'s three S10 assertions all still pass, and they are what the property actually rests on.

> [!warning] The re-run caught a break the test suite structurally could not
> `tools/balance_probe.gd` still referenced `AGREEMENT_ACCEPT_MIN` and failed to parse — every one of the thirty new runs produced three lines of parse error instead of fourteen years. `tools/` is excluded from `run_tests.sh` by design, so a green suite said nothing about it. The unbounded `while` that constant guarded also had to become a bounded loop: it lifted relations until the pair cleared a relations bar, and a counterparty that can refuse for a reason relations do not fix would have hung the probe rather than reported it.

## `SAVE_VERSION` stays at 11

Checked against the rule `game_state.gd` states — *would a missing field read as something wrong?* — rather than assumed. **This session adds no serialised field at all.** Both functions are derived at read time from live state; the two things they write, `relations` and `measures`, were already serialised at V1.3a and V1.3c.

That is a property rather than a coincidence, and it is what **no grievance ledger** buys: the relations number *is* the memory, so there is nothing for a save to carry. `tests/test_save_load.gd` asserts the version is still 11.

## Bounds

| Quantity | Bound |
|---|---|
| A stake vector | Normalised, sums to 1 by construction. Asserted for all ten. |
| Amity | `[−1, +1]`, clamped, and exactly 0.0 at new-game for all forty-five pairs. |
| A retaliation fraction | `[0, RETALIATION_FRACTION]`, asserted over all ninety ordered pairs. |
| An answered severity | Below `RETALIATION_MIN_SEVERITY`, no register entry is opened. |
| Third-party reach | `THIRD_PARTY_MIN_STAKE_SHARE` of an even share. Below it, X does not notice. |
| The coercion impulse | `COERCION_IMPULSE_MAX` = 6.0, measured unreached at −4.287 in the worst case. |

## Deliberately absent

- **No grievance ledger.** The relations number is the memory. This is what keeps `SAVE_VERSION` at 11 and what makes the model a pure read.
- **No agenda.** The nine still never act first, never propose an agreement, and never escalate past a single answer. **V1.3f.**
- **No lifting `Economy`'s `if ns.has_budget` guard.** Pricing every act by simulating the actor's own budget needs the nine to carry a live budget and opinion model, which is the model rewrite [[trade-model]] books separately.
- **No new content type and no new effect channel**, for the fourth session running.
- **`AGREEMENT_ACCEPT_MIN` and `SUPPORT_SIGMA` are deleted, not left unused.** A tuned constant nothing reads is a number a later session will find and reason from. `tools/bloc_probe.gd`'s sigma sweep went with them — it carried its own inline copy of a Gaussian the model no longer has.

---

Related: [[ROADMAP]] · [[diplomacy-model]] · [[trade-model]] · [[coercion-model]] · [[bloc-model]] · [[economy-model]]
