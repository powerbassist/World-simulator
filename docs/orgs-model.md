---
title: Orgs Model
tags:
  - model
  - sim
  - diplomacy
---

# Orgs Model

The supranational organisations: membership as data, one register per council,
one composition rule for the channels several orgs share, and accession and
withdrawal as multi-year domestic fights. Built at V3.2,
generalising what [[bloc-model]] was — the V1.3d machine, hardcoded to the one
EU object — which this doc replaces as the machine's model. bloc-model.md
stands as the one-org record; every number in it that survived the
generalisation is cited here.

Files: `src/sim/orgs.gd` (the machine) · `src/sim/bloc_constants.gd` (the
numbers) · `src/core/org.gd` (the content type) · `data/orgs/*.json` (the
register) · `GameState.orgs` (the registers) · `tools/orgs_probe.gd` (the
measurement).

## The register

`data/orgs/<id>.json` carries: `id`, `name`, `summary`; `members` (nation id →
`seats`); optional `parliament` (next election, term); `council`, `net_transfers`;
the standing prices `relations_bonus` and `trade_bonus`; the fight content
`accession_months`, `withdrawal_months`, `accession_position`,
`withdrawal_position`.

Four orgs ship: **eu** (8 members, parliament, council, transfers, bonuses
15.0 / 0.50), **eurozone** (same 8, no machinery yet), **schengen** (8 + CHE),
**nato** (FRA DEU ITA ESP NLD BEL LUX GBR — AUT neutral, CHE out — council from
this block). The register's real content is the cross-cutting facts the one
hardcoded object could not hold: **GBR is NATO and outside the EU; CHE is
Schengen and outside both; AUT is EU and neutral.**

Membership has TWO answers and the design keeps them apart. `members` on the
content is the authored START, read only at new-game and validation.
`NationState.orgs` is the LIVE truth — what an accession or withdrawal
rewrites — and every reader (the trade weight, resting relations, the
appraisal's outside term, the councils) asks it. A helper that read the content
table at tick time would freeze membership against a fight the player already
won.

## The composition rule (pre-declared before any content existed)

- **Opinion is ONE price.** `ns.bloc_burden` sums every org's rules' breach
  contributions and clamps ONCE at `BURDEN_MAX`; the `europe` issue reads that
  total and nothing else. No second approval number is structurally possible —
  no second channel is touched (V1.5c). **Named bound:** the cross-org clamp
  contact — a nation defying every eu rule gains no opinion price from defying
  a second org's rule. Unreachable until a second rule-carrying org ships
  content; the session that authors one owes the re-measurement (V1.3d's
  rescale precedent, one level up).
- **Transfers are per org.** Each org charges its own base, its own rules'
  transfers, and a fine on its own clamped burden; the budget line is the sum.
  Two clubs each fining their own defiers is the honest reading; the opinion
  price stays one number.
- **External measures are per org**, aimed at that org's outsiders, on the same
  directed keys a player's tariff uses; the first adopted holds the pair
  (coercion-model's one-measure-per-pair bound). Each entry carries the
  adopting org's id, which is what a withdrawal reads to remove exactly the
  org's own measures.
- **Bonuses sum over shared orgs.** Resting relations add Σ shared
  `relations_bonus`; gravity weights multiply by `1 + Σ shared trade_bonus`.
  eu carries the values the old constants held, UNCHANGED — that, and the
  preserved per-org agenda order, is what the bit-identity run proves.
- **Council limits are per org**: `MAX_RULES_IN_FORCE` counts each council's own
  binding rules; each council runs its own two-integer scheduler and agenda
  index.

## Seats

One seats field serves the EP and every council: the parliament org's seats are
the EP's real allocation; a non-parliament council's seats are authored weights
(NATO's are population-shaped, roughly population in millions — NATO decides by
consensus in reality and has no seats; the council machinery needs numbers, and
an invented weight is a number content carries, not one code guesses). The
loader refuses a council whose members all weigh zero: a zero-weight council
can never divide, which is the silent-failure class.

## The fights

A membership fight is **referendum-first, then a negotiation countdown, then
the flip** — someday.md's "multi-year domestic fight" shape. The referendum
machinery is reused whole: `Referendum.announce()` takes any question id, its
11-month campaign is the domestic fight, and losing charges the president the
same way losing an amendment vote does. What is new is only the countdown
(authored per org; eu 24 months, the Art. 50 shape) and the flip:

- `NationState.orgs` gains or loses the id — every consequence flows from that
  one write, because the readers read it live.
- The EP clock follows the parliament org: an acceding nation picks it up, a
  withdrawing one surrenders it. Seats follow automatically because they are
  read live at election time.
- Withdrawal stops the ex-member levying the org's collective measures; the
  measures aimed AT it stand — the common external tariff working as designed
  the day after exit.
- A transfer org's net positions re-derive for every REMAINING member, because
  the mean the formula divides by moved with the roster. The re-derive writes
  live members only: `net_positions()` derives from the AUTHORED table, which
  still lists the nation that just walked out.

**What the flip writes, and what the load path reconciles.** A joiner enters
with the org's authored `accession_seats`, written as LIVE seat state on
`NationState.org_seats` -- the council's division weighs members by it, and the
parliament org's seats are the same read. The content table is the authored
START and lists no joiner; a member whose vote weighs zero is a member in name
only (the pre-merge review's second-class-member finding). The EP clock a
joiner picks up is the authored next election ROLLED FORWARD in whole terms
until it is in the future -- a static date and a mid-run accession would
otherwise write a deadline that has already passed and never vote again.
Membership ends the org's collective measures in BOTH directions: the joiner
stops having the org's tariff levied on it (there is no repeal path that would
ever lift it otherwise), the leaver stops levying it. A transfer org's net
positions re-derive over the LIVE roster -- over the authored roster the
re-derive writes back identical values, a no-op wearing a derivative's clothes.
And because `last_referendum_result` is deliberately not serialised
(`last_project_result`'s case), a game saved in the one-month window after a
vote resolved but before the machine consumed it reloads with the fight ENDED,
membership unchanged -- the honest resolution, no outcome invented, and the
player not stranded. A negotiation-phase fight reloads intact: its countdown
is serialised state.

**The accession and withdrawal positions are MEASURED, not felt.** The first
draft's withdrawal position (econ +0.45, social +0.55) measured yes_share
**0.347** — unwinnable, a locked door rather than a fight, and
`tests/test_orgs.gd` caught it by running the real vote. The shipped positions
were swept on `Referendum.yes_share()` at a neutral-approval new-game and every
authored question sits **0.510–0.523** at rest: winnable by a president the
country does not hate, losable by one it does (`INCUMBENT_SWING` moves both
ways, and a campaign moves turnout).

**Player-initiated only.** The nine never begin a fight — there is no desire
term for membership in any agenda model, and inventing one unmeasured is the
synthetic-appetite shape foreign-policy-model refuses. referendum.gd's own
precedent, pinned by test.

## The two re-runs

**Track (a) — the generalisation — was bit-identical: 1680 of 1680 printed
lines, zero outcome changes**, against a worktree baseline at the pre-session
commit, both sides from worktrees, autoload noise absent (the committed
project.godot carries only DialogueManager). The prediction was written
first and held exactly.

**Track (b) — the fights and the content — was NOT bit-identity, and the
channels were the prediction:**

- (i) The AI agenda's candidate pool grew by `open_embassy` and `foreign_aid`
  (relations-positive acts), so relations paths can move in any run.
- (ii) Moving the 2 % floor to NATO changed the eu agenda rotation (7 → 6) and
  gave NATO a firing council.
- (iii) The fights are player-initiated only, so the accession machine moved
  nothing in an unplayed run.

Measured: 47 of 51 regimes differ, nearly all by 3–5 last-digit lines. The one
large mover and the ONE OUTCOME CHANGE of 99 outcome lines are the same regime:
GBR `managed_abolishes_the_monarchy`, where a 2029 rounding-boundary wobble
(growth +0.00 → −0.00) compounds through the trade-mix channel — trend
+1.32 → +1.30, the openness signature V1.3f's own re-run recorded for GBR —
into GDP 3929 → 3879 by 2037 and a 2039 election flip (33.3 % HELD → 23.3 %
LOST). FRA's regimes wobble last digits only; one coalition seat moves in
`managed_imposes_tariffs` (374 → 375), censures hold in both trees. Suite 80/80
green.

## Deliberately absent

- **No org-side consent for accession.** An admission vote has no material term
  the appraisal can price without a new term type; the domestic referendum is
  the whole gate. Recorded as the absence, not an oversight.
- **No AI desire for membership.** See above.
- **Eurozone and Schengen ship zero-priced.** Their member sets are the
register's content (CHE is the one real difference; a V3.3 tranche with a
non-euro EU member diverges them in data, which is the point of a register).
Pricing one — a trade bonus for Schengen, an inflation or credit channel for
the euro — needs a measured band and a BALANCE_PLAN pre-declaration, not an
opinion. **V4.0 measured the band (E1, 2026-09-14), and the zero price is now
a MEASURED BOUND, not an absence.** Method: the Schengen `trade_bonus` set
directly on the loaded org (the path an authored price would take —
`Trade._raw` reads it through `Org.shared_bonus`), everything else
bit-identical, headline approval read at 60 and at 168 months. At the eu's
own authored magnitude (0.50, the largest co-membership bonus in the
register) the FRA headline moves **+0.01** at 60 months; at the load-time
ceiling `MAX_AGREEMENT_WEIGHT_MULTIPLIER` (2.50) it moves **+0.03** at 60
months and **+0.05** at 168; even a bonus of 5.00 — past the loader's own
bound, run to prove saturation — reads **+0.03** at 60 months, +0.04 at 168.
The response saturates because the only consumer is
`TRADE_OPENNESS_BETA × d_open` inside `potential_shift_pct`, which
`SHIFT_MAX_PCT` = 1.0 clamps and which 60 months of `SHIFT_ADJUST` then
dilutes into a trend figure the growth addend prices at `GROWTH_SCALE_PP`
4.0 — the settled trend delta at the ceiling is **+0.002 points/yr**, so the
headline channel is structurally two orders of magnitude short of the
±3.0 poll-noise floor. **The euro side has no code channel at all**
(`inflation.gd`, `trade.gd`, `economy.gd` read nothing eurozone-shaped; an
inflation or credit channel would be a build, not a price, and this band was
a measurement only). Bound recorded: no reachable Schengen trade bonus
clears the floor; the euro question stays closed until a session builds a
channel AND measures it against this same floor. Either way, the
orgs-model trigger priced here is discharged.
- **No repeal of a rule in force** (bloc-model's rule, unchanged). The player's
  answer to a rule they hate is to defy it and pay, or to leave.
- **No war.** NATO here is an org with a council and a spending floor;
  Article-5-as-domestic-politics is where V1.3f's cut stands.

---
## V3.3 addendum: the council at 27, and what the seats arithmetic did

The roster grew and the council's content had to answer for it. Three facts,
all measured on the real tally machinery (the session's probe, run per
proposal per player-choice):

- **The eu seats table is the real 2024-29 allocation and sums to exactly
  720** over 27 members; eurozone is 17, schengen 26 (IRL the opt-out, CYP
  not yet admitted -- both exclusions named in the file), nato 24.
- **The contribution ceiling re-derived on its own placement rule**: 1.20 was
  "just above Luxembourg's output" on the eight-member mean; the EU-27 mean is
  poorer, LUX computes 1.339, so the ceiling moved to 1.35 and the test that
  forbids a bound-sitting member stays green.
- **One agenda position was re-authored, on a measurement**: at the old
  positions the 27-seat council produced NO division in which the player's
  abstention differed from her opposition -- constructive abstention was
  unreachable on every shipped proposal, which is the decorative-verb failure.
  `debt_reduction_rule` now sits where its division lands inside the player's
  pivotal band (385 for of 639 cast): her abstention lets it carry, her
  opposition blocks it, her backing passes it. `stability_pact` stays where
  V1.3d put it -- uncarryable by the player is the point of a council.

---
## V4.5 — the council, contested (clauses declared BEFORE the machine, 2026-10-14)

The deterministic rotation becomes a fight. Plan of record:
`docs/superpowers/plans/2026-10-14-v4.5a-council-machine.md` (V4.5a, the machine)
and V4.5b's (content, probe, panel). Module: `src/sim/council.gd`; ratification:
`src/sim/ratification.gd`; numbers: `src/sim/council_constants.gd`.

**The inertness clause.** Every V4.5 behaviour is gated on content the V4.4
register does not carry: an org with no `presidency` keeps the rotation, a
proposal with no `decision` reads its org's `decision_rule` (default `qmr`, the
V1.3d tally), a proposal with no `sponsor` lobbies nobody, and bargains, tabling
and ratification need a player command or a unanimity proposal. So V4.5a's
re-run is predicted BIT-IDENTICAL; one moved line is a defect.

**Decision classes.** `qmr`: the cast-seat share at `PASS_SEAT_FRACTION`,
unchanged. `unanimity`: carries iff no member votes against and at least one
votes for — abstention does not block (the real Council's constructive
abstention, which keeps the player's third vote option alive in the new class).
Unanimity IS the treaty class: it carries to ratification, QMR binds directly.

**Presidency.** Authored per org: an `order` of member ids, a term in `months`,
and the `anchor` date order[0]'s term began. The chair is DERIVED from the
calendar (no state, nothing to save), skipping a nation that has left. An AI
chair opens the eligible proposal it supports most (ties: authored order); a
human chair opens the one it chose with `Orgs.set_agenda()`, or the rotation if
it chose nothing. Any member may TABLE a proposal by paying the chair
`TABLE_RELATIONS_COST` relations; a tabled proposal opens first, sponsored by
whoever tabled it.

**Sponsors.** A proposal's authored `sponsor` is a NATION; the sponsor's face is
that nation's live head of government (`ns.pm_person_id`), and the person's
authored `ambition` is the sponsor's DRIVE — the one person state that both
prices the sponsor's lobbying and how much it minds the player's vote (no second
ambition meter). An AI sponsor lobbies at open: each member short of
`SUPPORT_THRESHOLD` by no more than `drive × LOBBY_SWING_PER_DRIVE` is swung by
exactly its gap (+`LOBBY_MARGIN`), paid in the sponsor's relations with it at
`LOBBY_RELATIONS_PER_SWING` per point. At the division the sponsor thanks a
human member who backed it (`SPONSOR_THANKS × drive`) and resents one who
opposed it (`SPONSOR_SNUB × drive`); abstention costs nothing.

**Bargains — three currencies, one per member per division.** The player asks a
member to vote `for` or `against`, paying in: a FAVOUR (relations with that
member, `FAVOUR_RELATIONS_COST`, refused below `FAVOUR_MIN_RELATIONS`, swing
`FAVOUR_SWING`); AID (`AID_PCT_GDP` of the player's GDP on the org's transfer
line for `AID_MONTHS`, swing `AID_SWING` — money is the price, through the
budget line orgs.gd already sums); or a VOTE TRADE (an IOU, swing `IOU_SWING`:
the next division the creditor sponsors, the player owes a `for`; anything else
costs `IOU_BETRAYAL` relations; unpaid IOUs lapse after `IOU_EXPIRY_MONTHS` + 1 register ticks -- the
register counts 60..0 inclusive, the same rule that pays aid in exactly
`AID_MONTHS` months).
A swing enters the member's vote as an additive on its appraisal; the
division's recorded reason names the bargain only when the bargain flipped it.

**Ratification at home.** A carried unanimity proposal is not adopted: every
member whose politics the game simulates (`has_budget`) must ratify it within
`RATIFY_WINDOW_MONTHS`. The ratification is a BILL — `Ratification.treaty_bill()`
builds a `Law` on the proposal's own position, `majority: simple`, and the
player's assembly divides it through `Legislature.resolve_vote()` (and the upper
chamber where it holds an absolute veto); rebels are priced by
`Discipline.penalise_rebellions()` exactly as for any bill. No second resolver.
All ratify: the treaty is adopted. One rejects, or the window closes: the treaty
falls FOR EVERY MEMBER (2005's shape), the sponsor charges the failing member
`RATIFY_FAIL_SPONSOR × drive` and every other member `RATIFY_FAIL_MEMBER`.
AI members that voted for it are taken to have ratified — they have no assembly
the game runs; recorded as a bound, not modelled.

**Bands owed (V4.5b's `tools/council_probe.gd`, declared here, measured there):**
- C1 the player decides — with bargains available, the share of divisions over
  a term the player's spending changes the outcome of: band 0.20–0.50 (a council
  you can never move is decorative; one you always move is a second legislature).
- C2 spending is not free — a player who bargains every division ends a term with
  mean relations to the bargained members at least 5 points below one who never
  bargains.
- C3 unanimity is reachable — at least one authored unanimity proposal carries
  on lobbying alone in a 168-month idle run, and at least one does not.
- C4 ratification is a fight — at a neutral-approval new-game, the FRA assembly's
  treaty forecast sits inside [40 %, 60 %] yes for at least two authored treaties.
- C5 the BURDEN_MAX re-measure — raw cross-org burden at total defiance with the
  V4.5b register, recorded with its number against the V3.5 1.33.

**The V4.5a re-run, PREDICTED 2026-10-14 before it ran:** BIT-IDENTICAL on every
`tools/balance_probe.gd` regime, both sides from worktrees (base `main` at
9e11165, candidate `v4.5-council`). The inertness clause is the whole argument:
the shipped register carries no `presidency`, no `decision`/`decision_rule`
and no `sponsor`, and no regime issues a council command, so every new path
collapses to V4.4's (swing +0.0, aid line +0.0, empty registers skipped). One
moved line outside the per-machine `listening on 127.0.0.1` noise is a DEFECT.

**HELD, 2026-10-14:** 1690 of 1690 printed lines identical across all fifty
regimes (50 `invariants: OK` blocks each side), and identical UNFILTERED -- not
even the autoload noise line differed. Suite 105/105 green (7:40) on the same
tree. Two bounds the machine records rather than models: the AI members of a
unanimity proposal are taken to have ratified (no AI assembly runs), and a
treaty needing a constitutional revision first (France's Art. 54) is not
modelled -- every treaty bill is an ordinary `simple`-majority act.

### Bands — verdicts (V4.5b1)

Measured 2026-10-15 by `tools/council_probe.gd` on the T4 register (20 eu, 8
climate, 6 nato proposals), after printing a diagnosis of every miss and before
sweeping anything. C6 (agenda reach: every proposal opens at least once in a
168-month idle run) was declared in the V4.5b1 plan beside C1–C5, before the
probe ran. No band was redefined after a result. Table T is byte-identical
before and after the sweep, so gates G1–G4 hold as T4 left them (NATO's G1
waived by the author's call).

- **C1 the player decides: BOUND at 0.050** (1 of 20 distinct proposals opened in
  the first term; per opening, 2 of 30). Of 30 openings, 21 already go FRA's way
  with FRA abstaining, so there is nothing to spend on. Of the other 9, 7 are
  unanimity divisions with two or three vetoers, which one bargain cannot turn.
  Only `nato/defence_floor_2_5` has a single blocker (ITA, gap 0.091). The
  probe's ceiling holds at 0.050 for any largest swing from 0.15 to 0.90, and
  swinging each of `FAVOUR_SWING`, `AID_SWING` and `IOU_SWING` across ×{0.5–1.5}
  moved nothing. `CHAIR_WINDOW` 2 reads 0.087, still a miss. **Open for the
  author:** the band says "with bargains available", but the probe tests one
  bargain per division, while the machine allows one per member. Read as one per
  member, the same openings give 0.20 at today's swings (on the band's edge) and
  0.25 at `IOU_SWING` ×1.5. **Kept as declared (2026-10-15):** re-reading a band
  after seeing its result is the selector failure this project refuses, so C1
  stands as a BOUND at 0.050. The lever still open is CONTENT: unanimity rows
  placed with a single vetoer within a bargain's reach.
- **C2 spending is not free: MISS → fixed by `FAVOUR_RELATIONS_COST` 6 → 12;
  PASS at 8.60** (band ≥ 5). At 6 the gap was 0.19. Two favours were struck on
  ITA (months 18 and 54). `DiplomacyK.DRIFT_RATE` (0.02/month) took 35 % of the
  price back by month 60. A +10.1 `settle_dispute` from ITA's own AI agenda at
  month 53 took the rest: it fires only in the bargaining player's diverged
  world, and it does so at every swept price, even when the player pays in aid
  instead. It is a near-constant offset of 7.2–7.7 points. The gap rises roughly
  linearly with the price (4: −2.44, 6: 0.19, 8: 3.35, 10: 5.97, 11: 7.29,
  12: 8.60, 14: 11.23) and crosses the band near 9.3. 12 sits inside the passing
  region; 10 (5.97) passes but sits close to the ~9.3 crossing. FAVOUR_SWING was swept too: from 0.1125 up nothing changes. The probe has no RNG, so the +10.1 AI act is a stable, repeatable artefact of that world.
  `FAVOUR_SWING` 0.075 drops the favour below ITA's gap, so the player pays in
  aid (gap −7.70). **Caveats:** the sample is one member and two strikes,
  because C1's starvation leaves little to bargain over, and one AI act moves
  the reading by about 8 points (at `CHAIR_WINDOW` 4 the old price of 6 read
  8.87). Tabling was 8, below the new favour; it moved to 14 so the declared
  ordering holds (favour 12 < tabling 14 < betrayal 15) -- not band-measured,
  since neither probe run tables.
- **C3 unanimity is reachable: PASS** (24 carried, 42 vetoed over 168 months).
- **C4 ratification is a fight: PASS** (14 of the 17 unanimity proposals forecast
  inside [40 %, 60 %] yes in FRA's assembly).
- **C5 the BURDEN_MAX re-measure: RECORDED at 2.215 raw** cross-org burden at
  total defiance, against V3.5's 1.33 (no band).
- **C6 agenda reach: BOUND at 5 never opened** (all eu: `debt_reduction_rule`,
  `eurozone_fiscal_capacity`, `cohesion_fund`, `defence_industry_fund`,
  `enlargement_preaccession_fund`). climate (8 of 8) and nato (6 of 6) pass.
  The cap is not the cause: `MAX_RULES_IN_FORCE` (4) was never reached at any of
  the 27 eu AI-chair openings. Each of the five sat in a chair's window 3–6
  times and lost to the chair's preferred proposal every time. `CHAIR_WINDOW`
  {2, 3, 4} leaves 3 / 5 / 4 never opened, so no window passes and it stays at
  3. The lever still open is CONTENT: re-placing those five rows so some chair
  ranks them first. The structural reason is that the eu has 27 openings in 168 months for 20
  proposals, and each chair pick that is not the window's head spends an
  opening on a repeat. A window of 1 (the pure rotation) would pass, but it
  would undo the author's 2026-10-14 call that an AI chair chooses within a
  window.

**The V4.5b1 track (b) re-run, PREDICTED 2026-10-15 before it ran** (base
`50071cd`, V4.5a's close; candidate the b1 tip; both from worktrees). NOT
bit-identity -- content landed. Lines may move only through these channels:
(i) the agenda: one opening per 6 months per council (was one per 21) under a
presidency window, so more divisions and a different order; (ii) relations:
sponsor lobbying, sponsor thanks/snubs never fire (no regime votes in councils;
the player abstains), and every treaty that carries FALLS at its ratification
window because no regime submits it -- `RATIFY_FAIL_SPONSOR`/`_MEMBER` dips on
FRA's pairs; (iii) more rules in force (qmr constraints and transfers carried
by the AI majority) reaching the deficit through the transfer line and fines,
and the `europe` issue through the clamped burden; (iv) collective tariffs on
non-members (GBR, CHE) through the directed register. Expected direction:
FRA's and the members' deficits slightly worse, `europe` salience up, GBR/CHE
trade weights down; approval moves of a point or two; outcome flips possible
where V4.4's re-baseline already sat on knife edges. A moved line that none of
(i)-(iv) explains is a DEFECT.

**HELD, with one channel restated (2026-10-15).** 51 of 51 regimes moved (as
predicted: the council meets in every regime); 50 `invariants: OK` blocks each
side; no script errors; 1724 candidate lines against 1690 (the extra lines are
election-attribution rows and discipline rows whose numbers moved). **Three
outcome flips, all LOST → HELD at the 2032 presidential**, each a knife edge
(`managed_books_ahead` 23.6 → 24.0 %, `managed_tightens_migration` 24.0 → 24.3 %,
`flat_tax` 23.7 → 24.2 %). Traced, not assumed (an idle FRA, `Orgs.tick_month`
alone, both trees): the burden arrives at month 12 instead of 48 and settles at
0.139 against 0.113 (the stability pact now carries in year one and France is in
breach), the transfer line is higher early (0.372 vs 0.333 at month 12), and the
idle run holds 13 rules against 6 -- no unanimity proposal among them: every
treaty falls unratified, channel (ii). **Restated:** the prediction's "`europe`
salience up" read wrongly at the election screen -- `europe` drops OUT of the
printed attribution in the candidate, because the deficit channel (iii) lifts
`public_finances` and `jobs` above it, not because Europe bites less (the burden
is higher, earlier). The three flips move by +0.3 to +0.5 vote points; WHICH
channel lifts the incumbent despite a heavier burden was NOT isolated (candidates:
the early burden settling into `start`-relative salience before the term's
election, or trade through the collective tariffs) -- recorded as an open
attribution for b2's review, the flips themselves accepted as knife-edge moves
inside the predicted channels.

**Recorded bound (V4.5b2): the projection never ratifies.** `Budget.project`
runs the months forward without the player pressing "Put it to the assembly", so a
projection that runs past a ratification window shows the treaty falling by default
(and its sponsor and members charged for it). The ratification card, the desk mark
and the calendar's "Ratification deadline" are what tell the player to act first;
the projection is not taught to guess.

### As built (V4.5b2)

The surfaces, in the order the player meets them (`src/ui/council_section.gd`,
`council_bargains.gd`, `orgs_panel.gd`):

- **Orgs needing the player sort first.** An org with a vote the player can
  steer, an IOU owed, or a treaty to ratify rises above the quiet ones; the
  others keep register order.
- **Council block, top to bottom:** the sponsor's face and drive (the live head
  of government's, not a fixed portrait); the decision copy (which rule decides
  this proposal -- qmr or unanimity, and who holds a veto); the chair line (who
  presides, for how many more months, who is next -- from the calendar-derived
  presidency); then **WORK THE ROOM**, with every price read from
  `council_constants.gd` rather than typed into copy (lobby, the three
  currencies, tabling); the **already-bargained line** (what the player has
  spent on this proposal, so a second ask is read as a second ask); **IOUs
  owed**; and the agenda verbs (table, set the agenda) when the player holds the
  chair.
- **The ratification card** puts the treaty to the assembly using the bill's
  **blurred** forecast -- the same `FORECAST_UNCERTAIN_BAND` the law panel uses.
  The fixed-forecast rule holds here too: the exact seat count is never shown,
  because the card is a bill briefing and the player does not get to read the
  assembly more precisely for a treaty than for a statute.
- **The desk mark and the calendar deadline.** A pending ratification marks the
  desk and puts a "Ratification deadline" on the calendar, so the window
  (`RATIFY_WINDOW_MONTHS`) is something the player is told about, not something
  that lapses.
- **The top-bar Europe figure** -- the one-number reading of where the council
  stands, interim until V4.8's unified reading surface.

**Decisions taken during b2.**
(1) `claim_primary`: a *deadline* verb outranks build order. When a ratification
window is closing, the card's button takes the primary slot over a build action
that was there first.
(2) The ratify forecast is blurred, as above -- first drafted with exact seats,
caught at the T4 review.
(3) Orgs needing action sort first -- first drafted in register order, which
buried a closing window under quiet orgs; found staging frames at T7.

**Not built.** Event hooks: no authored event needs one, so the closed
vocabulary in `events_constants.ON_ACTIONS` is unchanged. The `Budget.project`
bound is recorded above ("the projection never ratifies") and is not revisited.

Related: [[bloc-model]] · [[foreign-policy-model]] · [[coercion-model]] ·
[[referendum-model]]
