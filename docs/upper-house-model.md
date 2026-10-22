---
title: Upper House Model
tags:
  - decision
  - legislature
  - simulation
---

# Upper House Model

The second chamber, as built in V1.1e — the last session of the V1 tier.
Where its composition comes from, what its refusal does, and the two constants that
survived measurement.

Same standard as [[economy-model]], [[legislature-model]] and [[government-model]]: a
**game model**, judged on whether the player's decisions produce a legible, attributable
outcome — not on whether it would survive a comparative-politics seminar. Where realism
and legibility conflict, legibility wins, and the trade is noted.

## 1. The citations were already in the data, and one of them declared itself a stopgap

[[referendum-model|V1.7c]]'s headline was that every referendum citation was already
sitting in the nation files' own `government.amendment._note`, authored at V1.2c for a
mechanic that did not exist. **The same is true here, and one of them says so out loud:**

| File | What it already said |
|---|---|
| `FRA.json` `amendment._note` | *"Art. 89: a revision bill must pass **both chambers in identical terms**…"* |
| `DEU.json` `amendment._note` | *"Art. 79(2) GG… a 2/3 majority of BOTH the Bundestag's statutory membership and **the Bundesrat's votes. Only the Bundestag half is modelled — there is no Bundesrat in this game.**"* |
| `FRA.json` `dissolution._note` | *"…after consulting the PM and the presidents of **both chambers**"* |
| `ITA.json` | *"dissolving **either chamber**"*, *"absolute majority **in each chamber**"* |
| `src/sim/referendum.gd`'s header | Quotes Art. 89's *"must pass both chambers"* while modelling only the stage after it |

So V1.1e discharges a **declared stopgap in the data** rather than in the code, which is
new on this project's record. Germany's note is rewritten to say what was built.

## 2. Few are elected by the national electorate, and the model elects none

The design that suggests itself — run `Elections.vote_share()` again with a different
weighting — is wrong for eight of V1.1e's ten, and the reason is a fact rather than a
preference:

| Chamber | How it is returned |
|---|---|
| Sénat (FRA) | ~162 000 grands électeurs, overwhelmingly councillors of small communes |
| Bundesrat (DEU) | Delegated by the Land governments; Bremen casts 3 votes for 0.7m people, NRW 6 for 18m |
| House of Lords (GBR) | Appointed and hereditary, with no fixed statutory size |
| Eerste Kamer (NLD) | Elected by the provincial councils |
| Senado (ESP) | Four per province regardless of population, plus 57 named by the communities |
| Senaat (BEL) | 50 of 60 delegated by the community and regional parliaments |
| Bundesrat (AUT) | Delegated by the Land diets, with a floor of three |
| Ständerat (CHE) | Two per canton; Appenzell Innerrhoden's 16 000 people return one seat where Zürich's 1.5m return two |
| Senato (ITA) | **Directly elected, same electorate, same day** — which is exactly why Italian bicameralism is called *perfect* and reproduces the Camera's majority |
| — (LUX) | **There is no second chamber.** The Chambre des Députés is unicameral |

The 41-nation roster added six more, and two of them are the Italian case rather than the
French one:

| Chamber | How it is returned |
|---|---|
| Senat (POL) | **Directly elected on the same polling day**, but first-past-the-post in 100 single-member districts where the Sejm is proportional |
| Senatul (ROU) | **The same closed-list vote** and the same 5 % threshold as the Deputies |
| Senate (CZE) | Directly elected in two-round constituency contests, one third every two years |
| Seanad Éireann (IRL) | Vocational panels of councillors and MPs, university graduates, eleven nominated |
| House of Peoples (BIH) | Delegated by the entity parliaments, five per constituent people |
| Council of the Republic (BLR) | 56 chosen by the regional councils, 8 appointed by the President |

So a second chamber is the **lower chamber, lagged**, and `vote_share()` is never called
with a different weighting — for the same-day chambers too. Italy, Poland and Romania
return their whole upper house on the lower house's polling day; the model renews it by
`UPPER_RENEWAL` like every other, the legibility trade V1.1e made for Italy, now made for
three. Poland's is where the trade costs most: first-past-the-post can hand the Senat to
the side that lost the Sejm, as in 2019, and the lag reproduces a divergence only through
timing. Neither a same-day renewal nor an upper-house seat rule is built (§11).

## 3. An ideological tilt was designed, measured and deleted — twice

**The first version** gave each nation an `electorate` key naming the slice of the country
that returns its second chamber (`rural` for France's grands électeurs) and re-weighted
the lower chamber by each party's affinity for that bloc's ideal point. Swept, it put
`front_souverainiste` at **122 of France's 348 senators at a tilt of 1.0 and 267 at 4.0** —
the nationalist right running the Sénat. That is the opposite of the real chamber, where
the RN has almost no senators *precisely because* the indirect election filters it out.

The cause is structural rather than a bad choice of bloc: **every socially-traditional
ideal point in `election_constants.BLOC_IDEAL` sits nearest `nationalist_right`**, so any
anchor meaning "small-town and conservative" hands the chamber to it.

**The second version was worse in a more interesting way.** Anchoring on the lower
chamber's own seat-weighted centre — the establishment reading, and a derivation with no
authored field at all — made the second chamber refuse **zero** of the bills the first one
carried at every tilt from 1.0 to 6.0, and *carry* up to nine it had rejected.
**Moderation concentrates a chamber where the laws are, so it is a more permissive body
and not a check.**

`UPPER_TILT` and `government.upper.electorate` were both **deleted** — a constant and a
content field cut by their own measurement, [[calendar-model|U6a]]'s day budget and
[[foreign-policy-model|V1.3e]]'s `AGREEMENT_ACCEPT_MIN` a third time.

## 4. What makes it a check was already there, and it costs nothing

`src/sim/legislature.gd` resolves the second chamber's division on `spatial_support()`
where the Assembly votes on `support()`, and **the difference between those two is the
coalition bonus**. A government bill carries the Assembly because the coalition is whipped;
the Sénat has no government in it, so the whip is weaker there.

> **THE SECOND CHAMBER IS THE ASSEMBLY YOU USED TO HAVE, VOTING WITHOUT YOUR WHIP.**
> Unwhipped from the start, and out of date from the first election onward.

Measured at new game, with the composition **identical** to the Assembly's, the Sénat
refuses **5 of the 13 bills the Assembly carries**. `emissions_standards` is the sharpest:
the Assembly carries it **311–266** and the Sénat reads it **94–254**.

## 5. `UPPER_WHIP` — the probe's third correction, and a test caught it

The design was that the second chamber votes on `spatial_support()` **alone**. Measured,
that chamber refuses **seven of seven** authored constitutional amendments — France reads
`single_term_reform` **63–156** where the Assembly carries it 308–210 — and since France's
amendment row is `absolute` under Art. 89, **every amendment in the game becomes
unpassable and [[referendum-model|V1.7c]]'s whole verb dies one session after it shipped.**

That is a regression, not a mechanic, and `tests/test_save_load.gd` is what found it: its
referendum round trip reported *"no referendum was called, so the round trip measures
nothing"*.

What was wrong is the claim rather than the number. **No whip at all is not "unwhipped",
it is "no government exists"**: senators belong to the same parties as deputies, and a
government's own parties vote for its bills in both chambers. What the second chamber
lacks is the **threat** — it cannot bring the government down. The real Sénat has passed
twenty-four revisions since 1958.

| Band | Fails |
|---|---|
| (i) refuses ≥1 ordinary bill the Assembly carries | from 0.70 up |
| (ii) ≥1 authored amendment survives BOTH chambers | below 0.15 |
| (iii) a majority of the carried bills survive | never binds (worst is 5 of 13) |

Passing **[0.15, 0.65]**, both edges the model's and both interior to the swept range, so
the midpoint selects — [[unrest-model|V1.5c]]'s rule. **`UPPER_WHIP = 0.40`**: the Sénat
refuses 3 of the 13 ordinary bills the Assembly carries, and 2 of the 7 authored
amendments survive both chambers. France can still amend its constitution and still has to
fight for it, which is the shape Art. 89 describes.

## 6. The lag, and a band that was wrong twice

`Chambers.renew()` is a first-order step on the chamber's **share** at each legislative
election — [[defence-model|`capability_step()`]]'s shape a sixth time. On the seats it
would be a rounding rule pretending to be a model.

| Band | Fails |
|---|---|
| (i) the lag SURVIVES a career: after the two legislative elections a French president lives through, the chambers still differ by more than one seat of the smallest chamber on the roster (1/46 = 0.0217) | from 0.65 up |
| (ii) a career can MOVE it: the lag decays geometrically, and the elections needed to reach that floor must be at most the **three** a fourteen-year run holds | below 0.45, at 3.26 elections |

Passing **[0.45, 0.60]**. **`UPPER_RENEWAL = 0.50`**, which is not a tuning but the real
arrangement — half of France's Sénat is renewed every three years on a six-year term — and
it catches up in **2.08** elections, interior on both sides.

**Band (ii) was wrong twice, and the second time is the instructive one.** The first
version only asked that the distance *fall*, which every rate above zero satisfies, so the
passing set ran to the bottom of the grid and [[demography-model|V1.5b]]'s diagnostic fired:
a value at an endpoint of the swept range is a suspect rather than a result. The second
asked it to *halve* across two elections — a ratio nobody measured — and it cut France's
real 50 % by a hair, 0.532 against a threshold of 0.500. **An invented threshold that lands
within 6 % of the real figure is not a check, it is a coin toss with a rationale.** The
third is anchored on the harness's own horizon.

## 7. Two rows, because the distinction is between CLASSES of bill

`government.upper` carries `ordinary` and `amendment`, each one of
`chambers_constants.KNOWN_VERDICTS` — the **eighth** instance of the
dispatch-on-a-data-string pattern `formation_method`, `censure_rule`, `dissolution_rule`,
`lose_condition`, `head_of_state_kind`, `amendment_rule` and `referendum_mode` already use.

| Nation | ordinary | amendment | Basis |
|---|---|---|---|
| FRA | suspensive | **absolute** | Art. 45 gives the Assembly the last word; Art. 89 requires both chambers in identical terms |
| DEU | suspensive | **absolute** | Art. 77 Einspruchsgesetze; Art. 79(2) needs 2/3 of the Bundesrat |
| ESP | suspensive | absolute | Art. 90 override; Art. 167 needs 3/5 of each chamber |
| AUT | suspensive | suspensive | Art. 42 Beharrungsbeschluss. Art. 44(2)'s Land-competence case is a **recorded reduction** — this model has no Land competence to test |
| GBR | suspensive | suspensive | Parliament Acts 1911/1949. Both rows suspensive because parliamentary sovereignty recognises no entrenched class for the second to be absolute about |
| BEL | **none** | absolute | The 2014 reform removed the Senate from the ordinary procedure entirely; Art. 195 keeps full competence for revision |
| ITA | absolute | absolute | Art. 70, perfect bicameralism |
| NLD | absolute | absolute | Arts. 55 and 85 — accept or reject in full, no override |
| CHE | absolute | absolute | Art. 148, the chambers are equal in every respect |
| LUX | *(block absent)* | | Unicameral |

A single-valued enum could not say that without values meaning "the first thing here and
the second thing there", which is two facts wearing one name. **Belgium is the reason the
list has three values and not two**: it is the one nation whose second chamber does not see
an ordinary bill at all.

## 8. The hold is pure time, and time turned out not to be a cost

[[calendar-model|U6a]]'s finding is that every observable in this project is
piecewise-constant across a month, so a deferral that buys nothing is the
strictly-dominated shape this project has killed ten times. Table U3 swept the hold against
the widest per-bloc approval spread between a bill in force from month one and the same
bill arriving N months later:

| hold | worst bloc | headline |
|---|---|---|
| 1 | 0.0280 | 0.0084 |
| 6 | 0.3789 | 0.0757 |
| 12 | 2.3891 | 0.2819 |
| **15** | **5.5784** | 0.5234 |
| 18 | 7.3784 | 0.6424 |

All under the ±3.0 poll floor until **15**, which is one month short of the whole first
playable term. **A hold that only registers when it consumes the term is not a delay, it is
a block with a countdown on it.** The escalation this file declared in advance therefore
fired, and it was honoured by the response the plan named rather than by lengthening the
constant: **the release carries a price.**

`UPPER_HOLD_MONTHS = 12` is then **set by argument** and says so —
[[unrest-model|`UNREST_COOLDOWN_MONTHS`]]'s treatment. One year is the Parliament Acts
figure, the longest suspensive veto on the roster and the only one a statute states rather
than practice settling, and it satisfies the one band that is not about legibility: a bill
held on day one arrives inside the 16-month first term.

## 9. `UPPER_OVERRIDE_OFFSET` — and the career bound is what chose it

Charged on the **release** and not on the refusal, because that is when the government has
actually insisted. Routed through `Government.penalise_blocs()`, which is Article 49.3's own
accumulator and the one a fallen government, a reshuffle, a resignation and a dissolution
all already use — so this session adds a price and **no channel**.

[[events-model|V1.8]]'s E1b in a new place: a per-decision band passed while a career of
the same decision saturated the clamp. Table U0's played run releases **thirteen** held
bills over fourteen years, and the first value of 0.15 stacked those to **1.95** against a
`BLOC_OFFSET_MAX` of 1.00 — the run's worst bloc reached the clamp exactly.

| offset | one costs (headline pts) | career stack |
|---|---|---|
| 0.020 | 0.7920 | 0.2600 |
| **0.040** | **1.5840** | **0.5200** |
| **0.060** | **2.3759** | **0.7800** |
| 0.080 | 3.1679 | 1.0400 |

Band (i) — at least one point of approval, [[campaign-model|V1.7a]]'s ruler — cuts below
0.04; band (ii) — a career must leave the clamp slack — cuts above 0.06. Two model edges,
so the midpoint selects. **`UPPER_OVERRIDE_OFFSET = 0.05`**.

## 10. Article 49.3 is the way past the second chamber

A forced bill skips the chamber and does **not** skip the court, and both halves are real.
Art. 49.3 is the Government engaging its responsibility before the Assembly, and a
Government determined enough to do that has already given the Assembly the last word under
Art. 45 — so **49.3 IS the way past the Sénat, which is a property nobody authored**. It is
not a way past the Conseil constitutionnel: the 2023 pension reform reached it after a 49.3
and was partly struck, and that citation is in `FRA.json`'s own
`government.judicial._note`. Only `presidential_appointment` can force at all, and no nation
with an `absolute` ordinary row uses it, so nothing is bypassed here that could have killed
the bill outright.

## 11. What is deliberately not built

**A second chamber's own election.** Only two of V1.1e's ten are directly elected and one
of those returns the same result as the lower house; the 41-nation roster adds Poland's,
Romania's and the Czech Senate, and the same-day ones are lagged like the rest. §2.

**An ideological tilt.** Designed twice, measured twice, deleted twice. §3.

**A player verb to override.** The release is automatic and priced; a button offering
"override now or wait" is a second decision on one machine, and the probe found the wait is
not a real alternative. §8.

**Germany's real 2/3 Bundesrat bar on an amendment.** This model asks for a majority of
votes cast in the second chamber on every nation and every class of bill. A **recorded
reduction**, the shape [[electoral-systems]] uses per method, and bounded in practice
because Germany's Bundestag bar is already unreachable.

**A per-nation second-chamber term.** The renewal is one rate for every chamber, stepped at each
legislative election. France's six-year half-renewal is what `UPPER_RENEWAL` abstracts;
Britain's appointed peers have no term at all.

## 12. Why nothing diverges

| Quantity | Bound |
|---|---|
| `upper_share` | Renormalised to sum to exactly 1.0 on every renewal, so the chamber can neither grow nor shrink. Asserted in `tests/test_upper_house.gd`. |
| `Chambers.seats()` | `pr_national` over that share, which allocates exactly `upper_seats` by construction. |
| The three columns | Sum to the seats a party holds; a chamber with no seats returns an empty dictionary and `power_over()` returns `none`. |
| `held_bills` | Counts down monotonically and erases at zero. A bill cannot be held twice, because `available()` refuses a held bill. |
| `UPPER_OVERRIDE_OFFSET` | Accumulates through `Government.penalise_blocs()`, which clamps to `BLOC_OFFSET_MAX`. The worst reachable career is 0.65 of 1.00, measured and slack. |

---

Related: [[index]] · [[legislature-model]] · [[government-model]] · [[judiciary-model]] ·
[[amendment-model]] · [[referendum-model]] · [[electoral-systems]]
