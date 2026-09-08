extends RefCounted

## Every tunable in the bloc model, in one file -- the same shape as
## economy_constants.gd, opinion_constants.gd, trade_constants.gd and
## coercion_constants.gd. Rationale for every number is docs/bloc-model.md; this
## file is the values, that file is the argument.
##
## Not in data/ on purpose, and for the reason opinion_constants.gd gives: these
## are model parameters, not content a designer adds more of. The content a
## designer adds more of is data/bloc-proposals/*.json.


# --- The council -----------------------------------------------------------------

## Months between one proposal reaching the council and the next. Eighteen puts
## roughly three votes in a five-year term -- often enough that a player who is
## outvoted once sees another chance inside the same mandate, rare enough that
## the bloc is an occasion rather than a monthly chore. The legislature is where
## this game asks for a decision every month.
const PROPOSAL_INTERVAL_MONTHS := 18

## How long a proposal sits open before the council divides. The player's whole
## interaction with a vote lives in this window: read it, weigh it, cast. Three
## months is long enough to survive being missed on one monthly tick and short
## enough that a pending proposal is not permanent furniture.
const VOTE_DELAY_MONTHS := 3

## Share of the EP seats actually CAST that a proposal needs to pass. Modelled on
## the Council's real qualified majority, and deliberately ABOVE half: a bloc
## where a bare majority binds everyone would make the player's own vote almost
## never pivotal, and a bloc needing unanimity would never pass anything, which is
## the same decorative outcome by the other route.
##
## Cast, not total, and that is what makes abstention a third option -- see
## Bloc._resolve(). Against the whole council's strength, abstaining and opposing
## give an identical answer forever.
##
## EP seats rather than an invented council weight, because data/eu_parliament.json
## already carries them and they are already roughly population-shaped. That is
## what makes the file load-bearing beyond the elections it was written for.
const PASS_SEAT_FRACTION := 0.55

## The support level at which a member votes for rather than against. There is no
## abstention among the nine: a third outcome would need a rule for what produces
## it. The PLAYER may abstain, because a player choosing not to spend political
## capital is a real decision.
##
## Re-anchored at V1.3e, and it had to be rather than merely re-swept. V1.3d's
## support() was a Gaussian on (0, 1] and 0.50 was its midpoint; the scale
## underneath it is now foreign_policy.gd's appraisal, which is a benefit minus
## three costs and is signed. 0.50 against the new scale is unreachable -- the
## ideology term alone tops out at APPRAISE_IDEOLOGY_WEIGHT -- so every member
## would have voted against everything forever, and it would have looked like a
## council that had simply stopped agreeing.
##
## Zero was the honest anchor to sweep FROM -- a member votes for what leaves it
## better off -- and the sweep moved it. tools/foreign_policy_probe.gd table (c),
## against TWO criteria rather than V1.3d's one:
##
##   threshold   carried   FRA decides   lost anyway   abstention window
##      0.00        6           0             1                0
##      0.05        5           1             1                1
##      0.15        3           2             2                1     <-- shipped
##      0.20        3           1             3                0
##      0.25        1           2             4                2
##      0.40        1           0             6                0
##
## The fourth column is new and it is the reason 0.15 rather than 0.20. V1.3d swept
## only the first three, and its own constructive-abstention property then came out
## of the shipped content by luck -- abstaining differs from opposing ONLY when the
## other eight land in [172, 216) of 393 seats, a window 11 % of the range wide, and
## nothing in the content is placed to guarantee it. At 0.20 that window is empty:
## the council has three vote options and two outcomes, which is the decorative-verb
## failure with correct arithmetic. tests/test_bloc.gd now SCANS for a proposal in
## the window rather than naming one, so this cannot regress silently again.
##
## 0.15 also has the better first three: all non-zero and balanced. At 0.00 France
## is pivotal on NOTHING, which is V1.3d's own failure mirrored -- that session
## found six of seven proposals decided by France and called it a legislature the
## player controlled, and a council the player can never move is the same fault
## from the other side. France holds 81 of 393 member seats.
const SUPPORT_THRESHOLD := 0.15


# --- Rules in force --------------------------------------------------------------

## How many rules may bind at once. Past this the oldest is not evicted -- the
## council simply stops proposing, because a bloc that silently drops its own
## law to make room for another is a rule nobody voted to repeal. Four is what
## fits on the panel and what the burden scale below is measured against.
const MAX_RULES_IN_FORCE := 4

## The largest total burden a player can carry, summed over every rule in force.
##
## Reached EXACTLY at total maximal breach of every rule and never before, because
## the authored severities sum to exactly 1.0 -- which is not a coincidence and is
## checked by tests/test_bloc.gd. The probe's first run had them summing to 1.35,
## and the clamp then removed 0.35 of real burden: a player already defying three
## rules got NOTHING from breaching the fourth, which is the strictly-dominated
## shape docs/coercion-model.md's probe caught for high tariff severities. Rescaled
## so the clamp touches rather than bites, and no rule is ever free to break.
const BURDEN_MAX := 1.0

## Percent of GDP charged per unit of burden, on top of the standing contribution.
## The bloc's answer to being defied, and the second half of what makes defiance a
## decision rather than a free ride -- the first half is the `europe` issue.
##
## Anchored on the panel it prints on: economy_constants.TAX_BASE_SHARE makes one
## point of VAT worth about 0.53% of GDP, so a player at full burden pays about
## two thirds of a tax point in penalties. Enough to see on the budget line,
## far short of what compliance would cost on the spending lines it frees.
const FINE_PCT_GDP_PER_BURDEN := 0.35


# --- Transfers -------------------------------------------------------------------

## Net contribution as a percent of GDP for a member of exactly average
## prosperity, before the prosperity term below. France's real net contribution
## runs around 0.25-0.30% of GNI, which is what this is anchored on.
const CONTRIBUTION_BASE_PCT_GDP := 0.30

## How much richer-than-average pays and poorer-than-average receives, per unit of
## relative GDP per capita. Derived rather than authored, from population and GDP
## the nation files already carry -- the same treatment resting relations,
## cabinet competence and the trade weight all get, and for the same reason: an
## authored table of ten net positions is frozen, and this one moves if the roster
## does.
const CONTRIBUTION_PROSPERITY_SPAN := 0.50

## Bounds on the derived figure. Luxembourg's GDP per capita is far enough above
## the bloc mean to run the formula somewhere absurd, and a budget line that large
## would out-weigh every fiscal lever in the game. The floor is negative because a
## poorer member genuinely receives.
##
## V3.3 moved the ceiling by the rule that set it: it was placed just above
## Luxembourg's formula output on the EIGHT-member mean (~1.19 -> 1.20), and the
## EU-27 mean is poorer, which lifts every rich member's ratio -- Luxembourg's
## output is now 1.339 and Ireland's 1.102. Re-derived on the same placement
## (just above the maximum output, measured against the committed roster):
## 1.35. Nobody sits on it; Bulgaria reads 0.004 against a floor nowhere near.
const CONTRIBUTION_MIN_PCT_GDP := -0.60
const CONTRIBUTION_MAX_PCT_GDP := 1.35


# --- Content limits --------------------------------------------------------------

## The only fields a bloc rule's constraint may test, and the only operators.
## Every entry is the constrained nation's own state, read by Bloc._read_field()
## exactly the way Legislature._read_field() and Diplomacy._read_field() read
## theirs. An unknown field is a startup error, not a silently false predicate.
const CONSTRAINT_FIELDS := [
	"deficit_pct_gdp",
	"debt_to_gdp_pct",
	"total_spending_pct_gdp",
	"spending_defence",
	"spending_infrastructure",
	"tax_corporate",
	"tax_vat",
]

const CONSTRAINT_OPS := ["<", "<=", ">", ">="]

## How each field and operator is named to the player. Beside the lists they
## label rather than in the panel, which is opinion_constants.ISSUE_LABEL's
## placement and for its reason: a label map living in the UI drifts out of step
## with the list the loader validates against, and nothing would fail when it did.
## The screenshot pass caught the panel printing `deficit_pct_gdp <= 3.0` at a
## player, which is a model identifier wearing a sentence.
const CONSTRAINT_LABEL := {
	"deficit_pct_gdp": "Deficit, % of GDP",
	"debt_to_gdp_pct": "Debt, % of GDP",
	"total_spending_pct_gdp": "Total spending, % of GDP",
	"spending_defence": "Defence spending, % of GDP",
	"spending_infrastructure": "Infrastructure spending, % of GDP",
	"tax_corporate": "Corporation tax rate",
	"tax_vat": "VAT rate",
}

const CONSTRAINT_OP_LABEL := {
	"<": "under",
	"<=": "at most",
	">": "over",
	">=": "at least",
}

## How hard one rule can bite. Severity scales that rule's share of the burden,
## so a rule at 0.25 breached to its full tolerance costs a quarter of what the
## ceiling permits.
const MAX_RULE_SEVERITY := 1.0

## A constraint's tolerance is the breach size at which that rule contributes its
## full severity. Refused below this at load, because a tolerance near zero makes
## the burden a step function of a continuous quantity -- the player would cross
## from compliant to maximally guilty on a rounding error, and the panel would
## show a cliff where the model claims a slope.
const MIN_CONSTRAINT_TOLERANCE := 0.10

## The largest standing transfer one proposal may add or remove, percent of GDP.
## Bounded for the same reason MAX_AGREEMENT_WEIGHT_MULTIPLIER is: this is what
## keeps the budget line inside the range docs/economy-model.md's divergence
## argument was made over, BEFORE anything downstream clamps.
const MAX_PROPOSAL_TRANSFER_PCT_GDP := 0.60

## The largest severity a proposal may write into the directed measure register
## when the bloc sets an external tariff collectively. Capped below
## coercion_constants.MAX_MEASURE_SEVERITY on purpose: a bloc acting as one is
## slower and more compromised than a nation acting alone, and a collective
## embargo at full severity would make the player's own coercion verbs pointless.
const MAX_PROPOSAL_EXTERNAL_SEVERITY := 0.50
