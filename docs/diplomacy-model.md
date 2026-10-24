---
title: Diplomacy Model
tags:
  - model
  - sim
---

# Diplomacy Model

Pair-keyed relations, their monthly drift, and the player's diplomatic actions. Built at V1.3a, the schema session of the V1.3 block.

Files: `src/core/relations.gd` (the key) · `src/sim/diplomacy.gd` (the rules) · `src/sim/diplomacy_constants.gd` (the numbers) · `src/core/diplomatic_action.gd` (the content type) · `data/diplomatic-actions/*.json` (the content) · `tools/diplomacy_probe.gd` (the measurement).

> [!important] This block ships relations *with* a verb, not as a state layer
> A relations score whose first reader arrives a session later is the failure [[scenario-model|V1.2e]] caught at design time: an axis with no persistent channel is decorative. V1.3a ships the smallest closed loop instead — act on a neighbour, relations move, blocs at home react.

## The first state that is neither per-nation nor global

Every field in this game up to V1.3a hangs off a `NationState` or off `GameState` directly. A relations score belongs to a **pair**, and that is the whole reason this session was marked plan-first and High: everything V1.3b–f reads off whatever shape it picked, so a wrong pair key is rewritten along with all five sessions that use it.

Four questions were settled before any code.

### 1. Symmetric — one number per unordered pair

`GameState.relations` holds 45 entries over the ten nations, keyed `"DEU|FRA"` — sorted, and built only by `Relations.key()`, never by string concatenation at a call site. `rel(A, B) == rel(B, A)` is therefore **structurally true** rather than an invariant somebody has to maintain.

The rejected alternative was two directed numbers. It is truer in the abstract: Luxembourg cares more about Germany than Germany about Luxembourg. But that asymmetry is about **interest and leverage**, and both of its inputs — relative size, and (from V1.3b) trade share — are already per-nation and derivable per-viewer at read time. It is not a second relations number. Shipping 90 entries at V1.3a would have shipped a schema claiming information no source could supply, with all 45 pairs starting equal anyway.

> [!note] The escape hatch is named, so widening stays additive
> If V1.3c needs "A resents B more than B resents A", it adds a **directed grievance layer over** the symmetric level. The pair key does not change, and nothing already reading `relations` is rewritten.

> [!success] Taken at V1.3c, exactly as written
> `GameState.measures` is keyed `"FRA>DEU"` by a second builder in the same file, on a **different separator**, so `other()` refuses a directed key and `directed_parts()` refuses a symmetric one. Relations and agreements were not touched. A tariff and its retaliation are two entries because they are two acts — which is the thing a symmetric key could never say. See [[coercion-model]].

### 2. Derived starting values — from two inputs, not three

[[data-sources]] has nothing to author 45 numbers from; its own *what datasets cannot provide* list is explicit. The precedent leans derived anyway — [[cabinet-model|competence]] is derived, and military capability is already scheduled derived at V1.3f.

```
resting(A, B) = REST_BASE + EU_CO_MEMBER_BONUS + SHARED_BORDER_BONUS
              = 45.0     + 15.0 (if both)     + 8.0 (if bordering)
```

- **EU co-membership** already existed — `Nation.eu_member`, from `government.eu.member`. Live rather than degenerate: GBR and CHE are outside it.
- **A shared land border** did not, and is added as `government.neighbours` on each nation file. This is a **fact**, the same class as `assembly_seats`, not a tuning number. Borders outside the roster (Portugal, Slovenia, Denmark) are deliberately absent — nothing reads them. GBR's list is empty, which is correct and is why the field is required-and-possibly-empty rather than optional.
- **Size asymmetry was dropped**, and it falls straight out of question 1: under a symmetric key a size disparity has nowhere honest to go, because the pair's single number cannot express "the smaller partner has less leverage". It belongs to V1.3b's read-time trade weighting. Recorded here rather than silently omitted.

> [!success] Landed at V1.3b, and the escape hatch was not needed
> [[trade-model|The directed trade weight]] is normalised per viewer, so it has two sides where the pair key has one, and the disparity is simply the ratio between them: `w(LUX→DEU)` is **13.1×** `w(DEU→LUX)`, while `w(FRA→DEU)` and `w(DEU→FRA)` differ by 1.1×. Luxembourg's trade is mostly with Germany and Germany's is barely with Luxembourg; France and Germany matter to each other about equally. Neither statement is expressible here, both fall out there for free, and **nothing in this file changed to allow it** — which is what the note below predicted.

`GeoLoader.validate_neighbours()` (`src/core/loaders/geo_loader.gd`) fails at startup if a border is not mutual. Without it the symmetric key would be resting on an asymmetric input, and the derivation would depend on which file it happened to read first.

The four tiers this produces, and the pairs at each:

| Resting | EU both | Border | Pairs |
|---|---|---|---|
| **68** | yes | yes | AUT\|DEU, AUT\|ITA, BEL\|DEU, BEL\|FRA, BEL\|LUX, BEL\|NLD, DEU\|FRA, DEU\|LUX, DEU\|NLD, ESP\|FRA, FRA\|ITA, FRA\|LUX |
| **60** | yes | no | thirteen pairs, e.g. FRA\|NLD, DEU\|ITA |
| **53** | no | yes | AUT\|CHE, CHE\|DEU, CHE\|FRA, CHE\|ITA |
| **45** | no | no | every GBR pair, plus CHE's non-bordering ones |

Spread: **23 points**. That is the range an action has to be legible against.

### 3. `GameState.relations`, keyed by a sorted pair string

The obvious answer, and it survives `duplicate_state()`, `to_dict()`, `from_dict()` and the budget projection with one line each — JSON dictionary keys are strings natively. Mirroring onto each `NationState` was the alternative; it doubles the write path and reintroduces exactly the divergence the symmetric key just made impossible.

The scale is **0–100**, matching approval's readability rather than the `[-1, +1]` the ideology axes use. The player reads this number off a panel and an action's preconditions compare it, so it is in the units the player thinks in.

What *is* per-nation is `diplo_cooldown_months` — the acting nation's own record of what it has recently done, keyed `"action_id|TARGET"`. Per pair, not per verb: condemning Germany is no reason to be unable to condemn Italy.

### 4. `law_bloc_offset` was renamed to `bloc_offset`

The prefix stopped being true four writers ago. A law writes it; so do `Government.penalise_blocs()` after a censure or an Article 49.3, a cabinet resignation, a reshuffle, a dissolution, a scenario's authored starting approval — and now a diplomatic action, the fifth non-law writer. It is the model's **one** persistent per-bloc approval channel.

The save version was bumping for `relations` anyway, and a serialised field is only free to rename inside that window. No behaviour change: it is a state field, not a dispatch string, so [[political-systems|V1.2b's]] rename hazard does not apply.

## The action content type

`data/diplomatic-actions/*.json` is directory-scanned, exactly like `data/laws/` and `data/scenarios/` — adding an action is a file, not a file plus an index entry.

Borrowed from [[legislature-model|the law template]]: **preconditions, cooldown, effects.** Deliberately not borrowed:

| Not borrowed | Why |
|---|---|
| `position` | There is no assembly division to score against an ideology axis. Giving it one would be a parallel vocabulary for a mechanism that does not exist here. |
| `majority` | Same. A diplomatic action is an executive act. |
| `once` | The cooldown is per (action, target). A state visit to Germany and one to Italy are separate uses of the same verb; "once, ever, against anybody" is a shape no action wants. |

Two effect channels at V1.3a, three since. `relations` is **required and non-zero** — an action that moves no pair is a domestic gesture wearing a diplomacy label, the same class of quiet lie `scenario.gd` refuses for an overrides block that overrides nothing. `bloc_offset` is optional.

**`effects.agreement` is V1.3b's, and it is why that session shipped no content type of its own.** An `enter` carries the economic terms of a bilateral trade agreement — a weight multiplier and a per-sector shift — and an `exit` carries none and clears the pair. The register is `GameState.agreements`, on this file's own key. Full argument: [[trade-model]].

Preconditions may test `relations` (against the action's own target) or the acting nation's own fields. A **second pair-state field**, `agreement_active`, joined them at V1.3b, and it is what lets propose and withdraw gate themselves generically: an enter verb asks for 0, an exit verb asks for 1, and `Diplomacy.available()` needs no trade knowledge at all. An unrecognised field is a startup error, not a silently-false predicate.

## The embassies that already exist (V5.1-0d)

`open_embassy` was gated on a meeting and relations >= 50 and nothing else, so the game offered France an embassy in Zagreb and Nicosia, and a hands-off run had the AI open 33 embassies in the player's capital in its first three years. `NationState.embassies` is the register: DIRECTED (France's embassy in Rome is not Italy's in Paris), the ids of the capitals this nation holds a resident mission in. It is seeded at new game by `src/sim/diplomacy_embassies.gd` from a rule the data states, `data/world/embassies.json`: every roster state holds one in every other, except the pairs without diplomatic relations (Cyprus-Turkey, and Kosovo with the ten roster states that do not recognise it). The verb asks the seventh pair field, `embassy_held`, for 0, and writes the sixth effect channel, `embassy: "open"`. The register, not the 240-month cooldown, is what keeps it from reopening. SAVE_VERSION 41.

**Bounds, recorded.** The rule errs toward too many missions: Malta, Luxembourg, Iceland, Montenegro and Kosovo in truth accredit many ambassadors from a neighbouring capital. A Wikidata list was tried first and refused because its gaps were the bug itself (an embassy offered where one stands) -- [[data-sources]]. And on a pair without relations the verb is refused: the exceptions are copied to `NationState.no_relations` at the same seed and the verb asks the eighth pair field, `relations_exist`, for 1 (review pass 2: before it, Serbia at relations 50 could have opened an embassy in Pristina). Recognition itself is not modelled, so nothing opens those pairs during a game.

**The ninth pair field, `customs_union_shared` (V5.2 R10, the author's gate b).** 1 when the actor and the target share an org whose `customs_union` field is set (only the EU), read from live membership by `Org.shared_flag` through `diplomacy_verbs.gd`'s `pair_field`. `impose_tariffs` asks it for 0, so no member is offered a tariff on another, the AI included; leaving the union reopens the verb. A sanction is not a customs duty and is not gated ([[orgs-model]]).

## The host's cadence (V5.1 play gate)

A hands-off world sent **~26 state visits a year to the player** and almost none anywhere else: 53 of 75 AI acts in 24 idle months. With Germany as the player, 61 of 71 went to Germany, so the bias is towards the player, not towards France. The cause is two rules meeting:

- The agenda's only friendly motive is `deepen` = stake × warmth × room, where room = `AGENDA_AMITY_TARGET − amity` ([[foreign-policy-model]]).
- Third-party judgement credits the **actor** of every friendly act with every observer that has a stake in the target.

So AI-AI amity climbed from 0.0–0.2 at new game to 0.5–1.0 within two years, and the AIs' room with each other closed. An idle player never acts and never collects that credit, so it stayed the one target with room, and every AI visited it once per 12-month cooldown. A controlled run with the judgement at zero kept AI-AI amity at 0.0–0.3 and cut the player's share of acts from 72 % to 27 %.

**The rule is the host's, read off the action.** `host_interval_months` on a verb means that a nation which received it is offered it by nobody, the player included, until the interval has run. The register is `NationState.diplo_hosted_months` `{action_id: months}`: stamped on the target by `stamp()` in `src/sim/diplomacy_cooldowns.gd` and counted down beside `diplo_cooldown_months` in `_settle()`, before any actor's turn. A host stamped with N in month m is therefore offered the verb again from month m + N.

`state_visit` carries **6**: the UK's convention is two incoming state visits a year, and 2025's three was the first time in 37 years. The default is 0, so no other verb changes. An empty register reads as "nothing hosted recently", so the field carries no SAVE_VERSION bump.

Measured on all four playables over three to four idle years through `WorldMonth`: exactly 2 visits a year to the player, and 82–93 AI-to-AI visits over 4 years (`tests/test_visit_cadence.gd`). The judgement inflation itself is not touched; the cap only starves it ([[someday]]).

## The measurement, run before the content existed

`tools/diplomacy_probe.gd`. The plan named it and named what would count as a failure, which is the discipline [[amendment-model]], [[dissolution-model]] and [[scenario-model]] each established.

### 1. Reachable range — the escalation trigger did not fire

Sixty months of repeated use at maximum legal cadence, from each pair's resting value:

| delta | cooldown | moved from resting |
|---|---|---|
| ±3 | 24 | ±4.7 |
| ±3 | 12 | ±7.7 |
| ±5 | 12 | ±12.8 |
| ±8 | 12 | ±20.5 |
| ±12 | 12 | +25.1 / −30.7 |

The trigger the plan named — *the reachable range is too narrow for any precondition to bite, and that is a model decision rather than a tuning call* — did **not** fire. Even the mildest content moves a pair further than the 8-point gap between two resting tiers.

### 2. What survives of one action — the number that justifies `DRIFT_RATE`

> [!warning] The first version of table 1 measured the wrong thing, and looked like a finding
> It swept sustained use and then asked how many months a pair took to return within one point of resting. From a displacement of twenty points that is four-plus half-lives *by construction*, so nearly every row read "> 120 months" and the table appeared to be saying the drift does nothing. It is not. What it is saying is that a five-year **campaign** leaves a mark outlasting the player's term — defensible, and not what the constant needs to justify. A second table was added rather than the first one being reinterpreted.

One use, then nothing:

| @12 months | @36 months | @60 months | half-life |
|---|---|---|---|
| 78% | 48% | 30% | **35 months** |

A single act decays visibly inside a term and is mostly gone by the next election. `DRIFT_RATE = 0.02` stands, an order of magnitude slower than [[opinion-model|`INERTIA_RATE`]]'s 0.25 — approval is a mood and should fade inside a season; a diplomatic relationship is not.

### 3. Domestic visibility — the finding that set every content number

`opinion.gd` gives `target = 50 + 40 × (score + offset)`, so an offset of **0.075 moves a bloc's approval target exactly 3.0 points** — `poll_noise.gd`'s `NOISE_MAX_PCT`. The probe confirmed the arithmetic and then found the part the arithmetic does not show:

| offset | blocs hit | bloc move @12mo | **overall** move @12mo | verdict |
|---|---|---|---|---|
| 0.04 | 6 | +1.55 | +1.55 | lost in noise |
| 0.06 | 6 | +2.32 | +2.32 | lost in noise |
| 0.08 | 6 | +3.10 | **+3.10** | visible |
| 0.12 | 6 | +4.65 | **+4.65** | visible |
| 0.08 | 2 | +3.10 | +1.67 | lost in noise |
| 0.12 | 2 | +4.65 | +2.51 | **lost in noise** |

**An offset applied to fewer than six blocs never clears the noise floor in the headline approval figure — not even at the content ceiling.** `overall_approval_pct` is a weighted roll-up, so a split price is legible on the polling panel's per-bloc rows and nowhere else.

That is not fatal, and it is not a bug: a policy that divides the country genuinely should not move the average. But it had to be known before content was authored, because an action whose only price is a two-bloc offset would have shipped looking like a decision with no visible consequence.

## What the measurement did to the content

| Action | relations | cd | Domestic price | What it proves |
|---|---|---|---|---|
| `state_visit` | +5 | 12 | none | The cheap positive verb. |
| `public_condemnation` | −8 | 12 | rural +0.10, pensioners +0.08, business −0.12, urban −0.08 | A split price. Popular with voters who wanted a firmer line, costly with those who trade. |
| `bilateral_treaty` | +8 | 24 | business +0.10, workers −0.10 | The relations **gate** — `relations >= 70` — plus a split price. |
| `settle_dispute` | +10 | 24 | all six at −0.09 | The one whose cost the player reads in the **headline** figure (≈ −3.5 points at twelve months). |

V1.3c added four more on the same shape — `impose_tariffs`, `lift_tariffs`, `impose_sanctions`, `lift_sanctions` — with a fourth effect channel, `effects.measure`, and three new precondition fields. Their magnitudes were set by their own measurement; see [[coercion-model]].

Three consequences of the measurement, none of which were in the plan:

- **Every split price is authored at 0.08–0.12, near the `MAX_ACTION_BLOC_OFFSET` ceiling of 0.15**, because anything smaller does not clear ±3 even on its own bloc row.
- **`settle_dispute`'s six-bloc price is a cost, not a gain.** A six-bloc *gain* at the visible magnitude is exploitable: the cooldown is per target, so nothing stops the player applying it against all nine neighbours in one month, accumulating +0.72 into a channel clamped at +1.0 and saturating approval. A pure cost has no such incentive. `public_condemnation`, which does pay some blocs, is split precisely so that mass use moves blocs in opposite directions and is self-limiting.
- **`bilateral_treaty`'s gate at 70 discriminates by relationship, which is the point.** From the 68 tier one state visit clears it and holds for about two years. From 60 it takes sustained work. From 45 — every GBR pair — the strongest positive verb reaches 75.7 only under twelve-month spam, so the treaty is effectively closed to Britain. `tests/test_diplomacy.gd` asserts the gate is reachable at all, which is the check [[amendment-model|Germany's two-thirds]] failed.

## The counterparty response is a declared stopgap

> [!success] Discharged at V1.3e
> ~~An action's own `effects.relations` is the **entire** reaction. The target does not reason, does not retaliate, and no third pair moves.~~
>
> `tests/test_diplomacy.gd` asserted that acting on Germany left `DEU|ITA` at exactly its resting value, and **that assertion went red** the moment [[foreign-policy-model|the interest model]] landed. It is now one signed rule: an act by A on B is an act on everyone with a stake in B, so X cools toward the actor and warms toward the target, both scaled by `stake(X -> B)`. A sanctioned nation acquires sympathisers, and U5c's relations map layer is the readout for it.

**The alliance argument did not survive, and it is worth saying why.** This file recorded that third-pair effects *need an alliance model, which is V1.3f's*. That was true when it was written and stopped being true at [[bloc-model|V1.3d]]: stake carries EU co-membership and the shared border, so the channel exists **without an alliance in it**. Alliances at V1.3g make it stronger, not possible.

**V1.3c added the third**, in the same shape again: `Coercion.retaliation_terms()` mirrors a measure back once at a fixed fraction after a fixed delay, weighs nothing, and never acts first. `tests/test_coercion.gd` asserts it by mutation. The three compose — V1.3a's says the target does not *react*, V1.3b's says it does not *decide*, V1.3c's says it reacts by a fixed rule and decides nothing. See [[coercion-model]].

**V1.3b added the second entry to that checklist**, in the same shape and with the same kind of test: `Diplomacy.would_accept_agreement()` is a pair score against one threshold, the target's own economy is never consulted, and `tests/test_trade.gd` asserts it by mutating that economy to extremes and checking the verdict does not move. The two stopgaps compose rather than conflict — this one says the target does not *react*, that one says it does not *decide*.

> [!note] One thing V1.3b's version does that this one does not
> The agreement gate is a **gate**, evaluated before the effects, not a verdict applied after them. `execute()` has two outcomes and a post-hoc counterparty answer would have been a third — leaving the player +6 relations for a treaty that was refused. The existing `refused: true` shape carries it instead.

## Bounds

| Quantity | Bound |
|---|---|
| A pair's score | Hard-clamped to `[0, 100]` inside `Relations.adjust()`, so no writer can leave it outside the readable range. |
| One action's `relations` effect | `MAX_ACTION_RELATIONS_DELTA` = 25, checked at load. An action cannot quietly out-scale the drift pulling against it. |
| One action's `bloc_offset` per bloc | `MAX_ACTION_BLOC_OFFSET` = 0.15, checked at load. The same band `government_constants.gd`'s `FALLEN_BLOC_PENALTY` (−0.12) sits in — a diplomatic act may cost about what a collapsed government costs, and no more. |
| Accumulated `bloc_offset` | `BLOC_OFFSET_MIN/MAX` = ±1, the clamp [[legislature-model]] already applies, and clamped again with the satisfaction score before it reaches `APPROVAL_SPAN`. |

## Deliberately absent

- **No new `ISSUE_KEYS` entry.** Everything here pays through `bloc_offset`. Whether foreign policy earns an issue of its own is V1.3d's call, where the domestic politics of Europe is the mechanic rather than a side effect — and the cost is named in advance: six new `BLOC_SALIENCE_BASE` rows, against which [[declined|every tuned opinion constant was measured]].
- **No new dashboard tab.** You act *on* the nation you clicked, so the verbs live on the Europe tab's existing nation panel. A separate tab would need its own nation picker, duplicating the map.
- **No relations colouring on the map.** Named the cut candidate at plan time and cut, once the cold surface count came in above the roadmap's estimate.
- ~~**No trade coupling.** `external_impulse_pct` is V1.3b's, and unquieting it re-runs the balance harness.~~ Built at V1.3b — [[trade-model]]. Relations reach the economy through exactly one channel, the **mix** of the directed trade weight, and deliberately never through its level: an openness level that responded to relations would have made `state_visit` — free, unpriced, per-target cooldown — worth about two permanent points of GDP on infrastructure for nine clicks a year. The same exploit shape this file records the V1.3a probe catching, found the same way and before the content shipped.

---

Related: [[trade-model]] · [[legislature-model]] · [[opinion-model]] · [[scenario-model]] · [[data-architecture]] · [[data-sources]]
