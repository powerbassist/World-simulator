---
title: Electoral Systems
tags:
  - decision
  - elections
  - data
---

# Electoral Systems

The ten nations do not share one election. They share the game the player plays,
and nothing else about how a nation elects its government is invented — this
document is where every date, seat count and method came from, and what each
real system's reduction to something this MVP can actually compute does and does
not model. The vote-share formula those seats are allocated against is
[[election-model]].

## Why this is data, not one hardcoded rule

[[ROADMAP|S6]]'s original scope line — "seat allocation and the result screen
are bookkeeping" — assumed one term length and one allocation rule for every
nation. Given the instruction to match each nation's real system and add
European Parliament elections, that stopped being true partway through planning:
ten real systems is a schema decision of the same class [[ROADMAP|S1]] made for
the nation file itself, because every later session that touches the assembly —
[[ROADMAP|S7]] laws, [[v1|V1.1]] coalitions, [[v1|V1.2]] political systems —
reads whatever shape gets committed here. That is recorded on the roadmap
itself, not just in this file.

[[engine-decision|Rule 1]] still applies: no `if nation_id == "FRA"` anywhere.
Each nation's `government.election` block names a **method** —
`src/sim/electoral_systems.gd` dispatches on that string, never on which nation
is asking.

## The schedule

`government.election` in each `data/nations/*.json`, alongside the existing
`term_years` and `assembly_seats`. Same class as `fiscal` — **authored, but
real** — so `tools/import_data.py` never reads or writes it, and it does not
refresh on re-import.

| Nation | Chamber | Seats | Term | System | Next election | Source |
|---|---|---|---|---|---|---|
| FRA | Assemblée nationale | 577 | 5 | two-round | 2029-06 | By law no later than June 2029 ([Wikipedia, Next French legislative election](https://en.wikipedia.org/wiki/Next_French_legislative_election)) |
| DEU | Bundestag | 630 | 4 | pr_national (MMP reduced) | 2029-02 | By law no later than 25 March 2029; likeliest window late Jan–Mar ([Wikipedia, Next German federal election](https://en.wikipedia.org/wiki/Next_German_federal_election)) |
| ITA | Camera dei Deputati | 400 | 5 | parallel | 2027-12 | By law no later than 22 December 2027 ([Wikipedia, Next Italian general election](https://en.wikipedia.org/wiki/Next_Italian_general_election)) |
| ESP | Congreso de los Diputados | 350 | 4 | pr_dhondt | 2027-07 | Term runs to 23 July 2027; latest possible vote 22 August 2027 ([Wikipedia/healthplanspain.com, Next Spanish general election](https://en.wikipedia.org/wiki/Opinion_polling_for_the_next_Spanish_general_election)) |
| BEL | Chamber of Representatives | 150 | 5 | pr_dhondt | 2029-06 | Federal, regional and EP elections are held together every 5 years in June — 2024's were 9 June, alongside the EP vote ([Wikipedia, 2024 Belgian federal election](https://en.wikipedia.org/wiki/2024_Belgian_federal_election)) |
| NLD | Tweede Kamer | 150 | 4 | pr_national | 2030-05 | The 29 October 2025 election is already in the past at game start (January 2026); next moved to May 2030 to avoid clashing with March 2030 municipal elections ([Wikipedia, Next Dutch general election](https://en.wikipedia.org/wiki/Next_Dutch_general_election)) |
| LUX | Chambre des Députés | 60 | 5 | pr_national (Hagenbach-Bischoff reduced) | 2028-10 | By law no later than 8 October 2028 ([Wikipedia, Next Luxembourg general election](https://en.wikipedia.org/wiki/Next_Luxembourg_general_election)) |
| CHE | Nationalrat | 200 | 4 | pr_national | 2027-10 | Scheduled for 24 October 2027 ([Wikipedia, 2027 Swiss federal election](https://en.wikipedia.org/wiki/2027_Swiss_federal_election)) |
| GBR | House of Commons | 650 | 5 | fptp | 2029-05 | By law no later than 15 August 2029; expected polling day 1 May 2029 ([Wikipedia, Next United Kingdom general election](https://en.wikipedia.org/wiki/Next_United_Kingdom_general_election)) |
| AUT | Nationalrat | 183 | 5 | pr_national | 2029-09 | By law no later than September 2029, no fixed date announced ([Wikipedia, Next Austrian legislative election](https://en.wikipedia.org/wiki/Next_Austrian_legislative_election)) |

Every date was checked against a source at build time, not carried over from
training data — several of these turn on an election held close to the
knowledge cutoff, and a snap election moves a date without warning. If a real
election is called early after this session lands, the fix is a one-line data
edit to the affected nation's `government.election.next`, not a code change.

**The player inherits a term already in progress.** Game start is January 2026;
France's next ordinary election is June 2029, so the first playable term is 41
months, not a full 60. That is realistic — the player did not just win an
election, they took over an existing government — and it is also what gets the
[[ROADMAP|S6]] checkpoint playtest to a result screen in under four minutes of
wall clock at speed 3, rather than five simulated years.

**A double election happens on schedule, not by design.** France and Belgium
both have national elections in June 2029, the same month as the next European
Parliament election — exactly as happened in June 2024, and exactly why
`Elections.tick_month()` returns an Array rather than a single result.

## Electoral systems as methods, not branches

| Method | Used by | What it computes |
|---|---|---|
| `pr_dhondt` | ESP, BEL | D'Hondt highest-averages over the national vote share, after `threshold_pct`. |
| `pr_national` | DEU, NLD, LUX, CHE, AUT | Largest-remainder (Hare quota) over the national vote share, after `threshold_pct`. |
| `fptp` | GBR | Vote share raised to a power (`FPTP_EXPONENT = 3.0`) and renormalised — the classic empirical cube-law relationship between vote share and seat share under first-past-the-post. |
| `two_round` | FRA | The same power-law reduction, at a softer exponent (`TWO_ROUND_EXPONENT = 2.0`) — second-round alliances damp the amplification a plurality system produces on its own. |
| `parallel` | ITA | A weighted blend of `pr_national` and `fptp`, at `PARALLEL_PR_WEIGHT = 0.62` — the share of seats the Rosatellum allocates by proportional list, the rest by single-member contest. |

All five live in `src/sim/electoral_systems.gd`, one pure function per method
plus a dispatch on the `system` string.

### The honest caveat

The MVP has **no constituency geography** — the map is [[ROADMAP|S8]], and it
holds national borders only. `fptp` and `two_round` cannot be simulated seat by
seat, because there are no seats, only a national vote share. Every single-member
system in this table is therefore a **national-level reduction**:

- **GBR (FPTP)** and **FRA (two-round)** use a power-law amplification of the
  national vote share. This is the standard textbook approximation for how FPTP
  behaves in aggregate — it correctly amplifies a plurality into a
  disproportionate seat majority — and it is honest about what it throws away:
  no constituency can ever produce a result the national swing does not predict,
  so a regionally concentrated party (a nationalist or regionalist bloc with a
  geographic base, in reality) is under-rewarded relative to a party with the
  same national vote share spread evenly. `data/parties/GBR.json`'s
  `home_nations_bloc` is the party most affected by this; there is no fix short
  of constituency geography, and none is attempted here.
- **ITA (parallel)** inherits the same caveat for its majoritarian third, on top
  of correctly modelling the proportional two-thirds.
- **DEU (MMP)** reduces to plain national PR. Mixed-member proportional *is*
  proportional in aggregate by design — that is the entire point of the German
  system — so the reduction is honest rather than approximate: what it loses is
  overhang and levelling seats, a mechanism that exists to correct small
  district-level deviations from the national proportional result the model
  already computes directly. Nothing the MVP reads depends on that mechanism.
- **LUX (Hagenbach-Bischoff)** reduces to largest-remainder PR. The two methods
  produce near-identical results at Luxembourg's scale (60 seats across four
  multi-member constituencies); the divisor-method/quota-method distinction that
  separates them is not visible at this level of detail.
- **ESP**'s real 3% threshold applies per-constituency, not nationally;
  approximated here as a national 3% floor. At Spain's actual constituency sizes
  the national approximation rarely changes an outcome a per-constituency
  threshold would not, since most Spanish constituencies elect too few seats for
  a party above 3% nationally to fail a local threshold in enough districts to
  matter.

One constant per method, named and justified in [[election-model]]'s constants
table, replaceable the day constituency geography exists without touching
anything that calls `electoral_systems.gd`.

## The nine non-resolving nations

All ten nations carry this real, validated schedule. Only the player's resolves
an election — [[election-model]]'s gating section explains why: there is no
opinion model computed for the other nine to resolve a vote share from, the same
`has_budget` gate [[opinion-model|opinion]] already uses. The schedule exists now
because it is real and cheap to author; resolving it is [[v1|V1.2]]'s job, the
same session that gives a second nation a budget and blocs.

## European Parliament elections

`data/eu_parliament.json`: which of the ten are EU members, how many MEPs each
elects, and the shared election date. GBR left the EU in 2020; CHE was never a
member. Both are simply **absent** from the `members` table — there is no
`eu_member` boolean the code branches on internally; `EU.is_member(id)` is just
"does this id appear in the table", the same "field exists, tick does nothing"
shape `has_budget` uses elsewhere.

| Member | EP seats | Member | EP seats |
|---|---|---|---|
| DEU | 96 | BEL | 22 |
| FRA | 81 | AUT | 20 |
| ITA | 76 | LUX | 6 |
| ESP | 61 | | |
| NLD | 31 | | |

2024–2029 term, 720 seats total across all EU member states, ten of which are in
this game
([europarl.europa.eu](https://www.europarl.europa.eu/topics/en/article/20180126STO94114/2024-2029-european-parliament-how-many-meps-per-country),
[results.elections.europa.eu](https://results.elections.europa.eu/en/european-results/2024-2029/)).
Next election: **June 2029**, the fifth consecutive five-yearly EP election held
in that month.

EP elections resolve with the exact same `Elections.vote_share()` the national
one uses, allocated by `pr_national` onto the nation's EP delegation size instead
of its assembly. Deliberately **thin**: no EP-level politics, no European party
groups, no legislative effect on the nation's own assembly or budget.
[[scope|scope.md]] puts an EU-shaped diplomatic bloc in [[v1|V1.3]], and building
half of that here — a European Parliament with nothing it can do — would be worse
than not building it.

What the EP election *is* at MVP is the best thing the real schedule gave for
free: **a real, seat-counted, attributed electoral verdict that lands inside a
term without ending it.** Given how rare a national election is under some of
these terms — Austria and Luxembourg both run five years — the EP vote is, for a
member nation, the only mid-term feedback the player gets that isn't a poll. It
costs one data file and zero new mechanics, because it reuses every piece of
[[election-model]] the national election already needed.

---

Related: [[index]] · [[election-model]] · [[data-architecture]] ·
[[opinion-model]] · [[ROADMAP]]
