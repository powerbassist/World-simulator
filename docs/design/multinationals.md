---
title: Multinationals and foreign ownership, the spec
tags:
  - design
  - v5.4
  - bands
---

# Multinationals and foreign ownership

**Status: the author's four calls ANSWERED (2026-11-02, section 13); docs only, nothing built.** The author picked the subject on 2026-11-02 ("Multinationales et propriété étrangère"). The first draft merged as #273 recommending a plant as a row of its host nation; the author chose the full model instead, **one firm with several plants** (call 1), and this revision rebuilds sections 2 to 12 on it. The bands in section 11 are declared before any build; every constant, data row, probe flag or test named below is a proposal the parent routes to its owner (section 12).

Every point is labelled **MEASURED** (read in the source, the data or a fetched source), **INFERRED** (reasoned from what was measured) or **OPINION** (a design proposal). Line numbers are on `main` at `ce1faddf`.

**Tier.** V5.4, sub-block **f**, after d (the negotiation machine) and e (the city at depth, whose icons are "tintable by sector, nation and state"), because both are things it reuses (call 4, answered). [[v5]]'s V5.4 section does not list f yet; recording it there is the parent's.

## 0. What the author asked for

Today every firm belongs to one nation, and the only link across a border is a foreign takeover bid. The author wants three things the game does not have:

1. firms present in several nations, with plants, jobs and a headquarters;
2. foreign-controlled firms at the start, from a real source (Eurostat's foreign affiliates statistics, the OECD's AMNE database);
3. closures and takeovers that become diplomatic matters, "a German group closing a plant in France".

The 4 to 5 majors per sector that Content is authoring for France, Germany, Britain and Poland in V5.3 (the board's "More majors" card) are the ground this builds on: a group's foreign plants are authored on those majors, once.

## 1. What exists (MEASURED)

**The register.** `data/companies/<NATION>.json` holds 464 majors and 3,396 body firms over 41 nations. A row has eight fields, `id name sector share headcount city tier chief_id`; none says who owns it or where else it produces. `share` is of the firm's sector **in its own nation** ([[companies-model]] 2). France, Germany and Britain have 6 majors each (two per sector), Poland 8. There are three sectors: agriculture, industry, services.

**The bid machine.** `Industry._bids()` (`src/sim/industry.gd:456-509`) runs every month for every nation's majors:
- each major draws a bid with a hazard of `BID_HAZARD_YEARLY` 0.01 a year (`industry_constants.gd:91`), ×5 when courted (`:103`);
- the bidder is a larger same-sector major of another nation, and **never the player's nation** (`industry.gd:488` skips `state.player_nation_id`). So the player's majors never buy abroad;
- the price is the firm's value, `output × PRICE_TO_OUTPUT` (`companies.gd:227`), and the window is 3 months (`industry_constants.gd:96`). An unanswered bid lapses (`industry.gd:463-468`).

Only the player answers a bid. A grep finds no caller of `allow_bid` outside `companies.gd` and the process gate (`processes.gd:49`), so a bid on an AI nation's firm always lapses: no AI nation ever sells or buys.

**What allowing a bid does.** `allow_bid` (`companies.gd:876-884`) writes `owner` on the firm's register entry as a **nation code** (the bidder string is `NATION|firm_id`, and only the nation part is kept), pulses relations with the bidder nation by `BID_ALLOW_RELATIONS_PULSE` +0.5, and moves the action's `bloc_offset` (business +0.12, urban +0.04, workers −0.08, `data/company-actions/takeover.json:26-30`). Blocking pulses −0.5 (`companies_constants.gd:123`). The content's own note says it plainly: foreign ownership "is recorded, not modelled further, until a block owns it" (`takeover.json:2`).

**Who reads `owner`.** Only the process register, to void a process when the owner changes (`processes.gd:173`, `:287`). No figure reads it: not the jobs (`Companies.headcount`, `:263`), not the jobs offset into unemployment (`firm_jobs_offset_pct`, `:581`), not the value, the dividend, migration or closures. No panel prints it. After an allowed takeover the firm looks and behaves exactly as before.

**The relations pulse is invisible.** Relations run on 0 to 100 (`diplomacy_constants.gd:21-22`). A state visit moves a pair by +5 and a condemnation by −8, and one act's mark has a half-life of 35 months ([[diplomacy-model]], "What survives of one action"). A pulse of 0.5 is a tenth of the cheapest diplomatic verb. It also bypasses the third-party rule: `_pulse_relations` calls `Relations.adjust` directly (`companies.gd:1072-1076`), where a diplomatic action goes through [[foreign-policy-model]]'s stake-scaled reactions.

**Closures.** `src/sim/closures.gd` (V5.3 a, [[companies-model]] 41) announces at most one closure a month, for the **player's nation only** (`closures.gd:55`), when a major's output falls by more than `fall` over a window (`data/industry/closures.json`). The answers are let it close (the default), find a buyer, or rescue through the firm's subsidy verbs. About one closure a year per playable nation ([[companies-model]] 41). Nothing in a closure knows who owns the firm.

**Processes.** A nationalisation, a stake, a break-up or a privatisation is a process with stages, a price fixed at the start and a bloc move split in time ([[companies-model]] 40). None reads the owner, so nationalising a foreign-owned firm costs exactly what a domestic one costs and moves no relations.

**What relations move.** Relations reach the economy through one channel, the mix of the directed trade weight ([[diplomacy-model]], "Deliberately absent"), and they are read by every agreement gate and by the AI's agenda ([[foreign-policy-model]]). So any relations move this spec adds reaches GDP a little, through trade, and reaches diplomacy directly.

**The real figures (fetched 2026-11-02).** Eurostat's inward FATS, dataset `fats_activ`, reference year 2022 ([Eurostat news, 2024-11-21](https://ec.europa.eu/eurostat/en/web/products-eurostat-news/w/ddn-20241121-2)):
- in the EU, foreign-controlled enterprises are 1 % of market-producer enterprises but give **15 % of jobs** and **24 % of value added** in the business economy;
- of those enterprises, 63 % are controlled from another EU country and **37 % from outside the EU**;
- jobs share highest in Luxembourg (44 %), Poland (34 %) and Slovakia (28 %); value added lowest in France (16 %), Germany (17 %) and Italy (17 %).

France's, Germany's and Britain's **jobs** shares were not in the fetched text, and Britain is no longer in Eurostat's tables (the ONS publishes its own foreign-ownership figures). Content reads them from `fats_activ` and the ONS; this spec does not fill them from memory (section 14).

### 1.1 Who reads a firm today (MEASURED, a script over `src/` at `ce1faddf`)

The firm is read in three ways, and each moves differently under the new model:

| Read | Sites in `src/` | Files |
|---|---:|---|
| the register, `ns.companies` | 70 | 17: `companies.gd` 24, `industry.gd` 12, `companies_loader.gd` 6, `closures.gd` 6, `event_hooks.gd` 4, `industry_news.gd` 3, two each in `regions_loader.gd`, `processes.gd`, `statute.gd`, `companies_panel.gd`, one each in `game_state.gd`, `bills.gd`, `companies_roster.gd`, `companies_walk.gd`, `company_verb.gd`, `industry_card.gd`, `territory_city.gd` |
| the authored fields, `<firm>.share` / `.headcount` / `.city` | 40 | 11: `companies.gd` 11, `company.gd` 9, `regions_loader.gd` 5, `industry.gd` 5, `city.gd` 3, `companies_loader.gd` 2, one each in `capital.gd`, `region.gd`, `companies_walk.gd`, `migration.gd`, `statute.gd` |
| the `Companies` API | below | |

| API call | Sites in `src/` (files) | Sites in `tools/` + `tests/` |
|---|---|---:|
| `firms_of` | 16 (7: `companies.gd`, `companies_roster.gd`, `bills.gd`, `migration.gd`, `process_drag.gd`, `processes.gd`, `company_verb.gd`) | 32 |
| `majors_of` | 11 (5: `companies.gd`, `industry.gd`, `closures.gd`, `bills.gd`, `company_verb.gd`) | 86 |
| `share_of_company` | 12 (4: `companies.gd`, `industry.gd`, `closures.gd`, `processes.gd`) | 42 |
| `headcount` | 12 (6: `companies.gd`, `closures.gd`, `migration.gd`, `company_verb.gd`, `industry_card.gd`, `territory_city.gd`) | 18 |
| `output_eur_bn` | 9 (5: `companies.gd`, `closures.gd`, `process_drag.gd`, `region_funds.gd`, `industry_card.gd`) | 30 |
| `subsidy_of` | 7 (3) | 7 |
| `value_eur_bn` | 6 (6: `companies.gd`, `closures.gd`, `industry.gd`, `process_asks.gd`, `processes.gd`, `industry_card.gd`) | 6 |
| `state_share_of` | 6 (3: `companies.gd`, `processes.gd`, `industry_card.gd`) | 34 |
| `live_city_of` | 5 (4: `companies.gd`, `closures.gd`, `industry.gd`, `territory_city.gd`) | 5 |
| `headcount_in_city` | 1 (`region_panel.gd`) | 10 |
| `firm_jobs_offset_pct`, `firm_impulse_pct` | 1 each (`companies.gd`, into Economy) | 1 each |

The register's live keys are pinned by `tests/test_save_load.gd:2652-2654`: `share subsidy state_share city failed rescue_months_left bid_bidder bid_price_eur_bn bid_months_left subsidy_shadow subsidy_lapsed_month owner courted board_chair`, plus V5.3 a's `closure` and `closure_watch` ([[companies-model]] 41). `companies.gd` is at its size ratchet: 423 code lines in `tools/size_baseline.json`, so it may shrink and never grow.

## 2. The options, and the author's pick

1. A foreign plant as a row of its host nation, with `owner` and `parent_id` (the first draft's recommendation): every reader reaches a plant with no new read, but a group is not one firm.
2. **One firm, several plants (the author's pick, "Une entreprise, plusieurs usines").** A firm has a home nation, a headquarters and a list of plants, each in a host nation with its own city, headcount and share of the host's sector. It is the truer model and the dearer one: the first draft warned it touches most of the firm code, and section 9 counts the cost.
3. An owner label only.

The rest of this spec is option 2. The way it is built (section 7) borrows option 1's one advantage: each plant is **projected** into its host nation as a firm-shaped view, so a reader that asks "the firms of France" gets France's own firms' home plants plus the plants foreign firms run in France, and needs no rewrite.

## 3. The data model (OPINION)

### 3.1 In `data/companies/<HOME>.json`

A firm stays a row of its **home** nation's file. Its existing fields keep their meaning and become **its home plant**: `city` is the headquarters and the home plant's city, `share` and `headcount` are the home plant's. One new optional field lists the plants abroad:

```json
{
  "id": "DEU_kessler",
  "name": "Kessler Werke",
  "sector": "industry",
  "share": 0.11,
  "headcount": 64000,
  "city": "DE1_stuttgart",
  "tier": "major",
  "chief_id": "DEU_chief_kessler",
  "plants": [
    { "nation": "FRA", "city": "FRE_lille", "share": 0.03, "headcount": 6200 },
    { "nation": "POL", "city": "PL2_katowice", "share": 0.05, "headcount": 9800 }
  ]
}
```

(The names and figures are illustrative, not authored.)

- **A row with no `plants` is today's firm, unchanged.** Every file on main stays valid and means what it means now, which is what makes the migration of section 7 identical step by step.
- A plant's `share` is of the **host** nation's sector, the same unit as a host firm's `share`, so it adds into the host's sector partition and its coverage band ([0.85, 0.97], [[companies-model]] 31).
- A plant has no name, no chief and no tier of its own: it carries its firm's.
- **The loader refuses** a plant whose `nation` is the firm's home or not a roster nation, two plants of one firm in one nation, a `city` that is not a city of the host (`regions_loader.gd:116-125`'s check, run against the plant's host), a share outside the host tier's bounds, and a host sector whose named coverage, plants included, leaves the band.

### 3.2 Owners outside the roster

37 % of the EU's foreign-controlled enterprises are controlled from outside the EU (section 1): American, Japanese, Chinese groups the 41 nations do not include. They have no home file to carry their plants. They are authored as a row of the **host's** file with one field, `"owner": "world"`, the only value that field accepts in data. Such a firm counts in the host's foreign-controlled share and has no relations pair: the rule is "no pair when the controller is not a nation in play", read as `state.nations.has(controller)`, never a literal compare.

### 3.3 Who controls a plant

One read answers it, `Companies.controller_of(state, plant) -> String` (OPINION):

1. the firm's runtime `owner` if a takeover wrote one (the register key that exists today, `companies.gd:879`);
2. else the authored `owner` (`"world"`);
3. else the firm's home nation.

A plant is **foreign-controlled** in its host when its controller is not the host. That covers three cases with one rule: a German firm's plant in France, a French firm a German group bought (a runtime `owner`), and an American group's French row.

### 3.4 Two levels of state

A firm's state splits by one rule (OPINION): **what a host government's act or the host's economy changes is the plant's; what is about the group's control or survival is the firm's.**

| Level | Keys | Lives in |
|---|---|---|
| firm | `state_share`, `failed`, `rescue_months_left`, `failed_month`, `bid_bidder`, `bid_price_eur_bn`, `bid_months_left`, `bid_month`, `courted`, `owner`, a new `parent` (the bidding firm on a takeover), `board_chair`, the firm's processes | the **home** nation's `ns.companies[firm_id]` |
| plant | `share` (live), `subsidy`, `subsidy_shadow`, `subsidy_lapsed_month`, `city` (a relocation inside the host), `closure`, `closure_watch` | the **host** nation's `ns.companies[plant_id]` |

- A home plant's id is the firm's id, so its plant keys and its firm keys share the entry they share today. **Nothing in an existing register moves.**
- A plant abroad has the id `<firm_id>@<HOST>` (for example `DEU_kessler@FRA`) and lives in the host's register. The `@` cannot appear in an authored id (the loader refuses it), so the two never collide.
- `tests/test_save_load.gd` pins the split: a plant-abroad entry carries no firm-level key.

## 4. How the readers move (OPINION; section 1.1's counts)

### 4.1 The projection: `firms_of(loader, nation)` returns plants

`CompaniesRoster.firms_of()` (`companies_roster.gd:12`) returns, for a nation, a **plant view** for every plant in it: each home firm's home plant, then each foreign firm's plant hosted there, in a stable order (home rows in file order, then hosted plants sorted by id). A plant view is a `Company`-shaped value with the fields readers already use (`id sector share headcount city tier chief_id`) and three more: `firm_id`, `home`, `host`. For a home plant, the view **is** today's `Company` object, field for field.

So the readers that walk a nation's firms and read the authored fields, which are the sector and city readers, keep their code and simply see more rows:

| Reader | Today | Under the projection |
|---|---|---|
| `headcount_in_city` (`companies.gd:317`), the Territory panel | the nation's firms in a city | plants in the city, foreign ones included; a German plant's jobs are Lille's jobs |
| migration's jobs map (`migration.gd:169-172`) | `firms_of` by authored city | unchanged code; hosted plants pull migrants to their city |
| `firm_jobs_offset_pct` (`companies.gd:581`) into unemployment | every firm's live minus authored headcount | unchanged code; a hosted plant that shuts raises the host's unemployment |
| `firm_impulse_pct` (`:539`) into growth | standing subsidies and burdens through live share | unchanged code; a host's subsidy to a hosted plant is the host's impulse |
| the investment pool (`industry.gd:118`, majors only) | the nation's majors | a major's hosted plants join the host's pool, so they gain and give share inside the host's sector |
| relocation (`industry.gd:243`) | a major moves to a near region | per plant, inside its host (a plant never changes nation) |
| sector regulation, the burden's shedding (`headcount`) | the sector's firms | hosted plants obey the host's sector law |
| closures (`closures.gd:53-75`) | the player's majors | the player's nation's major plants, home and hosted |
| the Industry tab and the city card | the nation's firms | hosted plants listed with their controller |

### 4.2 The firm-level reads go through `firm_of(plant)`

The readers that ask about control or survival read the firm, wherever the plant is: `state_share_of`, the failure flag, `owner`, the bid scalars, `courted`, `board_chair`, the processes gate. A new `Companies.firm_entry(state, plant)` returns the home register's entry. For a home plant that is the entry the reader reads today, so the result is identical; for a plant abroad it is the home nation's entry. This is the main rewrite: the reads of firm-level keys among the 70 register sites (24 in `companies.gd`, 12 in `industry.gd`, 6 in `closures.gd`, 2 in `processes.gd`, and the event and news hooks) each become a `firm_entry` read.

- **Failure is the group's.** A failed firm employs nobody in **every** plant: `headcount()` reads the firm's `failed`, so a German group's collapse empties its Lille plant the same month, with no rule of its own (band M6).
- **Ownership is the group's.** A nationalised firm's state share covers every plant, and its dividend (below) includes them.

### 4.3 The group aggregates read across nations

Four reads become sums over a firm's plants:

- `output_eur_bn(firm)`: the sum of each plant's live share × its **host's** sector output;
- `value_eur_bn(firm)`: that sum × `PRICE_TO_OUTPUT` (`companies.gd:227`), so nationalising Kessler buys its plants abroad too, at their value;
- the dividend (`companies.gd:610`): `state_share × group output × DIVIDEND_YIELD`, paid to the **home** nation's budget;
- the bid's "larger" test (`industry.gd:488-498`): the group's output, not its home share.

These read other nations' `sector_output`. The rule that keeps them safe (OPINION): a group table (each firm's plant outputs) is built **once**, on the calling thread, at the start of the Companies step from the outputs already committed, and the aggregates read the table. No per-nation unit then reads another nation mid-step, and nothing new runs on a worker (rules 1 and 4 of `src/core/parallel.gd:8-23`). For a firm with no plants abroad the table holds its home plant alone, and every aggregate equals today's read.

### 4.4 Readers that stay per nation

`bills.gd` (an ownership bill is about a firm of the player's nation, so it lists **home** firms), `statute.gd`'s lobbying (the sector's biggest **home** major signs the ask; a foreign plant does not lobby a host's assembly in this block), the process kinds (on home firms; the one host-side process is 5.3's), Regions (`regions.gd` reads region GDP, not firms; the Territory panel reads `headcount_in_city`, covered above).

## 5. The rules (OPINION)

Each is a general rule over the plant fields, `controller_of` and the numbers in a new `data/industry/foreign_ownership.json`, never per firm or per nation. Every number is a first proposal Systems tunes against the bands.

### 5.1 A foreign group closing a plant (call 2: "C'est toi qui choisis")

When `closures.gd` announces a closure on a plant whose controller is a roster nation other than the host, the answers gain one: **summon the controller's government**.

| Answer | What it costs | What it buys |
|---|---|---|
| Let it close (the default) | the closure's own `bloc_offset`, as today | nothing; relations do not move |
| Find a buyer | as today | as today; a buyer takes the plant out of the group (5.3's spin-out, at the buyer's price) |
| Rescue | as today: the host's subsidy, written on the plant | as today |
| **Summon the controller's government** | relations with the controller fall by `protest_relations` (proposed 4 points) whatever the outcome, through the stake-scaled third-party rule like any diplomatic act | odds the group keeps the plant, shown as a range: `clamp(0.25 + 0.25 × (stake(controller→host) / even − 1), 0.10, 0.60)`, `stake` and `even` read from `foreign_policy.gd:154`, `:145`. Germany cares about France, so a German group listens more than a Swiss one |

A closure by a `"world"` controller offers no summon. The strip ([[v5.3-ab]] 2.1) shows the summon's three lines: money 0, "relations with Germany −4", the odds range and "the group may close anyway".

### 5.2 The group decides abroad

A hosted plant's closure trigger reads the worse of two falls: its own output's (today's rule) and its **group's** output (4.3). A group whose home market slumps closes a plant abroad first. A group's failure empties every plant at once (4.2).

### 5.3 Expropriation is a diplomatic act

- **The home state nationalises a group** (the V5.3 a process, unchanged in its stages): the price is the group's value (4.3), plants abroad included. Each host of a plant sees its relations with the home nation move by `−clamp(expropriation_k × that plant's value, 1, 8)` at the transfer, because a foreign state now owns a plant on its soil.
- **A host nationalises a hosted plant** (one new process kind, `nationalise_plant`, the nationalisation's stages and premium on the plant's value): at the transfer the plant **leaves the group**. Its entry gains `spun_out` and a state share of 1; from then it is a host firm read like any other, and its controller is the host. Relations with the former controller move by `−clamp(expropriation_k × plant value, 3, 15)`, through the third-party rule. A `"world"` controller moves nothing, and the strip says why.
- **The bid answers** are re-sized on the same scale: blocking costs `−clamp(block_k × group value, 2, 8)` and allowing gains half that, replacing the fixed ±0.5 (`companies_constants.gd:123-124`), both through the third-party rule. An allowed bid writes `owner` (the bidder's nation) and `parent` (the bidder) on the target firm: the target keeps its plants and is now controlled from abroad.

### 5.4 The player's groups abroad (call 3: "Oui")

- **Shown:** the player's firms' plants abroad, on the firm's card ("3 plants abroad, 18,000 jobs: Poland, Spain, Romania"), and in the country box (V5.1-d4's map click) as "your groups there: N jobs; theirs here: M jobs".
- **Outward bids:** `industry.gd:488` stops skipping the player's nation as a **bidder**. A bid by one of the player's majors on an AI nation's firm is an arrival: **back it** (the host's odds of accepting rise by `back_bonus`; if the host still refuses, relations fall by `back_refused_relations`) or **let the group try alone**. The host answers at the window's end through a gate on `would_accept_agreement`'s shape (`foreign_policy.gd:288`): stake and relations against a threshold. On a yes, the target firm takes `owner` = the player's nation and `parent` = the bidder. The group pays, not the state: no debt moves.
- **Investment as stake:** the jobs a nation hosts from another raise its stake toward that nation, a third term in `stake_vector()`'s raw sum (`foreign_policy.gd:165-200`) beside trade dependence and history: `W_INV × (jobs in A controlled from B) / (A's named payroll) / even`. Poland, which hosts German plants, cares more about Germany, accepts its agreements more readily and cools more when a third nation acts on it. The table is built once per month on the calling thread, before Diplomacy's fan-out reads it (`parallel.gd` rules 1 and 4).

## 6. What the player sees (OPINION, for Interface)

- **On a firm's card:** its home and headquarters, then its plants by nation with their jobs; a group's total jobs and value.
- **On a hosted plant's row** in the host's Industry tab: the firm's name and its controller's flag ("Kessler Werke, Lille plant, Germany"), in `MAP_NEUTRAL` like every other nation's mark; the player's own colour is never used for another nation (AGENTS.md's two kinds of colour).
- **In the Industry tab's sector card:** one line, "foreign-controlled: 14 % of named jobs (Germany 6 %, outside Europe 5 %, ...)".
- **On the map at depth (V5.4 e):** a plant's glyph tinted by its controller.

## 7. The migration, in steps (OPINION)

Each step ends with the balance table `cmp`-identical to the step before (`tools/balance_parallel.py`, the D10-style gate) until step 5, the first that authors a plant. A step that moves a byte is a defect in that step, not a re-baseline.

| Step | What it builds | Why it is identical |
|---|---|---|
| **1. The plant view** | `Company` parses `plants`; the loader's checks (3.1); `firms_of` returns plant views; the `@` id; `controller_of` | no file has `plants`, so every view is the home plant, the same object as today |
| **2. The two levels** | `firm_entry(state, plant)`; every firm-level read of section 4.2 goes through it; the register-key split pinned by a test | a home plant's firm entry is its own entry |
| **3. The group table** | the table of 4.3, built at the Companies step; output, value, dividend and the bid's size read it | a group of one plant sums to that plant |
| **4. The rules, inert** | 5.1's summon, 5.2's group trigger, 5.3's relations moves and the plant spin-out, 5.4's outward bid and stake term, all behind the controller test | no plant is foreign-controlled until step 5. The one way a runtime controller appears without plants is an allowed bid, and no balance regime answers one: `tools/balance_probe.gd` never calls `allow_bid` (MEASURED; its only bid answer is in `decision_surfaces_probe.gd:879`, which is not the balance gate) |
| **5. Content** | plants authored on the playable nations' majors, `"world"` rows, sized to `fats_activ` (and the ONS for Britain) | **moves numbers**: jobs by city, sector partitions, the investment pool, every machine draw over the new plants. The re-baseline goes to the author |
| **6. Investment as stake on** | 5.4's term reads non-zero | **moves numbers** at month 0: every stake vector, so agreement gates and the AI's agenda. A second re-baseline to the author |
| **7. The views** | section 6 | display |

Steps 1 to 4 are Systems' and can merge one by one, each green and identical. A probe or test that walks `firms_of` keeps passing through all four; the 86 `majors_of` and 42 `share_of_company` hits in `tools/` and `tests/` (section 1.1) need no change until step 5, when a test that counts a nation's firms sees its hosted plants.

## 8. What moves which sim numbers, and the save

### 8.1 Numbers (INFERRED)

| Change | Numbers it moves | When |
|---|---|---|
| Steps 1 to 4 | none (band M1) | never |
| Step 5, plants authored | jobs by city, unemployment through `firm_jobs_offset_pct`, migration's pull, sector shares through the pool, failures and bids over more majors, closures in the player's nation | from month 1 of every run; re-baseline 1 |
| 5.1 summon | relations with the controller (and third parties by stake), so the trade mix and so GDP slightly; jobs kept in the plant's city | on the player's answer |
| 5.2 and 4.2 group failure | closures and job losses in hosts of a failing or slumping group | in idle runs; part of re-baseline 1 |
| 5.3 expropriation, spin-out, bid re-size | relations, the trade mix, agreement gates; the home debt by a group's value | on the player's verb |
| 5.4 outward bids | the runtime owner of AI firms; relations on a refused backing | on the machine's draw, then the player's answer |
| Step 6, investment as stake | every stake vector from month 0 | re-baseline 2 |

Each re-baseline is the author's to accept before its merge, per the V5.3 rule.

### 8.2 The save: no bump (OPINION, by AGENTS.md's rule)

The rule: a bump only when "a missing field would read as something wrong".

- **Plant entries abroad** (`<firm_id>@<HOST>`) are new keys of the host's register. Absent, a plant reads its authored share, city and no subsidy or closure: true for every save made before the content had plants, exactly as a major added to content is lazily seeded into an older save's register today (`_seed_missing_majors`, `companies.gd:142`; [[companies-model]] 31). The same seeding seeds a plant.
- **The firm-level keys** stay in the home entry they live in today. `parent` and `spun_out` are new; absent they read "no runtime parent" and "never spun out", true for every older save, which cannot hold a takeover parent or a plant nationalisation.
- **Nothing is renamed or moved**, because a home plant's id is the firm's id (3.4).

So `SAVE_VERSION` stays where it is. `tests/test_save_load.gd` widens its `LIVE_KEYS` list (`:2652-2654`) by `parent` and `spun_out`, pins that a plant-abroad entry carries no firm-level key, and round-trips a game with one plant abroad, a summon, a spin-out and a takeover parent.

## 9. The cost, stated

**Files touched (INFERRED from section 1.1):**
- `src/core/company.gd` (the `plants` field), a new `src/core/plant.gd` or a plant-view builder, `src/core/loaders/companies_loader.gd` (the checks), `src/core/loaders/regions_loader.gd` (the city check per host);
- `src/sim/companies_roster.gd` (the projection), `src/sim/companies.gd` (24 register reads, the aggregates, the bid answers), `src/sim/companies_walk.gd`, `src/sim/industry.gd` (12: bids and failures go firm-level, investment and relocation stay plant-level), `src/sim/closures.gd` (6, the summon and the group trigger), `src/sim/processes.gd`, `process_asks.gd`, `process_drag.gd` (the group value, the plant spin-out), `src/sim/budget.gd` (the dividend over the group), `src/sim/foreign_policy.gd` (the stake term), `src/sim/event_hooks.gd` and `industry_news.gd` (firm-level reads);
- `src/ui/companies_panel.gd`, `industry_card.gd`, `company_verb.gd`, `territory_city.gd`, `region_panel.gd`, the country box;
- `tools/firms_generate.py` (plants on generated majors, if Content uses it), `tools/companies_probe.gd` (a plants flag), the closures probe, `decision_surfaces_probe.gd` (source `foreign`);
- tests: `test_save_load.gd`, `test_companies*.gd`, `test_industry.gd`, `test_closures.gd`, `test_processes.gd`, a new `test_plants.gd`.

About **25 source files and 6 test files**, and of the 70 register reads and 40 authored-field reads, the firm-level ones (section 4.2) rewritten, the rest unchanged behind the projection.

**The size ratchet.** `companies.gd` cannot grow (423 code lines in the baseline), so the group aggregates and `firm_entry` land in a new file (proposed `src/sim/companies_group.gd`), as the roster and walk splits did, and `companies.gd` keeps the public names and delegates.

**The tick.** The projection adds each hosted plant to its host's `firms_of`, so every per-firm read walks a few more rows. With, say, 200 plants roster-wide against 3,860 firms today (INFERRED, a planning figure for Content, not a target), about 5 % more rows; the group table is one pass over the plants a month. Band M10 holds the month's cost.

**Against the first draft's option 1:** option 1 needed no firm-level rewrite and no group table; option 2 pays for both, and in return a group is one firm with one failure, one owner, one value and one dividend, which is what the author asked for.

## 10. Pre-mortem: the next gate says "I never saw a foreign firm do anything"

1. **The arrivals are too rare.** At 0.01 a year per major, a France of 12 to 15 majors draws a bid about once in seven years (INFERRED, not measured), and a foreign-controlled closure is a fraction of one closure a year. Prevented by the group trigger (5.2), the outward bids (5.4) and band M3, which sets a rate and is measured before the build.
2. **The relations moves are invisible again.** Prevented by M4's floor of 3 points, a third of a condemnation.
3. **The summon always wins, or never.** Prevented by M5.
4. **The foreign share is wrong against reality.** Prevented by M2, measured against `fats_activ` by a loader test.
5. **The rewrite breaks something the suite does not see.** Prevented by M1: four steps, each `cmp`-identical, each its own PR.

## 11. Bands and done-when (declared before any build)

| Band | What holds | Measured by | A failure looks like |
|---|---|---|---|
| **M1, the migration moves nothing** | after each of steps 1 to 4, the balance table is `cmp`-identical to the step before; the suite stays green with no test edited for steps 1 to 3 | `tools/balance_parallel.py`, the D10-style gate, per step | any byte |
| **M2, the start matches the source** | in each playable nation, the share of named payroll (majors and body, plants included) under a foreign controller, `"world"` included, is within ±5 points of `fats_activ`'s jobs share for 2022 (Britain: the ONS figure); every host sector's coverage stays in [0.85, 0.97] with its hosted plants | a loader test over `data/companies/` | France at 2 % against a real figure in the teens |
| **M3, the player meets the subject** | over 120 months, both regimes, the four playable nations: 1 to 4 multinational arrivals a year on average (a bid on one of the player's firms, a foreign-controlled closure, a group-led closure, an outward bid), at most one a month from these sources, counted as source `foreign` (a foreign-controlled closure keeps its `closure` tag as well, so B7's totals do not change; M3 reads `foreign` alone) | `tools/decision_surfaces_probe.gd --density` | 0.2 a year, the bid machine's silence today |
| **M4, a diplomatic matter is visible** | a summon moves the pair by 3 to 8 points; a plant spin-out by 3 to 15; a blocked bid by 2 to 8; a closure the player lets happen moves no pair | `tests/` per rule; a companies probe flag | a move under 3 points |
| **M5, the summon is a choice** | the odds shown bracket the realised outcome in 100 % of probe runs; across the probe's staged states (high and low stake, a large and a small plant), each of the four closure answers is best on at least one of jobs kept, relations or EUR bn in at least one state | the closures probe, extended | "always summon" or "never summon" winning everywhere |
| **M6, the group is one firm** | a group's failure sets every plant's headcount to 0 in the same month, in every host, in 100 % of runs; a nationalised group's dividend equals `state_share × the sum of its plants' output × DIVIDEND_YIELD`; a group's value is the sum of its plants' | a plants test | a German group fails and its Lille plant runs on |
| **M7, investment as stake** | with every plant stripped the stake vectors are identical to the base; at month 0, POL's stake toward DEU rises (the term is live); every agreement gate that flips at month 0 among the four playable nations is listed in the re-baseline for the author | a foreign-policy test; the diplomacy probe | a silent flip |
| **M8, the save** | an older save loads, seeds its hosted plants at their authored values, and round-trips `parent`, `spun_out` and plant entries; a plant-abroad entry carries no firm-level key | `tests/test_save_load.gd` | a lost runtime owner, or a firm key on a plant |
| **M9, no `if nation_id`** | the rules read `controller_of`, the plant fields and `foreign_ownership.json`; a grep of the new code finds no nation literal | the existing lint and review | a branch on `"DEU"` |
| **M10, the month's cost** | Companies, Industry and Closures together cost at most 10 % more per month after step 5 than before it, on `tools/tick_budget_probe.gd`, run alone | the timing probe, on the parent's PROBE GO | a projection that walks the roster per firm |
| **M11, the author's gate** | after 30 minutes the author has met at least one foreign group as a decision, and names it | the playtest receiver's report, verbatim | "I never saw it" |

## 12. The build split, by owner, in order

Gameplay writes only this spec. Every item is a proposal the parent routes.

1. **Systems, steps 1 to 4**, one PR each, each `cmp`-identical (M1): the plant view and the loader's checks; `firm_entry` and the key split; the group table in `companies_group.gd`; the rules behind the controller test, with the density source `foreign`, the new process kind and `foreign_ownership.json` read through the loader. M4 to M6, M8, M9 on fixtures.
2. **Content, step 5, beside step 4:** plants on the playable nations' majors and their partners', `"world"` rows, sized to `fats_activ` (the ONS for Britain), each source in `REUSE.toml`; plants on generated majors through `tools/firms_generate.py` where the body generator is the owner ([[companies-model]] 37); `foreign_ownership.json`'s numbers, each with its reason. M2.
3. **Systems, step 6:** the stake term on; M7, the diplomacy re-run.
4. **Interface, step 7:** section 6; `tools/screenshot.gd` staged states for a group card, a hosted plant row and a summon.
5. **QA:** every band, the two re-baselines read against the author's acceptance, M10 on a PROBE GO, the windowed screenshot pass.

## 13. The author's calls (2026-11-02), ANSWERED

Through the parent's question tool. The picks are verbatim, with what each settles.

1. **La forme des données :** "Une entreprise, plusieurs usines". Option 2, not the first draft's recommendation: a firm with a home, a headquarters and plants abroad (sections 3 to 9).
2. **La fermeture par un groupe étranger :** "C'est toi qui choisis (Recommended)". The summon is the player's verb; a closure the player lets happen moves no relations (5.1).
3. **Tes groupes à l'étranger :** "Oui (Recommended)". Outward bids with the host's answer, and hosted jobs as a stake term (5.4).
4. **Quand :** "En V5.4 (Recommended)". V5.4 f, after d and e.

The calls as they were put to him:

1. **Comment représenter un groupe présent dans plusieurs pays ?** (a) *Recommandé :* une usine étrangère est une entreprise du pays où elle se trouve, avec deux champs en plus : son pays propriétaire et sa maison mère. Tout ce qui existe (emplois, chômage, fermetures) marche tout de suite. (b) Une seule entreprise avec une liste d'usines dans plusieurs pays : plus juste sur le papier, mais il faut réécrire presque tout le code des entreprises. (c) Juste une étiquette « propriétaire étranger », sans maison mère ni groupe. **RÉPONDU : « Une entreprise, plusieurs usines ».**
2. **Quand un groupe étranger ferme une usine chez toi, est-ce une affaire diplomatique ?** (a) *Recommandé :* c'est toi qui choisis : tu peux convoquer le gouvernement du pays propriétaire. Ça abîme la relation (environ 4 points) et ça donne une chance que l'usine reste, plus grande si ce pays tient à toi. Si tu laisses fermer, la relation ne bouge pas. (b) Automatique : toute fermeture par un groupe étranger refroidit la relation, même si tu ne fais rien. (c) Pas de diplomatie, seulement l'étiquette. **RÉPONDU : « C'est toi qui choisis (Recommended) ».**
3. **Tes propres groupes peuvent-ils racheter des entreprises à l'étranger ?** (a) *Recommandé :* oui. Le pays visé répond selon sa relation avec toi et l'importance que tu as pour lui, tu peux appuyer l'offre ou laisser faire, et les emplois que tes groupes créent chez un voisin le rendent plus attaché à toi (ça change la diplomatie dès le début de partie). (b) Non : tes usines à l'étranger existent au départ et s'affichent, mais tu n'en gagnes pas de nouvelles. **RÉPONDU : « Oui (Recommended) ».**
4. **Quand le construire ?** (a) *Recommandé :* en V5.4, après la négociation (d) et la ville en détail (e), parce qu'il réutilise les deux : les usines sur la carte, colorées par pays propriétaire. (b) Une petite partie tout de suite en V5.3, juste après les nouvelles grandes entreprises (les deux champs et la fermeture diplomatique), le reste en V5.4. (c) En V6, avec les accords sur les ressources. **RÉPONDU : « En V5.4 (Recommended) ».**

## 14. What could not be verified

- **France's, Germany's and Britain's jobs shares** under foreign control: not in the fetched Eurostat text; Content reads `fats_activ` (and the ONS for Britain). M2's ±5 points is set before those figures are read, so it may need the parent's look once they are.
- **The OECD's terms.** `REUSE.toml` records that they could not be read on 2026-11-01 (HTTP 403). Eurostat is the primary source; the OECD's AMNE tables are a cross-check only until the terms are read.
- **The arrival rates** in section 10 are arithmetic on the constants, not a probe run. M3's baseline is a `--density` run on main with the source added, before the rules.
- **The file and reader counts** in section 9 are inferred from section 1.1's grep; which of the 70 register reads are firm-level is classified by key (3.4), not read site by site.
- **The proposed numbers** (the summon's 4 points and odds, `expropriation_k`, `block_k`, `W_INV`, the 200 plants) are first proposals; each band says what must hold.
- **No GLM red-team** was run on this revision; the review is `code-review` and QA.
