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
const AnswerRow = preload("res://src/ui/answer_row.gd")
const IndustryVerbs = preload("res://src/ui/industry_verbs.gd")
const AidWords = preload("res://src/ui/aid_words.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const ClosureCard = preload("res://src/ui/closure_card.gd")
const SectorNeeds = preload("res://src/ui/sector_needs.gd")
const SectorsTimeline = preload("res://src/ui/sectors_timeline.gd")
const Closures = preload("res://src/sim/closures.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")

const FACE := Vector2(48, 62)
## The sheet's width, in px at text size 100: about a third of the page (Design's T3 on #441).
const WIDTH := 420.0
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
		PanelKit.plain_line(body, Strings.t("No decision waits."))
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
	# A plant's sub is its jobs, which its Jobs tile reads.
	if not String(row["kind"]) in ["closure", "search", "rescue"]:
		PanelKit.plain_line(words, String(row["sub"]))
	# The date the answer is due: an amber tag at the head's right (Design's T6), the only amber here.
	if int(row["due"]) >= 0:
		var due := PanelKit.chip(top, Strings.t("answer by %s") % SectorsTimeline.answer_by(state, int(row["due"])), UiTheme.CHIP_WARN, "event")  # i18n: ok an icon file name
		due.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		due.set_meta("answer_by", String(row["key"]))
	_tiles(body, state, ns, row, company)
	_answers(panel, body, state, loader, ns, row, company)
	# A ghost, not bold text: a click has two looks, a button or a ghost (Design's T9).
	var open := PanelKit.button(Strings.t("Open %s") % Labels.sector(String(row["sector"])), PanelKit.Size.L)
	open.theme_type_variation = UiTheme.GHOST
	open.set_meta("open_tab", SectorNeeds.tab_of(String(row["sector"])))
	open.pressed.connect(func() -> void: panel.tab_requested.emit(SectorNeeds.tab_of(String(row["sector"]))))
	body.add_child(open)
	return body


## The figure tiles (Design's T6): the price the answer turns on, the row's own jobs, the
## firm's worth. A plant's row counts the plant's jobs; a failing major none (a failed firm
## employs nobody); the rest the firm's. The date is the head's tag, not a tile.
static func _tiles(body: Control, state, ns, row: Dictionary, company) -> void:
	var tiles := HFlowContainer.new()
	tiles.add_theme_constant_override("h_separation", 8)
	tiles.add_theme_constant_override("v_separation", 8)
	body.add_child(tiles)
	var kind := String(row["kind"])
	var source: Dictionary = row["source"]
	# A price ask (a stake, a nationalisation, a sale): its first answer books the price. A
	# contested ruling's first answer is pressing on, which is not a price: no tile.
	var priced: bool = String(source.get("ask", {}).get("kind", "")) != "contest" and not (source.get("ask", {}).get("answers", []) as Array).is_empty()
	if kind == "ask" and priced:
		var first: Dictionary = source["ask"]["answers"][0]
		PanelKit.figure_tile(tiles, EffectsStrip.cost_text(-float(first["debt_eur_bn"])), Strings.t("Price"))
	elif kind == "bid":
		PanelKit.figure_tile(tiles, Strings.t("%s bn") % Num.f(float(source["price_eur_bn"]), 1), Strings.t("Offer"))
	elif String(row.get("money", "")) != "":
		PanelKit.figure_tile(tiles, String(row["money"]), Strings.t("Cost"))
	if kind in ["closure", "search", "rescue"]:
		PanelKit.figure_tile(tiles, CompanyVerb.thousands(float(source.get("jobs", 0.0))), Strings.t("Jobs"))
	elif company != null and kind != "failing":
		PanelKit.figure_tile(tiles, CompanyVerb.thousands(Companies.headcount(ns, company)), Strings.t("Jobs"))
	if company != null and kind != "failing":
		PanelKit.figure_tile(tiles, Strings.t("%s bn") % Num.f(Companies.value_eur_bn(ns, company), 1), Strings.t("Worth"))
	if int(row["due"]) < 0 and int(row["ends"]) >= 0:
		PanelKit.figure_tile(tiles, SectorsTimeline.date_in(state, int(row["ends"])), Strings.t("Ends"))


## What the row asks, built by the reader that knows its kind.
static func _answers(panel, body: Control, state, loader, ns, row: Dictionary, company) -> void:
	var source: Dictionary = row.get("source", {})
	match String(row["kind"]):
		"ask", "process":
			PanelKit.heading(body, Strings.t("Your answer") if String(row["kind"]) == "ask" else Strings.t("Under way"))
			IndustryProgress.process_row(body, state, loader, ns, source, panel._on_stop, panel._on_answer)
		"closure", "search":
			ClosureCard.build(body, state, loader, ns, source, panel._on_closure,
				String(source.get("status", "")) == Closures.ANNOUNCED)
		"rescue":
			IndustryProgress.rescue(body, loader, ns, source)
		"failing":
			PanelKit.plain_line(body, Strings.tn("Its rescue window closes in %d month.", "Its rescue window closes in %d months.",
				int(source["months_left"])) % int(source["months_left"]))
			var action = panel._action_by_id("strategic_rescue")
			if action != null and company != null:
				_verb_row(panel, AnswerRow.list(body), state, loader, ns, company, action)
		"bid":
			PanelKit.plain_line(body, Strings.t("%s offers %s bn for %s -- %d months left.") % [
				loader.nation_name(String(source["bidder_nation"])), Num.f(float(source["price_eur_bn"]), 1),
				loader.firm_name(ns.id, String(source["company_id"])), int(source["months_left"])])
			# available() is the door execute() refuses through: a verb it does not offer is not drawn.
			var offered: Array = Companies.available(state, ns, loader.company_actions, String(source["company_id"]), loader)
			var list := AnswerRow.list(body)
			for action_id in ["block_takeover", "allow_takeover"]:
				var action = panel._action_by_id(action_id)
				if action != null and offered.has(action) and company != null:
					_verb_row(panel, list, state, loader, ns, company, action)
		"programme":
			# What the programme does, in its data's words; its stop is changed in the finance bill.
			PanelKit.plain_line(body, Strings.row_summary("investment-actions", source["action"]))
			PanelKit.plain_line(body, Strings.t("It runs until you change it in the finance bill, on the sector's tab."))


## A firm verb as an answer row (a bid's Block / Allow, a rescue window's package): the verb's
## own gated button, its price as the verbs print it, the blocs it moves.
static func _verb_row(panel, list: VBoxContainer, state, loader, ns, company, action) -> void:
	var money: Array = IndustryVerbs.money_line(state, loader, ns, company, action, {})
	# A refused verb says why beside it, never only greyed (band A5).
	var why := CompanyVerb.refusal(state, loader, ns, company, action)
	AnswerRow.add(list, panel._action_button(ns, company, action), String(money[1]),
		AidWords.offsets(state, loader, ns, company, action), Strings.t(why) if why != "" else "")  # i18n: row-ok the sim's reason, its English the msgid
