---
title: Campaign Model
tags:
  - decision
  - elections
  - simulation
---

# Campaign Model

V1.7a, the first session of the V1.7 block. The campaign phase: a window before the
vote in which the president spends money to change **who turns out**.

Same standard as [[election-model]] and [[opinion-model]]: a **game model**, judged on
whether the player's decisions produce a legible, attributable electoral verdict.

`src/sim/campaign.gd` is the model, `src/sim/campaign_constants.gd` is the one tuned
constant and four bounds, `data/campaign-actions/campaign.json` is the ladder, and
`tools/campaign_probe.gd` is what set both.

## 1. The row asked for three things and two were already answered

[[v1]] §7's first bullet is *"a window before the vote, spending **time** and **money**
on **messaging**"*. Counted against what is built:

| noun | verdict |
|---|---|
| **time** | Does not exist, and it was **deleted** rather than never built. [[calendar-model\|U6a]] swept a monthly budget of the player's days against a band fixed before the sweep and found it structurally unreachable: the median month offers 27 legal acts asking 124 days, so every budget from 4 to 24 bound in **100 %** of months. The reason carried forward is not about calendars — `available()` returns what is **legal** and nothing models what the player **wants**, so any ceiling priced against legality always binds. **Instance forty.** |
| **messaging** | [[media-model\|V1.5d]]'s, and the bullet says so itself: *"V1.5d may build the peacetime half; if it does, this bullet **reads** it rather than rebuilding it."* It did. V1.5d cut the campaign-time twin on the ground that messaging which damps hostile framing **is** `press_freedom`'s positive direction with a different label — one accumulator, two writers. So this session writes nothing on `framing_gain` and nothing on `press_freedom`, and `tests/test_campaign.gd` reads the source to say so. |
| **money** | The only noun that survives, and its **target** had to be found. |

**Instance forty-one is in the section rather than in a row.** §7 is titled *Elections
as a phase* and two of its three bullets are not phases: electoral-system choice is a
constitutional amendment, and promises bind across a whole term. And the block cell's
fourth item, **referendums**, has no bullet in §7 at all — it lives in §1's list, in the
re-parked V1.1f row, and in `nation.gd`'s `KNOWN_AMENDMENT_RULES` comment, which already
names *"V1.1f/V1.7"* as `referendum_required`'s owner. Three places point at V1.7 and
the section carries nothing. Cross-referenced into **both** rows.

## 2. The target is turnout, and it is the one quantity with no writer

`election_constants.BLOC_TURNOUT` is read in **exactly two places, both inside
`Elections.vote_share()`**, and nothing in this project has ever written it. That makes
a live per-bloc offset a **first writer with no double count to resolve** — which
neither of the other two candidates could claim:

- **approval.** `vote_share()`'s `pull` term already reads `ns.bloc_approval`, and
  approval **is** the term's record. A campaign term there is a second writer of the one
  quantity the whole game is judged on, and it would make the last eight months worth
  more than the first fifty-two.
- **framing.** Refused above, by V1.5d.

And the distinction is the honest one rather than a convenience: **a campaign does not
change what people think of your record.** The record is the record, and V1.5d's press
decides how loudly it is heard. It changes who bothers to vote on it.

## 3. Log-odds, so the turnout is bounded by construction

```
turnout(b) = σ( logit(BLOC_TURNOUT[b]) + mobilisation[b] )
```

Two things fall out that nobody authored:

1. **Strictly inside (0, 1) for every finite shift**, so there is no clamp on turnout
   anywhere and no value of `MOBILISATION_MAX` that could produce a share above one.
   [[cycle-model|V1.6a]]'s argument: a bound with no number to set wrong is stronger
   than a clamp. `tests/test_campaign.gd` sweeps ±10 to check it, and **records that a
   `double` saturates at a shift of about 36** — the mathematical bound is exact, the
   representation is not, and 36 is forty times the guard rail.
2. **The same effort moves a low-turnout bloc further than a high-turnout one.**

| bloc | base | +0.20 | +0.40 | +0.60 |
|---|---|---|---|---|
| students | 0.450 | 0.500 | 0.550 | 0.599 |
| urban | 0.620 | 0.666 | 0.709 | 0.748 |
| workers | 0.650 | 0.694 | 0.735 | 0.772 |
| rural | 0.700 | 0.740 | 0.777 | 0.810 |
| business | 0.750 | 0.786 | 0.817 | 0.845 |
| pensioners | 0.820 | 0.848 | 0.872 | 0.892 |

There is more room to mobilise students than pensioners, and the model says so without
a table — which is the arithmetic doing what [[election-model]]'s `BLOC_TURNOUT` comment
only asserts.

## 4. The window is a level read, and the clear is its other half

`Campaign.is_open()` compares the clock against `ns.next_executive_year/_month`. There
is **no flag, no scheduler and no hook in `elections.gd`** — [[defence-model|V1.3g]]'s
rule, that nothing in this project ever lifts a flag it has set, so an obligation which
opens itself must also close itself.

The register clears the month the window **shuts**, which is the month after the vote,
because `Elections.tick_month()` pushes `next_executive_*` a full term forward on a win.
That is why this file needs no call from `elections.gd` at all: the one edge that would
have needed one is read as a level instead. A legislative or European election landing
inside the run-up **reads** the mobilisation and does not clear it, which is correct — a
mobilised electorate votes in whatever election is held.

**The executive vote and not the legislative one**, and `Elections.init_nation()` is
what makes that one read rather than two: where there is no separately elected executive
it already points `next_executive_*` at the legislative date. France campaigns for the
presidency and Germany for the Bundestag with no branch anywhere.

## 5. An effort is a standing rate with a deadline

The first design made an act a **one-off purchase** billed for one month. Under it,
acting **late** is strictly better — same mobilisation, less time paying for it — and
this project has killed that shape six times (V1.3c's severities, V1.3d's fourth rule,
U6a's booking, V1.4c's dividend, V1.5d's censorship, V1.6e's flat bill).

So an effort **accrues every month it runs and bills every month it runs**. Start early
and you buy more and pay more; start late and you buy less and pay less. Linear in
months on both sides, and neither end dominates.

`stop` exists and `abandon` does not, and the difference from [[projects-model|V1.6f]]
is the model: a project can only be abandoned because half a motorway is worth nothing,
where a campaign effort already run has already reached the voters it reached. That is
`investment.gd`'s `withdraw`. It is there at all for [[defence-model]]'s reason — an
obligation only the clock can close is a permanent monotone charge — and the window does
close it, but not until the vote, and a president who has run out of money in March
should not have to lose in June to stop paying.

## 6. The bill

`campaign_bill_pct_gdp` is the **sixth** computed spending line, after V1.3d's bloc
transfer, V1.3g's deployment bill, V1.4a's subsidy bill, V1.6e's investment bill and
V1.6f's project bill. Not a sixth `SPENDING_KEYS` entry, because that list is keyed 1:1
to cabinet portfolios and a sixth line is a sixth minister.

**The second bill in this project that stops, and it stops harder than V1.6f's.** A
project's bill ends when the work does, which is a length the player chose by choosing
the project. This one ends on a date the constitution chose — which is why the decision
it poses is about **timing** where the project's is about **size**.

The fiscal price is not authored anywhere: the bill widens the deficit, which reaches
`public_finances` through machinery S5 built, and it does so **in the months immediately
before the vote**, when every bloc is looking.

**And the asymmetry is the model.** The money and the mobilisation are both spent at the
ballot box; the resentment is not, because `ns.bloc_offset` is a permanent accumulator.
A campaign leaves a mark that outlives the campaign — visible in the harness, where
`managed_campaigns_early` re-elects on a 2027 vote it moved and comes back **lower** in
2032 than a president who never campaigned.

## 7. What the probe corrected, and it corrected the session five times

Eighteen sessions running.

### (a) The band was invented, and the anchor is measured

The first clause (i) read *"at least 0.50 points of vote share"* — a number picked
because it sounded like a margin. Every candidate failed against it, and the table never
said whether 0.50 was the right ruler. It was not. The honest ruler is the only other
thing that moves `Elections.vote_share()` at all: **approval**, through the `pull` term.

| approval | Δ share | Δ gap |
|---|---|---|
| +1.0 | 0.3415 | 0.4512 |
| +2.0 | 0.6797 | 0.8980 |
| +3.0 (the poll floor) | 1.0147 | 1.3404 |

So a full run-up must be worth **at least one point of approval** — below that governing
swamps it — and **at most the poll floor**, above which a campaign substitutes for the
record. The upper edge is `POLL_FLOOR_PTS` for a reason worth stating: a swing smaller
than the published polls can resolve is exactly the swing a campaign may own. The player
has spent the term reading blurred figures, and the campaign decides the race those
figures could not call.

### (b) The headroom arithmetic was wrong by a factor of a hundred

`_headroom()` divided the measured tax swing by 100 and reported **4.7777** points where
there are **0.2039**. Clause (ii) then passed at every candidate — and a band that passes
everywhere is a bound (V1.5a), except that this one was not even that: it was an
arithmetic error wearing one. The dearest pair the concurrency gate allows costs 0.1750,
inside the real headroom by 0.0289.

### (c) The emulation claim was false above the shipped window

The probe's header claimed a run starting `d` months out emulates any window of `d` or
more. It does not: `Campaign.tick_month()` **clears** on a level read of the shipped
constant, so every row above it was a campaign wiped on the next tick, reporting a zero
bill beside a non-zero move. Rows above the constant are now refused rather than
printed, and the sweep of record is run with the constant raised — V1.6b's *set the
constant once and re-run*, applied to an integer.

### (d) The content's targeting was the gap, not any constant

At saturation the authored ladder reached **0.199** points where perfect targeting at
the same cap reaches **1.14** — a targeting efficiency of 17 %. The first ladder was
almost entirely positive: every effort mobilised somebody and depressed nearly nobody, so
no window and no scale could clear the lower edge. Real campaigns **demobilise** as well
as mobilise, and once each effort carried a real negative side the same cap cleared it.
**The correction was to the content and not to any constant**, which is
[[companies-model|V1.4b]]'s discipline arriving a second time.

What makes this more than a content fix is `(c3)`, which nothing authored:

| bloc | size | turnout | Δ share at +0.30 | verdict |
|---|---|---|---|---|
| workers | 0.30 | 0.65 | −0.0770 | not theirs |
| pensioners | 0.24 | 0.82 | −0.0501 | not theirs |
| urban | 0.15 | 0.62 | **+0.1997** | theirs |
| rural | 0.13 | 0.70 | −0.0772 | not theirs |
| business | 0.10 | 0.75 | +0.0368 | theirs |
| students | 0.08 | 0.45 | +0.0604 | theirs |

France's centrist incumbent owns the three **smallest** blocs — 0.33 of the electorate
against 0.67 that mobilising would hurt them. A French centrist's campaign is
structurally a demobilisation campaign, and no line of content says so.

### (e) The guard rail was binding, and binding here inverted the decision

`MOBILISATION_MAX` at 0.60 was reached by the reachable stack. Usually a binding guard
rail merely sets the number ([[economy-model]]'s `IMPULSE_MAX` finding, caught in five
places); here it did worse. **Once the accumulator saturates, a longer run-up is
strictly worse** — it costs more months of bill for exactly the same reach — so the
clamp was not setting the timing decision, it was **inverting** it. At 0.90 the worst
stack two efforts can reach over a full window is 0.6800, slack by 0.2200.

## 8. `CAMPAIGN_WINDOW_MONTHS`, and maximin slack

The one tuned constant. The feasible set is **[7, 10]**: below 7 the authored ladder
cannot reach the lower edge, above 10 the reachable stack passes the guard rail.

V1.5d established that where two model criteria bound a quantity from opposite sides
neither edge selects and **the interior governs** — but "the interior of a passing
**list**" is a statement about the grid, and V1.5b's whole finding is that a grid must
never choose. **The interior of the feasible region needs none**: take the candidate
whose *worst* relative slack is largest.

| d | lower-edge slack | guard-rail slack | min |
|---|---|---|---|
| 7 | 5.8 % | 33.9 % | 5.8 % |
| **8** | **23.1 %** | **24.4 %** | **23.1 %** |
| 9 | 40.3 % | 15.0 % | 15.0 % |
| 10 | 57.3 % | 5.6 % | 5.6 % |

Stable under refinement (both slacks are continuous in `d`), stable under widening (a
candidate outside the region has negative slack), and it degrades correctly: where one
criterion is far looser than the other it returns the edge of the tighter one, which is
what a bound should do. **`CAMPAIGN_WINDOW_MONTHS` = 8.**

## 9. The constants

| constant | value | how it was set |
|---|---|---|
| `CAMPAIGN_WINDOW_MONTHS` | 8 | Two-sided; **maximin slack** over the feasible set, §8 |
| `MOBILISATION_MAX` | 0.90 | Guard rail, declared not a selector. Reachable peak 0.6800, slack 0.2200 |
| `MAX_MOBILISATION_PER_MONTH` | 0.10 | Content ceiling; largest authored rate 0.055 |
| `MAX_CAMPAIGN_COST_PCT_GDP` | 0.20 | Content ceiling; dearest allowed pair 0.1750 against 0.2039 of headroom |

**No strength constant and no price constant**, which is `projects_constants.gd`'s call
inherited whole: what an effort costs and who it reaches are two independent authored
facts, so the ladder is the lever. **And no concurrency ceiling** — how many efforts run
at once is the `campaign_count` precondition every authored action carries, which makes
it content, and a model constant duplicating a content gate is the failure V1.6e deleted
`INVESTMENT_BILL_MAX_PCT_GDP` for.

## 10. The ladder

| effort | cost %GDP | reach, per month |
|---|---|---|
| doorstep operation | 0.030 | workers +0.030, urban +0.025, students +0.030 |
| donor circuit | 0.045 | business +0.055, urban +0.025, **workers −0.045, students −0.030** |
| town-hall tour | 0.055 | rural +0.050, pensioners +0.030, **urban −0.020** |
| digital push | 0.075 | students +0.050, urban +0.050, **pensioners −0.045, rural −0.025** |
| broadcast campaign | 0.100 | pensioners +0.050, rural +0.035, workers +0.020, **students −0.030** |

**Zero dominated pairs**, checked rather than assumed. The five are deliberately
incomparable: each names a different part of the electorate, so no pair can be ordered by
cost alone and the decision is *which voters to spend the run-up on* rather than *how
much to spend*.

## 11. Share is not winning, and nobody authored that

The pair that maximises the incumbent's own vote share is **not** the pair that
maximises their lead:

| pair | Δ share | Δ gap |
|---|---|---|
| digital push + doorstep | **+0.4204** | −0.4033 |
| donor circuit + town halls | −0.2417 | **+0.6475** |

Mobilising a bloc lifts **every** party that bloc likes, and the parties nearest you in
ideology space are exactly the ones sharing your voters — `Elections.vote_share()`
renormalises per bloc, so turnout is a rising tide inside a bloc rather than a transfer
between parties. Under a plurality verdict the quantity to maximise is the **lead**, and
the best play can be to run a campaign that lowers your own vote.

Recorded rather than fixed: it is a property of [[election-model]]'s vote-share model and
not a defect in this one. It is also why `balance_probe.gd`'s regime ranks efforts on the
**gap**.

## 12. The `ISSUE_KEYS` question is answered NO, on test 1 alone

The eighteenth. As V1.6e's and V1.6f's were, and for the same reason: this ships a
content object with an authored `bloc_offset`, so the price is nameable without a
fourteenth key. Three consecutive sessions have now failed the same test for the same
reason — **a session shipping a content object has somewhere to put the price.**

## 13. `SAVE_VERSION` stays at 23

Three fields added and none earns a bump. All three read as *"no campaign"* when absent,
which is the truth about every version-23 save because those games had no campaign verb —
`measures` at V1.3c, `pacts` at V1.3g, `appointments` at U6a, `sector_investment` at
V1.6e.

They are serialised regardless, and the reasons differ:

- `campaign_running` — a verb writes it and no tick can recompute it. A save that dropped
  it would silently stand a campaign down and hand the player back its bill.
- `campaign_mobilisation` — spent at the ballot box, so a save reloaded in the last month
  of a run-up would otherwise go to the vote with a campaign already paid for and no
  longer held.
- `campaign_bill_pct_gdp` — recomputed on the first tick; serialised so a save read back
  and never ticked reports the budget it was saved with.

`tests/test_save_load.gd` asserts the version is **still 23**, so V1.7b has to come and
say why it moves — V1.3c's device, pointed at the next session for the sixth time.

## 14. The balance re-run

**Bit-identical across all 34 existing regimes**, predicted in advance: the diff is
**additions only, zero removed lines**. Two new regimes, the expensive kind — a campaign
is a verb no budget regime issues.

Same budget, same efforts, different month:

| 2027, at the vote | deficit | approval | worst bloc | incumbent share |
|---|---|---|---|---|
| `managed` (no campaign) | −2.70 | 46.6 | students 44 | 25.9 % |
| `managed_campaigns_early` (opens Sep 2026, eight months) | **−2.80** | **46.0** | **students 42** | 25.7 % |
| `managed_campaigns_late` (opens Mar 2027, two months) | −2.70 | 46.6 | students 44 | 25.9 % |

**The timing trade-off is what the harness shows, and it shows it on the price rather
than on the prize.** Eight months of run-up costs a tenth of a point of deficit, six
tenths of approval and two points off the worst bloc; two months costs nothing the
printed columns can resolve. Both HELD, and by 2032 **both come back lower than
`managed`** (26.4 % and 26.3 % against 26.7 %) — the permanent `bloc_offset` of §6,
outliving the campaign that bought it.

**The incumbent's own share FALLS under `early`, and that is §11 rather than a defect.**
The regime ranks efforts on the **lead** — a live score, derived at the moment of acting
and naming no effort and no nation — and the best play for the lead here is a
demobilisation play that lowers the incumbent's own vote. The printed column is the
share, so the harness records the half that looks worse.

**The first pair of regimes was wrong twice and the run said so, not the reading.** The
months were 9 and 16, and 16 IS the month of the vote — so "late" campaigned for zero
months and printed a presidential result identical to "early" to the digit. And the
first ordering rule was *cheapest first*, on the reasoning that a regime picking the
optimal pair would be measuring the probe's answer; it picked the pair table (h) measures
at **+0.058 points**, the weakest positive of ten, and produced a result identical to
`managed`. **A demonstration of nothing is not a demonstration**, and every other verb in
this harness is exercised at something a president would plausibly do.

## 15. Where it sits

One window, `campaign`, in the State cluster beside the Diary — one
`_windows.register()` and one line in `main.gd`'s `_build_action_bar()`.

**Not rows on the Polling panel**, which is the closer thematic fit and the wrong one:
that panel's contract is that every figure on it has been through `poll_noise.gd`, and a
mobilisation figure is not a poll — the government knows exactly what it is paying for
and exactly who it has reached. [[society-model]] §11 moved the delivery readout off that
panel for the identical reason one block earlier.

**Never empty and never silent**, which is the opposite call from the overview's delivery
lines. A campaign panel is a surface the player opens **outside** a run-up — that is when
they are planning one — so it always prints how far away the vote is, what each effort
costs, and who it reaches, with the buttons appearing only once the window opens.

**And no diary row.** A "campaign opens" entry would be a fixed offset from a date the
strip already carries, and `calendar.gd` may preload only its own constants — a property
`tests/test_calendar.gd` enforces and this session declined to weaken for a derived date.

## 16. The screenshot pass

The seventeenth, and it found two bugs — one the content's and one the tool's.

**A content name collided with a window.** `stop_donor_circuit` was authored as *"Clear
the Diary"*, which is a perfectly good English idiom for cancelling a round of breakfasts
and is also the name of a **window this game already has**. On the panel it read as a
calendar action attached to a campaign effort. Renamed to *"Cancel the Breakfasts"*. A
name that is right in isolation and wrong in the shell is exactly what a frame catches
and a green suite cannot.

**And `--campaign` pinned the scroll past the thing it exists to check.** `--build` and
`--invest` both scroll to the bottom, because for those panels the row the flag acted on
is last. Here the top is the half that has to be checked — the months to the vote and the
campaign bill, which is the figure the budget panel's own campaign line must agree with —
so the first frame opened on a sentence cut in half with the ledger off-screen.
**V1.6e's correction has a direction as well as a subject**: scroll to where the flag's
own claim is.

With both fixed, the two frames agree: the panel reads *"Months to the vote 4 · Campaign
bill 0.075 % of GDP"* with Urban +4.6 and Business +3.9 against a live register, and
`--campaign --open budget` reads *"of which the campaign 0.07 % (2 bn)"* rather than an
em dash.

---

Related: [[index]] · [[election-model]] · [[opinion-model]] · [[media-model]] ·
[[projects-model]] · [[v1]] · [[ROADMAP]]
