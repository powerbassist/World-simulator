extends RefCounted

## The Industry tab's In progress strip -- V5.3 a + b step 2, docs/design/v5.3-ab.md
## 2.3: a decision that takes time is shown at the top of the tab it belongs to,
## each row with its stage, the months left and what comes next, and a Stop that
## says what stopping costs before it is pressed (Processes.stop_price(), the sim's
## figure: the break fee or the legal fees spent, and the U-turn's blocs).
##
## A STAGE THAT ASKS (#248, process_asks.gd: "each stage asks you something") puts
## its question on its row, each answer a button with the money it books and the
## blocs it moves, and the answer taken if the player says nothing. Its Stop gives
## way while the question stands: walking away and stopping are among the answers.
##
## A PLANT CLOSURE ANNOUNCED (#251, closures.gd) is a decision card here too: the
## firm, its city, the jobs and the month it lands, then its answers SIDE BY SIDE --
## each its own strip (what it books, the jobs it keeps or loses, the blocs it moves)
## and its button -- and the answer taken if the player says nothing. A buyer search
## shows its months left.
##
## Hidden while nothing runs, which is every game until a process starts: a strip
## that said "nothing in progress" would be words for nothing (the prose budget).

const Processes = preload("res://src/sim/processes.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Closures = preload("res://src/sim/closures.gd")
const Region = preload("res://src/core/region.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")

## One answer's column on a closure card, in px: three fit a docked window.
const ANSWER_WIDTH := 300

## A process's stage, and what its end brings, as a player reads them.
const STAGE := {
	"negotiation": "the negotiation",  # i18n: msgid
	"offer": "the offer",  # i18n: msgid
	"transition": "the transition",  # i18n: msgid
	"investigation": "the investigation",  # i18n: msgid
	"remedy": "the remedy",  # i18n: msgid
	"sale": "the sale",  # i18n: msgid
}
const NEXT := {
	"negotiation": "the transfer",  # i18n: msgid
	"offer": "the transfer",  # i18n: msgid
	"transition": "state control",  # i18n: msgid
	"investigation": "the ruling",  # i18n: msgid
	"remedy": "the break-up",  # i18n: msgid
	"sale": "the windfall",  # i18n: msgid
}
## The question each kind of ask puts (process_asks.gd's STAGE_ASK), and its answers.
const QUESTION := {
	"price": "The seller names the stake's final price.",  # i18n: msgid
	"offer": "The nationalisation's price falls due.",  # i18n: msgid
	"contest": "The authority finds for the break-up; the firm contests it.",  # i18n: msgid
	"bid": "The best bid for the state's share is in.",  # i18n: msgid
}
const ANSWER := {
	"accept": "Accept",  # i18n: msgid
	"walk": "Walk away",  # i18n: msgid
	"pay": "Pay",  # i18n: msgid
	"stop": "Stop",  # i18n: msgid
	"press_on": "Press on",  # i18n: msgid
	"settle": "Settle",  # i18n: msgid
	"hold": "Hold for a new bid",  # i18n: msgid
}


## The strip under `parent`, or null while nothing runs. `stop` is called with the
## process id and the row's words when its Stop is pressed; `answer` with the
## process id, the answer's id and the row's words when an ask is answered;
## `closure` with the closure id, the answer's id and the card's words.
static func build(parent: Control, state, loader, ns, stop: Callable, answer: Callable, closure: Callable) -> Control:
	var rows := Processes.rows(ns)
	var closures := Closures.open(ns)
	if rows.is_empty() and closures.is_empty():
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	parent.add_child(box)
	PanelKit.heading(box, Strings.t("In progress"))
	for row in closures:
		_closure(box, state, loader, ns, row, closure)
	for row in rows:
		var verb := Strings.row_name("company-actions", _action(loader, String(row["action_id"])))
		var firm: String = loader.firm_name(ns.id, String(row["company_id"]))
		var stage := String(row["stage"])
		var months := int(row["months_left"])
		PanelKit.plain_line(box, Strings.tn("%s, %s: %s, %d month left, then %s.", "%s, %s: %s, %d months left, then %s.", months) % [
			verb, firm, Strings.t(String(STAGE.get(stage, stage))), months, Strings.t(String(NEXT.get(stage, "")))],  # i18n: row-ok stage words from the table above
			PanelKit.Tone.PLAIN)
		var what := "%s, %s" % [verb, firm]
		var ask: Dictionary = row.get("ask", {})
		if row.has("answer"):
			PanelKit.plain_line(box, Strings.t("Answered: %s.") % Strings.t(String(ANSWER.get(String(row["answer"]), ""))))
		elif not ask.is_empty():
			_ask(box, String(row["id"]), ask, what, answer)
			continue
		var price: Dictionary = Processes.stop_price(state, ns, loader, String(row["id"]))
		if not bool(price.get("ok", false)):
			# No Stop, and the row says why: a drawn ruling (the stage's last month, a
			# referral the authority clears asks nothing) or a stage past stopping.
			PanelKit.plain_line(box, Strings.t("The authority has reached its finding.") if stage == "investigation"
				else Strings.t(String(price.get("reason", ""))))  # i18n: row-ok the sim's reason, its English the msgid
			continue
		var flow := PanelKit.buttons(box)
		var button := PanelKit.sized(Button.new())
		button.text = Strings.t("Stop")
		button.set_meta("process_id", String(row["id"]))
		var gain := -float(price["debt_eur_bn"])
		var money := PanelKit.plain_line(flow, EffectsStrip.cost_text(gain), PanelKit.Tone.PLAIN)
		money.autowrap_mode = TextServer.AUTOWRAP_OFF
		money.theme_type_variation = EffectsStrip.cell_variation(EffectsStrip.money_tone(gain))
		button.set_meta("money_label", money)
		var who := EffectsStrip.who_text(price.get("bloc_offset", {}))
		if who != "":
			var angers := PanelKit.plain_line(flow, who)
			angers.autowrap_mode = TextServer.AUTOWRAP_OFF
		button.pressed.connect(func() -> void: stop.call(String(row["id"]), what))
		flow.add_child(button)
		flow.move_child(button, 0)
	return box


## The question, each answer a row (its button, the money it books, the blocs it
## moves), and what happens if the player says nothing.
static func _ask(box: Control, process_id: String, ask: Dictionary, what: String, answer: Callable) -> void:
	var question := PanelKit.plain_line(box, Strings.t(String(QUESTION.get(String(ask["kind"]), ""))), PanelKit.Tone.PLAIN)
	question.theme_type_variation = UiTheme.WARN_TEXT
	for option in ask["answers"]:
		var id := String(option["id"])
		var flow := PanelKit.buttons(box)
		var button := PanelKit.sized(Button.new())
		button.text = Strings.t(String(ANSWER.get(id, id)))
		button.set_meta("answer_id", id)
		button.set_meta("process_id", process_id)
		button.pressed.connect(func() -> void: answer.call(process_id, id, what))
		flow.add_child(button)
		var gain := -float(option["debt_eur_bn"])
		var money := PanelKit.plain_line(flow, EffectsStrip.cost_text(gain), PanelKit.Tone.PLAIN)
		money.autowrap_mode = TextServer.AUTOWRAP_OFF
		money.theme_type_variation = EffectsStrip.cell_variation(EffectsStrip.money_tone(gain))
		button.set_meta("money_label", money)
		var who := EffectsStrip.who_text(option["bloc_offset"])
		if who != "":
			PanelKit.plain_line(flow, who).autowrap_mode = TextServer.AUTOWRAP_OFF
	PanelKit.plain_line(box, Strings.t("Unanswered by next month: %s.") % Strings.t(String(ANSWER.get(String(ask["default"]), ""))))


## A closure: announced, its card and answers; searching, its months left.
static func _closure(box: Control, state, loader, ns, row: Dictionary, closure: Callable) -> void:
	var firm: String = loader.firm_name(ns.id, String(row["company_id"]))
	var city = Region.find_city(loader.regions.get(ns.id, []), String(row["city_id"]))
	var place: String = String(city.city_name) if city != null else firm
	if String(row["status"]) == Closures.SEARCHING:
		var left := int(row["months_left"])
		var sought := Strings.tn("A buyer is sought for %s's plant in %s: %d month left.", "A buyer is sought for %s's plant in %s: %d months left.", left)
		PanelKit.plain_line(box, sought % [firm, place, left], PanelKit.Tone.PLAIN)
		return
	var due := maxi(int(row["due"]) - (int(state.year) * 12 + int(state.month)), 0)
	var jobs := CompanyVerb.thousands(float(row["jobs"]))
	var closing := Strings.tn("%s will close its plant in %s: %s jobs, in %d month.", "%s will close its plant in %s: %s jobs, in %d months.", due) % [firm, place, jobs, due]
	if due == 0:
		# Drawn in its due month, before the tick lands it (a load, a redraw).
		closing = Strings.t("%s will close its plant in %s: %s jobs, this month.") % [firm, place, jobs]
	var head := PanelKit.plain_line(box, closing, PanelKit.Tone.PLAIN)
	head.theme_type_variation = UiTheme.WARN_TEXT
	var flow := PanelKit.buttons(box)
	var what := "%s, %s" % [firm, place]
	for option in Closures.answers(state, ns, loader, String(row["id"])):
		var id := String(option["id"])
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = ANSWER_WIDTH
		flow.add_child(column)
		var strip := EffectsStrip.new()
		column.add_child(strip)
		var money: Array = _closure_money(option)
		strip.show_lines(Strings.t("Treasury"), String(money[0]), float(money[1]),
			EffectsStrip.who_text(option["bloc_offset"]), _closure_jobs(option))
		var button := PanelKit.sized(Button.new())
		button.text = _closure_label(loader, option)
		button.set_meta("closure_answer", id)
		button.set_meta("money_label", strip.money_label)
		button.pressed.connect(func() -> void: closure.call(String(row["id"]), id, what))
		column.add_child(button)
	PanelKit.plain_line(box, Strings.t("Unanswered, the plant closes."))


## [text, gain]: a close books nothing; a buyer search its losses now and the
## sweetener at a sale; a rescue the subsidy's bill a year.
static func _closure_money(option: Dictionary) -> Array:
	match String(option["kind"]):
		"close":
			return [EffectsStrip.cost_text(0.0), 0.0]
		"buyer":
			var now_bn := -float(option["debt_eur_bn"])
			var sale_bn := -float(option["sweetener_eur_bn"])
			# The tone reads both sums: a search that costs little now still books
			# its sweetener at a sale (pass 1: a cost read as neutral).
			return [Strings.t("%s now, %s more at a sale") % [EffectsStrip.sum_text(now_bn),
				EffectsStrip.sum_text(sale_bn)], now_bn + sale_bn]
	var year := -float(option["debt_eur_bn_per_year"])
	return [Strings.t("%s a year") % EffectsStrip.money_text(year), year]


## The jobs, said for each answer: a buyer is a chance, not the default's loss
## (QA's note on #251: its jobs_lost carries the full cut either way).
static func _closure_jobs(option: Dictionary) -> String:
	var jobs := CompanyVerb.thousands(float(option["jobs_lost"]))
	match String(option["kind"]):
		"close":
			return Strings.t("%s jobs lost.") % jobs
		"buyer":
			var months := int(option["months"])
			var odds := Strings.tn("A %d %% chance a buyer keeps the %s jobs, in %d month; else they are lost.", "A %d %% chance a buyer keeps the %s jobs, in %d months; else they are lost.", months)
			return odds % [roundi(100.0 * float(option["chance"])), jobs, months]
	return Strings.t("The jobs are kept.")


static func _closure_label(loader, option: Dictionary) -> String:
	match String(option["kind"]):
		"close":
			return Strings.t("Let it close")
		"buyer":
			return Strings.t("Find a buyer")
	var action = _action(loader, String(option["id"]))
	return Strings.row_name("company-actions", action) if action != null else String(option["id"])


static func _action(loader, id: String):
	for a in loader.company_actions:
		if String(a.id) == id:
			return a
	return null
