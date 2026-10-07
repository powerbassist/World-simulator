---
title: Pledge Model
tags:
  - decision
  - elections
  - simulation
---

# Pledge Model

V1.7b, the second session of the V1.7 block. Campaign promises: a `{field, op, value}`
triple made in the run-up, binding across the term it wins, and charged for every month
it stands broken.

Same standard as [[campaign-model]], [[election-model]] and [[opinion-model]]: a **game
model**, judged on whether the player's decisions produce a legible, attributable
electoral verdict.

`src/sim/pledges.gd` is the model, `src/sim/pledges_constants.gd` is the bounds — and
**there is no tuned constant in it at all** — `data/pledges/pledges.json` is the ladder,
and `tools/pledge_probe.gd` is what set the ladder.

## 1. The row said the price was a quantity that does not exist. It said so twice.

The ROADMAP's V1.7 decomposition records this as **the row most likely to split**:

> The price is a quantity that does not exist, which is V1.5d's *legitimacy* problem
> again. […] if the price cannot land on an existing register the way V1.5d landed
> legitimacy on the grievance, then the ledger and the price are two sessions.

It lands, and **V1.5d's own criterion is what puts it there — applied in the other
direction.** [[media-model]] §6 sent legitimacy to the grievance because legitimacy is
*willingness to accept your rule **outside** the ballot box*. Trust in a promise is the
opposite: it is squarely **at** the ballot box. So it belongs on the register that
reaches the ballot box, which is `ns.bloc_offset` — the permanent per-bloc
approval-target accumulator [[campaign-model]] §6 already made a campaign's own lasting
mark.

A separate trust stock would also have been the thing [[v1]] §5 warns against in so many
words: *a second approval number with a different label*. Probe table (b0) measured the
landing site **before a line of content existed**, which is what makes this a
measurement and not a preference. **One machine, no split.**

## 2. "Read at the END of the term" — instance forty-two

The row's contrast is right (a pledge is read at judgement, where a law's precondition is
read at proposal) and its timing is wrong. It fails twice on facts that can be counted:

1. **A single term-end read is strictly dominated by last-minute compliance.** Promise
   unemployment at or below seven, run it at nine for four years, squeeze it to 6.9 for
   the final month, pay nothing. That is the shape this project has killed eight times
   (V1.3c's severities, V1.3d's fourth rule, U6a's booking, V1.4c's dividend, V1.5d's
   censorship, V1.6e's flat bill, V1.7a's one-off purchase, and this session's refused
   `renounce` op).
2. **It is structurally invisible at the vote it is about.** `src/ui/main.gd` runs
   `Opinion.tick_month()` and then, much later in the same month,
   `Elections.tick_month()`. Anything writing `bloc_offset` after the first reaches
   `bloc_approval` on the **next** month's tick — and even moved ahead of Opinion,
   `INERTIA_RATE = 0.25` delivers a quarter of the price before the vote. A term-end
   judgement charges a president for a broken promise at an election already decided
   without it.

So a promise is judged on a **level** every month it is live, and the accrual is the
price. "The end of the term" is where the *total* is read, and the total is the integral.
That is [[campaign-model]]'s *an effort is a standing rate with a deadline* applied to the
**price** rather than to the spend.

**Graded-by-the-miss was designed and cut.** Scaling the charge by how badly the field
missed needs a per-field normaliser — a table with no measurement behind it, which is
[[unrest-model]]'s own warning. Breach is **binary per month**, and the count of breached
months is the whole memory: V1.3e's *no grievance ledger* in a new place, where the number
**is** the record.

## 3. `PRECONDITION_FIELDS` is the right shape and the wrong list

Three of `legislature_constants.PRECONDITION_FIELDS`' seven entries cannot be promised —
`overall_approval_pct` is circular (a promise to be popular, priced in popularity),
`terms_served` is not a state of the country, and `unrest_pct` ships an asserted
`>=`-only invariant that a `<=`-shaped promise inverts. So pledges get their own list.

It is also **wider**, and that is where the session's texture is. Probe table (c0)
measures every candidate field two ways over a full term under three real budgets:

| field | luck | choice | exposure | verdict |
|---|---|---|---|---|
| `growth_annual_pct` | 8.215 | 0.641 | **0.928** | the ladder's gamble end |
| `unrest_pct` | 46.123 | 47.285 | 0.494 | kept |
| `unemployment_pct` | 1.182 | 0.656 | 0.643 | the classic promise |
| `debt_to_gdp_pct` | 49.786 | 69.881 | 0.416 | kept |
| `deficit_pct_gdp` | 1.284 | 16.445 | **0.072** | the fiscal constraint |
| every tax and spending row | **0.000** | 2.5 – 6.0 | 0.000 | self-imposed |
| ~~`inflation_pct`~~ | 0.114 | 0.045 | — | **deleted** |

- **LUCK** is the widest span *within* one budget — what the world does to you.
- **CHOICE** is the span *across* budgets at the end — what you do to yourself.

**An outcome pledge is a bet on the world** and [[cycle-model|V1.6a]]'s cycle is what
makes it a real one; **a rate pledge is a self-imposed constraint** — *no new taxes*
costs flexibility, not luck. Two genuinely different promises on one schema.

**`inflation_pct` was on the list and the probe deleted it.** 0.114 of luck and 0.045 of
choice are both under the resolution of the model that produces them, which is
[[inflation-model]]'s own finding (a reachable deviation of 0.145 points) arriving from
the other side: an authored threshold either side of that is a **constant verdict**, kept
in all sixty months or broken in all sixty, with nothing the player does moving it.
Deleted rather than authored around — V1.5b's treatment of
`DEPENDENCY_ELASTICITY["health"]` — and `tests/test_pledges.gd` fails if it returns.

## 4. One verb, two prices, two times

Making a promise pays a **positive** `bloc_offset` at the moment it is made, inside the
run-up, so it reaches `Elections.vote_share()`'s `pull` term through eight months of
`INERTIA_RATE` and buys the election you are standing in. Breaking it charges a
**negative** one every month of the term that election wins.

**You buy this election with a promise and pay for it at the next one.** That is
[[society-model]]'s *the delta prices the announcement, the stock prices the delivery* —
here literally, on one channel, with opposite signs at different times.

**There is no fifth anti-double-count.** `pledge` + the promised field's own opinion issue
(a broken deficit promise also costs through `public_finances`) fails `law.gd`'s stated
criterion — *same act, same landing site **and** same units*. The deficit is one act and
promising otherwise is another; the landing sites differ. Refused in the file, because
`law.gd` warns that the next session reaches for one by symmetry and **symmetry is not the
test** — V1.5c's and V1.5d's refusals a third time.

## 5. No `op` on the channel, and that is the model

Five directories ship a start and a stop, because an obligation only the clock can close
is a permanent monotone charge — [[defence-model]]'s rule, which is why
`campaign_constants.CAMPAIGN_OPS` carries `stop`. **It does not transfer.** A pledge
charges only while it stands broken, so it stops the month the player comes back into
compliance: the off switch already exists and it is called **governing**. A `renounce` op
priced below the accrual would be strictly better than complying, and priced above it
would never be used.

`PLEDGE_OPS` is `["<=", ">="]` — **two of five, and the three refusals are the design**.
`==` on a float is a promise nobody could keep, and `<` / `>` are the same promise a hair
apart. Refused at load, `_extract_company()`'s refusal of a firm id in a new place.

## 6. The window, the freeze and the retirement are all level reads

A promise may be made only inside `Campaign.is_open()` and it binds the term that run-up
is for. Both dates are **frozen at the moment it is made**, out of `ns.next_executive_*`
and `ns.term_months`, and everything afterwards is a comparison against the clock. There
is no "the pledge is live" flag and nothing in `elections.gd` knows this file exists —
`tests/test_pledges.gd` reads that file and fails if it names `Pledges`.

**Frozen rather than derived, and that is the one place it matters.**
`Elections.tick_month()` pushes `next_executive_*` a full term forward the moment the
incumbent wins, so a promise deriving its own deadline from that field would move its own
goalposts on the night it was won.

**And `available()` refuses a termed-out incumbent, which the probe found rather than the
design.** Table (a0) prints three run-ups over fourteen years and the third opens in
September 2036 against a `termed_out` notice in May 2037: `Campaign.is_open()` is a pure
clock read with no term-limit branch, so the window opens for a president who cannot
stand. Spending money on a successor's campaign is at least arguable and V1.7a is left as
it is; a **promise** about a term you are barred from serving binds nobody.

## 7. The bands

| | edge | value |
|---|---|---|
| (i) | **not free money** — a full-term breach must cost more than the promise's own reward, or every promise is strictly dominant | measured per promise |
| (ii) | **readable** — a full-term breach must move the headline past the poll floor | ≥ **3.00** pts |
| (iii) | **it must not substitute for the record** — at most what one term of governing moves the headline, measured as the spread between `hands_off` 47.38, `managed` 49.93 and `austerity` 25.50 | ≤ **24.43** pts |
| (iv) | **guard rail, declared not a selector** — `BLOC_OFFSET_MIN` | −1.00 |

## 8. The ladder

| promise | field | reward | full-term breach | ratio | clamp |
|---|---|---|---|---|---|
| The employment guarantee | `unemployment_pct` ≤ 7.5 | +1.208 | 4.036 | 3.34× | 27 % |
| The tax lock | `tax_income_pct` ≤ 20.0 | +1.032 | 4.378 | 4.24× | 30 % |
| The deficit rule | `deficit_pct_gdp` ≤ 3.0 | +0.968 | 3.682 | 3.80× | 27 % |
| The health guarantee | `spending_health_pct_gdp` ≥ 11.0 | +1.080 | 5.814 | 5.38× | 30 % |
| The growth pledge | `growth_annual_pct` ≥ 1.0 | +1.088 | 3.447 | 3.17× | 25 % |

All five pass (i), (ii) and (iii). At the ballot box, through
`Elections.vote_share()` rather than through the headline:

| promise | made: Δ share | Δ gap | broken: Δ share | Δ gap |
|---|---|---|---|---|
| The employment guarantee | +0.3899 | +0.5740 | −1.3705 | −2.0177 |
| The tax lock | +0.3588 | +0.4321 | −1.5623 | −1.9511 |
| The deficit rule | +0.3927 | +0.4536 | −1.4762 | −1.7183 |
| The health guarantee | +0.3885 | +0.5289 | −2.1844 | −2.9565 |
| The growth pledge | +0.4002 | +0.5035 | −1.3378 | −1.7091 |

**The price-to-reward ratio falls as EXPOSURE rises** — 3.17× at exposure 0.928 up to
5.38× at 0.000, monotone, checked rather than asserted. You are paid more per unit of
risk for a promise you cannot control, and punished hardest for breaking one you could
have kept by doing nothing.

## 9. What the probe corrected, and it corrected the session five times

Nineteen sessions running.

### (a) Table (a0) measured the wrong state, in the probe written to avoid it

The reachability table's `_tick()` deliberately omits `Elections`, so `next_executive_*`
never moved and 168 months reported **one run-up and zero judgements** — which would have
read as *the verb is unreachable and the row should split*. With the real election
running: **three run-ups (2026-09, 2031-09, 2036-09), three executive verdicts, two full
judgements.** V1.3f's error, a fourth time, and the third time inside a file whose header
already warned about it.

### (b) The growth pledge failed band (ii) and the content moved

2.873 against a floor of 3.00. Fixed by raising its four breach rates ~20 %, not by
lowering the band — V1.4b's discipline, and it left the ratio ordering intact because the
growth pledge is still the cheapest per unit of risk.

### (c) The dominance test itself was the wrong test

The first version compared the authored pair (reward, breach) and reported **five
dominated promises**: the tax lock beaten by the growth pledge, the hospitals beaten by
both. Every one is an artefact. **The pair is not the decision**, because the third
quantity is *how often the promise is actually broken*, and that is nowhere in the
content — it is a property of the budget the player intends to run. [[campaign-model]]
§11's *share is not winning* in a new place.

The honest test runs each promise end to end against three post-election policies. Net
vote share at the 2032 vote, having won 2027 on `managed`:

| promise | hold `managed` | switch to `austerity` | switch to `spendthrift` |
|---|---|---|---|
| The employment guarantee | −0.3199 (35/59) | −1.1135 (59/59) | **+0.3897** (1/59) |
| The tax lock | +0.3460 (0/59) | −1.3262 (59/59) | **+0.4255** (0/59) |
| The deficit rule | +0.3725 (0/59) | **+0.4966** (0/59) | −1.1842 (59/59) |
| The health guarantee | **+0.3759** (0/59) | −1.9915 (59/59) | +0.4226 (0/59) |
| The growth pledge | −0.1209 (25/59) | −0.5494 (37/59) | −0.1746 (26/59) |

**Zero promises dominated in every column, and each column has a different best
promise.** The ladder is not orderable without knowing the budget the player intends to
run, which is what makes it a choice rather than a shopping list.

### (d) The ordering statistic was LUCK and it had to be EXPOSURE

The ratio-against-luck check failed on one adjacent pair: `deficit_pct_gdp` measures 1.284
of luck against `unemployment_pct`'s 1.182, eight per cent apart — while its CHOICE column
is 16.445 against 0.656, twenty-five times as large. Luck in isolation says the deficit is
the more uncontrollable of the two; **luck as a share of luck plus choice says the
opposite, and says it by a factor of nine.** On exposure the ladder is monotone.

### (e) The balance regime pair was confounded and needed a control

`managed_breaks_its_word` raises the income tax **and** cuts the health line, and both
move approval on their own through issues S5 built — so against `managed_keeps_its_word`
it printed the budget and the promise added together and attributed all of it to the
promise. `managed_breaks_nothing` runs the identical switch and promises nothing, and the
pair that isolates the price is that one. `tests/test_trade.gd` needed the same control at
V1.6a and V1.6c needed it twice.

### The guard rail is slack

Worst reachable two-promise stack **0.5700** (the tax lock + the deficit rule, on
`business`), 57 % of the clamp, **0.4300 of slack**. Largest authored rate 0.0050 against
a ceiling of 0.0100. Recorded honestly: `bloc_offset` is shared with laws, government
penalties, scenarios, diplomatic acts and V1.7a's campaign, so **this is a floor on the
exposure and not a ceiling.**

## 10. The constants — there are none

`pledges_constants.gd` ships **no tuned constant at all**, which is
`projects_constants.gd`'s position inherited whole and the second time this project has
reached it. Everything in it is a whitelist that fails a bad file at load or a ceiling
that catches a mistyped digit:

| | what it is |
|---|---|
| `PLEDGE_OUTCOME_FIELDS`, `PLEDGE_RATE_FIELDS` | whitelists; the rate half mirrors `TAX_KEYS` and `SPENDING_KEYS`, pinned **both ways** by the test |
| `PLEDGE_OPS` | two of five comparators; the refusals are the design |
| `PRECONDITION_FIELDS` | the whitelist plus two gate-only fields |
| `MAX_BREACH_OFFSET_PER_MONTH` = 0.010 | content ceiling; largest authored rate 0.0050 |
| `PLEDGE_TERMS` | the term table, so a term added without a row fails to load |

**And no concurrency ceiling.** How many promises may stand at once is the `pledge_count`
precondition every authored promise carries, which makes it content — and it binds
**across run-ups**, because a promise made in 2026 is still being judged when the 2031
run-up opens.

## 11. `SAVE_VERSION` stays at 23

`ns.pledges` absent reads as "nothing promised", which is the truth about every version-23
save because those games had no pledge verb — `measures` at V1.3c, `pacts` at V1.3g,
`appointments` at U6a, `campaign_running` at V1.7a.

**It is serialised regardless and that half is not free**, which is `regulation_burden`'s
case at V1.4b rather than the campaign bill's: a verb writes it, no tick recomputes it,
and **the reward has already been paid**. A save that dropped the register would hand the
player the upside of every promise they ever made and delete the liability.
`tests/test_save_load.gd` checks that premise rather than asserting it.

`NationState.from_dict()` **restores the register's types**: JSON has one number type, so
every `int` in an entry comes back as a float and a round trip would silently change the
shape of the thing it round-tripped. `pledges.gd` casts on every read and does not care;
whoever reads it next might.

V1.3c's device is **answered and re-armed**: the version does not move, and V1.7c has to
come and say why it does.

## 12. The `ISSUE_KEYS` question is answered NO, on test 1 alone

The nineteenth, and the **fourth consecutive session** to fail the same test for the same
reason: this ships a content object with an authored `bloc_offset`, so the price is
nameable without a fourteenth key. V1.6e, V1.6f and V1.7a were the other three.

## 13. Where it sits

A **Promises** section on `src/ui/campaign_panel.gd`, not a window of its own: a promise
is made in the run-up, so it belongs in the surface that runs the run-up. It costs one
`preload` and no `_windows.register()`, and it inherits that panel's two rules — the whole
body scrolls from the first line, and it is **never empty and never silent**, printing the
ladder and its prices four years before a run-up opens.

**Below the campaign rather than above it**, which is what makes `--pledge` and
`--campaign` want opposite ends of one scroll. V1.6e's correction has a **direction** as
well as a subject, and here two flags on one panel need different ones.

## 14. The balance re-run

**Bit-identical across all 36 existing regimes**, predicted in advance: the diff is
**additions only, zero removed lines.** The register starts empty and `tick_month()`
returns on `is_empty()` before it touches anything.

**Three new regimes, and the third is the one the first run proved was needed.** Same
budget, the same promise, and a switch that breaks it:

| 2027 vote | 2032 vote | |
|---|---|---|
| `managed_keeps_its_word` | 26.2 % HELD | **27.0 % HELD** |
| `managed_breaks_its_word` | 26.2 % HELD | **10.6 % LOST** |
| `managed_breaks_nothing` | 25.9 % HELD | 11.1 % LOST |

Read as the pairs that isolate each half: the promise is worth **+0.3 points at the
election it is made for** (26.2 against 25.9) and **−0.5 points at the election it is
judged at** (10.6 against 11.1), on a budget that breaks it. Keeping it instead holds the
office at 27.0.

## 15. The screenshot pass

The eighteenth, and it found two bugs, both the readout's.

**The breach cost had no unit.** The offers printed *"a month broken: Pensioners 0.14,
Rural 0.10, Business 0.18"* — four bare numbers in no unit, two lines below an effort row
printing points of **turnout** in the identical shape. Now signed, with the unit named
once at the end.

**And a live promise never said what it had cost.** The row read *"broken 14 of 14
months"* against a player who could see the per-month price on the offers below and had no
way to read what the promise they had already made was costing — the one figure the
section exists to be a ledger of. It now reads *"Unemployment no more than 7.5 % · BEING
BROKEN · broken 14 of 14 months, −0.99 approval"*, derived rather than stored, because the
breach rates are content and the count is the state.

---

Related: [[index]] · [[campaign-model]] · [[election-model]] · [[opinion-model]] ·
[[media-model]] · [[unrest-model]] · [[v1]]
