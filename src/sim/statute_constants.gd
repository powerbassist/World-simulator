extends RefCounted

## V4.2 T2: the composition machine's constants. Same shape as
## economy_constants.gd and legislature_constants.gd -- model parameters, not
## content, so not in data/. The machine is src/sim/statute.gd; this file is
## the values, docs/legislature-model.md is the argument.

## The drafting budget: what a bill of a given size costs in months before it
## can be proposed. DECLARED at T2, swept at T3 against the bands in
## docs/legislature-model.md -- and the sweep HELD every value (probe run
## 2026-10-03, seed 20261003): P1(i)'s floor is cleared by the shipped rows
## (full|max worst-bloc price 1.183 against the 1.0 readability floor), P3
## lands on this arithmetic at both band edges (size 1.0 -> 3 months, 6.0 ->
## 8), and P5 found two cells where the derived price exceeds BLOC_OFFSET_MAX
## (half|max +1.325, full|max +1.183 on urban -- the quote-to-landing gap the
## ledger records as realized deltas, a recorded bound of the form, not a
## tuning debt). P1(ii) measured the division effects-blind at 25 of 25
## positions -- no constant here can make breadth cost votes; see the model
## doc's open author call.
const DRAFT_SIZE_MAX := 6.0
const DRAFT_MONTHS_BASE := 2
const DRAFT_MONTHS_PER_SIZE := 1.0
const DRAFT_COOLDOWN_MONTHS := 24

## V4.2 T4. What a proposed tax key may carry. These are BIRTH gates at
## draft() -- content refusals, not clamps: a spec outside them is refused
## whole, never trimmed to fit, because a clamp would silently re-price the
## bill the player was shown.
##
## The ceiling on `base_share` is wealth's 4.00, the largest base
## economy_constants.TAX_BASE_SHARE prices -- a net-wealth stock at four times
## annual output. A proposed base above it is a quantity the revenue model has
## no shape for, not a bigger tax.
const NEW_TAX_BASE_SHARE_MAX := 4.0
## The ceiling on the key's own erosion coefficient. Above 1.0, any rate above
## the birth rate drives the shared curve's raw value negative and the answer
## is EROSION_MIN all the way up -- the clamp, not the model, would be setting
## the number above the reference. The authored five span 0.25 (vat) to 0.80
## (wealth); 1.0 is the curve-stays-live bound above them.
const NEW_TAX_EROSION_MAX := 1.0
## A tax is born at a rate, and the birth rate doubles as the key's erosion
## reference (the zero-reference rule's own answer: there is no authored
## "normally levied at" for a key the player invented, so the rate its own
## bill set is the reference) -- the curve divides by it, so a zero-rate birth
## has no curve at all. 100 is a percent's ceiling; the authored sliders top
## at 70, wealth at 3.0 for its stock-scale base.
const NEW_TAX_RATE_MAX := 100.0
## The ceiling on the PRODUCT the revenue formula actually reads: base_share
## x rate. The two caps above bound their fields independently, so base 4.0 x
## rate 100 = 400 % of GDP could be born -- a yield nothing else in the birth
## gate brakes (zero drafting size, zero derived bloc price, no salience row).
## Anchored at wealth's OWN max yield: 4.0 base x 3.0 rate = 12.0, the most
## the revenue model has ever been asked to price. A product above it is a
## quantity the model has no shape for, exactly as an over-ceiling base is.
const NEW_TAX_YIELD_CEILING := 12.0
## The demand-impulse multiplier a custom key reads in Budget.commit()'s
## level_effect loop, where the authored five read their MULT_TAX rows. The
## lowest of the five (wealth's 0.25): per-key demand multipliers are authored
## constants' privilege exactly as the opinion scales are, and the shared
## default gives a player-proposed key the SMALLEST demand footprint the model
## has ever charged a tax, so it can never out-lever the authored set by
## default.
const CUSTOM_TAX_MULT_DEMAND := 0.25

## V4.2 T5. The two commissioned polls, priced as a ONE-OFF cost of GDP. The
## conversion to euros happens once, in statute.buy_poll(), through the GDP
## level -- the same route companies.gd's bailout takes -- so this table stays
## a price list and never a second place that knows the debt arithmetic. An
## assembly poll buys the whip count down to ABSTAIN_BAND for that one bill; a
## popular poll buys the country's bloc read at the precise margin. Each kind
## is bought ONCE per bill -- the register keys purchases by bill AND kind
## (poll_noise's fixed-forecast rule: a poll is a published figure, and a
## second commission would be a re-roll of the same number).
const POLL_KIND_ASSEMBLY := "assembly"
const POLL_KIND_POPULAR := "popular"
const POLL_COSTS := {
	"assembly": 0.05,
	"popular": 0.04,
}

## V4.2 T6. The assembly's own life: private members' bills and the chiefs'
## lobbying. Both hazards are per PLAYER nation per month -- has_budget is the
## standing refusal of AI nations legislating, the gate legislature.tick_month()
## already reads -- and both draw on Cycle.unit("statute|<event>|<nation>",
## absolute month), the events.gd discipline: no rand anywhere, a replay
## produces the same bills.
##
## PMB_HAZARD_MONTHLY prices the backbench floor. At 0.08 the draw fires just
## under once a year (0.08 x 12 = 0.96), which is the band the test pins
## against: often enough that a player who never drafts still has a statute
## book moving under them, rarely enough that an endorsement stays a decision
## rather than a chore. The realized count runs UNDER the draws, because the
## candidate pool closes as bills resolve -- a failed bill sits out its
## authored cooldown, a once-law passed is gone -- and the measured idle band
## (120 months, FRA, the test's own loop) is 9 bills, right on the draw rate;
## the test pins 1 <= bills <= 20, well inside the draw ceiling of 12 per
## decade.
const PMB_HAZARD_MONTHLY := 0.08

## One month between tabling and division: the announcement card IS the
## player's window to endorse, and the assembly divides on the next tick
## with or without them -- the assembly proposes and the assembly decides.
const PMB_MONTHS_TO_VOTE := 1

## What the president's endorsement adds to every party's support line on the
## bill's own division, read through resolve_vote()'s DEFAULTED support_bonus
## parameter -- the same additive form coalition_bonus takes inside support().
## A tenth of a point: enough to carry a bill sitting on the abstain band
## (LK.ABSTAIN_BAND is 0.05 -- law_panel.gd's 0.15 is the FORECAST blur, not
## the division), not enough to buy one the house opposes, since
## the spatial term spans [-1, 1] and the bonus re-clamps like every line.
const PMB_ENDORSE_SUPPORT := 0.10

## The endorsement's own political price, applied ONCE at endorse() through
## the ONE applier -- the player's public stand, not the bill's (the bill
## prices the country at its division like any law's effects do). Mirrors the
## authored pair high_earner_surtax prices -- workers +0.05, business -0.15 --
## at the smallest magnitude on each side, because an endorsement is a signal
## read as executive activism, worth a nudge to the workers' bloc and the same
## against business, not a law's worth of either.
const PMB_ENDORSE_PRICE := {"workers": 0.05, "business": -0.05}

## LOBBY_HAZARD_MONTHLY prices a chief-backed bill at roughly one every four
## years (0.02 x 12 = 0.24 draws) -- five times rarer than the backbench
## floor, because a lobbied bill exists to raise the question a plain PMB
## does not ("whose bill is this?") and a raised question stays raised only
## when it is rare. Fires only when a sector's regulation burden stands above
## LOBBY_BURDEN_FLOOR AND that sector has a major whose chief can sign the
## ask AND the authored book carries a burden-easing law for the sector --
## any leg missing and the fired draw falls through to the plain backbench.
##
## THE FALL-THROUGH'S RECORDED COST: a fired lobby draw never wastes the
## month -- the chief still brings a bill (a plain backbench one, when no
## burden-easing law exists to name) -- so on its fire months a burdened
## nation's EFFECTIVE plain-bill rate is PMB_HAZARD + LOBBY_HAZARD (0.10)
## rather than PMB_HAZARD alone. Accepted, not tuned away: the fall-through
## is mandated (a spent draw tabling nothing would read as the backbench
## falling silent in the month a chief came to it), and the added VOLUME is
## small in the band's own units -- fires are ~0.24/yr at the 0.02 hazard
## and only where a sector stands burdened (an idle world holds none above
## the floor), so the fall-through adds ~0.24 bills/yr on top of the
## backbench's ~0.96/yr: together far under the 1-20-per-120-months band
## the test pins, whose measured idle run is 9 bills.
const LOBBY_HAZARD_MONTHLY := 0.02

## The burden above which a sector's majors have something worth a bill: 0.1
## on the signed burden register, a TENTH of companies_constants'
## REGULATION_BURDEN_MAX clamp. Below it the sector's rules are noise no
## chief would spend a bill on; the authored deregulation laws' own burdens
## (-0.35, -0.4) clear the floor whole, so a relief bill is always in reach
## of a sector actually paying for one.
const LOBBY_BURDEN_FLOOR := 0.1

## What one unit of movement on each channel spends from the budget. Tax and
## spending in points, the accumulators in their authored units, scaled so a
## typical authored single-channel law costs ~1.0.
const CHANNEL_COST := {
	"tax_rates_pct": 0.2, "spending_pct_gdp": 0.25,
	"structural_unemployment_pct": 2.0, "potential_growth_pct": 4.0,
	"other_revenue_pct_gdp": 1.0, "company": 3.0, "society": 3.0,
}

## The auto-derived political price: per channel, per bloc, per RAW UNIT of
## that channel's signed value -- contribution = value x price, for either
## sign, so a composed CUT reads the mirror of the composed rise exactly as
## the authored levers do (corporate_tax_cut is +0.2 business on -5.0). NOT
## per unit of budget size: the anchor row fixes the unit. Mirrors the
## authored laws' own bloc_offset patterns per unit; every row cites the law
## it mirrors. bloc_offset and institutional are absent BY CONSTRUCTION --
## the price is what this table derives, and a setting is never composed
## (T1's repeal gate would refuse the bill at birth). "retirees" in the plan
## sketch is BLOC_KEYS' "pensioners"; a bloc that is not in BLOC_KEYS would
## sit in the derived price as a dead key nobody reads.
##
## Keys with an authored mover are the mover's own ratio. Keys with none
## (capital_gains, wealth, defence, the growth row) are authored by their
## nearest analogue and flagged inline -- T3's bands are the check on all of
## them.
const CHANNEL_PRICE := {
	"tax_rates_pct": {
		# THE ANCHOR ROW, high_earner_surtax verbatim: +5.0 income buys
		# business -0.15 / workers +0.05, so -0.03 / +0.01 per point.
		"income": {"business": -0.03, "workers": 0.01},
		# corporate_tax_cut: +0.2 business on -5.0, so -0.04 per point of
		# either sign. The authored law prices business alone.
		"corporate": {"business": -0.04},
		# vat_consolidation: -0.1 workers / -0.05 students on +2.0.
		"vat": {"workers": -0.05, "students": -0.025},
		# No authored mover. The income anchor's business price: capital
		# income is business-adjacent, and a levy on it angers the same bloc
		# at the same rate.
		"capital_gains": {"business": -0.03},
		# No authored mover. The plan sketch's own row (business -0.04,
		# pensioners +0.02 on a rise -- a wealth levy is redistribution
		# toward the asset-poor), corrected to the real bloc key.
		"wealth": {"business": -0.04, "pensioners": 0.02},
	},
	# Priced per portfolio, and a cut and a rise differ: the CUT row's signs
	# are its own (it prices |value|), because loss aversion is authored
	# content, not symmetry -- retirement_age_reform's pension cut buys
	# -0.35 pensioners on -1.2 while the health rises buy +0.15/+0.10 per
	# point. Where no authored cut exists, the cut row is 1.5x the rise,
	# citing that law as the anchor.
	"spending_pct_gdp": {
		# health_service_reform (+1.0 -> pensioners +0.15, urban +0.10) and
		# childcare_expansion (+0.3 -> urban +0.2, workers +0.1); urban read
		# between the two.
		"health": {
			"rise": {"pensioners": 0.15, "urban": 0.2, "workers": 0.1},
			"cut": {"pensioners": -0.25, "urban": -0.3, "workers": -0.15},
		},
		# public_sector_pay_settlement (+0.3 education, shared with health
		# +0.4, buys workers +0.2 / urban +0.08), read per education point.
		"education": {
			"rise": {"workers": 0.15, "urban": 0.1},
			"cut": {"workers": -0.25, "urban": -0.15},
		},
		# No authored mover. Priced at a fraction of the social floor so a
		# defence-only bill is not free -- business.json's _cost_and_buy
		# rule -- with the split (a rise pleases the garrison constituencies,
		# a cut the urban ones) authored judgement, flagged for T3.
		"defence": {
			"rise": {"rural": 0.05, "pensioners": 0.05},
			"cut": {"urban": 0.05, "students": 0.05, "rural": -0.05},
		},
		# Cut verbatim from retirement_age_reform (-1.2 -> pensioners -0.35,
		# business +0.15, per point -0.29 / +0.12); rise mirrored at the
		# health-reform level -- the authored evidence for a pension rise is
		# that law read backwards, moderated to the rise-scale rows.
		"pensions": {
			"rise": {"pensioners": 0.15},
			"cut": {"pensioners": -0.29, "business": 0.12},
		},
		# housing_programme (+0.6 -> urban +0.2, rural +0.05, per point
		# 0.33 / 0.08). regional_devolution's rural +0.2 on +0.2 is excluded:
		# a devolution price on a constitutional-class act, not a spending
		# ratio.
		"infrastructure": {
			"rise": {"urban": 0.3, "rural": 0.08},
			"cut": {"urban": -0.45, "rural": -0.12},
		},
	},
	# The labour cluster's consistent pair -- working_time_reduction
	# (+0.3 -> workers +0.25, business -0.2) and labour_market_flexibilisation
	# (its exact mirror) -- read per point. minimum_wage_rise prices 2.0/-1.5
	# per point and is the outlier; the cluster is the row.
	"structural_unemployment_pct": {"workers": 0.8, "business": -0.7},
	# No clean authored ratio: competition_enforcement and
	# emergency_procurement_powers are the only growth movers and both carry
	# their company/society prices in the same bloc row. Priced as the
	# diffuse-hope row -- growth is a general good, business leaning positive
	# per emergency_procurement_powers' business +0.10.
	"potential_growth_pct": {"workers": 0.4, "urban": 0.4, "business": 0.5},
	# carbon_levy verbatim: +0.5 -> business -0.1, urban +0.1, rural -0.15.
	"other_revenue_pct_gdp": {"business": -0.2, "urban": 0.2, "rural": -0.3},
	# The per-unit mean of the three sector-regulation laws
	# (emissions_standards, workplace_safety_act, banking_conduct_rules):
	# business -0.5..-0.74, workers +0.26..+0.35, urban +0.13..+0.43,
	# pensioners +0.46 (banking). rural/students excluded -- their authored
	# signs disagree across the three.
	"company": {"business": -0.6, "workers": 0.3, "urban": 0.25, "pensioners": 0.15},
	"society": {
		# anti_corruption_agency (-0.5 -> urban +0.15, business -0.05) and
		# emergency_procurement_powers (+0.4 -> business +0.10, urban -0.12,
		# students -0.08), per unit.
		"corruption": {"urban": -0.3, "business": 0.15, "students": -0.1},
		# labour_migration_scheme verbatim per unit (+0.35 -> business +0.20,
		# urban +0.15, rural -0.25, workers -0.10); immigration_tightening's
		# business +0.05 is noise against the scheme's +0.57 and is not the row.
		"migration": {"business": 0.55, "urban": 0.4, "rural": -0.7, "workers": -0.3},
		# The three labour laws agree: per unit, workers +0.8, business
		# -0.6 (minimum_wage_rise, working_time_reduction,
		# labour_market_flexibilisation).
		"settlement": {"workers": 0.8, "business": -0.6},
		# The three press laws, per unit: public_broadcasting_reform,
		# broadcasting_oversight_act, emergency_broadcasting_powers (the two
		# censorship acts price urban/students at +0.5..+0.8 against a fall).
		"press_freedom": {"urban": 0.4, "students": 0.7, "rural": -0.3,
			"pensioners": -0.2, "workers": 0.25},
		# The four judicial laws, per unit of the +-3.0 they move: tiny
		# everywhere -- the authored price of a court act sits in its
		# position and its absolute majority, not in the bloc offsets.
		"judicial_independence": {"urban": 0.05, "students": 0.07, "business": 0.03,
			"rural": -0.03, "pensioners": -0.02, "workers": -0.02},
	},
}
