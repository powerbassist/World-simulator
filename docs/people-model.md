---
title: People Model
tags:
  - decision
  - content
  - ui
---

# People Model

The named-individual register, as built in [[ROADMAP|U6b]] — the deferral
[[cabinet-model|V1.1d]] took deliberately and [[v1]] §5 has been assuming ever
since.

Same standard as [[government-model]], [[bloc-model]] and [[calendar-model]]: a
**game model**, judged on whether the player's decisions produce a legible,
attributable political outcome. Where realism and legibility conflict,
legibility wins, and the trade is noted.

## 1. The row said "author the roster". The roster already existed

U6b's cell in the U5a decomposition reads *"the roster V1.1d deferred — named
individuals, plus the banned-names check and the `SAVE_VERSION` bump."* Counted
cold, **~70 named people were already authored**, as loose strings in five
places:

| Where | What | Count |
|---|---|---|
| `data/nations/*.json` | `leader.name`, `government.head_of_state.name`, `government.formation.head_of_government_name` | 30 slots |
| `data/parties/*.json` | `leader_name` | 57 |
| `data/laws/amendments.json` | a restored monarch's `name` | 1 |
| `NationState` | `pm_name`, `head_of_state_name`, `start_head_of_government_name` — **live and serialised** | 3 fields |

Two of those were already the failure this project's registers exist to prevent.
**Every one of the ten nation files wrote one person's name twice** — as
`leader.name` and again as either `head_of_state.name` (France, Switzerland) or
`head_of_government_name` (the other eight) — and `data/parties/` wrote it a
third time, which `party.gd`'s own comment documented as a *convention*: *"Where
this party governs its nation, the name matches that nation's authored leader."*
A convention is what a register replaces.

So U6b's real job was **making a person first-class the way a party already is**:
one record, an id, and state that stores the id. The tier table had no U6b row —
**tenth consecutive instance** of the missing-row failure V1.3b recorded.

## 2. A person is an ID, a NAME — and, since V4.3, what they WANT

`src/core/person.gd` was born with two fields, on an argument that held for the
political cast: **the reference that owns the relationship already states it.**
Three fields were cut before the file was written. V4.3 re-admits one of them,
narrowed; the other two cuts stand:

| Field | Status |
|---|---|
| `title` | **Still cut.** A head of state's title is `ns.head_of_state_title`, which an amendment can change. A person carrying one would go stale the moment the office did. |
| `role` | **Still cut.** The office a person holds is *the slot pointing at them*. A `role` field would be a second record of the reference graph, and Daniel Moucron — head of state **and** a party leader — shows it cannot even be single-valued. |
| `party_id` | **Re-admitted at V4.3, backbencher form.** A party leader is still whoever that party's `leader_person_id` points at, and anyone a slot or a leadership points at leaves this field empty. It exists because a *bench* politician's affiliation has no slot pointing at it — authored once here, resolved against the nation's own party list at load, rather than dangling with no edge at all. |

What the two-field construction bought survives for the political cast: no
field a slot already states. But the second half of the original argument —
*no field that could carry a mechanism* — held only while every person was the
political cast, and **V4.3 overturns it deliberately** ([[v4]] §V4.3, the tier's
own citation): a person outside the political register has *nothing pointing at
them*, so the register could never grow a union leader or a judge without
giving them something authored. The answer is the character layer — `kind`,
`traits`, `ambition`, `wants`, §14 — and its own law is the one this file now
enforces instead: **a person is a WANT carrier, not a mechanism carrier.** The
numbers that move (loyalty, standing, grudges, overrides) are live state on
`NationState`, never fields here; `tests/test_people.gd` reads the file and
fails on any EIGHTH field.

## 3. Ids are namespaced where party ids are not

`<NATION>_<surname>` — `FRA_moucron`, `DEU_vogler`. Validated against the file's
own stem, so global uniqueness follows from per-file uniqueness plus a prefix
that cannot repeat. The flat duplicate check is kept anyway and is **redundant by
design**: it can only fire if the prefix rule is relaxed, which is exactly when a
duplicate stops being impossible.

The asymmetry with party ids is deliberate and is the whole argument for the
scheme. A party id is only ever read **inside a nation's context** —
`loader.parties` is `{nation_id -> Array}` and every reader has the nation in
hand — so two nations may share one silently and nothing breaks. A person id is
read **bare**: off `ns.pm_person_id`, off an appointment entry that carries no
nation field, out of `last_censure` in a save. A bare read needs a
self-describing key. **Re-namespacing party ids is a declared cut**: if a later
session reads a party id bare, that session pays for it.

The id is ASCII-folded by the nation's own convention (`Müller → DEU_mueller`)
while the name keeps its accents; a nobiliary particle belongs to the surname
(`Van Craen → BEL_van_craen`), or the id claims a surname the person does not
have. A regnal name has no surname and slugs whole (`Baudouin III →
BEL_baudouin_iii`). Full convention in [[fictionalization]].

## 4. No person is unreferenced, and the loader refuses one

`_validate_people()` checks the usual direction — every reference resolves, and
resolves to a person of that nation — and then checks the unusual one: **every
person is pointed at by something.** An orphan fails the load.

That is not tidiness. It is the same standard as the session's own probe: an
unreferenced person is content with no caller, which is precisely what U6b cut a
five-deep minister bench for. Authoring a name and wiring it to nothing should
fail loudly rather than sit in a file looking like a feature.

**V4.3 widened what a reference is.** A person is referenced by a slot, OR by a
**non-politician `kind`** — the kind is the meter hook, so a union leader with
no slot anywhere is pointed at by the grievance ladder their kind reads — OR by
an **authored `party_id`**, the backbencher edge §2 re-admitted. A politician
with no slot, no kind and no party is still an orphan and still fails the load.
The rule change is what lets the register grow a bench at all: before it,
every person had to be electable-by-slot, which is precisely the cast the
register could never leave.

## 5. The probe corrected the model once and itself twice

`tools/people_probe.gd`, run at **L0 — before `data/people/` existed**, on a
bench synthesised in memory from `loader.parties`. The derivation needs *ids*;
names are the last thing a roster needs, and measuring first is what let the
measurement change the design.

### (P1) The reachability ceiling

| Nation | Parties | Static ceiling | Observed |
|---|---|---|---|
| DEU | 6 | 5 | 5 |
| FRA | 6 | 5 | 5 |
| GBR | 6 | 5 | 5 |

A single-party government holds every portfolio, so the ceiling is
`PORTFOLIO_KEYS.size()` wherever one party alone is a legal coalition — which is
everywhere. **No slot could be cut on reachability**, and the hoped-for saving of
"author 3 rather than 5" was measured dead.

### (P2b) Identity churn — the correction that changed the model

The first derivation gave each party a flat **ordered** bench and picked by rank
among the portfolios that party currently held. The probe measured **22 department
changes in one fourteen-year run** with no intervening election: adding one
portfolio to a party renumbers every minister it already has, so a person moves
department for a reason that has nothing to do with them.

Replaced with the **shadow cabinet** — `bench[portfolio]`, keyed rather than
ordered. Churn went to **0 in every run**, and it is *structurally impossible*
rather than damped, which is the shape [[foreign-policy-model|V1.3f]]'s
`AGENDA_AMITY_TARGET` correction took. It is also far more legible: a party has a
health spokesperson, and when the party takes Health that person becomes Health
Minister. That needs no explaining on a screen.

The rule also removed the "one person, one office" exclusion the rank model
needed — a leader leads, and five spokespeople shadow five departments, so a
leader is structurally not a minister.

### (P2) Distinct people seen — the kill switch, which FIRED

Pre-committed at **12** before the sweep, on the reasoning that two executives
plus a distinct minister per portfolio across three elections should clear it.

| Nation | Regime | Seen | Median | Ministers | Elections | Churn | Vacant |
|---|---|---|---|---|---|---|---|
| DEU | hands_off | 12 | 7 | 10 | 1 | 0 | 0.0 % |
| DEU | austerity | 11 | 2 | 9 | 1 | 0 | 92.3 % |
| FRA | hands_off | 13 | 6 | 11 | 2 | 0 | 6.0 % |
| FRA | managed | 9 | 6 | 8 | 2 | 0 | 0.0 % |
| **FRA** | **austerity** | **6** | **1** | **5** | **0** | **0** | **87.5 %** |
| GBR | hands_off | 7 | 6 | 6 | 3 | 0 | 0.0 % |
| GBR | austerity | 12 | 2 | 10 | 1 | 0 | 89.3 % |

Worst case **6**, against a floor of 12. **The minister bench is cut** — deleted
before it was authored, the treatment [[calendar-model|U6a]] gave its own day
budget and [[foreign-policy-model|V1.3e]] gave `AGREEMENT_ACCEPT_MIN`.

Two readings matter and the table separates them. The low scores come from two
structurally different places: a **collapsed government** (FRA/austerity at 87.5 %
wholly-vacant months — the cast is small because the cabinet is empty, which is
the model working) and a **stable single-party government** (GBR/hands_off at
7 with *zero* vacancy and three elections — one party, its leader, its five
shadows, and fourteen years). The second is the real finding: roughly **20–33 % of
a 30-person-per-nation bench is ever seen**, and no amount of play changes it.

Two of the probe's own numbers were wrong on the first run and both were
[[foreign-policy-model|V1.3f]]'s error — measuring the wrong state. The election
counter read `months_in_term == 0` and reported **zero elections for every nation
over fourteen years**, which is impossible, and churn was gated on it. A
`vacant%` column was added afterwards because the first table's worst reading was
a government that had collapsed rather than a roster that was thin, and a cast
size with no vacancy column beside it cannot tell those apart.

### What the cut costs, visibly

The People window's cabinet group names the **party** that holds each portfolio,
which is what `government_panel.gd` has always printed. That group is the visible
price of the cut and it is recorded here rather than hidden: the window answers
"who runs Health?" with a party, and will keep doing so until a session gives a
minister something to *do* that a party cannot do.

## 6. `SAVE_VERSION` 13 → 14, on a re-key rather than a new field

`pm_name → pm_person_id`, `head_of_state_name → head_of_state_person_id`,
`start_head_of_government_name → start_head_of_government_person_id`.

The rule is unchanged — *would a missing field read as something wrong?* Nothing
was **added**, so the naive reading is that nothing is at risk. But a version-13
save carries the **old keys**, so without a bump all three load as `""` while the
file itself looks intact, and the game renders a government nobody governs. An
absent `pm_person_id` reads as *no head of government*, which is a claim about the
world rather than a missing label: `military_capability`'s case at
[[defence-model|V1.3g]] and `eu_member`/`neighbours` at [[trade-model|V1.3b]], in
their strongest form yet.

What U6b did **not** add is again the interesting half:

- **No per-person serialised state at all.** A person is pure content, so there is
  nothing for a save to carry — the property [[foreign-policy-model|V1.3e]] got
  from *no grievance ledger*, arrived at from the other direction.
- **The field that would have earned this bump on its own was never written.** A
  stored `ns.cabinet_person` was the declared escalation if churn came back high;
  the shadow-cabinet keying took churn to zero and the probe then cut the bench
  entirely, so the question never reached the loader.
- **`appointments`' `person_id` earns nothing.** It is a derived label; an absent
  one reads as "not recorded", and the entry's identity is still
  `Calendar.verb_key()`.

## 7. `verb_key()` did not change, and U6a's hatch was not needed

[[calendar-model|U6a]] declared `person_id` on the appointment entry, written by
nobody, against the possibility that U6b would key appointments on people and
have to re-key the register — which would have bumped `SAVE_VERSION` twice.

**It was not needed**, and the reason is the argument that shrank the whole
session: a person is the **face** of a target that already exists, so booking a
state visit to Germany *is* booking its leader. One act, one key. `person_id` is a
derived **label**, resolved at booking time by the panel that knows the target,
and `tests/test_calendar.gd` asserts that two entries differing only in
`person_id` are the same verb — refused as a duplicate, and cancellable by a key
derived without the person.

Only the diplomatic kind carries one. A law is proposed to an assembly and a
reshuffle hands a department to a party; with the bench cut, neither has a person
to name, and `""` says so rather than guessing at a leader who is not taking the
job.

## 8. The restored monarch — a content bug the register fixed

`data/laws/amendments.json` authored `"name": "Alexander IV"` inside the
Restoration Act's institutional effect, and that law applies to any
`parliamentary_republic`. **Every republic in Europe restored the same king.**

The law now names an **office** and carries no name for any kind;
`government.pretender_person` answers it per nation. A monarchy points that slot
at its own sitting monarch, so a republic-then-restoration returns the right
house rather than inventing a second claimant. `law.gd`'s validator inverted with
it: a head-of-state name is now refused for *every* kind, where before it was
required for all but `elected_president`.

Five new names were authored for the five republics. **They are the only new
names in the session** — the other 66 of the register's 71 are moves.

## 9. `check_names.sh` cannot see an untracked file

The first run of the check over the new register passed with **zero hits and zero
files scanned**. `tools/check_names.sh` iterates `git ls-files`, so a brand-new
content directory is invisible to it until it is tracked — meaning the largest
exposure the check has ever had was, for one run, not being checked at all.

Recorded because it is a property of the check rather than of this session: **any
session that authors a new content directory must `git add` before the check
means anything.** With the register tracked, all 71 names pass, and
`people_probe.gd`'s P3 pre-flight agrees against 141 banned entries.

## 10. Why nothing diverges

| Quantity | Bound |
|---|---|
| A person's identity | Content, read once at startup, never mutated — the same guarantee every `data/` file has. |
| The register's size | Fixed by `data/people/*.json`. No code creates a person, so there is no accumulator. |
| A person id in state | Only ever copied from content or from another state field. The three re-keyed fields are written by `Government.form()`/`init_nation()` and `Legislature._apply_head_of_state()` and by nothing else. |
| An unresolvable id | `DataLoader.person_name()` returns `""`, which is what the panels already did with an empty name before the re-key. The loader refuses an unresolvable reference at startup, so `""` is reachable only for a genuinely empty slot. |
| An orphan | Refused at load. |
| `appointments`' `person_id` | A label outside `verb_key()`, so it cannot create, split or collide with an appointment identity. |

The argument is not the evidence. `tests/test_people.gd` checks the register
loads for all ten, ids are prefixed, every nation and party reference resolves,
no person is unreferenced, a duplicate id / a bad prefix / an orphan each fail the
load, `Person` declares exactly two fields, `src/sim/` reads neither
`person_name` nor `person_by_id`, **no data file spells out a person's name any
more**, and every nation's pretender is its own. `tests/test_people_panel.gd`
covers the window: all four groups, no blank label, names actually resolved, the
cabinet column agreeing with the Politics panel, a vacancy reading as `VACANT`,
and no button but Close.

## 11. The balance re-run, predicted and confirmed

**Bit-identical across all fourteen regimes** — 534 identical lines, zero
differences, and no fifteenth regime. Predicted in advance on grounds that were
checkable rather than asserted: every re-keyed field is a String no equation
reads, the readers are `%s` interpolation in `src/ui/`, and the one comparison
(`government.gd`'s `start_head_of_government_person_id != ""`) is an emptiness
test whose truth value is unchanged for all ten nations.

This is the first session in a long run to need **no new regime at all**.
[[calendar-model|U6a]] and [[defence-model|V1.3g]] each needed one because each
added a verb; U6b adds none. A name is not a decision.

## 12. Where it sits

```
DataLoader.load_all()
  → _load_people(id)     ×10, BEFORE parties, since a party resolves its leader
  → _load_parties(id)    ×10
  → …
  → _validate_people()   every reference resolves; every person is referenced

src/sim/    moves person IDS and resolves none of them
src/ui/     resolves, via DataLoader.person_name(id)
```

The one exception is `nation_select_panel.gd`, which runs before a game exists
and has no loader. `menu.gd` passes it a flat `{id: name}` map rather than the
loader itself — the panel needs a name, not a data layer.

**There is no `people.gd` module.** A name lookup is a dictionary read and every
panel that wants one already holds the loader, so a module for it would be the
widest-dependency-for-the-narrowest-job failure [[calendar-model]] §5 argues
against. The module the plan named was to hold the minister derivation; the probe
cut the bench, and the module went with it rather than shipping as a wrapper
around `Dictionary.get`.

## 13. What is deliberately not built

**Named ministers.** §5. The bench was measured and cut before it was authored.
[[cabinet-model]]'s deferral is recorded as **still correct** rather than
reversed.

**Any attribute on a person.** No age, portrait, biography, career, competence,
loyalty or ambition. §2 — and `Person` having no field to hold one is what makes
this enforceable rather than aspirational.

> **OVERTURNED AT V4.3, BY NAME** ([[v4]] §V4.3, the tier citation this file's
> §2 also carries): a person now carries `kind`, `traits`, `ambition` and
> `wants` — the want carrier §14 defines. What this bullet still refuses, and
> §2's field-count check still enforces: **age, biography, career, competence**
> — nothing reads them; **loyalty, or any number that moves** — state lives on
> `NationState` (SAVE_VERSION 36), never on the content register, so a person
> file cannot drift from what the player did; **portraits as a field** — an
> asset keyed by the id the register already has ([[portrait-attribution|V3.7]]),
> not an attribute. The U6b law that survives is the one §2 still states: no
> field a slot already says.

**Journalists, celebrities, business.** They have no target that exists, so
meeting one *is* a new effect channel. [[v1]] §4 and §5 own them, each arriving
with the mechanism that gives it something to do — the split the whole U6
decomposition was taken on.

> Half-overturned at V4.3: the journalist and the union leader exist now as
> KINDS (`press_owner`, `union_leader`, §14.4) — because their target DID come
> to exist, the meters of [[unrest-model]], [[media-model]] and
> [[judiciary-model]]. What stays refused is meeting one as an EVENT channel:
> a person acts through the acts §14.5 prices, not through a new effect key.

**A person on the nation panel beyond the leader line that was already there.**
That panel is at 860px against U5a's ~886 ceiling and has paid for the fold twice
(V1.3e, V1.3g). U6b's change there is a *resolve*, not a new row.

## 14. The character layer (V4.3)

The tier block [[v4]] §V4.3 calls *People who want things*. Everything above
this line is the register as U6b built it; this section is what V4.3 added and
the law it added it under. Plan of record:
`docs/superpowers/plans/2026-09-17-v4.3-people-who-want-things.md`.

### 14.1 Content vs state — who a person is vs what you did to them

| Content (`data/people/*.json`, never moves) | Live state (`NationState`, SAVE_VERSION 36) |
|---|---|
| `kind` — the six, below | `person_loyalty{id: float}` — [-1, +1], moves with acts |
| `traits` — 2–3 from the fixed eight, below | `person_standing{id: float}` — [0, 1], political weight |
| `ambition` — [0, 1], static drive | `person_grudges{id: float}` — [0, 1], written by betrayal, decays |
| `party_id` — optional backbencher edge | `party_leader_override{party_id: person_id}` — challenges |
| `wants[]` — objects + stance, below | `person_party_override{id: party_id}` — defections |

A want denied is a grudge; a want served is loyalty. The whole price book is
two channels, both existing registers — no third number was built.

### 14.2 The trait set — eight, each mechanically defined

`src/sim/character_constants.gd`, `TRAIT_KEYS`. Each trait gates an act
threshold or price (the CK lever the tier signed); 2–3 per person, authored:

| Trait | The whole mechanical definition (as shipped — the table was corrected to the code) |
|---|---|
| `ambitious` | standing SEED bonus (+STANDING_SEED_AMBITIOUS_BONUS at init — standing never moves again); challenge standing-threshold lowered by CHALLENGE_AMBITIOUS_DISCOUNT |
| `loyal` | grudge taken ×0.5 (LOYAL_GRUDGE_FACTOR); resign floor relieved (LOYAL_RESIGN_RELIEF) |
| `principled` | grudge taken ×2 (PRINCIPLED_GRUDGE_FACTOR) — a denied want bills them double; no standing channel exists |
| `pragmatic` | grudge decay ×2 (PRAGMATIC_DECAY_FACTOR) — they let go faster; no stance-softening mechanism exists |
| `vain` | challenge standing-threshold lowered by CHALLENGE_VAIN_DISCOUNT (0.1) when they carry a leadership want — a threshold discount, not an act-choice weighting |
| `stubborn` | grudge decay halved (STUBBORN_DECAY_FACTOR) |
| `networked` | their brief carries ×1.5 bloc_offset magnitude (NETWORKED_MAGNITUDE) |
| `fervent` | a METER want's denial pulse ×1.5 (FERVENT_METER_FACTOR) for the collective kinds — the meter is their own register; no salience read exists |

A ninth needs a measurement, not a mood. `ambition` the scalar and `ambitious`
the trait are different things and both exist — the scalar is the dial, the
trait is the floor.

### 14.3 The want grammar

```json
{"object": "programme:prog_the_hospital_year", "stance": "sponsor"}
{"object": "office:portfolio:health", "stance": "want"}
{"object": "office:premiership", "stance": "want"}
{"object": "office:party_leadership:renouveau_civique", "stance": "want"}
{"object": "meter:grievance", "below": 35.0, "stance": "demand"}
{"object": "meter:judicial_independence", "above": 0.8, "stance": "defend"}
```

Objects resolve AT LOAD — shape and closed vocabularies in `person.gd`
(kinds, traits, stance-for-family, threshold coherence: a meter want carries
EXACTLY ONE of `below`/`above`, and no other family reads one), cross-register
halves in `data_loader._validate_people()`, the first place the whole loader is
in hand — people load BEFORE parties and programme, so a want cannot be checked
against registers that are not filled yet. Unresolvable = load error, loud,
naming the file and the person id. **Satisfaction is DERIVED, never stored** —
`Programme.progress_of()`, the office-holder slots, the meter reads; the
region-share discipline, one level up.

### 14.4 Kinds and the meters they read

`KIND_KEYS`: `politician` (the version-35 default every pre-V4.3 entry reads),
`regional_figure`, `union_leader`, `press_owner`, `judge`, `activist`.
`KIND_METERS` hooks the non-political kinds to EXISTING meters — grievance
(`ns.unrest_pct`, [[unrest-model]]), press_freedom ([[media-model]]), judicial
independence ([[judiciary-model]]) — and **no second meter is built**: the
Victoria-3 collective escalation (Passive→Agitating→Protesting→Rioting) is
unrest's own ladder with a person's face on it. `characters.gd` READS these and
never writes them. A kind with no meter and no political lever is a load error
by test, so a seventh kind must declare where it plugs in.

### 14.5 Acts land on existing machines

**Four acts shipped this block** (resign, defect, challenge, brief_against —
`ACT_KEYS`); the table's "Demand a portfolio" and "Endorse / refuse" rows
DID NOT — the want feed exists (a portfolio want prices through satisfaction
and the grudge ladder) but the verbs were cut for scope, and they belong to
whichever block builds the dismissal/endorsement surfaces.

| Act | Landing site | Never touches |
|---|---|---|
| Resign (office-holder) | office slot cleared + `Government.penalise_blocs` | cabinet effectiveness math (a portfolio stays party-held — the mechanism; the register persons it) |
| Defect | `person_party_override` + card + bloc_offset price | `seats_by_party` (elections' to write; the seat follows the whip) |
| Leadership challenge | `party_leader_override` + standing contest | party content, `seats_by_party` |
| Brief against / leak | bloc_offset through **the ONE applier** (`Legislature.apply_effects`) | a second approval writer |
| Demand a portfolio | want + grudge (feeds resign/challenge) | cabinet.gd's assignment rule |
| Endorse / refuse (election) | bloc_offset-priced, campaign-visible card | elections.gd internals |
| Sponsor / oppose a programme entry | reads `Programme`; a conclusion pays through the on_* effects ([[programme-model]] §V4.1's lobbying channel) | a new channel |

`characters.gd` is a leaf: character_constants + legislature (the applier) +
government (penalise). Tick order **after `Cabinet.tick_month`, before
`Elections.tick_month`** — wants read Opinion-settled state, acts price
bloc_offset that Opinion reads next month, and Elections, the stamp pair's
only writer, still runs last. Pinned by a source-scanning test.

### 14.6 The bands — DECLARED, swept twice, and what the whole-branch review changed

Written before the probe ran (the project law); `tools/characters_probe.gd`
measures, this section records. The first sweep found two machine defects;
the whole-branch REVIEW (PR #44, round one) found two more the probe had
masked — and both rounds' verdicts are the record:

- **P1: PASS — 0 acts in an idle 168-month term** (band ≤ 2), after the
  first sweep's failure (7 briefs by people whose wants were denied by the
  STARTING world) bought the edge-trigger: a want that TURNS denied writes
  one pulse, a want that stays put writes nothing. V4.0's
  prices-the-inherited-cycle defect, found in a person's shape.
- **P2: the honest split — the brief rung is LIVE, the higher rungs are
  CONTENT-BOUND.** The first ship's channel was ARITHMETICALLY DEAD (pulses
  +0.02 against decay −0.05 — no grudge survived the month it was written —
  and NO negative loyalty writer, so resign's floor was unreachable), which
  the first probe's injection-masked P2 hid; the review's C2 found it. The
  re-derivation: decay 0.008 (a standing denial nets +0.012/month), the
  brief's own GRUDGE_BRIEF_RELIEF valve (0.012 — exactly one month's single
  denial, so a lone ally leaks for ever without escalating), and the
  LOYALTY_ACT_COST the briefer pays (the walk's other end: four briefs from
  neutral reach the resign floor). Measured on the re-swept reachable
  fixture (meters flipped to denied at month 24): **4 distinct briefers
  fire; challenges and resignations do NOT, because escalation needs
  TWO-PLUS simultaneous denials and no authored person carries more than
  one METER want** — the valve pins a single denial at the rung its serves,
  which is the envelope invariant working as designed. The higher rungs go
  live the day content authors multi-denial people or a later block builds
  the dismissal verb. NOT the first ship's silence: the ladder is
  reachable, the content is not yet wide enough to climb it.
- **P3: PASS — measured** over both runs' ledgers (every fired act belongs
  to a person the meters denied; the gates read the register).
- **P4: bounded by construction** — every act prices through
  `Government.penalise_blocs`, NEGATIVE by the constants' own convention
  (the review's C1: the first ship's three prices were POSITIVE, so an act
  of betrayal RAISED approval — found by the every-authored-penalty-is-
  negative convention, fixed by declaring the prices negative at the
  constants); the accumulator clamps and the opinion model smooths.
- **P5: PASS — no rand() in characters.gd**, pinned by
  tests/test_characters.gd's two-identical-states check.

### 14.7 Refuses carried forward from the tier

Dynasties, marriage, inheritance, lifespans, the leader's personal wealth.
Refused HERE as well: seat movement by defection, a second
grievance/press/court meter, per-person relations graphs — loyalty is to the
player, one edge, not a matrix ([[v4]] §V4.5 owns the nation-to-nation
relations channel).

### 14.8 As built (2026-09-18) — shipped, harvested, and what owes an eye

The block shipped on `v4.3-people` (9236f48 → c52c7a7): the schema, the six
registers (the planned five plus `person_want_state`), the machine, the
1,595-person bench, the surfaces, the V3.7 wall AND the bench wall
harvested (2,206 rasters, zero people without art). Two machine defects the
band probe found are recorded in §14.6 (the edge-trigger and the grudge
floor); two more the whole-branch review found (the dead channel, the price
signs) are fixed in the same section. The re-baseline re-run is
[reports/v43-rerun-prediction.md](../reports/v43-rerun-prediction.md) —
bit-identical first, then act-lines-only (two briefs in `managed_censors`,
the regime built to deny them) after the fixes.

**WHAT STILL OWES A HUMAN:** the AUTHOR's face verdict — the contact sheet
(`.superpowers/sdd/frames/v43_wall_contact_neutral.png`) and the
confidence-marked counterpart review table
(`reports/portrait_counterparts_review.md`); rejects go through
`python tools/curate_references.py --reject <pids>` and the regenerate
path. The GUI verification of the PANELS is done (the People panel
photographed live at `.superpowers/sdd/frames/v43_people_panel.png`); the
FACES are the only unjudged surface.

**Portrait tiering as shipped:** met cast = `bench: false` (the V2.3
register, five emotions, committed), bench = `bench: true` (single neutral,
committed). The flag is on `Person` (the eighth field, an art-logistics
marker argued at the field) and read by `tools/portraits_generate.py`
(`--bench-neutral-only`) and `tests/test_portraits.gd` (tier-aware
completeness) — one flag, three readers, no list. The bench generator's
`--regen-wants` rebuilds bench want lists when the candidate MIX changes
(the meters-first re-mix needed it); the 213 originals' wants are authored
content and never regenerate.

**The standard review's round (2026-09-20) — two machine fixes, five record fixes, both
machine fixes proven harness-silent.** The /code-review standard pass at `72ad3dd` scored 16
candidates and kept 7 at ≥80. The two machine finds, fixed and pinned:

- **A completed programme entry counted as ALIVE (score 92).** `_programme_entry` scanned the
  all-terms register with no term gate and accepted `status == "complete"`, so an
  oppose-stance author of any completed entry read their want denied for ever and the C2
  channel billed the standing denial (+0.012/month) to the end of the run — the
  priced-forever class the ownership latch exists to refuse, reached not by a dropped save
  but by the machine's own comment lying about its code. Measured content: 1,103 of 2,237
  programme wants are oppose; 816 people carry 2+ standing wants. Fixed: the read is
  term-gated (`chosen_term == ns.terms_served`, the `Programme.this_term()` comparison
  inlined to keep the leaf's preloads untouched) AND alive-only (`status == "active"`); the
  comment now states both gates. Pinned by `test_characters`'s
  `_check_programme_want_is_term_scoped_and_alive_only` (not chosen / active this term /
  completed this term / active past term).
- **A fired challenge never reached the premiership (score 85).** The challenge act writes
  `party_leader_override` and nothing else; `Government._describe` filled `pm_person_id`
  from the AUTHORED edge (`government.gd`'s `by_id[pm_party_id].leader_person_id`, and the
  incumbent branch restored the start-of-game record), so the next election or fall
  reinstated the person the player watched deposed — the resurrected-rival outcome the
  SAVE_VERSION 36 argument refuses for dropped saves, reproduced by the machine itself.
  `_clear_office`'s comment claimed the refill read the live leadership; now it does:
  override first, then the start-of-game special case, then the authored edge, in
  `_describe` (the one funnel all three formation builders share). `events_panel.gd`'s
  largest-party-leader line reads override-first too (the second surface the find named).
  Pinned by `test_characters`'s `_check_challenge_reaches_the_premiership` (override names
  the challenger; clearing it restores the authored path exactly).

**The re-run obligation, discharged by structure plus measurement instead of a two-hour
double batch.** The harness (`tools/balance_probe.gd`) never references Programme — grep
proves no regime ever chooses an entry, so `ns.programme` is `[]` every month of every
regime and the term gate cannot change any read there; the override register is written
only by the challenge act, and the branch's recorded act inventory (the V4.3 re-run's
verdict) shows challenges never fire in the harness. Empirical half: `hands_off` and
`managed` (the regimes that elect and form governments every term) run byte-identical
against a `72ad3dd` worktree — `reports/stdrev/` holds both sides. The other five finds are
records, not machines: §14.2's trait table rewritten to the shipped constants (the
constants' header already claimed the table was corrected; now it is), the
`LOYALTY_ACT_COST`/`GRUDGE_ACT_RELIEF` paragraphs naming the right valve, the six-register
comment sweep (nation_state headers, duplicate/from_dict, game_state's bump-timing note,
the tests), and the want voice moved to `person_card.gd`'s shared `STANCE_LABEL` /
`object_text` so the panel and the card cannot print two renderings of one want (the
panel's private copies deleted). `tools/characters_probe.gd.uid` staged (the U5b gotcha).
Suite 87/87 with the two new checks.

---

Related: [[index]] · [[cabinet-model]] · [[calendar-model]] ·
[[fictionalization]] · [[transition-model]] · [[government-model]] ·
[[data-architecture]] · [[v1]] · [[ROADMAP]]


