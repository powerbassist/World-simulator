---
title: Media Model
tags:
  - decision
  - sim
  - balance
---

# Media Model

Outlets, framing and press freedom, as built at [[ROADMAP|V1.5d]] — the fourth and last
session of the V1.5 block. A register of newspapers, a per-bloc salience gain derived
from where each one stands relative to the government, and a press-freedom dial that
charges its price in a quantity the project already had.

Same standard as [[unrest-model]], [[society-model]] and [[demography-model]]: a **game
model**, judged on whether the player's decisions produce a legible, attributable
political outcome. Where realism and legibility conflict, legibility wins, and the trade
is noted.

## 1. The row asked for the SOURCE of a machine that has been running since S10

[[v1]] §5's first bullet reads *"media outlets with political leanings that frame the
player's actions."* Counted cold, the framing machine already exists:

```gdscript
static func salience_weights(base, sat, gain):
    severity = clampf(-sat[issue], 0, 1)
    w        = base[issue] * (1 + gain * severity)     # then renormalised
```

`SALIENCE_GAIN = 5.0` amplifies bad news for every bloc of every nation, and has since
S10. **"Bad news travels" is a claim about the press**, and this project has been making
it for six blocks with no outlet behind it — amplification with no source.

So V1.5d adds no machine. It makes one existing scalar into six and supplies what decides
them. **Twenty-fifth instance** of the stale-row failure [[trade-model|V1.3b]] first
recorded, and the fourth block running where the row's premise did not survive a count.

The session found a **twenty-sixth** on the same day: `public_broadcasting_reform` had
been in `data/laws/institutional.json` since the MVP pricing itself as
`other_revenue_pct_gdp: -0.05` — a media law whose only mechanism was a funding line.
That is [[society-model|V1.5a]]'s `anti_corruption_agency` verbatim, *"described the law's
side effect and called it the mechanism"*, and re-authoring it onto
`effects.society.press_freedom` makes this the block's **fourth booked retro-fit**.

## 2. What is deliberately not here, and the scandal decision

**Scandals left the block entirely**, and that is a third outcome [[v1]] §8's warning box
did not enumerate. §8 says two outcomes are legal — be §8's first instance, or be
explicitly non-generic — and that silence is not among them.

"Requiring a response" is a choice list, and a revelation with preconditions, choices and
consequences **is** §8's definition. A genuinely non-generic scandal scheduler therefore
means dropping the response clause, at which point a scandal is a negative framing shock:
§1's machine wearing a second label. And §8's own reason for being last is that the event
schema is the union of the channels §3–7 create — **V1.5d creates one**, so writing the
schema now writes it before §6 and §7 create theirs, which is the failure §8 names.

So the bullet leaves §5 the way rule of law left it for §1's judiciary at this block's own
decomposition. §8 does not shrink and gains no early instance; it gains a cross-reference.
Cross-referenced into §5 **and** §8, because leaving it in one row is how the row got
stale twenty-six times.

**Government messaging is cut**, and §7 keeps the campaign half untouched. Two reasons:
messaging that damps hostile framing **is** press freedom's positive direction with a
different label, which is one accumulator and two writers; and the "time" half is
unbuildable, because [[calendar-model|U6a]] swept a monthly day budget and **deleted** it.

## 3. An outlet is five fields, and the refusal is the design

`data/outlets/<NATION>.json`, a per-nation lookup on `data/companies/`'s shape. Authored
for the playable three; an absent file gives no press, which is what all ten had before.

| field | note |
|---|---|
| `id`, `name` | `outlet_name` internally — `name` is a `Node` property, the dodge four value types already make |
| `audience` | one of the six `BLOC_KEYS`. **The differentiator** |
| `reach` | of its own audience bloc; the named reaches sum to **less than** 1.0 and the remainder is unaffiliated |
| `position` | the two-axis space parties, laws and bloc proposals all use |

**There is no `alignment`, `hostility`, `bias` or `stance` field**, and `outlet.gd`'s
unrecognised-key error says so out loud rather than leaving it as an absence a later
reader repairs. Alignment is derived from `position` against the nation's live
`coalition_position`; an authored one would be a second writer of it, and the whole point
of deriving it is that **the press turns on you when your government changes**. That is
`_extract_company()`'s refusal of a firm id in a third register.

`audience` is the field to argue about, and it is what makes this more than a second
`SALIENCE_GAIN`: different papers reach different people, so the same government failure
is amplified for one bloc and not another. Without it every outlet in a nation answers
alike — [[foreign-policy-model|the clustered `coalition_position` finding]], caught at
design time. Authored positions span economic −0.80…+0.80 against a party field of
−0.80…+0.50, so the spread check is met rather than assumed.

## 4. The gain, and the mean anchor is the session's one model correction

```
align_o     = 1 − 2·dist(outlet.position, ns.coalition_position) / MAX_POSITION_DISTANCE
raw[b]      = Σ_{o.audience == b}  reach_o · (−align_o)
mean        = Σ_b BLOC_SIZE[b] · raw[b]
dev[b]      = (1 + press_freedom) · (raw[b] − mean)
gain[b]     = max(FRAMING_GAIN_MIN, SALIENCE_GAIN · (1 + FRAMING_BETA · dev[b]))
```

**The session was designed START-anchored** — the gain measured against the nation's own
press stance at new game, which is `start_service_quality`'s idiom and the one this
project reaches for by reflex. Step 0's table (A) refuted it before a line of `src/` was
written:

| nation | max `coalition_position` travel, 168 months | reforms |
|---|---|---|
| **FRA** | **0.044 – 0.056** | 2 |
| DEU | 0.600 | 1 |
| GBR | 0.263 – 0.870 | 1–2 |

France holds a majority through every election, so its government's *position* barely
moves. Britain's travel puts the constant near 16; **France's puts it near 250.** An
anchor that is right for the roster and wrong for the player is
[[foreign-policy-model|V1.3e]]'s globally-anchored amity in a new place.

**The pre-committed fallback was refused, and refusing it is argued rather than slipped
in.** That fallback was *delete the alignment term and let `press_freedom` backlash drive
the deviation alone*. It makes the outlet register **inert until the player passes a law**,
and a register nothing reads until a command fires is the decay
[[diplomacy-model|V1.3a]]'s rule exists to prevent.

Anchoring on the size-weighted national mean instead buys six things:

1. **`Σ_b BLOC_SIZE[b] · dev[b] == 0` by construction**, so the size-weighted mean gain is
   exactly `SALIENCE_GAIN` and every opinion constant measured since S10 keeps its
   calibration. `tests/test_media.gd` asserts it rather than hoping.
2. The channel is driven by the **spread of authored positions**, not by government
   travel, so France works. Travel still moves the landscape for Germany and Britain.
3. **A friendly press gets a channel.** Under a start anchor it could not: `severity` is
   `clampf(−sat, 0, 1)`, so good news is already at zero and any lowering of the gain was
   a free win — censorship would have been **strictly dominated** on the framing axis, the
   shape this project has killed five times.
4. **`press_freedom = −1` flattens every bloc to exactly `SALIENCE_GAIN`.** Total
   censorship erases the media landscape and leaves the national average: it helps the
   blocs reading hostile papers and **hurts** the blocs reading friendly ones.
5. A bloc nobody publishes for lands at `−mean` — no papers, no amplification — which is
   what makes `reach` load-bearing. GBR's `students` row is authored empty so a real game
   exercises it.
6. No baseline field, so `SAVE_VERSION` stays at **18**.

Normalise-and-redistribute is this project's most-used idiom: `trade.gd`'s directed
weights, `companies.gd`'s share partition, and `salience_weights()` itself.

## 5. The feasibility arithmetic, and why the band is on a bloc row

Step 0's table (B), computed before any sweep. Partitioning a bloc's issues into bad `B`
(severity `v_i = −sat_i`) and non-bad `P`:

```
score(G) = (P1 − M1 − G·M2) / (R + G·M1)
```

A Möbius transform in `G`, with three consequences:

1. **Monotone decreasing in `G`, always** — Cauchy–Schwarz on `M1² ≤ B0·M2`. A hostile
   press can only lower a bloc's score.
2. **It saturates at `−M2/M1`**, a ceiling computable with no simulation. A bloc whose
   `APPROVAL_SPAN·(score(5) − asymptote)` is under ±3.0 **cannot clear a band at any
   `FRAMING_BETA`** — the arithmetic impossibility [[unrest-model]] §4 names.
3. **It is exactly inert under a uniform satisfaction vector**, including the uniform-zero
   vector of a new game. The channel's size is a function of the **dispersion** of
   severities, not their level — and most of the effect is good news being crowded off the
   simplex, so it bites hardest against a government leaning on one good issue.

Measured headroom is **4.0–17.4 points on a bloc row**. But an outlet names ONE audience,
so the headline sees `headroom × BLOC_SIZE`: 0.4–4.5, and only `workers` at size 0.30 can
carry it alone. **The band therefore goes on a bloc row and never on the headline** —
[[diplomacy-model]]'s finding for the sixth time, and here it is structural in the content
schema rather than in a tuning table. `CORRUPTION_DELIVERY_BETA`'s criterion (i) verbatim.

The clamp column is why bands are measured on `managed` and `tax_max` and never on
`spend_zero`: `opinion.gd` clamps `score + law_offset − unrest_opinion_load` to `[−1, +1]`
before scaling, and under `spend_zero` that binds for four blocs of six and swallows the
whole framing term.

## 6. Press freedom: two prices, and no legitimacy quantity was invented

The fourth `effects.society` term, signed, `[−1, +1]`, **sole writer
`Legislature.apply()`**. A channel carrying four registers written by four consecutive
sessions is schema rather than luck, which is what [[society-model]] §3 bet on with one
term — and `_extract_society()` is generic over `SOCIETY_TERMS`, so all four of its error
strings updated themselves.

Price one is the framing scale in §4. Price two is a **fourth term in
`Unrest.unrest_target()`**, and it is this session's answer to *"press freedom as a dial
with legitimacy costs"*. [[v1]] §5 handed V1.5d the choice of inventing a legitimacy
quantity or dropping the clause. **Neither.** Legitimacy is willingness to accept your
rule outside the ballot box, and [[unrest-model]] §2 says of its own grievance that *"a
country can be angry for reasons its approval figure does not contain"*. Censorship is
such a reason, and `UNREST_BLOCS` is `["workers", "students"]` — exactly who marches over
it. `PRESS_UNREST_BETA` lives in `unrest_constants.gd` beside `SETTLEMENT_BETA` and
`INEQUALITY_BETA`, the two it must be compared against; the clamp stays with media, which
is the split rule [[unrest-model]] §6 already used.

### The anti-double-count is in a SIGNATURE, and there is no fourth load-time refusal

`law.gd`'s block warned that the next session to add a term here would reach for a fourth
refusal by symmetry. **V1.5d is that session, it reached, and the paragraph stopped it.**
All four candidate pairs fail the stated criterion — *same act, same landing site **and**
same units*:

| pair | verdict |
|---|---|
| `press_freedom` + `structural_unemployment_pct` | units and sites both differ — V1.5c's deleted refusal, identically |
| `press_freedom` + `bloc_offset` | site coincides, units and mechanism do not; refusing it would fail `public_broadcasting_reform`, which carries one |
| `press_freedom` + `society.settlement` | two mechanisms landing on one number, not one priced twice |
| `press_freedom` + `society.corruption` | different sites, different units |

**The refusal that IS warranted has no shape a law schema can express.** `press_freedom`
must not reach the grievance target through both `PRESS_UNREST_BETA` and
`Unrest.hardship()` — same act, same landing site, same units, the first kind. But that is
one register reaching one number twice through *code*, not two keys on one law. So
`Opinion.salience_weights()` takes its gain as a **required third argument** and
`unrest.gd` states `SALIENCE_GAIN` out loud. A default would make silence mean "unframed",
so the next session adding a caller would get the wrong gain **by omission** with nothing
going red — which is exactly what `law.gd` says about conventions only the docs enforce.

## 7. Where it sits

```
Economy.tick_month()
Budget.tick_month()
Bloc.tick_month()
Media.tick_month()          <- V1.5d, writes ns.framing_gain
Opinion.tick_month()        <- its only reader
...
Society.tick_month()
Unrest.tick_month()
```

**Before Opinion**, which is the opposite of where Society and Unrest sit. Those write a
load Opinion consumes *next* month to break a loop through approval. This file reads
`coalition_position`, which Elections and Government rewrite *after* Opinion in the same
sequence — so it is already reading last month's government and the loop

```
approval → censure → re-formation → framing → approval
```

is broken structurally, for free. Sixth time that argument has been made and the first
where the lag costs nothing.

`media.gd` preloads two constant files and nothing else. Not `opinion.gd` (a cycle) and
not `foreign_policy.gd` for its identical `_position_alignment()`, because that file
preloads `trade.gd` preloads `coercion.gd` and this one runs inside the monthly opinion
tick. `MAX_POSITION_DISTANCE` is declared locally because `sqrt(2²+2²)` is **geometry, not
a tuning** — `foreign_policy.gd` says the same about its own copy.
`tests/test_media.gd` reads the file and fails if either name appears.

**`Budget.project()` does NOT get a slot, and that is the first refusal of V1.3b's repair
since it was written.** Every previous addition reaches a projected *figure*: the bloc
charges a penalty, a subsidy costs money, a stock decays, a strike shrinks output. Framing
reaches a figure only through approval, and approval reaches the budget only through an
election that loop does not hold — and `project()` does not run Opinion at all. Adding it
would be a tick whose result nothing reads.

## 8. The probe corrected the session four times, fifteen sessions running

`tools/media_probe.gd`. Bands and tiebreakers fixed before any sweep.

### (a) `FRAMING_BETA` — the pre-committed tiebreaker was wrong twice over

Band (i): a hostile bloc row past ±3.0. Band (ii): the `managed` headline no further than
±3.0. Both declared model criteria, so the tiebreaker was pre-committed as the **midpoint**
— [[unrest-model]] §10(e)'s rule, applied rather than re-derived.

| beta | (i) bloc row | (ii) headline | clamp | band |
|---|---|---|---|---|
| 3.00 | 2.98 | 0.11 | slack | fail |
| **3.02** | **3.01** | 0.11 | slack | PASS |
| 4.00 | 4.52 | 0.17 | slack | PASS |
| **4.50** | **5.45** | **0.21** | **slack** | **PASS** |
| 6.00 | 9.27 | 0.34 | slack | PASS |
| 6.20 | 9.94 | 0.36 | **BINDS** | fail |

**1. Band (ii) is a bound and not a selector** — [[society-model|V1.5a]]'s failure (2), in
the session that inherited the warning. The `managed` headline moves 0.44 at beta 7.0 and
1.02 at beta 20.0 against a ceiling of 3.0; it never fires. The interval's real upper edge
is the `FRAMING_GAIN_MIN` clamp, a **guard rail**.

**2. So rule (e) says the model edge governs and smallest-passing ships — and that is
wrong here for a reason (e) did not contemplate.** Rule (e) was written against a **lumpy**
response: V1.5c's own table (d2) reads −2.11, −2.95, −3.16, −9.01, so its floor sat on a
shelf and refinement could not move it. This response is **linear**, so "smallest passing"
is just "wherever the band crosses": 3.02 clears the floor by 0.3 %, and every refinement
of the grid moves the answer.

**The rule, extended: rule (e) assumes the model edge is a PLATEAU. When it is a smooth
CROSSING, the model edge does not select either** — and with neither edge selecting, the
only value stable under both widening and refinement is the interior. Both edges of
`[3.02, 6.00]` are structural rather than grid artefacts, so the midpoint is structural
too and is the value furthest from both failure modes. **4.50.**

### (b) The band was measured on a government already thrown out

Band (i) was first measured on `tax_max` from month 1 — under which France loses the 2027
election and the run **stops at month 16**. It showed a discontinuity there: 2.87 at beta
3.20 against 4.03 at 3.30, a discrete outcome flipping inside a sixteen-month window.

Re-measured on `managed>tax_max` — govern well, **win**, then provoke — the response is
smooth and monotone throughout and the discontinuity is **gone**. That is
[[unrest-model|V1.5c]]'s reachability lesson applied rather than inherited as a sentence,
and the cross-check was worth more than the constant.

### (c) `PRESS_UNREST_BETA` — both clauses failed to select, so it is set by argument

Band (i) passes at **every** candidate from 1.0 to 40.0: the grievance stock is continuous,
so any positive term shifts the crossing month and "moves the date" orders nothing —
`UNREST_COOLDOWN_MONTHS`' failure a fourth session running. Band (ii) is a real ceiling
(any value past ~41.7 makes a calm country strike) but selecting on it would mean
*"`hands_off`'s measured peak, minus a rounding error"*, which is V1.5c's table (b)
verbatim.

**Set by argument, and it says so.** A saturated settlement closes 12.0 points of
grievance; a saturated censorship must open fewer, because a pay settlement addresses the
material hardship the stock is built out of while press restriction is a political
provocation reaching two blocs of six. That is `QUALITY_SCALE_PP`'s ratio rule — the
indirect half is worth less than the direct half — and a ratio against a fixed constant is
stable under both widening and refinement, which is what neither band was. **8.0**, two
thirds of `SETTLEMENT_BETA`.

The sweep still earned its keep: it could have falsified the value through band (ii) and
did not, and it produced the legibility figure — under `managed>austerity` a saturated
censorship moves the first act from month **57 to month 41**, sixteen months earlier, with
a calm country peaking at 11.28 against a threshold of 45.0.

**The control caught the same reachability trap as (b), harder.** Measured from month 1,
`austerity` loses in 2027 and the control fired **no act at all**, so "moves the date"
degenerated into "an act happens". On `managed>austerity` at `balance_probe.gd`'s own
switch month of 20, the control reproduces that file's `managed_then_austerity` peak of
**48.74 to the digit** — two harnesses agreeing, which is what V1.5c spent a session on.

### (d) The clamp table measured the wrong press stance, and a second table caught it

`FRAMING_GAIN_MIN` is **slack by 2.009 at the ordinary press** and **reached at a saturated
free one**: `press_freedom = +1.0` doubles the spread, so the bloc reading the paper
friendliest to the government arrives at exactly zero and its readers stop amplifying bad
news at all.

That is **definitional saturation** rather than a guard rail doing a constant's work —
`UNREST_MAX` has the same character — and reaching it takes repeated liberalising laws.
But the sweep in (a) reported its clamp column at `press_freedom = 0.0`, where the binding
point is beta 6.20; at +1.0 it is 3.10. [[foreign-policy-model|V1.3f]]'s
measuring-the-wrong-state error, caught by printing both stances rather than by a later
session. `tests/test_media.gd` now pins **both** directions, so a change to the floor, the
beta or the press scaling has to come and look at it.

## 9. `SAVE_VERSION` stays at 18

| Field | Earns the bump? |
|---|---|
| `press_freedom` | No. Absent it reads 0.0 — the truth about every version-18 save, since no v18 game could pass a press law. `settlement_stance`'s case. Serialised anyway: a law writes it once and no tick recomputes it. |
| `framing_gain` | No. Rewritten in full on the next tick, failing soft for one month — `unrest_opinion_load`'s case. |
| *(no baseline field)* | **The interesting half.** Every stock this block shipped captured a reference; this one measures a deviation from where the nation's other blocs are *right now*, recomputed from content and a `coalition_position` the save already carries. |

The design pass predicted a bump to 19 on a `start_press_stance`, and it was **correct
about the design it was given** — with no `start_coalition_position` serialised, an absent
baseline would recompute against the current government and a save reloaded after the
press turned would score the hostility as new, which is `start_bloc_burden`'s case at
V1.3d. The mean anchor deleted the field and the bump with it. Both are recorded rather
than the second quietly replacing the first. `tests/test_save_load.gd` pins the
**absence**, so a later session storing a baseline turns it red and has to say why.

## 10. The balance re-run, and the prediction that was wrong in a useful way

**Stated before running:** framing is live at `press_freedom = 0` with a non-zero spread
from month 1 in all three authored nations, so the run will *not* be bit-identical — unlike
V1.4a/b/c, whose channels read exactly 0.0 until a player command.

**The first run came back with a diff of exactly zero lines, and that refuted the
prediction — which is how it caught a real bug.** `balance_probe.gd` and
`tests/test_balance.gd` never called `Media.tick_month()`, so both harnesses were running
the pre-session model and their agreement meant nothing. That is [[calendar-model|U6a]]'s
day-loop finding in a new place: **a system the harness never calls is a system whose
bit-identity proves nothing about it.** Wired into both in the same commit as the model.

With the harness fixed, over 28 shared regimes:

| | |
|---|---|
| GDP, growth, trend, unemployment, debt, deficit | **bit-identical in all 28** |
| Approval | moves in all 28, by at most **3.00 points** (`managed_then_austerity_settles`, the most provoked regime) |
| Outcome changes (HELD ↔ LOST) | **zero** |

The **29th regime is the cheap kind** — a law applied at a month, `AMENDMENT_REGIMES`'
shape, so only the content is new. `managed_censors` is also the legibility evidence, and
the comparison is exact: same budget, same everything, one `broadcasting_oversight_act` at
month 24.

| | worst bloc, 2029 onward | 2033 approval |
|---|---|---|
| `managed` | rural 45–47 | 50.9 |
| `managed_censors` | **students 40** | 50.2 |

The economy is bit-identical between them. What the press law changes is **which bloc is
angriest**: students read the paper furthest from a centrist government and are one of the
two `UNREST_BLOCS`, so the cost lands on exactly the row that would march.

## 11. The readout

One line on the overview's GOVERNMENT column, beside V1.5a's and V1.5c's, **silent at
zero**. It prints the press-freedom **stance** and not the framing spread, and that is the
call worth recording: the spread is non-zero from month 1 in all three authored nations —
a fact about the *country* — so a line on it would be permanent furniture saying nothing,
the failure this column has avoided four times. The stance is zero until a press law
passes, so the line appears when there is something to say about a **decision**.

The effect reaches `polling_panel.gd`'s agenda list and `elections.gd`'s attribution **for
free**, through `ns.issue_salience` and with no edit near either file. That is the feature:
the press decides what losing gets blamed on.

`tools/screenshot.gd` gained `--press`, which provokes before it censors — the
`emergency_broadcasting_powers` law is gated on `unrest_pct >= 35`, so a calm France
cannot reach it and a frame of a law nobody can pass proves nothing.

## 12. Why nothing diverges

| Quantity | Bound |
|---|---|
| `framing_gain` | `[FRAMING_GAIN_MIN, ∞)` below, and no ceiling is needed above: `salience_weights()` renormalises onto the simplex, so a large gain **concentrates** weight rather than growing it. The floor exists because that function returns its weights UNNORMALISED when their total is non-positive, which a negative gain reaches. |
| The size-weighted mean | Exactly `SALIENCE_GAIN`, by construction of the anchor. Asserted. |
| `press_freedom` | `[−PRESS_FREEDOM_MAX, +MAX]`, clamped on the accumulated value in `Legislature.apply()`. One writer, no tick. |
| The unrest term | A bounded stance times a constant, inside a target `unrest_target()` already clamps. |
| approval → censure → re-formation → framing → approval | Broken by the one-month lag in §7, structurally. |

## 13. What is deliberately not built

**Scandals.** §2 — they are §8's, and §8 builds them.

**Government messaging.** §2 — it is press freedom backwards, and §7 owns the campaign
half.

**A thirteenth `ISSUE_KEYS` entry.** Answered **NO**, fifth recording, and the reason is
new: framing modifies **weights**, and an issue whose satisfaction is a weight is a
category error — the question does not reach V1.3d's test 1. Recorded beside `ISSUE_KEYS`
with *that* reason rather than V1.5a's collinearity one or V1.5c's no-direct-term one,
because a reader would otherwise assume they are the same.

**A per-issue outlet bias table.** `BLOC_SALIENCE_BASE` already says who cares about what,
and a second one would be a table with no measurement behind it.

**Journalists as named people.** [[people-model]]'s argument is that a person has no field
that could carry a mechanism, so an `editor_person_id` would be a label, not a lever.

**A `Budget.project()` slot.** §7.

---

Related: [[index]] · [[opinion-model]] · [[unrest-model]] · [[society-model]] ·
[[demography-model]] · [[legislature-model]] · [[people-model]] · [[v1]] · [[ROADMAP]]
