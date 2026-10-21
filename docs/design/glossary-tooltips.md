---
title: Glossary tooltips — making the game instructive
tags:
  - design
  - ui
---

# Glossary tooltips — making the game instructive

The author's idea (2026-10-21, verbatim): "le jeu doit être instructif, certains
mots clefs ou expressions seront soulignés en pointillés, en passant la souris
dessus, un tooltip s'ouvrira pour expliquer ce que ça veut dire".

This page is the design: which terms, how they are stored, when one is marked,
how the tooltip behaves, where the work lands, and the proof the builders and QA
must show. It owns no code. Interface builds the mechanism, Content builds the
table, and the definitions below are the designer's.

## Sources and labels

- Every definition cites the `docs/*-model.md` section it summarises, by its
  heading (never a line number: those files change). Labels: **MEASURED**,
  **INFERRED**, **OPINION**, as in [[v5.0-replay]].
- The raw material: the author's V5.0 complaints ([[v5.0-replay]]), the V5.2
  decision map ([[v5.2-spec]]), [[glossary-fr]], and the text the player reads
  (`data/` rows and the msgids of `data/i18n/fr/ui.json`).
- **The counts are MEASURED** by a read-only script (kept in the session
  scratchpad, not committed) over `main` at `1c663abb` on 2026-10-21. It counts
  whole-word, case-insensitive matches of about 150 candidate terms in 782 UI
  msgids and in the player-facing string fields of `data/` (818 event strings,
  242 law strings, 232 party strings, 74 programme strings, and the rest).
  UI text not yet in `ui.json` is not counted.

## What exists today

- **MEASURED (grep, `src/ui`):** 129 `Label.new()` against 1 `RichTextLabel.new()`
  (the dev console). Nothing the player reads can carry a marked term today.
- **MEASURED:** the prose primitive is `PanelKit.line()` (`src/ui/panel_kit.gd`),
  a word-wrapped `Label`, with 309 call sites in 30 files. The other prose sinks
  are the card body (`src/ui/message_stack.gd`) and the event text
  (`src/ui/events_panel.gd`). **So one primitive carries nearly all the prose**,
  and converting it is the bulk of the work (see "Where it lands").
- **MEASURED (engine source, `godotengine/godot` tag `4.7.2-stable`,
  `scene/gui/rich_text_label.cpp`, `_draw_line`):** a `[hint]` tag is underlined
  with `draw_dashed_line()`, dash length `MAX(2.0, underline_width * 2)`, in the
  **font's colour** with its alpha scaled by the theme's `underline_alpha`. A
  `[url]` (meta) tag is underlined with a solid `draw_line()`.
- **From the class reference** (fetched through the godot-docs server, whose
  engine version could not be confirmed): `RichTextLabel` has `hint_underlined`,
  `meta_underlined` with `META_UNDERLINE_NEVER / ALWAYS / ON_HOVER`, the signals
  `meta_hover_started`, `meta_hover_ended` and `meta_clicked`, and `[u color=…]`.
  **There is no dotted or dashed style for `[u]`, and no public per-glyph
  rectangle** (no `get_character_bounds`).

## The term list — 48 entries, ranked

Three gates for every entry. It appears in text the player reads (the count),
it serves a decision the player makes (an existing verb, or the V5.2 map), and
a model section defines it. A high count alone does not qualify: "president"
(70) and "minister" (66) are names of roles, not concepts, and are folded into
one entry (48). Terms the player never reads (`bloc offset`, `output gap`,
`service quality`: 0 each) are out, however central to the model.

The rank is: **tier 1**, a term the author was lost on in V5.0, or the lever
behind such a complaint; **tier 2**, a term on a decision the player makes
every term; **tier 3**, context a decision reads.

Each definition is the one-line text (English; French is parked for Content).
The live value, where there is one, is what the UI already shows (see rule L1).

### Tier 1 — where the author was lost

| # | Id | Term | Count | Why it is in | Definition | Live value | Model section |
|---|---|---|---|---|---|---|---|
| 1 | `programme` | programme | 50 | R5, "cannot register anything to the agenda" | The plan you choose for a term: a set of measures with a goal and a deadline. It is offered only on the first day of a term, before the clock runs; completing it pays, failing it costs. | your programme and its progress | [[programme-model]] §2 "The field contract" |
| 2 | `approval` | approval | 9 | R7, the portrait's mood reads approval | How much the voters back you: each voter bloc's satisfaction with the issues it cares about, averaged by the bloc's size. It moves a quarter of the way to its target each month. | the headline poll | [[opinion-model]] "Approval" |
| 3 | `poll` | poll | 13 | R7: what the mood icon actually shows | What you see of approval. The true figure is never published; a poll adds noise of up to 3 points either way, redrawn each month. | the headline poll | [[opinion-model]] "Polling noise" |
| 4 | `state_stake` | stake (in a firm) | 4 | P12, nationalisation "?" | The share of a firm the state owns. Buying more (nationalising) is paid from the debt at a price set by the firm's output, and the state then takes that share of its dividends. | the firm's state share | [[companies-model]] §20-22 (V1.4c) |
| 5 | `embassy` | embassy | 1 | R6, embassies offered where they exist | A resident mission in another capital. Every roster state already holds one in every other, except pairs with no diplomatic relations, so opening one is offered only where none stands. | whether you hold one there | [[diplomacy-model]] "The embassies that already exist (V5.1-0d)" |
| 6 | `spending` | spending (a budget line) | 23 | P3, "budget levers broken" | A budget line, as a share of GDP. Moving it changes the service the voters feel and the deficit; the forecast shows the next 24 months. | the line's share of GDP | [[economy-model]] "Budget"; [[cabinet-model]] "Effectiveness multiplies the delta, not the level" |
| 7 | `tax_rate` | tax rate | 6 | P3, the other half of the levers | The rate of one of the five taxes. Raising it brings revenue and costs the blocs that weigh that tax. | the rate | [[tax-model]] §3 "Brackets"; [[opinion-model]] "Issues" |

### Tier 2 — the decisions of every term

| # | Id | Term | Count | Why it is in | Definition | Live value | Model section |
|---|---|---|---|---|---|---|---|
| 8 | `deficit` | deficit | 20 | the budget's bottom line | Spending minus revenue in a year, as a share of GDP. A deficit adds to the debt; the voters who care about public finances count it. | deficit, % of GDP | [[economy-model]] "Budget" |
| 9 | `debt` | debt | 21 | sets the yield | What the state owes, against GDP. Its level sets the bond yield, and its interest is paid from the budget. | debt, % of GDP | [[credit-model]] §1 "What stays anchored"; §7 "The price is an existing line" |
| 10 | `bond_yield` | bond yield | 2 | the price of the debt | The interest rate the markets charge you, read from the debt each month; never stored. | the yield | [[credit-model]] §5 "What the yield reaches" |
| 11 | `credit_rating` | rating | 2 | a downgrade is news | A letter band read off the bond yield. A downgrade is the yield crossing into a worse band. | the rating | [[credit-model]] §6 "The rating is one extra read" |
| 12 | `gdp` | GDP | 50 | every share is of it | The economy's yearly output, in billions of euros: the sum of its three sectors. | GDP | [[economy-model]] "Scope and units" |
| 13 | `growth` | growth | 13 | the jobs issue rides it | How fast GDP rises in a year. Trend growth is read off the nation's sector mix (France's is about 1.3 %); the business cycle and your budget move actual growth around it. | growth, and the trend | [[economy-model]] §1 "Trend growth", §4 "Actual growth" |
| 14 | `unemployment` | unemployment | 16 | workers weigh it most | The share of the workforce without a job. It falls when growth beats the trend and drifts back toward a structural rate. | unemployment | [[economy-model]] §6 "Unemployment" |
| 15 | `inflation` | inflation | 3 | the thirteenth issue | How fast prices rise in a year. Above its anchor it drags growth, and the voters judge you on it. | inflation | [[inflation-model]] §4 "Price one", §5 "Price two" |
| 16 | `business_cycle` | cycle / recession | 10 | explains a bad year | The economy's own swings, set by the date: partly shared by every nation, partly each nation's own, and the same in every game on the same date. A wave you cannot stop, only ride. | none | [[cycle-model]] §2 "The generator" |
| 17 | `voter_bloc` | bloc (of voters) | 32, both meanings | who approval is made of | One slice of the electorate (workers, pensioners, urban, rural, business…), each with its own issues and weights. | the bloc's approval | [[opinion-model]] "Blocs" |
| 18 | `issue` | issue | 2 | what the blocs judge | One of the thirteen things the voters judge you on: jobs, growth, taxes, health, public finances and the rest. | none | [[opinion-model]] "Issues"; "The thirteenth issue" |
| 19 | `salience` | salience | 3 | why a fix bought nothing | How much a bloc cares about an issue now. The news moves it, and fixing something nobody cares about buys nothing. | none | [[opinion-model]] "Salience"; "Salience moves with the news" |
| 20 | `majority` | majority / seats | 45 | every vote | A majority is more than half the Assembly's seats: 289 of 577 in France, where no two parties reach it, so a majority government is at least three parties. | your coalition's seats | [[government-model]] "Censure"; [[legislature-model]] "Vote resolution" |
| 21 | `coalition` | coalition | 6 | who governs | The parties that form the government: the nearest group in ideology that reaches a majority. | the coalition | [[government-model]] "A coalition is a point in ideology space"; "The formation search" |
| 22 | `censure` | censure | 11 | how a government falls | The Assembly's vote to bring the government down. In France a minority government falls only if the left and right opposition vote together. | none | [[government-model]] "Censure" |
| 23 | `article_49_3` | Article 49.3 | 7 | a verb with a hidden price | Adopts a bill with no vote taken. The Assembly may answer with a censure motion; forcing costs approval whether or not the motion carries. | when it can next be used | [[government-model]] "Article 49.3" |
| 24 | `party_discipline` | discipline / rebels | 5 | why a bill failed | How tightly a party votes its line. Members far from that line may rebel, voting as they would with no whip on them. | none | [[discipline-model]] "Rebellion is a seat-level split of scalars that already existed" |
| 25 | `dissolution` | dissolution | 6 | the snap election | Dissolving the Assembly calls an election a few months away. It cannot be called while one is pending, during a lockout, or just before a scheduled vote. | months of lockout left | [[dissolution-model]] "What the command does" |
| 26 | `referendum` | referendum | 8 | a second hurdle, not a shortcut | A second ratification stage, not a bypass: a bill the Assembly passed must also win the popular vote. Withdrawing one has a price. | a pending referendum | [[referendum-model]] §2 "A referendum is a second ratification stage, not a bypass"; §5 "The price" |
| 27 | `amendment` | constitutional amendment | 18 | the hardest law | A change to the constitution. It needs the nation's own higher threshold, and Article 49.3 cannot force one. | the threshold | [[amendment-model]] "The threshold is per-nation data, not a global constant"; "Article 49.3 cannot force a constitutional amendment through" |
| 28 | `second_chamber` | second chamber | 3 | why a law is held | The upper house (France's Senate), not elected by the national vote. It can hold a bill for a time, and Article 49.3 is the way past it. | a held bill | [[upper-house-model]] §2, §8 "The hold is pure time", §10 |
| 29 | `term_limit` | term limit | 2 | the end of the run | The most terms the head of state may serve (two for France). Reaching it ends the presidency, as losing does. | terms served | [[election-model]] "Win and lose"; [[playability-audit]] V1 |
| 30 | `cabinet` | cabinet / portfolio | 10 | who spends | Each of the five spending lines has a minister from a coalition party; a competent one makes your changes to that line count for more. | the minister | [[cabinet-model]] "Portfolios are the five spending lines"; "Effectiveness multiplies the delta, not the level" |
| 31 | `reshuffle` | reshuffle | 5 | a verb with a price | Giving a portfolio to another coalition party. It costs approval every time, whether or not the new holder is better. | reshuffles this term | [[cabinet-model]] "The player command" |
| 32 | `pledge` | pledge | 3 | a promise with a bill | A campaign promise. It buys votes in the election you stand in, and costs every month of the next term if it is broken. | open pledges | [[pledge-model]] §4 "One verb, two prices, two times" |
| 33 | `corruption` | corruption | 2 | why services decay | How much of what you spend fails to reach the service. A corrupt state's services decay even when spending is unchanged. | the readout on the Overview | [[society-model]] §4 "Corruption multiplies the STOCK, not the delta" |
| 34 | `unrest` | unrest / grievance | 9 | strikes come from it | A grievance stock built from the state of the country (inequality, a muzzled press and weakened courts among its terms). Above its thresholds the unions act. | unrest | [[unrest-model]] §1; [[media-model]] §6; [[judiciary-model]] §7 |
| 35 | `relations` | relations | 4 | gates every treaty | How warm a pair of nations is. Acts raise or lower it, and some verbs need it high enough (an embassy needs 50). | relations with this nation | [[diplomacy-model]] "The first state that is neither per-nation nor global"; "The action content type" |
| 36 | `state_visit` | state visit | 1 | the key to treaties | A trip that books days in your diary and opens a meeting window with that leader for a year; the treaty-class verbs need it. | the meeting window | [[calendar-model]] §12 "The meeting window" |
| 37 | `council` | council | 28 | the Union decides there | The Union's decision body. A proposal divides by qualified majority or unanimity, and you can lobby and bargain for votes. | the next division | [[orgs-model]] "V4.5 — the council, contested"; [[bloc-model]] §4 "The council" |
| 38 | `bargain` | bargain / IOU | 8 | how you buy a vote | Paying a member for its vote: a favour (relations), aid (a budget line) or a vote trade, an IOU you owe at the creditor's next division. | your open IOUs | [[orgs-model]] "V4.5 — the council, contested" (Bargains — three currencies) |
| 39 | `desk` | desk | 11 | where decisions wait | Where events wait for your answer: four at most, the most severe first. | events waiting | [[events-model]] §5 "The machine" |
| 40 | `diary` | diary | 5 | time is the scarce thing | Your calendar. A booking occupies days, travel included, and two bookings cannot overlap. | the next booking | [[calendar-model]] §12 "The block, and the scarcity that is occupancy" |

### Tier 3 — context a decision reads

| # | Id | Term | Count | Why it is in | Definition | Live value | Model section |
|---|---|---|---|---|---|---|---|
| 41 | `treaty` | treaty / agreement | 13 | trade between two | An agreement between two nations that changes the trade between them; the partner must accept it. | agreements in force | [[trade-model]] §4 "Agreements — no new content type"; [[foreign-policy-model]] §3 "Whether a partner signs" |
| 42 | `tariff` | tariff / sanctions | 20 | a measure aimed at one nation | A measure aimed at one nation: it cuts trade with them, collects a little revenue, and they may retaliate. | measures in force | [[coercion-model]] §1, §3 "What a tariff collects", §6 |
| 43 | `ratification` | ratification | 3 | a treaty's second test | A treaty the council carries must pass every member's own assembly; one rejection sinks it for all. | none | [[orgs-model]] "V4.5 — the council, contested" (Ratification at home) |
| 44 | `subsidy` | subsidy | 6 | the industry verb | Paying a firm to grow its output and jobs. The bill is a spending line, and the blocs notice it. | the subsidy bill | [[companies-model]] §5 "What a subsidy costs, and who notices" |
| 45 | `power_grid` | plant / grid | 34 | where to build | A power station serves the national grid, so it helps the whole country, not only its region; where you site it sets its connection cost and local opposition. | your plants | [[energy-model]] §3 "The grid is national"; §4 "Two sited halves" |
| 46 | `press_freedom` | press freedom | 1 (+18 "press") | a dial with a price | How free the press is to frame you. Restricting it changes the coverage and adds to unrest. | press freedom | [[media-model]] §6 "Press freedom: two prices" |
| 47 | `judicial_independence` | courts / judicial independence | 18 | why a law was struck down | How far the courts can go. A law whose reach exceeds the court's tolerance is struck down. | judicial independence | [[judiciary-model]] §4 "The tolerance form"; §6 "The gate is a lock with a key you can buy" |
| 48 | `heads` | head of state / head of government | 11 | who is who | France has both: the President (head of state, elected on its own clock) and the Prime Minister (head of government, formed from the Assembly). Their two clocks differ. | the holders | [[government-model]] "Two clocks" |

- **Ready for V5.2, not marked yet:** loyalty, grudge, standing (a person's),
  knowledge, rapport ([[people-model]] §14.1; [[v5.2-spec]], "The registers").
  They join the table when V5.2's scenes print them.
- **OPINION:** 48 is inside the 30–60 the task asked for. Fewer leaves the
  economy unexplained; more crosses the noise line before the rules below
  even apply.

### Two-meaning words

The inventory found three words that mean two things in this game. Each gets
**separate entries, marked by hand**, never by matching the word:

| Word | Meaning A | Meaning B |
|---|---|---|
| bloc | a slice of the electorate (entry 17, [[opinion-model]] "Blocs") | the Union as one object (the council's rules, [[bloc-model]] "The fourth kind of state") |
| stake | the state's share in a firm (entry 4, [[companies-model]] §20-22) | how much a partner weighs in foreign policy ([[foreign-policy-model]] §1 "Stake") |
| standing | a person's political weight ([[people-model]] §14.1) | a nation's standing with third parties ([[foreign-policy-model]] §5) |

## The data model

A table in `data/` (Content's), proposed as `data/glossary/terms.json`:

| Field | Required | What it holds |
|---|---|---|
| `id` | yes | a stable key, `snake_case` (the ids above) |
| `term` | yes | the word as shown, English |
| `definition` | yes | one line, at most about 200 characters |
| `body` | no | a longer text, shown under the line when the tooltip is locked |
| `see_also` | no | entry ids; the loader refuses an unknown one |
| `live` | no | the name of a **shown** value in a closed table the UI owns (rule L1) |
| `model` | yes | the model doc and section the definition summarises, e.g. `opinion-model#Approval` |

- **Translatable through `Strings`**: `Strings.row("glossary", id, "term" |
  "definition" | "body", english)` ([[localisation]]). English first; French is
  parked until Content picks it up.
- **The loader refuses** an unknown `see_also` id, an unknown `live` name and a
  missing `model`, at load and loudly. The precedent is the want objects:
  "Unresolvable = load error, loud" ([[people-model]] §14.3).
- **Rule L1 — a live value is what the UI already shows.** Approval is the poll,
  never the hidden figure: "Approval is not published. The player sees a poll"
  ([[opinion-model]] "Polling noise"). The yield and the rating are reads, never
  stored fields ([[credit-model]] §6). So `live` names a reader the UI already
  calls (the headline poll, `Credit.yield_pct`, `Credit.rating`), never a
  `NationState` field, which would let a tooltip leak what the fog hides.

### Marking a term in text

- **Recommended: markup in the source text.** A data row or a UI string carries
  `[g=approval]approval[/g]` around the word. It is deterministic, and it is
  the only way to tell the two meanings of "bloc" apart.
  - **Its cost (INFERRED):** a marked msgid is a new msgid. Its French row in
    `data/i18n/fr/ui.json` or the `data/i18n/fr/*.json` tables must be
    re-keyed with the same markup, and the i18n lint must learn the tag.
- **The alternative: a runtime pass** that wraps the first occurrence of each
  entry's translated `term`. No msgid churn, but it cannot disambiguate, so the
  three two-meaning words would be excluded.

## The noise rules

- **N1 — First occurrence only.** A term is marked once per text block (a card,
  a section of a window, a tooltip), at its first occurrence.
- **N2 — At most two per paragraph, three per block.**
- **N3 — From the curated list only.** No auto-link of every match; with source
  markup, a term is marked only where a writer put the tag.
- **N4 — Never on a heading, a figure, a button or a clickable row.** A click on
  a marked term locks its tooltip, so a term on a control would eat the
  control's click.
- **N5 — No self-link, no cycle.** A tooltip never marks its own term, nor a
  term already open further up the chain.

**Failure looks like:** half the text underlined, which is the failure the
author would see first.

## The behaviour

| Rule | Value (proposed, OPINION) | Why |
|---|---|---|
| Hover delay | 0.4 s before a tooltip opens | long enough not to fire while the mouse passes over a term on its way elsewhere |
| Grace on leaving | 0.3 s | the mouse must be able to travel from the term into its tooltip |
| Placement | below and right of the term, flipped to fit, clamped to the viewport with an 8 px margin | never off screen, at 1920×1080 or at the 960×540 floor (`WindowMode.MIN_SIZE`) |
| Width | at most 360 px; a long `body` scrolls | fits the 960×540 floor with room for one nested tooltip beside it |
| Nesting | up to 3 levels | as in Crusader Kings III and Victoria 3: a term inside a tooltip opens its own |
| Lock | a click on the term, or holding still 1.2 s, with a thin fill on the plate's edge as it locks | a locked tooltip stays while the mouse moves into it, so a nested term can be hovered |
| Close | moving away from an unlocked chain; Escape or a click elsewhere closes every level | one key always clears the screen |
| Clicks | an unlocked tooltip passes the mouse through; only a locked one takes clicks, and only on itself | a tooltip must never block a click on the world |
| Keyboard and gamepad | Tab cycles the marked terms of the focused window, Enter opens and locks, Escape closes | **UNVERIFIED**: `RichTextLabel` has no per-tag focus, so this is a custom cycle |
| Live value | "Your value: 41 % (a poll, ±3)", with the source named | the fog rule: a figure the player sees with its source ([[v5]], "fog is shown, never silent") |
| Visual | the Bureau plate: near-opaque graphite, an `EDGE` hairline on all four sides, no accent; the underline neutral, never the accent colour | the panel grammar (`AGENTS.md`, UI conventions) |

### Drawing the dotted underline — three paths, all UNVERIFIED until Interface prototypes

1. **`[url=g:id]`, `META_UNDERLINE_NEVER`, and a dashed line drawn by hand.**
   The meta signals give hover and click. But `RichTextLabel` exposes no
   per-glyph rectangle, so drawing under the word needs one, and there is none.
   **Blocked as it stands.**
2. **`[hint=g:id]` for the dashed line, `[url=g:id]` around it for the signals,
   and `_make_custom_tooltip()` overridden to return an empty control** so the
   engine's own one-level tooltip never shows. It is the cheapest, and the dash
   comes free from the engine (the 4.7.2 source above). Two things to prove:
   that the two tags nest, and that an empty custom tooltip suppresses the
   engine's. **The line is drawn in the text's own colour at `underline_alpha`,
   not in `EDGE`.**
3. **A custom text control** that shapes its paragraph through `TextParagraph`
   and the `TextServer` and draws itself, underline included. It gives full
   control and `EDGE` exactly, at the cost of the most code.

- **Recommended (OPINION):** prototype path 2 first, because it reuses the
  engine. Fall back to path 3 if the tags do not nest, or if the author wants
  the `EDGE` colour exactly (author call 1).

## Where it lands, in what order, and the cost

The costs are OPINION (S, M or L, relative).

| Step | Owner | Lands in | What | Cost |
|---|---|---|---|---|
| 0 | Interface | a branch, no merge | the path-2 prototype on one `RichTextLabel`: dashed term, hover, lock, a nested tooltip, the engine tooltip suppressed | S |
| 1 | Content | `data/glossary/terms.json` + its loader check | the 48 entries above, in English | S |
| 2 | Interface | **V5.1-c** (the shell) | the mechanism: a rich line control and the tooltip stack, the card body and the event text converted | M |
| 3 | Interface | **V5.1-d** (the windows) | `PanelKit.line()` returns the rich line, which reaches 309 call sites in 30 files through one primitive; d re-homes every window anyway | M |
| 4 | Content | the `data/` rows and UI strings that carry a term | the `[g=…]` markup, under the noise rules, and the French rows re-keyed | M |
| 5 | Content | `data/i18n/fr/` | the French glossary, when the author un-parks it | S |

- **Not a widening of c without the author's yes:** step 2 is the only one in
  c, and it is the mechanism plus the two sinks c already rebuilds (the card,
  the inbox). The 309 `PanelKit.line()` sites go to d (author call 3).
- **INFERRED risk:** `PanelKit.line()` returns a `Label` today, and a caller
  that uses `Label`-only API breaks when it returns a `RichTextLabel`. Step 3
  starts with a grep of what the 309 callers do with the result.

## The proof, for the builders and QA

| # | Proof | Shape |
|---|---|---|
| P1 | Every marked term resolves, and no entry is orphaned | a test: every `[g=id]` in `data/` and in the UI strings names an entry, and every entry is marked somewhere or is listed in `see_also`; removing an entry turns it red. The loader's refusals above are its first half. |
| P2 | A tooltip fits on screen | at 1920×1080 and at 960×540 (`WindowMode.MIN_SIZE`), nested to depth 3, and under `test_i18n_fit`'s +35 % pseudolocalization |
| P3 | A windowed screenshot of a hovered and of a locked term | a `tools/screenshot.gd` flag, run windowed (`AGENTS.md`: `--headless` draws nothing) |
| P4 | Each definition cites its model section | the `model` field: a check that the doc exists and the heading is in it |
| P5 | The play gate | the author hovers three named terms, **approval**, **Article 49.3** and **programme**, and says, verbatim, whether each one helped |

**Failure looks like:** half the text underlined (N1-N3 broken); tooltips that
only restate the word (a definition with no "what it does" half); tooltips off
screen (P2); a definition that contradicts its model (P4 catches a missing
section, the review catches a wrong sentence).

## The author's calls

Each has the recommendation first.

1. **The underline's colour.**
   (a) *Recommended:* the text's own colour at reduced alpha (path 2): neutral,
   never the accent, and free from the engine.
   (b) The `EDGE` hairline colour exactly (path 3): more code.
2. **How a term is marked.**
   (a) *Recommended:* markup in the source text: deterministic, and it tells the
   two meanings of "bloc", "stake" and "standing" apart; Content re-keys the
   French rows of every marked string.
   (b) A runtime pass over each entry's term: no msgid churn, and the three
   two-meaning words are excluded.
3. **When the prose is converted.**
   (a) *Recommended:* the mechanism, the card and the event text in V5.1-c; the
   309 `PanelKit.line()` sites in V5.1-d, which re-homes every window anyway.
   (b) Everything in c, which widens the shell block.
4. **How a tooltip locks.**
   (a) *Recommended:* both a click on the term and holding still 1.2 s.
   (b) A click only.

## What could not be verified

- The godot-docs server's engine version was not confirmed; the drawing facts
  above come from the `4.7.2-stable` source instead.
- Whether `[hint]` and `[url]` nest on one word, and whether an empty
  `_make_custom_tooltip()` suppresses the engine's tooltip (path 2).
- A keyboard and gamepad path through marked terms (`RichTextLabel` has no
  per-tag focus).
- The counts cover the UI strings that are in `ui.json`; text not yet extracted
  there is not counted.
- Each definition summarises its section as read for this page; the sections
  are long, and a definition can still miss a nuance. P4 checks the citation,
  not the sentence.
