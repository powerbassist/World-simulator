extends RefCounted

## One sector card on the Industry tab -- V5.3 a + b step 2, docs/design/v5.3-ab.md
## 3.2 "The tab, rebuilt", the readability gate's "Industry: lisible NON" answered.
## Closed, a card is one line: the sector, its output, the jobs at its named firms
## and a mark when one of its firms waits on a decision (a bid, a failing major).
## Opened, it holds the sector's own lever (the state programme, V1.6e), its majors
## as rows -- a name, two figures and ONE Act button -- and its body firms folded
## into a line. Act opens the firm's verbs (industry_verbs.gd) under its row.
##
## The sector's trend against the nation's (the spec's fourth figure) waits on a
## sim query (asked of Systems, 2026-11-01): the UI does not copy economy.gd's sum.
##
## The open card, the open firm, the opened body list and the focused verb are the
## panel's (they survive its rebuilds); this file only draws them.

const Companies = preload("res://src/sim/companies.gd")
const Industry = preload("res://src/sim/industry.gd")
const Investment = preload("res://src/sim/investment.gd")
const CompaniesK = preload("res://src/sim/companies_constants.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const Labels = preload("res://src/ui/labels.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")
const IndustryVerbs = preload("res://src/ui/industry_verbs.gd")
const BillButton = preload("res://src/ui/bill_button.gd")

## How far an opened card's content and a firm's verbs sit in, in px.
const INDENT := 20


static func build(panel, parent: Control, ns, sector: String) -> void:
	var state = panel._state
	var loader = panel._loader
	var firms := Companies.firms_in_sector(loader, ns.id, sector)
	var jobs := 0.0
	for company in firms:
		jobs += Companies.headcount(ns, company)
	var open: bool = panel._open_sector == sector

	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	parent.add_child(card)
	# A flow, not a box: a row with a button wraps under +35 % (test_i18n_fit).
	var head := PanelKit.buttons(card)
	var toggle := PanelKit.sized(Button.new())
	toggle.text = Labels.sector(sector)
	toggle.toggle_mode = true
	toggle.button_pressed = open
	toggle.set_meta("sector", sector)
	toggle.pressed.connect(func() -> void: panel._toggle("_open_sector", sector))
	head.add_child(toggle)
	var figures := PanelKit.plain_line(head, Strings.t("%s bn · %s jobs") % [
		Num.f(float(ns.sector_output.get(sector, 0.0)), 0), CompanyVerb.thousands(jobs)], PanelKit.Tone.PLAIN)
	figures.autowrap_mode = TextServer.AUTOWRAP_OFF
	if _waiting(state, ns, loader, sector):
		var mark := PanelKit.plain_line(head, Strings.t("Decision due"), PanelKit.Tone.PLAIN)
		mark.theme_type_variation = UiTheme.WARN_TEXT
		mark.autowrap_mode = TextServer.AUTOWRAP_OFF
	if not open:
		return
	card = _indented(card)

	var burden: float = Companies.regulation_burden_of(ns, sector)
	if burden > 0.0:
		PanelKit.plain_line(card, Strings.t("Regulated: %s") % Num.fs(burden, 2))
	elif burden < 0.0:
		PanelKit.plain_line(card, Strings.t("Deregulated: %s") % Num.fs(burden, 2))
	_programme(panel, card, ns, sector)
	var body := []
	for company in firms:
		if Companies.is_major(company):
			_firm_row(panel, card, ns, company)
		else:
			body.append(company)
	_body(panel, card, ns, sector, body)


## A bid or a failing major in this sector: the card says so while closed.
static func _waiting(state, ns, loader, sector: String) -> bool:
	var ids: Array = []
	var bid: Dictionary = Industry.pending_bid(state, ns, loader)
	if not bid.is_empty():
		ids.append(String(bid["company_id"]))
	for failure in Industry.failing(state, ns, loader):
		ids.append(String(failure["company_id"]))
	for company in Companies.firms_in_sector(loader, ns.id, sector):
		if ids.has(String(company.id)):
			return true
	return false


## The sector's own lever (V1.6e): the state programme's line and its verbs.
static func _programme(panel, card: Control, ns, sector: String) -> void:
	var intensity := Investment.intensity_of(ns, sector)
	var capital := Investment.capital_of(ns, sector)
	var shift := float(Investment.sector_trend_shift(ns).get(sector, 0.0))
	var label := PanelKit.plain_line(card, Strings.t("No state programme"))
	# THREE FIGURES AND NOT ONE (V1.6e): what the treasury is committed to, what that
	# has built, and what it is worth -- the gap between the first two is the lever.
	if intensity > 0.0:
		label.text = Strings.t("State programme %.0f %% · capital %s · %s %%/yr to this sector") % [100.0 * intensity, Num.f(capital, 2), Num.fs(shift, 3)]
		label.theme_type_variation = UiTheme.GOOD_TEXT
	elif capital > 0.0:
		# A lapsed programme's capital depreciates to zero, still paying a fading
		# trend shift: not "nothing", or the figure moving in the rows above is unnamed.
		label.text = Strings.t("No programme · capital %s depreciating · %s %%/yr to this sector") % [Num.f(capital, 2), Num.fs(shift, 3)]
	var buttons := PanelKit.buttons(card)
	for action in Investment.available(panel._state, ns, panel._loader.investment_actions):
		if String(action.effects.get("investment", {}).get("sector", "")) != sector:
			continue
		var button := PanelKit.sized(Button.new())
		button.text = Strings.row_name("investment-actions", action)
		button.tooltip_text = Strings.row_summary("investment-actions", action)
		button.pressed.connect(func() -> void: panel._on_invest(ns, action))
		buttons.add_child(button)


## A major as a row: its name, its jobs, its worth, and ONE Act. Opened, the row
## grows the firm's standing line and its verbs.
static func _firm_row(panel, card: Control, ns, company) -> void:
	var row := PanelKit.buttons(card)
	# One label sized to its text: a wrapping label in a flow has no width of its own
	# and wraps at every letter (the first frame's Act column).
	var figures := PanelKit.plain_line(row, Strings.t("%s · %s jobs · worth %s bn") % [company.company_name,
		CompanyVerb.thousands(Companies.headcount(ns, company)), Num.f(Companies.value_eur_bn(ns, company), 1)], PanelKit.Tone.PLAIN)
	figures.autowrap_mode = TextServer.AUTOWRAP_OFF
	var act := PanelKit.sized(Button.new())
	act.text = Strings.t("Act")
	act.toggle_mode = true
	var id := String(company.id)
	act.button_pressed = panel._open_firm == id
	act.set_meta("company_id", id)
	act.pressed.connect(func() -> void: panel._toggle("_open_firm", id))
	row.add_child(act)
	if panel._open_firm != id:
		return
	var standing := _standing(panel, ns, company)
	var verbs := _indented(card)
	if standing != "":
		PanelKit.plain_line(verbs, standing)
	IndustryVerbs.build(panel, verbs, ns, company)
	var bills := PanelKit.buttons(verbs)
	for bill in BillButton.ready_bills(panel._state, ns, panel._loader, id):
		bills.add_child(BillButton.make(panel._loader, bill))


## The firm's standing in one line: what the state holds and pays, and its chair.
static func _standing(panel, ns, company) -> String:
	var parts := PackedStringArray()
	var held := Companies.state_share_of(ns, company.id)
	if held > 0.0:
		parts.append(Strings.t("Public %.0f %%, %s bn a year to the treasury") % [
			100.0 * held, Num.f(held * Companies.output_eur_bn(ns, company) * CompaniesK.DIVIDEND_YIELD, 2)])
	var intensity := Companies.subsidy_of(ns, company.id)
	if intensity > 0.0:
		parts.append(Strings.t("Subsidised %.0f %%") % (100.0 * intensity))
	var chair := String(ns.companies.get(company.id, {}).get("board_chair", ""))
	if chair != "":
		var chair_name: String = panel._loader.person_name(chair)
		parts.append(Strings.t("Chair: %s") % (chair_name if chair_name != "" else chair))
	return ". ".join(parts)


## What a card or a firm opens sits one step in from the row that opened it, so the
## eye reads it as that row's, not as the next row of the tab.
static func _indented(parent: Control) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", INDENT)
	parent.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	margin.add_child(box)
	return box


## The body firms, folded into one line; opened on a click, the five largest.
static func _body(panel, card: Control, ns, sector: String, body: Array) -> void:
	if body.is_empty():
		return
	var jobs := 0.0
	for company in body:
		jobs += Companies.headcount(ns, company)
	var key := "body:" + sector
	var fold := PanelKit.sized(Button.new())
	fold.flat = true
	fold.text = Strings.tn("%d smaller firm · %s jobs", "%d smaller firms · %s jobs", body.size()) % [body.size(), CompanyVerb.thousands(jobs)]
	fold.toggle_mode = true
	fold.set_meta("fold", key)
	fold.button_pressed = panel._open_body == key
	fold.pressed.connect(func() -> void: panel._toggle("_open_body", key))
	card.add_child(fold)
	if panel._open_body != key:
		return
	var live := {}
	for company in body:
		live[company.id] = Companies.headcount(ns, company)
	var ranked := body.duplicate()
	ranked.sort_custom(func(a, b): return float(live[a.id]) > float(live[b.id]))
	for i in mini(5, ranked.size()):
		PanelKit.plain_line(card, Strings.t("%s · %s jobs") % [
			ranked[i].company_name, CompanyVerb.thousands(float(live[ranked[i].id]))])
