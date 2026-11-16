extends RefCounted

## A firm's sheet at the right of its sector's tab -- V5.3 screen 5 slice 2, the author's C
## (render-C-slice2.png). Nothing folded: the firm's head and three figures, the file it
## carries (a plant closure, its answers and the region the jobs leave), then the State's
## verbs, each priced by the firm, one focused at a time (industry_verbs.gd, the rows the
## overview drew before: one source for both).
##
## Every figure is a reader's: the jobs and the worth are Companies', the State's share
## Companies.state_share_of, the closure ClosureCard's, the verbs' money IndustryVerbs'
## (Companies.preview on a copy), the aid's words AidWords' (PR 3's reads). The 12-month
## change the picture staged is cut: the sim keeps no series per firm.

const Companies = preload("res://src/sim/companies.gd")
const Closures = preload("res://src/sim/closures.gd")
const Region = preload("res://src/core/region.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Num = preload("res://src/ui/num.gd")
const Strings = preload("res://src/ui/strings.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")
const ClosureCard = preload("res://src/ui/closure_card.gd")
const IndustryVerbs = preload("res://src/ui/industry_verbs.gd")
const BillButton = preload("res://src/ui/bill_button.gd")
const Portrait = preload("res://src/ui/portrait.gd")

const FACE := Vector2(56, 72)


## The sheet of `company` under `parent`. `panel` keeps the focused verb, the refusal and
## the commands (firm_commands.gd through its _on_act and _on_closure).
static func build(panel, parent: Control, ns, company) -> void:
	var state = panel._state
	var loader = panel._loader
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	parent.add_child(top)
	top.add_child(Portrait.control_for(String(company.chief_id), FACE))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(words)
	var city = Region.find_city(loader.regions.get(ns.id, []), Companies.live_city_of(ns, company))
	# The city alone: the tab already names the sector, and the right click the chief (the text diet).
	if city != null:
		PanelKit.plain_line(words, String(city.city_name).to_upper(), PanelKit.Tone.PLAIN).theme_type_variation = UiTheme.MICRO
	var name := PanelKit.plain_line(words, company.company_name, PanelKit.Tone.PLAIN)
	name.theme_type_variation = UiTheme.LEAD

	var figures := HBoxContainer.new()
	figures.add_theme_constant_override("separation", 28)
	parent.add_child(figures)
	PanelKit.figure(figures, CompanyVerb.thousands(Companies.headcount(ns, company)), Strings.t("Jobs"))
	PanelKit.figure(figures, Strings.t("%s bn") % Num.f(Companies.value_eur_bn(ns, company), 1), Strings.t("Worth"))
	PanelKit.figure(figures, Strings.t("%s %%") % Num.f(100.0 * Companies.state_share_of(ns, company.id), 0), Strings.t("State"))

	if String(panel._last_refusal) != "":
		ResultTone.tint(PanelKit.line(parent, panel._last_refusal), ResultTone.BLOCKED)
	for row in Closures.open(ns):
		if String(row["company_id"]) == String(company.id):
			var file := PanelKit.section(parent, Strings.t("Its plant closure"))
			ClosureCard.build(file, state, loader, ns, row, panel._on_closure)

	var verbs := PanelKit.section(parent, Strings.t("The State's verbs"))
	IndustryVerbs.build(panel, verbs, ns, company)
	var bills := PanelKit.buttons(verbs)
	for bill in BillButton.ready_bills(state, ns, loader, String(company.id)):
		bills.add_child(BillButton.make(loader, bill))
