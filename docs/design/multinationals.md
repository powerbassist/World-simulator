---
title: Multinationals and foreign ownership, the spec
tags:
  - design
  - v5.4
  - bands
---

# Multinationals and foreign ownership

**Status: proposed (2026-11-02), docs only.** Nothing here is built. The author picked the subject on 2026-11-02 ("Multinationales et propriété étrangère"). The bands in section 7 are declared before any build; every constant, data row, probe flag or test named below is a proposal the parent routes to its owner (section 8). The author's calls are in section 9, in French, the recommendation first.

Every point is labelled **MEASURED** (read in the source, the data or a fetched source), **INFERRED** (reasoned from what was measured) or **OPINION** (a design proposal). Line numbers are on `main` at `f3af7cc0`.

**Tier.** [[v5]]'s V5.4 ("the real network and the city at depth") does not list this subject in its signed sub-blocks a to e. This spec proposes it as **V5.4 f**, after d (the negotiation machine) and e (the city at depth, whose icons are "tintable by sector, nation and state"), because both are things it reuses. That placement is call 4; this file does not edit the tier.

## 0. What the author asked for

Today every firm belongs to one nation, and the only link across a border is a foreign takeover bid. The author wants three things the game does not have:

1. firms present in several nations, with plants, jobs and a headquarters;
2. foreign-controlled firms at the start, from a real source (Eurostat's foreign affiliates statistics, the OECD's AMNE database);
3. closures and takeovers that become diplomatic matters, "a German group closing a plant in France".

The 4 to 5 majors per sector that Content is authoring for France, Germany, Britain and Poland in V5.3 (the board's "More majors" card) are the ground this builds on: the foreign-controlled firms at the start are some of those new majors, marked, so Content authors each firm once.

## 1. What exists (MEASURED)

**The register.** `data/companies/<NATION>.json` holds 464 majors and 3,396 body firms over 41 nations. A row has eight fields, `id name sector share headcount city tier chief_id`; none says who owns it. `share` is of the firm's sector **in its own nation** ([[companies-model]] 2). France, Germany and Britain have 6 majors each (two per sector), Poland 8. There are three sectors: agriculture, industry, services.

**The bid machine.** `Industry._bids()` (`src/sim/industry.gd:456-509`) runs every month for every nation's majors:
- each major draws a bid with a hazard of `BID_HAZARD_YEARLY` 0.01 a year (`industry_constants.gd:91`), ×5 when courted (`:103`);
- the bidder is a larger same-sector major of another nation, and **never the player's nation** (`industry.gd:488` skips `state.player_nation_id`). So the player's majors never buy abroad;
- the price is the firm's value, `output × PRICE_TO_OUTPUT` (`companies.gd:227`), and the window is 3 months (`industry_constants.gd:96`). An unanswered bid lapses (`industry.gd:463-468`).

Only the player answers a bid. A grep finds no caller of `allow_bid` outside `companies.gd` and the process gate (`processes.gd:49`), so a bid on an AI nation's firm always lapses: no AI nation ever sells or buys.

**What allowing a bid does.** `allow_bid` (`companies.gd:876-884`) writes `owner` on the firm's register entry as a **nation code** (the bidder string is `NATION|firm_id`, and only the nation part is kept), pulses relations with the bidder nation by `BID_ALLOW_RELATIONS_PULSE` +0.5, and moves the action's `bloc_offset` (business +0.12, urban +0.04, workers −0.08, `data/company-actions/takeover.json:26-30`). Blocking pulses −0.5 (`companies_constants.gd:123`). The content's own note says it plainly: foreign ownership "is recorded, not modelled further, until a block owns it" (`takeover.json:2`).

**Who reads `owner`.** Only the process register, to void a process when the owner changes (`processes.gd:173`, `:287`). No figure reads it: not the jobs (`Companies.headcount`, `:263`), not the jobs offset into unemployment (`firm_jobs_offset_pct`, `:581`), not the value, the dividend, migration or closures. No panel prints it (a grep of `src/ui/` finds no read). After an allowed takeover the firm looks and behaves exactly as before.

**The relations pulse is invisible.** Relations run on 0 to 100 (`diplomacy_constants.gd:21-22`). A state visit moves a pair by +5 and a condemnation by −8, and one act's mark has a half-life of 35 months ([[diplomacy-model]], "What survives of one action"). A pulse of 0.5 is a tenth of the cheapest diplomatic verb. It also bypasses the third-party rule: `_pulse_relations` calls `Relations.adjust` directly (`companies.gd:1072-1076`), where a diplomatic action goes through [[foreign-policy-model]]'s stake-scaled reactions.

**Closures.** `src/sim/closures.gd` (V5.3 a, [[companies-model]] 41) announces at most one closure a month, for the **player's nation only** (`closures.gd:55`), when a major's output falls by more than `fall` over a window (`data/industry/closures.json`). The answers are let it close (the default), find a buyer, or rescue through the firm's subsidy verbs. About one closure a year per playable nation ([[companies-model]] 41). Nothing in a closure knows who owns the firm.

**Processes.** A nationalisation, a stake, a break-up or a privatisation is a process with stages, a price fixed at the start and a bloc move split in time ([[companies-model]] 40). None reads the owner, so nationalising a foreign-owned firm costs exactly what a domestic one costs and moves no relations.

**What relations move.** Relations reach the economy through one channel, the mix of the directed trade weight ([[diplomacy-model]], "Deliberately absent"), and they are read by every agreement gate and by the AI's agenda ([[foreign-policy-model]]). So any relations move this spec adds reaches GDP a little, through trade, and reaches diplomacy directly.

**The real figures (fetched 2026-11-02).** Eurostat's inward FATS, dataset `fats_activ`, reference year 2022 ([Eurostat news, 2024-11-21](https://ec.europa.eu/eurostat/en/web/products-eurostat-news/w/ddn-20241121-2)):
- in the EU, foreign-controlled enterprises are 1 % of market-producer enterprises but give **15 % of jobs** and **24 % of value added** in the business economy;
- of those enterprises, 63 % are controlled from another EU country and **37 % from outside the EU**;
- jobs share highest in Luxembourg (44 %), Poland (34 %) and Slovakia (28 %); value added lowest in France (16 %), Germany (17 %) and Italy (17 %).

France's, Germany's and Britain's **jobs** shares were not in the fetched text, and Britain is no longer in Eurostat's tables (the ONS publishes its own foreign-ownership figures). Content reads them from `fats_activ` and the ONS; this spec does not fill them from memory (section 10).

## 2. The three options

All three keep the house rule: content in data, no `if nation_id`, one system per job.

### Option 1 (recommended): a foreign plant is a row in the host nation's file

A firm that a foreign group controls is an ordinary row in the **host's** `data/companies/<HOST>.json`, with two new optional fields (OPINION):

```
owner      a nation id of the roster, or "world" (an owner outside the roster)
parent_id  the major in data/companies/<owner>.json that controls it (optional)
```

- `share` stays "of its sector in its nation", so every existing read (`headcount_in_city`, the jobs offset, migration's jobs map, closures, the processes gate, the investment pool) reaches a foreign plant with **no new read**. A German group's plant in Lille is a French firm with a German owner, which is also how Eurostat counts it.
- A group is the parent major plus every row whose `parent_id` names it. The headquarters is the parent's city. "Present in several nations" is the group, read by an index the loader builds once.
- At runtime the owner can change (an allowed bid). The register's existing `owner` key overrides the authored field, the same pattern as `city` (authored in data, a relocation's override in the register, [[companies-model]] 33). An allowed bid also writes a new `parent` key with the bidding firm.
- `"world"` stands for the United States, Japan, China and every other owner outside the 41 nations, the 37 % above. Such an owner counts in the foreign share and has no relations pair: the rule is "no pair when the owner is not a nation in play", read as `state.nations.has(owner)`, never a literal compare.
- **The loader refuses** an `owner` that is neither a roster id nor `"world"`, an `owner` equal to the row's own nation, and a `parent_id` that does not resolve to a major of the owner's file in the same sector.

**Cost:** two fields, one loader index, the rules of section 3, and Content's marking. **What it misses:** a group is not one balance sheet; a plant's output is its own host sector's, not the group's.

### Option 2: plants on the parent

The parent major carries `plants: [{nation, city, share, headcount}]`, one firm in several nations.

- Truer to how a group reads on paper (one firm, one name, one P&L).
- But `share` is per nation and per sector, so each plant needs its own share in another nation's sector, and every leaf that walks `firms_of(loader, nation)` (the jobs offset, `headcount_in_city`, migration, closures, the investment pool) must also walk every other nation's plants into this one. That is a cross-nation read inside per-nation work, in a tick that runs Economy per nation and Diplomacy per actor (`world_month.gd:39-43`). INFERRED: it touches most of `companies.gd`, which sits at its size ratchet ([[companies-model]] 40).

### Option 3: an owner label only

Add `owner` to existing rows, no `parent_id`, no group. A closure of a foreign-owned firm becomes a diplomatic matter (section 3.1); nothing else.

- Cheapest: one field and one rule, and closures already fire.
- It drops the author's first point (a group present in several nations) and the parent link of 3.2.

## 3. Option 1's rules

Each is a general rule over the `owner` and `parent_id` fields and the numbers in a new `data/industry/foreign_ownership.json`, never per firm or per nation (OPINION; every number is a first proposal Systems tunes against the bands).

### 3.1 A foreign group closing a plant

When `closures.gd` announces a closure on a firm whose owner is a roster nation other than the host, the answers gain one: **summon the owner's government** (the author's example, a German group closing a plant in France).

| Answer | What it costs | What it buys |
|---|---|---|
| Let it close (the default) | the closure's own `bloc_offset`, as today | nothing; relations do not move (call 2) |
| Find a buyer | as today | as today |
| Rescue | as today: a subsidy, now to a foreign-owned firm | as today |
| **Summon the owner's government** | relations with the owner nation fall by `protest_relations` (proposed 4 points) whatever the outcome, through the stake-scaled third-party rule like any diplomatic act | odds the group keeps the plant, shown as a range: `clamp(0.25 + 0.25 × (stake(owner→host) / even − 1), 0.10, 0.60)`, `stake` and `even` read from `foreign_policy.gd:154`, `:145`. Germany cares about France, so a German group listens more than a Swiss one |

A closure by a `"world"` owner offers no summon (there is no government in play to summon), which is also true to how a foreign closure from outside Europe plays.

The strip ([[v5.3-ab]] 2.1) shows the summon's three lines: money 0, "relations with Germany −4", the odds range and "the group may close anyway".

### 3.2 The group decides abroad

A foreign plant's closure trigger reads the worse of two falls: its own output's (today's rule) and its **parent's** (the parent's output is its share times its home sector's output, `companies.gd:216`). A group whose home market slumps closes the plant abroad first. And when a parent fails (`industry.gd:347`'s commit), each of its plants in the player's nation announces a closure the next month, bypassing the fall test. Closures runs after Industry in the month (`world_month.gd:100`), so the parent's flag is already written when it reads.

### 3.3 Expropriation is a diplomatic act

A nationalisation or a minority stake on a foreign-owned firm (the V5.3 a process, unchanged) moves relations with the owner nation at the transfer by `−clamp(expropriation_k × value_eur_bn, 3, 15)`, through the third-party rule. A break-up ruled against a foreign-owned firm moves them by half that. The strip names it ("relations with Germany −6 at the transfer"). A `"world"` owner moves nothing, and the strip says why.

The bid answers are re-sized on the same scale: blocking costs `−clamp(block_k × value, 2, 8)` and allowing gains half that, replacing the fixed ±0.5 (`companies_constants.gd:123-124`), and both go through the third-party rule.

### 3.4 The player's groups abroad (call 3)

The rows whose `parent_id` names one of the player's majors are **the player's groups abroad**, shown on the parent's card ("3 plants abroad, 18,000 jobs: Poland, Spain, Romania").

If the author takes call 3 (a), the player's majors become eligible bidders abroad: `industry.gd:488` stops skipping the player's nation as a **bidder**. A bid by one of the player's majors on an AI nation's firm is an arrival for the player: **back it** (the host's odds of accepting rise by `back_bonus`; if the host still refuses, relations fall by `back_refused_relations`) or **let the group try alone**. The host answers at the window's end through a gate on `would_accept_agreement`'s shape (`foreign_policy.gd:288`): stake and relations against a threshold. On a yes, the target's register entry takes `owner` = the player's nation and `parent` = the bidder. The firm pays, not the state: no debt moves.

**What owning abroad buys (OPINION, call 3):** the jobs a nation hosts from another raise its stake toward that nation, a third term in `stake_vector()`'s raw sum (`foreign_policy.gd:165-200`) beside trade dependence and history: `W_INV × (jobs in A owned from B) / (A's named payroll) / even`. Poland, which hosts German plants, cares more about Germany, accepts its agreements more readily and cools more when a third nation acts on it. This is the one rule that makes ownership move diplomacy without anyone pressing a button, and the one that moves numbers at month 0 (section 5).

## 4. What the player sees (OPINION, for Interface)

- **On the firm row:** the owner's flag and name after the firm's ("Kessler Lille, Kessler AG, Germany"), in `MAP_NEUTRAL` like every other nation's mark; the player's own colour is never used for another nation (AGENTS.md's two kinds of colour).
- **On a group's card:** its plants by nation, each with its jobs, and the headquarters city.
- **In the Industry tab's sector card:** one line, "foreign-controlled: 14 % of named jobs (Germany 6 %, outside Europe 5 %, ...)".
- **On the map at depth (V5.4 e):** a plant's glyph tinted by its owner nation, the e-block's "tintable by nation".
- **In the country box** (V5.1-d4's, a map click on another nation): "your groups there: N jobs; theirs here: M jobs", the two sides of the pair.

## 5. What moves which sim numbers (INFERRED)

| Change | Numbers it moves | When |
|---|---|---|
| The `owner` and `parent_id` fields alone | none: no read touches a figure (band M1) | never |
| New foreign plant rows beyond the majors card | jobs, shares, the investment pool and every machine draw, like any new firm | the majors card's re-baseline, not this block's |
| 3.1 summon | relations with the owner (and third parties by stake), so the trade weight's mix and so GDP slightly; jobs in the city when the plant is kept | on the player's answer |
| 3.2 parent link | more closures in the player's nation: jobs by city, unemployment through `firm_jobs_offset_pct`, closure bloc offsets | in idle runs, from the first parent slump; a re-baseline |
| 3.3 expropriation and bid re-size | relations, the trade mix, agreement gates | on the player's verb |
| 3.4 outward bids | the register's owner and parent on AI firms, relations on a refused backing | on the machine's draw, then the player's answer |
| 3.4 investment as stake | every stake vector, so every agreement gate, the AI's agenda and the third-party reactions, from month 0 | at month 0: the largest re-baseline of the block |

Each of these is a number the author accepts before its merge, per the V5.3 rule.

**The save.** No `SAVE_VERSION` bump (OPINION, AGENTS.md's rule). The fields are content. The register keys are on the firm's `ns.companies` entry, which the field table deep-copies: `owner` already exists, `parent` and a closure's `summoned` status are new, and absent each reads "the authored owner, no runtime parent, not summoned", the truth for every older save. Pinned by `tests/test_save_load.gd` beside the existing `owner` round trip (`test_save_load.gd:2654`).

## 6. Pre-mortem: the next gate says "I never saw a foreign firm do anything"

1. **The arrivals are too rare.** At 0.01 a year per major, a France of 12 to 15 majors draws a bid about once in seven years (INFERRED, not measured), and a foreign-owned closure is a fraction of one closure a year. Prevented by the parent link (3.2), the outward bids (3.4) and band M3, which sets a rate and is measured before the build.
2. **The relations moves are invisible again.** Prevented by M4's floor of 3 points, the size of a third of a condemnation.
3. **The summon always wins, or never.** Prevented by M5: no answer dominates across the states the probe stages.
4. **The foreign share is wrong against reality.** Prevented by M2, measured against `fats_activ` by a loader test.

## 7. Bands and done-when (declared before any build)

| Band | What holds | Measured by | A failure looks like |
|---|---|---|---|
| **M1, labels move nothing** | with the rules of section 3 off, the balance table is `cmp`-identical with and without every `owner` and `parent_id` field | `tools/balance_parallel.py`, the D10-style gate | any byte |
| **M2, the start matches the source** | in each playable nation, the share of named payroll (majors and body) under a foreign owner, `"world"` included, is within ±5 points of `fats_activ`'s jobs share for 2022 (Britain: the ONS figure); every row with an owner passes the loader's checks | a loader test over `data/companies/` | France at 2 % against a real figure in the teens |
| **M3, the player meets the subject** | over 120 months, both regimes, the four playable nations: 1 to 4 multinational arrivals a year on average (a bid on one of the player's firms, a foreign-owned closure, a parent-led closure, an outward bid), at most one a month from these sources, counted as source `foreign` | `tools/decision_surfaces_probe.gd --density` | 0.2 a year, the bid machine's silence today |
| **M4, a diplomatic matter is visible** | a summon moves the pair by 3 to 8 points; an expropriation by 3 to 15; a blocked bid by 2 to 8; a closure the player lets happen moves no pair (call 2 (a)) | `tests/` per rule; a companies probe flag | a move under 3 points |
| **M5, the summon is a choice** | the odds shown bracket the realised outcome in 100 % of probe runs; across the probe's staged states (high and low stake, a large and a small plant), each of the four closure answers is best on at least one of jobs kept, relations or EUR bn in at least one state | the closures probe, extended | "always summon" or "never summon" winning everywhere |
| **M6, the group decides abroad** | each parent failure with plants in the player's nation produces a closure announcement at each such plant within one month in 100 % of runs; a parent slump past `fall` does the same | a closures test | a German parent fails and its French plant runs on |
| **M7, investment as stake (call 3 (a))** | with every owner stripped the stake vectors are identical to the base; at month 0, POL's stake toward DEU rises (the term is live); no agreement gate among the four playable nations flips at month 0 without the flip being reported to the author | a foreign-policy test; the diplomacy probe | a silent flip |
| **M8, the save** | an older save loads, reads every owner from data, and round-trips the new keys | `tests/test_save_load.gd` | a lost runtime owner |
| **M9, the author's gate** | after 30 minutes the author has met at least one foreign group as a decision, and names it | the playtest receiver's report, verbatim | "I never saw it" |

## 8. The build split, by owner, in order

Gameplay writes only this spec. Every item is a proposal the parent routes.

1. **Content, first, with the majors card:** `owner` and `parent_id` on the new majors of the four playable nations and on their counterparts' files, sized to `fats_activ` (and the ONS for Britain), each source in `REUSE.toml`; owners drawn on generated body rows through `tools/firms_generate.py` (the body is generator-owned, [[companies-model]] 37); `data/industry/foreign_ownership.json`'s numbers, each with the reason it is that number.
2. **Systems:** the loader fields, checks and group index; the register's `owner` override and `parent` key; 3.1 to 3.3 in `closures.gd`, `processes.gd` and `companies.gd`'s bid answers; the density source `foreign`; M1 to M6 and M8. Then 3.4 if call 3 is (a), with M7 and the diplomacy re-run.
3. **Interface:** section 4, after the fields exist; `tools/screenshot.gd` staged states for a foreign-owned row, a group card and a summon.
4. **QA:** every band, the re-baselines read against the author's acceptance, the windowed screenshot pass.

## 9. Calls for the author (in simple French, the recommendation first)

1. **Comment représenter un groupe présent dans plusieurs pays ?** (a) *Recommandé :* une usine étrangère est une entreprise du pays où elle se trouve, avec deux champs en plus : son pays propriétaire et sa maison mère. Tout ce qui existe (emplois, chômage, fermetures) marche tout de suite. (b) Une seule entreprise avec une liste d'usines dans plusieurs pays : plus juste sur le papier, mais il faut réécrire presque tout le code des entreprises. (c) Juste une étiquette « propriétaire étranger », sans maison mère ni groupe.
2. **Quand un groupe étranger ferme une usine chez toi, est-ce une affaire diplomatique ?** (a) *Recommandé :* c'est toi qui choisis : tu peux convoquer le gouvernement du pays propriétaire. Ça abîme la relation (environ 4 points) et ça donne une chance que l'usine reste, plus grande si ce pays tient à toi. Si tu laisses fermer, la relation ne bouge pas. (b) Automatique : toute fermeture par un groupe étranger refroidit la relation, même si tu ne fais rien. (c) Pas de diplomatie, seulement l'étiquette.
3. **Tes propres groupes peuvent-ils racheter des entreprises à l'étranger ?** (a) *Recommandé :* oui. Le pays visé répond selon sa relation avec toi et l'importance que tu as pour lui, tu peux appuyer l'offre ou laisser faire, et les emplois que tes groupes créent chez un voisin le rendent plus attaché à toi (ça change la diplomatie dès le début de partie). (b) Non : tes usines à l'étranger existent au départ et s'affichent, mais tu n'en gagnes pas de nouvelles.
4. **Quand le construire ?** (a) *Recommandé :* en V5.4, après la négociation (d) et la ville en détail (e), parce qu'il réutilise les deux : les usines sur la carte, colorées par pays propriétaire. (b) Une petite partie tout de suite en V5.3, juste après les nouvelles grandes entreprises (les deux champs et la fermeture diplomatique), le reste en V5.4. (c) En V6, avec les accords sur les ressources.

## 10. What could not be verified

- **France's, Germany's and Britain's jobs shares** under foreign control: not in the fetched Eurostat text; Content reads `fats_activ` (and the ONS for Britain). M2's ±5 points is set before those figures are read, so it may need the parent's look once they are.
- **The OECD's terms.** `REUSE.toml` records that they could not be read on 2026-11-01 (HTTP 403). This spec recommends Eurostat as the primary source and the OECD's AMNE tables only as a cross-check until the terms are read.
- **The arrival rates** in section 6 are arithmetic on the constants, not a probe run. M3's baseline is a `--density` run on main with the source added, before the rules.
- **The proposed numbers** (the summon's 4 points and odds, `expropriation_k`, `block_k`, `W_INV`) are first proposals; each band says what must hold.
- **No GLM red-team** was run on this draft; the review is `code-review` and QA.
