---
title: Coercion Model
tags:
  - model
  - sim
  - economy
---

# Coercion Model

Tariffs and sanctions: what they collect, what they destroy, who answers, and what it costs at home. Built at [[ROADMAP|V1.3c]], the third session of the V1.3 block.

Files: `src/sim/coercion.gd` (the rules) · `src/sim/coercion_constants.gd` (the numbers) · `data/diplomatic-actions/measures.json` (the content) · `GameState.measures` (the register) · `tools/coercion_probe.gd` (the measurement).

> [!important] Revenue now, trend later
> This is the session's central call and everything below follows from it. A tariff collects on the trade that still crosses the border and destroys some of the trade it is levied on. The collection is a **revenue line**; the destruction is a **permanent trend cost**, paid through the openness channel [[trade-model|V1.3b]] already built and already measured. Neither is authored: both fall out of two constants.

## The first directed state

Relations are symmetric and agreements are symmetric, because a relationship and a contract each have one shared value. A **measure does not**. `FRA>DEU` and `DEU>FRA` are two separate acts, and a retaliation is precisely the second one.

[[diplomacy-model|V1.3a]] named this in advance:

> If V1.3c needs "A resents B more than B resents A", it adds a **directed grievance layer over** the symmetric level. The pair key does not change, and nothing already reading `relations` is rewritten.

That is exactly what shipped. `src/core/relations.gd` gains `directed_key()` and a **different separator** (`>` against `|`) so the two kinds of key cannot be confused: `other()` returns `""` for a directed key, `directed_parts()` returns `[]` for a symmetric one, and `tests/test_coercion.gd` asserts both. Nothing that reads `relations` or `agreements` changed.

## 1. What a measure does to trade

```
severity_on_pair(A,B) = severity(A>B) + severity(B>A)
trade_multiplier      = max(FLOOR, 1 − MEASURE_TRADE_BITE × severity_on_pair)
                      = max(0.10,  1 − 0.80 × severity)
```

Applied to the pair's raw gravity weight in `Trade._raw()`, for measures in **either direction**. The register is directed; the trade effect is not. Goods stop moving both ways whichever side imposed, and that is not a fact about who is angry.

**Exactly 1.0 on a clean pair**, by construction rather than by tuning. That is half of what makes the balance re-run below provable rather than likely.

### The openness asymmetry, which is the model's whole trade-off

`Trade._raw()` took a single `with_agreements` flag and now takes two — `with_agreements` and `with_measures`. `openness_index()`'s counterfactual is therefore *"no agreements **and no measures**"*, so imposing a tariff drops the index below 1.0 and takes trend growth down through the same `potential_shift_pct` channel infrastructure and education write.

This does **not** reopen [[trade-model|the `state_visit` exploit]]. A measure costs relations, costs blocs, invites retaliation, and moves the level *down*. There is nothing to farm.

## 2. What a measure does to the target

```
coercion_impulse(B) = −COERCION_DAMAGE × Σ_A severity(A>B) × w_before(B→A)
                      clamped to ±COERCION_IMPULSE_MAX
```

A **new additive term** in `Economy._tick_nation()`'s growth sum, beside the demand and external impulses:

```gdscript
growth = trend + GAP_CLOSE × (−gap) + demand_impulse + external_impulse + coercion_impulse
```

Sustained while a measure is in force rather than decaying like `demand_impulse_pct`: a sanction in force is a standing condition, not a shock, and it must stop when the measure is lifted rather than fade while it is still biting.

> [!note] This is not the trade impulse, and the AI-impulse deferral stands
> `Economy.tick_month()`'s `if ns.has_budget` guard is **untouched**. The nine still take no *trade* impulse; [[trade-model]] records the coupled eigenvalues so it can be lifted knowingly, and lifting it replaces the 28-month output-gap half-life [[economy-model]] argues the game's pacing from — a model rewrite, not a wiring change.
>
> The coercion term is a different channel and runs for all ten. The path is **one hop**: the player sanctions Germany, Germany's growth falls, and the player feels it back through their *own* `external_impulse_pct` at `w(FRA,DEU)`. No loop, because Germany has no external impulse to carry it onward.

### Damage reads the trade *destroyed*, not the trade *surviving*

The probe's second correction, and it was a trap in the content caught before any content existed. Read off the post-measure weight, a full embargo does almost nothing — it has destroyed the trade it was damaging through — so **every severity above the revenue peak was strictly dominated**: less revenue *and* less damage, for more trend cost.

`Trade.weights_before_measures()` exists for this. The two effects read different weights because they are different quantities:

| | reads | shape in severity |
|---|---|---|
| **Damage** | the trade a measure destroys | monotone up |
| **Revenue** | the trade that still crosses | interior maximum |

Only revenue has the Laffer shape, and that is the true story rather than a tuned one.

### Where V1.3b's directed table earns its keep a second time

Damage scales with `w(target → imposer)` — how much the target depends on you, not how much you depend on them.

| pair | w(t→i) | target's peak impulse |
|---|---|---|
| FRA > LUX | 0.257 | **−2.054** |
| LUX > FRA | 0.021 | **−0.170** |

**12.1×**, against the weights' own 12.2×. France sanctioning Luxembourg is devastating; Luxembourg sanctioning France is a gesture. Neither statement is expressible on a symmetric key, and an unweighted constant would have made the smallest nation in the roster as dangerous as the largest.

## 3. What a tariff collects

```
revenue_pct_gdp(A) = TARIFF_YIELD × Σ_B severity(A>B) × w_after(A→B)   over tariffed B
```

A revenue **line of its own** on `ns.revenue_pct_gdp`, written by `Budget.recompute()` beside the `other` line — not a fourth entry in `TAX_KEYS`. [[v1]] §6's five-tax target does not include tariffs, and a tariff has no slider, no base share and no erosion curve, and is per-partner rather than national. Folding it into `other` was the alternative and is worse: a revenue source the player chose and cannot see on the panel is [[scenario-model|the decorative-axis failure]] with a different label.

`Budget.recompute()` grew a `state` parameter for it — three call sites, all of which already had the state. Not a cached field written by the economy pre-pass, because the budget panel is the one surface that promises *this is what will happen*, and a tariff imposed this month whose revenue appeared next month would be a lie on exactly that surface.

### Severity is the only dial, and an authored rate was cut

The probe's **first** correction. `effects.measure` originally carried both `severity` and `tariff_rate_pct`. Measured, yield was exactly linear in the rate — **0.0005 per point, at every rate, for every nation** — because the trade bite read severity and the rate only scaled the answer. Two numbers describing one intensity is the redundancy [[trade-model|`trade_probe.gd` caught]] between the gravity tie bonuses and the relations term, resolved the same way: carry it once. `src/core/diplomatic_action.gd` refuses a file carrying a rate, so an author reaching for one finds out why there isn't one.

What that bought is a Laffer curve that is **real rather than asserted**, with an interior maximum at `1 / (2 × MEASURE_TRADE_BITE) = 0.625`:

| severity | w after | rev % GDP | vs a tax point | openness |
|---|---|---|---|---|
| 0.200 | 0.292 | 0.117 | 0.23× | 0.9473 |
| 0.400 | 0.250 | 0.200 | 0.40× | 0.8947 |
| **0.625** | 0.197 | **0.246** | **0.49×** | 0.8355 |
| 0.800 | 0.150 | 0.240 | 0.48× | 0.7894 |
| 1.000 | 0.089 | 0.179 | 0.36× | 0.7367 |

France against Germany. Past the peak a harsher tariff collects **less**, because it has destroyed more of the trade it is levied on. Nothing authors that.

The anchor is the panel the line sits on: `economy_constants.TAX_BASE_SHARE` makes one point of VAT worth 0.53 % of GDP, so **one tax point is roughly half a percent**. A tariff on the largest partner is worth about half a tax point; tariffing the whole roster at full severity is worth **4.0 tax points and costs 80 % of the openness index**, which is most of the `SHIFT_MAX_PCT` budget. That is the trade-off stated in numbers.

> [!note] Tariffing everybody makes the weight term cancel
> A uniform multiplier on all nine pairs divides out under normalisation, so revenue is exactly `TARIFF_YIELD × severity` for every nation identically — 1.25 % at 0.625, 2.00 % at 1.0. Not a bug: it says a nation that tariffs everyone collects on its whole external demand whatever the shape of it. The openness figure beside it is what carries the cost, and that does not cancel.

## 4. Domestic blowback

**Imposing** pays through `bloc_offset`, the channel a law, a censure, a reshuffle, a dissolution and a diplomatic action already write. No new `ISSUE_KEYS` entry — that call was [[ROADMAP|V1.3d's]], and it went the other way: six new `BLOC_SALIENCE_BASE` rows were authored, for reasons that are about the bloc rather than about coercion. See [[bloc-model]].

**Receiving** pays through `opinion.gd`'s existing terms: `sat["growth"]` reads `growth − trend` and `sat["jobs"]` reads `start_unemployment − unemployment`. No `bloc_offset_target` channel was invented. **Whether that path is legible was the session's named escalation trigger**, and it is the one question the plan flagged as most likely to fail.

### The trigger, and why it did not fire

The prior was bad. [[trade-model]] measured the transmission channel's headroom at **6 % of `IMPULSE_MAX`** under a synthetic partner recession larger than any sanction should produce, and the first sweep — with damage read off the post-measure weight — came back at **−1.41 approval against a ±3.0 poll-noise floor**: not legible for any playable nation.

Fixing the weight the damage reads (§2) is what moved it. At the shipped constants, one full-severity embargo by the largest partner, held sixty months against a control:

| actor | peak coercion | peak growth | peak unemp | **peak approval** | legible? |
|---|---|---|---|---|---|
| FRA | −2.633 | −2.637 | +1.225 | **−7.373** | yes |
| DEU | −2.437 | −2.441 | +1.134 | **−6.654** | yes |
| GBR | −1.932 | −1.935 | +0.898 | **−4.938** | yes |

The weakest playable nation clears ±3.0 with **1.9 points to spare** rather than by exactly nothing, which is [[scenario-model|`deu_grand_coalition`'s]] mistake avoided.

**The asymmetry that made this survivable is worth stating:** the *imposing* side is legible **by construction** — tariff revenue is a number on the budget panel and the relations cost is a number on the nation panel. Only the *receiving* side ever depended on the transmission channel.

### The clamp was raised, because it was binding in reachable play

`COERCION_IMPULSE_MAX` was provisionally 4.0, "comfortably inside `IMPULSE_MAX_PCT`". The sweep found that **binding**: a player who tariffs three or more partners collects three or more retaliations, damage sums over imposers, and the clamp rather than the model was setting the growth rate — [[economy-model|the `IMPULSE_MAX` failure]] committed a third time.

It ships at **6.0**, equal to `IMPULSE_MAX_PCT`: a coercion shock may be as large as the largest budget shock and no larger, which is a principled anchor where "somewhat less" was a feeling.

| imposers × severity | what produces it | peak impulse | clamped? |
|---|---|---|---|
| 1 × 1.00 | one embargo | −2.633 | no |
| 3 × 0.60 | three retaliations | −3.349 | no |
| 9 × 0.60 | nine retaliations | −4.800 | no |
| 9 × 1.00 | V1.3e's worst case | −6.000 | **yes** |

Everything this session can reach stays off the clamp. It binds only once V1.3e gives the other nine agency, and `tools/balance_probe.gd` now asserts the player is never *on* it.

## 5. A measure breaks an agreement

[[trade-model]] booked this here — *"no agreement duration or expiry. V1.3c owns it, via a sanction breaking one"* — and it is discharged in one line rather than by building a duration model: `Diplomacy.execute()` erases `state.agreements[Relations.key(a, b)]` when an impose lands on that pair.

Symmetric key, deliberately: the contract had two sides even though the measure has one, so imposing on a partner ends the treaty for both. `src/core/diplomatic_action.gd` refuses an action carrying **both** `effects.agreement` and `effects.measure`, because it would describe an outcome depending on the order the channels are applied in.

## 6. Retaliation is the third declared stopgap

> [!success] Discharged at V1.3e
> ~~A nation under a measure mirrors it back once, at `RETALIATION_FRACTION` of the severity, after `RETALIATION_DELAY_MONTHS`.~~ The target now decides how hard to answer -- from how much the imposer depends on it against how much it depends on the imposer -- and can decide **not to answer at all**, which a fixed mirror could not. `RETALIATION_FRACTION` survives as the ceiling.
>
> What falls out rather than being authored: France tariffing Luxembourg is answered at 0.058, Luxembourg tariffing France at the 0.600 ceiling. **10.4x**, against the weights' own 12.2x -- the thing the directed table made *sayable* and no session until V1.3e could act on.
>
> `tests/test_coercion.gd` asserted the old rule by mutation and **went red with its own message naming this session**. Still one step and still never first: escalation and acting on its own initiative are V1.3f's. See [[foreign-policy-model]].

Third on V1.3e's checklist, after [[diplomacy-model|V1.3a's no-reaction]] and [[trade-model|V1.3b's accept-gate]]. The three compose rather than conflict: one says the target does not *react*, one says it does not *decide*, this one says it reacts by a fixed rule and decides nothing.

`tests/test_coercion.gd` asserts it **by mutation** — the target's GDP cut 100×, unemployment at 39 %, growth at −11 %, approval at 3, sectors gutted, and a third pair moved — and the answer must not move. **That test must fail and be rewritten at V1.3e.**

It lives in `Diplomacy.tick_month()`, which already ran for all ten nations and whose own comment anticipated exactly this. No new module tick, no new line in `main.gd`'s chain, and it rides into `Budget.project()` free because V1.3b already made the projection tick `Diplomacy`.

### Convergence is structural, not a consequence of the fraction

Each register entry carries a `retaliated` flag, set whether or not an answer lands. The exchange therefore terminates at **two entries** regardless of `RETALIATION_FRACTION`; the fraction being below 1.0 is about the answer being an answer rather than about making an infinite series converge.

| month | entries | FRA sev | DEU sev | FRA impulse | relations |
|---|---|---|---|---|---|
| 1 | 1 | 1.000 | — | 0.000 | 68.00 |
| 3 | 2 | 1.000 | 0.600 | 0.000 | 64.00 |
| 4 | 2 | 1.000 | 0.600 | −1.516 | 64.08 |
| 24 | 2 | 1.000 | 0.600 | −1.516 | 65.38 |

Relations take the hit at the moment of retaliation and then drift back toward resting, which is `DRIFT_RATE` doing its job over a measure that stays in force.

## GBR again, and this is the third time

[[trade-model|V1.3b's GBR trigger fired]] and closed a feature to one playable nation in three at the obvious constants. Checked again here, and **the gate direction inverts**: a hostile verb has no relations floor to clear, so copying `AGREEMENT_ACCEPT_MIN`'s shape onto a measure would have closed the feature to whoever is *friendliest*. There is no gate.

What Britain's isolation costs it is **leverage**, and the first version of the probe's table measured the wrong thing — it picked each nation's own largest trade partner, when damage scales with `w(target → imposer)`. Swept over all nine instead:

| actor | best hit on | best damage | best revenue |
|---|---|---|---|
| FRA | ESP | −2.983 | 0.179 |
| DEU | NLD | −3.366 | 0.161 |
| **GBR** | CHE | **−0.780** | **0.120** |

**Revenue is open to GBR** — within 1.5× of the others, because tariffing collects on your *own* external demand and every nation has one. **Damage is not**: its best possible hit is a quarter of the other two's, because damage needs someone who depends on you and nobody much depends on Britain in this roster.

Forced by the trade vector rather than chosen, and thematically right: leverage is what a nation outside the bloc with no land borders actually lacks. Recorded rather than tuned away.

## The balance re-run

[[trade-model]] booked one to this session: *"tariffs move revenue and sanctions move a partner's growth, and both reach figures every economy constant was measured against."*

Ten regimes × three playable nations = **thirty fourteen-year runs**, captured from a worktree at the V1.3b commit and diffed against the rebuilt tree.

**All thirty are bit-identical.** Not within tolerance — byte for byte, once the engine's own gitignored-addon noise is filtered. The invariant the model was shaped to make provable: no regime imposes a measure, so the register is empty, the trade multiplier is exactly 1.0, the coercion impulse exactly 0.0 and the tariff line exactly 0.0, all by construction. Every economy constant measured before V1.3c is still valid, unchanged and unargued.

An eleventh regime, `managed_imposes_tariffs`, is where the coercion channel gets its own fourteen years: the player tariffs their largest partner at month 6, the partner retaliates three months later, and both sit in force for the rest of the run. Clean over 168 months, no clamp reached.

`_check()` gained one assertion, scoped the way V1.3b's was: the coercion impulse must never sit **on** `COERCION_IMPULSE_MAX`, because a guard rail setting the growth rate is the failure this model exists to avoid.

## `SAVE_VERSION` stays at 10

Checked against the rule `game_state.gd` states — *would a missing field read as something wrong?* — rather than assumed:

- absent `measures` reads as `{}`: **correct**, a version-10 save could not impose one. [[trade-model|`agreements`' case]] exactly.
- absent `coercion_impulse_pct` reads as 0.0: **correct**, nothing was in force.
- absent `retaliated` reads as no pending retaliation: **correct**.

No field earns a bump. `tests/test_save_load.gd` asserts all three *and* asserts the version is still 10, so a later session raising it has to come and say why.

## Bounds

| Quantity | Bound |
|---|---|
| One authored measure's severity | `MAX_MEASURE_SEVERITY` = 1.0, checked at load. Deliberately **past** the revenue peak of 0.625, so the ceiling is not the interesting point on the curve. |
| A pair's trade multiplier | `MEASURE_TRADE_FLOOR` = 0.10. A severed pair would renormalise the weight vector onto the remaining eight and read as the player *gaining* trade with everyone else. |
| The coercion impulse | `COERCION_IMPULSE_MAX` = 6.0, equal to `IMPULSE_MAX_PCT`. Asserted unreached by `tools/balance_probe.gd`. |
| Tariff revenue | Bounded by `TARIFF_YIELD` at 2.0 % of GDP, since the weight term cancels when everything is tariffed. |
| Measures per directed pair | One. A second would need a rule for how two sets of terms compose, and no content wants one. |

## Deliberately absent

- ~~**No EU tariff competence.** A bloc that sets external tariffs collectively is [[ROADMAP|V1.3d's]], and reaching into it here would build the bloc badly.~~ Built at V1.3d: a `common_external_tariff` proposal writes this register for every (member, non-member) ordered pair through `Relations.directed_key()`, the **same key** a player's own tariff uses — so nothing in `src/sim/coercion.gd` or `src/sim/trade.gd` needed a line changed to read it. See [[bloc-model]].
- **No third-party effects.** Sanctioning Germany does not move `DEU|ITA` or Austria's economy. V1.3e's, and `tests/test_coercion.gd` pins it.
- ~~**No new `ISSUE_KEYS` entry**, unchanged from V1.3a and V1.3b.~~ Still true of V1.3c, and V1.3d answered the deferred question **yes**: `europe` is the twelfth. The reason it could not be another `bloc_offset` writer is that `bloc_offset` never reaches `issue_salience`. See [[bloc-model]].
- **A scenario cannot author a measure in force.** [[scenario-model|The three axes]] are unchanged, stated so it is a decision rather than an assumption.
- ~~**No sanctions on a bloc.** One measure, one pair. Multi-target coercion is V1.3d's, where a bloc exists to act as one.~~ Built at V1.3d, and it is what a non-member playable nation receives: the bloc acting as one is the only thing in this game that imposes from eight directions at once. Still one measure per pair — the multi-target part is eight entries, not a new shape.

---

Related: [[ROADMAP]] · [[trade-model]] · [[diplomacy-model]] · [[economy-model]] · [[opinion-model]] · [[data-architecture]]
