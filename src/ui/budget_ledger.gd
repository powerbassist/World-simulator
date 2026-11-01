extends RefCounted

## The Budget's table -- its rows and the cells it prints, moved out of
## budget_panel.gd at V5.3 a + b (the panel sat at its size ratchet and the change
## column needed the room). Static, the panel's own text: the rows, the formatters
## that print a snapshot's line, and since V5.3 a + b the change column, the
## difference of the two columns the table already prints (docs/design/v5.3-ab.md
## 4.1), signed per row and toned on the balance's sign.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")

const FIGURE_ROWS := [
	["revenue", "Revenue"],  # i18n: msgid last
	# Indented under Revenue the way debt service is under Spending, because it is
	# a component and not a fourth headline. A line of its own rather than folded
	# into `other`: V1.3c's tariffs are a revenue source the player CHOSE, and one
	# they cannot see on the panel is the decorative-axis failure
	# docs/scenario-model.md records, with a different label. Reads "—" while
	# nothing is imposed, which is every game that has not used the verb.
	["tariffs", "  of which tariffs"],  # i18n: msgid last
	# V1.4c, beside the tariff line and on the same argument: a revenue source the
	# player chose, which no slider on this panel sets. It differs from tariffs in
	# that it arrives from a decision taken on a different screen entirely, so a
	# budget that quietly widened its revenue after a nationalisation would be the
	# unnamed-reason failure the four indented lines here all exist to prevent.
	# Reads "—" while the state holds nothing, which is every game that has not used
	# the verb.
	["dividends", "  of which dividends"],  # i18n: msgid last
	["spending", "Spending"],  # i18n: msgid last
	["debt_service", "  of which debt service"],  # i18n: msgid last
	# V1.3d, indented under Spending for the same reason tariffs are indented under
	# Revenue, and on the same argument: a member's contribution, whatever the
	# rules in force move it by, and the penalties for defying them are all money
	# leaving the budget, and the player did not set any of it with a slider.
	# Reads "—" for a non-member, which is exactly 0.0 by construction.
	["bloc_transfer", "  of which the Union"],  # i18n: msgid last
	# V1.3g, beside the Union line and on the same argument a third time: money
	# leaving the budget that the player set with no slider. It differs from both
	# lines above in the way that matters most here -- an OBLIGED deployment is
	# spending the player did not choose AT ALL, so a panel that did not show it
	# would leave a deficit moving for a reason nothing on screen names.
	# Reads "—" while nothing is deployed, which is every game that has not allied.
	#
	# THIS ROW WAS MISSING UNTIL V1.4c, and its comment was here without it. V1.3g
	# wrote `_set_figure("deployments", ...)` and no ["deployments", ...] entry, and
	# _set_figure() returns silently on an unknown key -- so the deployment bill has
	# never appeared on this panel, and V1.4a then wrote "beside the deployment line"
	# about a line that was not there. V1.3g's own screenshot pass could not catch it:
	# the tool bug it did find made that figure an em dash anyway.
	["deployments", "  of which deployments"],  # i18n: msgid last
	# V1.4a, beside the deployment line and on the same argument a fourth time:
	# money leaving the budget that the player set with no slider. Without it a
	# subsidy signed on the Companies panel would widen the deficit here with
	# nothing on this screen naming the reason -- which is the failure this row and
	# the three above it all exist to prevent.
	# Reads "—" while nothing is subsidised, which is every game that has not used
	# the verb.
	["subsidies", "  of which subsidies"],  # i18n: msgid last
	# V1.6e, beside the subsidy line and on the same argument a FIFTH time: money
	# leaving the budget that the player set with no slider on this panel. It differs
	# from the subsidy line in the one way that matters to a player reading this
	# screen -- a subsidy's effect arrives inside a year and a sector programme's
	# takes most of a term, so this is a line that will sit here costing money for
	# several years before the growth it bought is visible in the rows below.
	# Reads "—" while no programme stands, which is every game that has not used
	# the verb.
	["investment", "  of which investment"],  # i18n: msgid last
	# V1.6f, beside the investment line and on the same argument a SIXTH time -- and
	# with the one difference this panel exists to show: every line above it is a
	# STANDING rate the player can lower, and this one runs for a fixed term and then
	# STOPS. A president reading this screen is looking at a bulge in the deficit with
	# a known end date, which is the whole of what makes a project a commitment rather
	# than a policy. Reads "—" while nothing is under construction, which is every
	# game that has not used the verb.
	["projects", "  of which public works"],  # i18n: msgid last
	# V2.8: a build in progress and every running station are on the spending total
	# with no slider on this panel, so the row is the only place the player can see
	# WHAT the fleet costs. It stops when the player closes a station, which is why the
	# off switch is a verb. (V1.7a's campaign row stood above it until V5.2 C6 moved
	# the campaign's price onto the governing party's money.)
	["energy", "  of which energy"],  # i18n: msgid last
	["deficit", "Deficit"],  # i18n: msgid last
	["debt", "Debt"],  # i18n: msgid last
	# V1.6d. NOT a budget figure, and it is on this panel anyway because the
	# instruments that move it are money levers -- the brackets, the
	# capital-gains rate and the wealth rate now live on the Tax Code window
	# (V4.2 T5), and this is the line that shows what they did to the
	# distribution. docs/unrest-model.md's grievance reads it, and until V1.6d
	# nothing the player did moved it at all.
	#
	# NEVER SILENT, which is the dependency ratio's and the credit rating's rule
	# rather than the delivery lines': every game has an inequality index from the
	# first frame, so a line that appeared only once it moved would hide the level the
	# offset is measured against.
	["gini", "Inequality (Gini)"],  # i18n: msgid last
	["", ""],
	# V1.6a: the three projection rows now read as a RANGE. See _forecast_text().
	# "2 years" since V5.3 a + b, the spec's word for the forecast (4.1), and
	# shorter: "in 24 months" was the widest caption under +35% pseudo, and the
	# change column needed its pixels.
	["proj_growth", "GDP growth, 2 years"],  # i18n: msgid last
	["proj_unemployment", "Unemployment, 2 years"],  # i18n: msgid last
	["proj_debt", "Debt ratio, 2 years"],  # i18n: msgid last
]

## The rows that are money, by the snapshot key they print and whether the
## balance gains when the line rises (a revenue line) or loses (a spending line,
## the deficit). Debt, the index and the forecast rows have no change cell: debt
## does not move the instant a budget is committed, and the forecast's own two
## columns are its comparison.
const CHANGE_ROWS := {
	"revenue": ["total_revenue_pct_gdp", true],
	"tariffs": ["tariff_revenue_pct_gdp", true],
	"dividends": ["dividend_revenue_pct_gdp", true],
	"spending": ["total_spending_pct_gdp", false],
	"debt_service": ["debt_service_pct_gdp", false],
	"bloc_transfer": ["bloc_transfer_pct_gdp", false],
	"deployments": ["deployment_bill_pct_gdp", false],
	"subsidies": ["subsidy_bill_pct_gdp", false],
	"investment": ["investment_bill_pct_gdp", false],
	"projects": ["project_bill_pct_gdp", false],
	"energy": ["energy_bill_pct_gdp", false],
	"deficit": ["deficit_pct_gdp", false],
}


## Appends each row's change cell, [text, tone], to the [now, proposed] pair the
## panel has written: a money row's move in EUR bn a year, an em dash when it
## does not move, nothing on a row that is not money.
static func add_changes(figures: Dictionary, now: Dictionary, proposed: Dictionary) -> void:
	for key in figures:
		var cell := ["", PanelKit.Tone.PLAIN]
		if CHANGE_ROWS.has(key):
			var moved := EffectsStrip.moved_bn(now, proposed, String(CHANGE_ROWS[key][0]))
			var gain := moved if bool(CHANGE_ROWS[key][1]) else -moved
			cell = [PanelKit.MISSING if absf(moved) < 0.05 else EffectsStrip.money_text(moved), EffectsStrip.money_tone(gain)]
		figures[key].append(cell)


static func figure_keys() -> Array:
	var out: Array = []
	for row in FIGURE_ROWS:
		if row[0] != "":
			out.append(row[0])
	return out


## Two decimals, chosen against the reachable range rather than copied from the row
## above: tax_constants.GINI_POLICY_MAX_PT bounds the whole policy offset at 8.60 points,
## but the grain a player moves it in is a bracket notch, which is hundredths. One
## decimal would print the same figure for two different budgets.
static func gini_text(snap: Dictionary) -> String:
	if not snap.has("gini_effective"):
		return "—"
	return PanelKit.Num.f(float(snap["gini_effective"]), 2)


## An em dash rather than "0.00%" while nothing is imposed. The two say different
## things: a zero invites the player to wonder what they did wrong, where a dash
## says the line is not in play. Every game that has never used the verb reads the
## dash, which is most of them.
## The same em dash for the same reason, with one difference the tariff line does
## not have: this figure is SIGNED. A net receiver -- or a member drawing on a
## programme the council adopted -- shows a negative, and "+" is forced so the
## direction is readable without comparing it against the line above.
static func bloc_text(snap: Dictionary) -> String:
	var pct: float = float(snap.get("bloc_transfer_pct_gdp", 0.0))
	if is_zero_approx(pct):
		return "—"
	return PanelKit.Strings.t("%s%% GDP") % PanelKit.Num.fs(pct, 2)


## A line that is an em dash at zero, its percentage and euros otherwise -- one
## function since V5.1-d1b3 for the four that were copies: a deployment and a
## subsidy (unsigned: they only ever cost, and there is no receiving side of a
## deployment, and the money a firm makes with a subsidy is private), and on the
## revenue side the dividends and the tariffs (unsigned: a holding pays or the state
## does not have one -- a firm that loses money still hands over nothing rather
## than billing the treasury, docs/companies-model.md section 13).
static func line_text(snap: Dictionary, key: String) -> String:
	if is_zero_approx(float(snap.get(key, 0.0))):
		return "—"
	return pct_and_eur(snap, key)


## The four bills that only ever cost and buy something other than money -- an
## investment programme and a building (trend growth), a campaign (turnout), the
## energy fleet -- each an em dash while nothing runs. One function since V5.1-d1b3;
## they were four copies differing only in the key.
##
## THE MISSING-KEY BRANCH IS SEPARATE FROM THE ZERO BRANCH, and V1.6d is why. That
## session's row read a missing snapshot key with `.get(key, 0.0)` and printed a
## confident "0.00" against a live figure. Both branches print an em dash here, so
## the display is the same either way -- what is not the same is that a key vanishing
## from Budget.snapshot() cannot be quietly absorbed into "nothing is running".
##
## THE COUNT OF LIVE BUILDS WAS ONCE ON THE PROJECTS ROW and the fifteenth screenshot
## pass took it out: "0.19% (6 bn) (1 building)" was wider than any other cell, and
## both value columns size to their widest row, so the panel grew a horizontal scroll
## bar. The count belongs on Public Works: the budget says what is being paid, the
## diary says when it lands, and Public Works says what and how many.
static func bill_text(snap: Dictionary, key: String) -> String:
	if not snap.has(key):
		return "—"
	if is_zero_approx(float(snap[key])):
		return "—"
	return pct_and_eur(snap, key)


static func pct_and_eur(snap: Dictionary, key: String) -> String:
	var pct: float = snap[key]
	return PanelKit.Strings.t("%s%%  (%.0f bn)") % [PanelKit.Num.f(pct, 2), pct / 100.0 * float(snap["gdp_eur_bn"])]
