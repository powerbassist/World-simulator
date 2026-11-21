extends RefCounted

## The Sectors overview's side sheet -- G3 S3, "C La frise": the timeline's picked row, and
## the decision it carries answered here, beside the list (sectors_timeline.gd). One sheet,
## one job: the firm's face and name, its figure tiles, then what the row asks -- a process's
## answers or its Stop, a closure's answers, a rescue window's verb, a bid's two verbs -- each
## built by the reader that already built it for the old strip (IndustryProgress.process_row,
## ClosureCard.build), so an answer's money and blocs read the same wherever it is answered.
##
## `panel` is companies_panel.gd: its _on_answer / _on_stop / _on_closure run the commands
## (firm_commands.gd) and its _action_button gates a verb by the sim's own door.

const Companies = preload("res://src/sim/companies.gd")
const IndustryProgress = preload("res://src/ui/industry_progress.gd")
const ClosureCard = preload("res://src/ui/closure_card.gd")
const SectorNeeds = preload("res://src/ui/sector_needs.gd")
const SectorsTimeline = preload("res://src/ui/sectors_timeline.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")

const FACE := Vector2(48, 62)
## The sheet's width, in px at text size 100 (the picture's 500).
const WIDTH := 440.0
## A kind's words over the title, in tracked capitals beside the sector's name.
const KIND_WORDS := {
	"ask": "Waits on your answer",  # i18n: msgid
	"process": "Under way",  # i18n: msgid
	"closure": "A plant closure",  # i18n: msgid
	"search": "A buyer sought",  # i18n: msgid
	"rescue": "A plant rescue",  # i18n: msgid
	"failing": "A rescue window",  # i18n: msgid
	"bid": "A takeover bid",  # i18n: msgid
	"programme": "A programme",  # i18n: msgid
}


## The sheet under `parent` for `row` (a SectorsTimeline row), or the empty sheet's line.
static func build(panel, parent: Control, row: Dictionary) -> VBoxContainer:
	var state = panel._state
	var loader = panel._loader
	var ns = state.player()
	var body := PanelKit.sheet(parent)
	body.set_meta("decision", String(row.get("key", "")))
	if row.is_empty():
		PanelKit.plain_line(body, Strings.t("Nothing is under way. A decision the economy puts to you lands on the timeline, with its date."))
		return body
	var company = panel._firm_object(ns.id, String(row["company_id"])) if String(row["company_id"]) != "" else null
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	body.add_child(top)
	if company != null:
		top.add_child(Portrait.control_for(String(company.chief_id), FACE))
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	top.add_child(words)
	PanelKit.plain_line(words, ("%s · %s" % [Labels.sector(String(row["sector"])),
		Strings.t(String(KIND_WORDS.get(String(row["kind"]), "")))]).to_upper(), PanelKit.Tone.PLAIN).theme_type_variation = UiTheme.HEADING  # i18n: row-ok the table's msgids
	var title := PanelKit.plain_line(words, String(row["title"]), PanelKit.Tone.PLAIN)
	title.theme_type_variation = UiTheme.LEAD
	PanelKit.plain_line(words, String(row["sub"]))
	_tiles(body, state, ns, row, company)
	_answers(panel, body, state, loader, ns, row, company)
	var open := PanelKit.button(Strings.t("Open %s") % Labels.sector(String(row["sector"])), PanelKit.Size.L)
	open.flat = true
	open.set_meta("open_tab", SectorNeeds.tab_of(String(row["sector"])))
	open.pressed.connect(func() -> void: panel.tab_requested.emit(SectorNeeds.tab_of(String(row["sector"]))))
	body.add_child(open)
	return body


## The figure tiles: the firm's jobs, then the date the row settles (its answer, or its end).
static func _tiles(body: Control, state, ns, row: Dictionary, company) -> void:
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	body.add_child(tiles)
	if company != null:
		tile(tiles, CompanyVerb.thousands(Companies.headcount(ns, company)), Strings.t("Jobs"))
	if int(row["due"]) >= 0:
		tile(tiles, SectorsTimeline.date_in(state, int(row["due"])), Strings.t("Answer by"))
	elif int(row["ends"]) >= 0:
		tile(tiles, SectorsTimeline.date_in(state, int(row["ends"])), Strings.t("Ends"))
	if String(row.get("money", "")) != "":
		tile(tiles, String(row["money"]), Strings.t("Cost"))


## A figure on a tile (G3's figure tile): the side sheet's, the sector tab's head and firm sheet.
static func tile(parent: Control, value: String, caption: String) -> PanelContainer:
	var plate := PanelContainer.new()
	plate.theme_type_variation = UiTheme.TILE_PANEL
	parent.add_child(plate)
	PanelKit.figure(plate, value, caption)
	return plate


## What the row asks, built by the reader that knows its kind.
static func _answers(panel, body: Control, state, loader, ns, row: Dictionary, company) -> void:
	var source: Dictionary = row.get("source", {})
	match String(row["kind"]):
		"ask", "process":
			PanelKit.heading(body, Strings.t("Your answer") if String(row["kind"]) == "ask" else Strings.t("Under way"))
			IndustryProgress.process_row(body, state, loader, ns, source, panel._on_stop, panel._on_answer)
		"closure", "search":
			ClosureCard.build(body, state, loader, ns, source, panel._on_closure)
		"rescue":
			IndustryProgress.rescue(body, loader, ns, source)
		"failing":
			PanelKit.plain_line(body, Strings.tn("Its rescue window closes in %d month.", "Its rescue window closes in %d months.",
				int(source["months_left"])) % int(source["months_left"]))
			var action = panel._action_by_id("strategic_rescue")
			if action != null and company != null:
				PanelKit.buttons(body).add_child(panel._action_button(ns, company, action))
		"bid":
			PanelKit.plain_line(body, Strings.t("%s offers %s bn for %s -- %d months left.") % [
				loader.nation_name(String(source["bidder_nation"])), Num.f(float(source["price_eur_bn"]), 1),
				loader.firm_name(ns.id, String(source["company_id"])), int(source["months_left"])])
			# available() is the door execute() refuses through: a verb it does not offer is not drawn.
			var offered: Array = Companies.available(state, ns, loader.company_actions, String(source["company_id"]), loader)
			var flow := PanelKit.buttons(body)
			for action_id in ["block_takeover", "allow_takeover"]:
				var action = panel._action_by_id(action_id)
				if action != null and offered.has(action) and company != null:
					flow.add_child(panel._action_button(ns, company, action))
		"programme":
			PanelKit.plain_line(body, Strings.t("It runs until you change it in the finance bill, on the sector's tab."))
