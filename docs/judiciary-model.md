---
title: Judiciary Model
tags:
  - decision
  - legislature
  - simulation
---

# Judiciary Model

The court, as built in V1.1e. Whether a passed bill survives, the rule-of-law
stock that decides, and the price of moving it.

[[v1]] §1 asks for *"courts that can strike down laws, a check the player cannot simply
outvote"*, and that bullet **also owns §5's *"rule of law — institutional strength gating
what the player can get away with"***, handed here at V1.5's decomposition on
the argument that two uncontestable gates on player action would be one machine claimed
twice. So this is one machine wearing both labels rather than two sharing a page.

## 1. The dataset exists, and that is three rows in a row

[[v1]] §6 says an inequality index *"cannot be derived"*; [[demography-model|V1.5b]] found
age structure published; [[unrest-model|V1.5c]] found the Gini published. **The World Bank
publishes this one too** — Worldwide Governance Indicators, all ten nations, all ten years
of the window every other indicator already uses, **no gaps at all**, so it needs neither a
nearest-year fallback nor a provenance year of its own.

Two things about the code, both found by fetching it rather than assuming it:

- The WGI were **re-coded**. `RL.EST`, which is what every citation of this series still
  names, returns *"The indicator was not found. It may have been deleted or archived."*
  The live code is `GOV_WGI_RL.SC`, and it lives on WGI's own database — so this is the
  first indicator in `tools/import_data.py` whose download line carries `&source=3`.
- The **score** (0–100) rather than the **estimate** (−2.5…+2.5), because every stock this
  project keeps on a nation is already on a 0–100 scale — approval, `service_quality`,
  `unrest_pct`, `gini_index` — so the estimate would be the one quantity in the game
  needing a conversion nobody could check.

| | ITA | ESP | FRA | GBR | BEL | DEU | AUT | NLD | CHE | LUX |
|---|---|---|---|---|---|---|---|---|---|---|
| Rule of law | 67.6 | 73.0 | **73.8** | 78.8 | 79.0 | **84.9** | 85.8 | 86.3 | 87.3 | 87.3 |

Span **19.7 points**, mean **80.38**. The measured **slope** exists — nine of the ten fall
over 2015–2024 and only Italy rises — and is deliberately **not** imported: a court that
weakens every year on its own is [[defence-model|the permanent monotone charge]], and
V1.5c's Gini drift is a stopgap standing in for levers that do not exist where this stock
has a lever from day one.

## 2. Three nations have no review, by three different doctrines

`government.judicial.review` is the **ninth** dispatch-on-a-data-string field, and nothing
authored the pattern below — it fell out of reading each constitution for its own sake.

| | Body | Basis for `none` |
|---|---|---|
| **GBR** | — | Parliamentary sovereignty, the same doctrine that puts its `amendment_rule` at `ordinary_law`. Human Rights Act 1998 s.4(6) says in terms that a declaration of incompatibility does not affect an Act's validity |
| **NLD** | — | **Art. 120 Grondwet EXPRESSLY forbids** the courts to review an Act's constitutionality |
| **CHE** | — | **Art. 190 Cst.** binds every authority to *apply* federal statutes — a binding-force clause rather than a withheld grant. Cantonal law is reviewable, federal law is not |

The other seven are `constitutional`. **Britain's 78.8 is computed and never read**, which
IS parliamentary sovereignty.

**Two values and not four**, and the collapse is a recorded reduction rather than an
oversight: abstract review before promulgation (France, Art. 61) and concrete review after
it (Germany, Italy, Spain, Austria, Belgium, Luxembourg) differ only in **timing**, and this
model applies a law's effects at passage. Authoring a distinction nothing reads is what
[[political-systems]] refuses when it declines to author absolute monarchy for a roster with
none.

## 3. The doctrine is proportionality, and every denominator already existed

A law's **reach** is the largest fraction of any substantive effect clamp it uses, in
[0, 1], computed once at load. Nine of the ten nations are civil-law states whose
constitutional courts test state action against *Verhältnismäßigkeit* or its local name:
not whether a measure is wise, and not whether it is popular, but **whether it goes further
than the end requires**. So what is measured is how far a law goes, against the furthest
this model lets anything go.

```
reach(law) = max over channels of |effect| / that channel's clamp
tolerance(ns) = JUDICIAL_TOLERANCE × ROSTER_MEAN_RULE_OF_LAW / judicial_independence
struck        = reach(law) > tolerance(ns)
```

Every denominator was set by an earlier session for its own reasons —
`legislature_constants`' three scalar clamps, `companies_constants`' regulation burden, and
the five `SOCIETY_TERMS` maxima. An authored `unconstitutionality` score would be **one
strength written twice**, which `src/core/investment_action.gd` already refuses by name.

### The probe's first correction: `bloc_offset` was in, and it made the court a popularity contest

The first version of `reach()` included `bloc_offset`. Measured over all thirty-eight
authored laws it **dominated every other channel** — it is authored in hundredths against a
clamp of 1.0 where the scalar channels are authored in small fractions of 5.0 and 1.0 — so
`reach` came back numerically **equal to the largest bloc_offset on the law**, and a court
built on it strikes down whatever is unpopular. That is the opposite of what a court is for,
and it is one quantity read twice: [[legislature-model]] already says `bloc_offset` exists
precisely for laws with no number the budget produces. **A court does not rule on
popularity.**

**Budget levers are out** on this file's own rule rather than a new claim: a law with a
genuine budget effect *is* a budget change, routed through the same `Budget.commit()` the
budget screen uses, and the size of a tax rate is Parliament's business.

**`effects.institutional` is out** for two reasons that agree, so neither is doing the
other's work: it sets an absolute value with no magnitude to take a fraction of, **and a
constitutional amendment is never reviewable anyway**, because once it passes it becomes
the standard the court applies. The Conseil constitutionnel has declined jurisdiction over
revisions since 2003; Germany's eternity clause is the apparent exception and is already
modelled, as `permits_system_change: false`.

**The cost is measured rather than waved at**: ten of the thirty-one ordinary laws reach
exactly 0.000 and are structurally unreviewable — every electoral-reform Act, every tax law,
and `regional_devolution`, which is the one a real court would most certainly hear.
Recorded as a bound rather than patched, because the alternative is an authored score.

## 4. The tolerance form, and why the linear one died

`1 − independence/100 × S` was written first and the sweep killed it. Its zero point is
arbitrary — a court at 100 tolerates exactly nothing, for no reason the model can state —
and it **amplifies** the roster's spread: a 15 % gap in independence between France and
Germany came out as a 29 % gap in tolerance at the middle of the range and worse at the top,
so the passing interval collapsed to two grid points and **Germany could not legislate**.

The inverse form says something a model can defend instead — **a court twice as independent
tolerates half as much** — and holds the ratio at exactly the ratio of the scores. The
anchor is the roster's own measured mean, which is [[cycle-model|V1.6a]]'s
`cycle_amplitude_rel` shape, [[media-model|V1.5d]]'s mean anchor and
[[referendum-model|V1.7c]]'s `status_quo_position()` one block on.

## 5. `JUDICIAL_TOLERANCE` — five clauses, all written on the content

[[campaign-model|V1.7a]]'s correction taken seriously: that session's first band clause was
**invented** (*at least 0.50 points of vote share*, a number that sounded like a margin) and
every candidate failed it.

| | Clause | Fails |
|---|---|---|
| (i) | France's court must block **both** `emergency_*` laws at new game. A constitutional court that does not stop emergency powers is not one — and *"Emergency powers"* is tiered **Someday** in [[mechanics-governance]], so the two authored approximations of it are exactly what this gate is for | above 0.367 |
| (ii) | **Germany**, the second playable nation with a court, must still pass a majority of ordinary laws. V1.2a chose Germany for institutional contrast, not paralysis | — |
| (iii) | A full capture must unlock both emergency laws, or the key does not work | below 0.323 |
| (iv) | A full capture must leave something still blocked, or it is a master key | — |
| (v) | Every rung of the ladder must itself be passable at the independence it is reached at | — |

**Passing [0.323, 0.367]** on a 0.001 grid swept over [0.200, 0.600], 45 points wide. Both
edges are the **model's**; the midpoint **0.345** is interior to the passing set *and* to
the swept range — [[demography-model|V1.5b]]'s diagnostic that a value at an endpoint of the
sweep is a suspect rather than a result.

**What it buys.** France blocks **9 of 25** reviewable laws; a full capture unlocks 6 and
leaves 3 — `anti_corruption_agency`, `farm_standards_act` and
`public_sector_pay_settlement`, the three furthest-reaching laws in the game — so **a
captured court is still a court**. Germany blocks 17 and still passes 18 of 35 ordinary
laws. And the ten split into **three tiers** out of a World Bank series and one dial:

| Blocks | Nations |
|---|---|
| 3 of 25 | ITA |
| 9 of 25 | BEL, GBR\*, FRA, ESP |
| 17 of 25 | DEU, AUT, NLD, CHE\*, LUX |

\* computed and never read.

## 6. The gate is a lock with a key you can buy

`judicial_independence` is the **fifth** `effects.society` term, by a fifth session — and
`law.gd`'s `_extract_society()` is generic over that dictionary, so all five of its error
strings updated themselves a second time. It is the first entry whose per-law bound is
**not** the stock's own clamp: the four before it are signed stances starting at 0.0 for
everybody, and this one is a **level** imported per nation, so passing the clamp as the
per-law bound would let a single Act abolish the courts outright.

**Signed both ways**, which is [[companies-model|V1.4b]]'s deregulation argument plus one
V1.4b did not need: a one-way level makes a court-strengthening law **inert on a clean
state**.

**The court is transparent, and that is a decision rather than a concession.**
[[legislature-model]] blurs the *vote* forecast on purpose; this gate is not blurred. A
division is a body of people whose minds the player is trying to read; a court is a **rule**,
and a rule the player cannot read is not a check on their power, it is a trap. So the doomed
bill stays on the law list with the verdict and both numbers printed beside it, rather than
being filtered out of `available()`: **a lock taken out of view teaches nobody that there is
a key.**

### The ladder had to move, and the fix that is also true is the better fix

The first three court-weakening Acts were positioned in the socially-traditional corner
(social +0.5 to +0.7), which is where judicial capture sits in the popular imagination.
Measured, **all three playable nations refused every rung**: France 92–370, Britain 130–325,
Germany 277–353. All three start with a socially liberal or centrist coalition, so the whole
mechanic was authored content no player could reach — [[referendum-model|V1.7c]]'s finding,
and its remedy: sweep the ideology grid for the real window and author into it.

France's window is economic [−0.4, 0.0] × social [−0.6, 0.0], and **that is the truer
framing rather than a concession**. Judicial-independence rollback in Europe is sold on
*democratic legitimacy* — unelected judges overriding elected parliaments — which is
majoritarian and not traditionalist. Poland's was sold as decommunisation, Hungary's as
constitutional renewal, and in France *le gouvernement des juges* is a critique made from
the left as often as from the right. The bloc prices did not move, because who **objects**
was already right: urban, students and business, who want legal certainty.

Two bounds recorded rather than tuned away: **Germany's own court strikes every rung of its
own capture** (reach 0.333 against a tolerance of 0.327), which is a good property and not a
miss; and **Britain's assembly refuses them** on a more polarised roster, where there is no
court to capture anyway.

## 7. `JUDICIAL_UNREST_BETA` — set by ratio, because the band could not select

Legitimacy is where [[media-model|V1.5d]] put it: willingness to accept your rule **outside**
the ballot box, which is [[unrest-model|the grievance]] — and `UNREST_BLOCS` is
`["workers", "students"]`, exactly who marches when a government captures its own courts.

**Not a second press freedom with a different label**, and the check is written down rather
than assumed: press freedom moves `framing_gain`, how loudly bad news travels; this moves
whether a passed law survives. Different landing site, different units, so
[[legislature-model]]'s *same act, same landing site, same units* criterion is not met.
`law.gd` already records that the next session would reach for a fourth anti-double-count
pair **by symmetry** and that symmetry is not the test; V1.1e reached, checked, and refused.

Table J2's band (i) passes at 0.15 and at every candidate above it; band (ii) — a capture
must not on its own carry a calm country over `UNREST_THRESHOLD_PCT` — never binds inside
the sweep at all (peak unrest 15.95 at a beta of 1.00 against a threshold of 45.0). **A
bound is not a selector**, and a passing set running to the top of the grid is the grid
choosing. That is the one-sided failure V1.5a, V1.5b, V1.5c and V1.5d each recorded, here
for a fifth time.

So the ratio chooses, against the sibling this term was modelled on:

```
JUDICIAL_UNREST_BETA = PRESS_UNREST_BETA / INDEPENDENCE_LAW_MAX = 8.0 / 9.0 = 0.889
```

which says that capturing the courts as far as one Act may reach costs what censoring the
press as far as one law may reach costs. The two are the same kind of act on the same two
blocs through the same register, so **equal is the claim that needs no evidence and any
other number is one that would**. V1.5d set `PRESS_UNREST_BETA` itself the same way.

**Read on the DEVIATION and not the level**, for `start_service_quality`'s reason: a country
whose courts have always been weak is not permanently rioting about it, and Italy is not
angrier than Switzerland on frame one. `tests/test_judiciary.gd` asserts the term is exactly
0.0 for all ten at new game.

## 8. Where the gate sits, and the three places it deliberately is not

`_review_and_apply()` is called from `propose()`, from `_force()` and from the release of a
held bill — every path on which a bill takes effect without the country having voted on it.

**Not inside `apply_effects()`.** That function has had two callers since [[events-model|V1.8]]
and the second is an **event choice**, which is §1's *"Decree / executive order — bypass the
assembly on a narrow set of matters, at a legitimacy cost"*. A decree annulled by a court is
the Conseil d'État reviewing an administrative act — a different body reviewing a different
thing — and *"Judicial appointments"* and *"Emergency powers"* are both tiered **Someday**.
Recorded, not built.

**Not inside `apply()`.** Tests, probes, `tools/screenshot.gd` and `tools/balance_probe.gd`
all call it directly to set up state, and a gate there would silently refuse them. This is
also why the balance re-run is bit-identical: `AMENDMENT_REGIMES` and every law regime apply
a law rather than proposing one.

**Not in `_settle_referendum()`.** A law the country has ratified is not reviewable — the
Conseil constitutionnel declined jurisdiction over a referendum law in 1962 — and it agrees
with the exclusion `reviews()` already makes for an amendment, since a referendum in this
game only ever ratifies one.

**A strike-down carries no extra price.** The cost is the law you did not get and the
cooldown you burned — the failure branch that already exists. A `bloc_offset` on top would
double-count the division that was already paid for.

## 9. The kill switch cleared

Named on a **specific** pair of runs rather than on "some reachable regime", which is the
clause [[credit-model|V1.6c]] tightened on its own record. Both hold the same budget for a
full term; one passes the ladder and then everything the capture unlocks, the other governs
and passes nothing.

| run | approval | deficit | unrest | laws in force |
|---|---|---|---|---|
| control | 49.76 | 2.76 | 2.45 | 0 |
| captured | 45.16 | 2.78 | 3.19 | 46 |

**Capture ends worse on approval and worse on the deficit.** It buys 46 extra laws in force
and pays for them.

## 10. The `ISSUE_KEYS` question, answered NO on test 1

The **twentieth**, and a fifth consecutive session for the same reason: this session ships
content objects — four judicial-reform Acts, each with an authored `bloc_offset` — so there
is somewhere to put the price. Recorded in `opinion_constants.gd` beside `ISSUE_KEYS`.

## 11. What is deliberately not built

**Judicial appointments.** *"Pack the court, slowly, and change what is possible"* is tiered
**Someday**. The ladder moves a score; nobody is named.

**A corruption coupling.** Designed and cut. §5 of [[v1]] kept `corruption` in its own block
precisely because it *"shares no state with a court"* — so coupling them would falsify §5's
own stated reason for the split, and it would make `anti_corruption_agency` a
court-strengthening Act without saying so. It would also have forced a fourth
anti-double-count pair in `law.gd`; **reached for, checked, refused.**

**Review of an event choice.** §8, and the deferral is recorded in `legislature.gd` beside
the gate.

**A per-nation court composition.** The strength is one imported number. Anything richer is
*Judicial appointments*.

## 12. Why nothing diverges

| Quantity | Bound |
|---|---|
| `law.reach` | `minf(worst, 1.0)` over fractions of clamps that are themselves bounded. Computed once at load and never mutated. |
| `tolerance()` | Clamped to `[0, 1]`, with an explicit floor at an independence of 1.0 so a captured court cannot divide by nothing — and the answer there is 1.0, which is the same answer as `no review` reached from the opposite direction. |
| `judicial_independence` | `[INDEPENDENCE_MIN, INDEPENDENCE_MAX]`, clamped on the accumulated value in `Legislature.apply_effects()`. One writer. A three-Act ladder against a nine-point per-Act bound cannot reach the floor from any authored start, which `tests/test_balance.gd` asserts as slack. |
| `unrest_load()` | A bounded multiple of a bounded deviation, combined at a site `Unrest.unrest_target()` re-clamps to `[UNREST_MIN, UNREST_MAX]`. |

---

Related: [[index]] · [[upper-house-model]] · [[legislature-model]] · [[society-model]] ·
[[unrest-model]] · [[media-model]] · [[amendment-model]] · [[data-sources]]
