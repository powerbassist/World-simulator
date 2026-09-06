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
withdrawal as multi-year domestic fights. Built at [[ROADMAP|V3.2]],
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
  opinion.
- **No repeal of a rule in force** (bloc-model's rule, unchanged). The player's
  answer to a rule they hate is to defy it and pay, or to leave.
- **No war.** NATO here is an org with a council and a spending floor;
  Article-5-as-domestic-politics is where V1.3f's cut stands.

---
Related: [[bloc-model]] · [[foreign-policy-model]] · [[coercion-model]] ·
[[referendum-model]] · [[ROADMAP]]
