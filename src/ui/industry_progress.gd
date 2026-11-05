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

const ProcessAsks = preload("res://src/sim/process_asks.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const DateText = preload("res://src/ui/date_text.gd")
## A closed process's words and tone (closed_last_month's outcomes, the walk apart).
const ENDED := {
	"landed": "done",  # i18n: msgid
	"accepted": "your counter was accepted, done",  # i18n: msgid
	"stopped": "stopped",  # i18n: msgid
	"refused": "refused",  # i18n: msgid
	"cleared": "cleared",  # i18n: msgid
	"settled": "settled",  # i18n: msgid
	"void": "called off",  # i18n: msgid
}
const ENDED_TONE := {"walked": ResultTone.BAD, "landed": ResultTone.GOOD, "accepted": ResultTone.GOOD}

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
	var rescues := Closures.rescues(ns)
	# An open row says its own counter's outcome (_outcome): the closed lines are the rest.
	var ended: Array = ProcessAsks.closed_last_month(state, ns).filter(func(line: Dictionary) -> bool:
		return not rows.any(func(r: Dictionary) -> bool: return String(r["id"]) == String(line["id"])))
	if rows.is_empty() and closures.is_empty() and rescues.is_empty() and ended.is_empty():
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	parent.add_child(box)
	PanelKit.heading(box, Strings.t("In progress"))
	for line in ended:
		_ended(box, loader, ns, line)
	for row in closures:
		_closure(box, state, loader, ns, row, closure)
	for row in rescues:
		_rescue(box, loader, ns, row)
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
		_outcome(box, row)
		if row.has("answer"):
			PanelKit.plain_line(box, Strings.t("Answered: %s.") % _label(String(row["answer"])))
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
	var counters: Array = []
	for option in ask["answers"]:
		var id := String(option["id"])
		if option.has("counter"):
			counters.append(option)
			continue
		var flow := PanelKit.buttons(box)
		var button := PanelKit.sized(Button.new())
		button.text = _label(id)
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
	if not counters.is_empty():
		_counters(box, process_id, counters, what, answer)
	PanelKit.plain_line(box, Strings.t("Unanswered by next month: %s.") % _label(String(ask["default"])))


## #280's counters as ONE row (the parent's design): a chip per counter (5, 10, 15 %),
## the picked chip's strip under the row -- the countered price, the blocs, its chances
## as the sim shows them (the range, NEVER the drawn odds) and the walk-away risk --
## and one button that makes the picked counter. The picks are read, then answered.
static func _counters(box: Control, process_id: String, counters: Array, what: String, answer: Callable) -> void:
	var row := PanelKit.buttons(box)
	PanelKit.plain_line(row, Strings.t("Counter"), PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_OFF
	var group := ButtonGroup.new()
	# No fixed width (the parent's ruling on #281): the strip takes half the row, a
	# spacer the other half, so it shrinks with a narrow workspace and wraps at a larger
	# text size, while its money stays near its caption rather than at the far edge.
	var strip := EffectsStrip.new()
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.set_meta("counter_strip", true)
	var half := HBoxContainer.new()
	half.add_child(strip)
	var rest := Control.new()
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	half.add_child(rest)
	var go := PanelKit.sized(Button.new())
	go.text = Strings.t("Make the counter")
	go.set_meta("answer_id", "counter")
	var picked := [String(counters[0]["id"])]
	var show := func(option: Dictionary) -> void:
		picked[0] = String(option["id"])
		strip.show_lines(Strings.t("Treasury"), EffectsStrip.cost_text(-float(option["debt_eur_bn"])), -float(option["debt_eur_bn"]),
			EffectsStrip.who_text(option["bloc_offset"]),
			Strings.t("A %d to %d %% chance they accept. Refused, the old price stands, or they walk away: %d %% of refusals.") % [
				roundi(100.0 * float(option["odds_lo"])), roundi(100.0 * float(option["odds_hi"])), roundi(100.0 * float(option["walk"]))])
	for option in counters:
		var chip := PanelKit.sized(Button.new())
		chip.text = Strings.t("%d %%") % roundi(100.0 * float(option["counter"]))
		chip.toggle_mode = true
		chip.button_group = group
		chip.button_pressed = String(option["id"]) == picked[0]
		chip.set_meta("counter_id", String(option["id"]))
		chip.pressed.connect(func() -> void: show.call(option))
		row.add_child(chip)
	box.add_child(half)
	box.add_child(go)
	go.pressed.connect(func() -> void: answer.call(process_id, String(picked[0]), what))
	show.call(counters[0])


## A process the month end just closed, for that one month (the parent's ruling on
## #281): walked is BAD and names the hold's last month, done is GOOD, the rest plain.
static func _ended(box: Control, loader, ns, line: Dictionary) -> void:
	var outcome := String(line["outcome"])
	var what := "%s, %s" % [Strings.row_name("company-actions", _action(loader, String(line["action_id"]))),
		loader.firm_name(ns.id, String(line["company_id"]))]
	var text := Strings.t("%s: %s.") % [what, Strings.t(String(ENDED.get(outcome, outcome)))]  # i18n: row-ok the table's words
	if outcome == "walked":
		var last := int(line["hold_ends"]) - 1
		var until := DateText.month_year((last - 1) % 12 + 1, floori((last - 1) / 12.0))
		text = (Strings.t("%s: the buyers walked away, no bids until %s.") if String(line["side"]) == "buyers"
			else Strings.t("%s: the seller walked away, no talks until %s.")) % [what, until]
	var label := PanelKit.plain_line(box, text, PanelKit.Tone.PLAIN)
	label.set_meta("closed_outcome", outcome)
	if ENDED_TONE.has(outcome):
		ResultTone.tint(label, String(ENDED_TONE[outcome]))


## An answer's words: the table's, or a counter's ("Counter 10 %", #280's negotiate_N).
static func _label(id: String) -> String:
	if id.begins_with("negotiate_"):
		return Strings.t("Counter %d %%") % int(id.trim_prefix("negotiate_"))
	return Strings.t(String(ANSWER.get(id, id)))


## A counter's outcome, once drawn (#280): accepted, or refused with the old price
## asked again. A walk-out closes the process, so its row is gone.
static func _outcome(box: Control, row: Dictionary) -> void:
	var talk: Dictionary = row.get("negotiation", {})
	match String(talk.get("outcome", "")):
		"accepted":
			PanelKit.plain_line(box, Strings.t("Your counter was accepted.")).set_meta("negotiation", "accepted")
		"back":
			PanelKit.plain_line(box, Strings.t("Your counter was refused: the old price is asked again.")).set_meta("negotiation", "back")


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


## A plant rescue running (#277, the parent's call: a running rescue must be seen):
## the plant, the jobs it keeps, what it costs a year and the months left.
static func _rescue(box: Control, loader, ns, row: Dictionary) -> void:
	var firm: String = loader.firm_name(ns.id, String(row["company_id"]))
	var city = Region.find_city(loader.regions.get(ns.id, []), String(row["city_id"]))
	var place: String = String(city.city_name) if city != null else firm
	var left := int(row["months_left"])
	var rescued := Strings.tn("%s's plant in %s is rescued: %s jobs kept, %s a year, %d month left.", "%s's plant in %s is rescued: %s jobs kept, %s a year, %d months left.", left)
	var line := PanelKit.plain_line(box, rescued % [firm, place, CompanyVerb.thousands(float(row["jobs"])),
		EffectsStrip.sum_text(-float(row["rescue_eur_bn_per_year"])), left], PanelKit.Tone.PLAIN)
	line.set_meta("rescue", String(row["company_id"]))


## [text, gain]: a close books nothing; a buyer search its losses now and the
## sweetener at a sale; a rescue the plant's price a year for its term (in millions
## when small, never "0.0 bn"), its tone on the whole term.
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
	var months := int(option["months"])
	return [Strings.tn("%s a year for %d month", "%s a year for %d months", months) % [EffectsStrip.sum_text(year), months],
		-float(option["total_eur_bn"])]


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
	var term := int(option["months"])
	return Strings.tn("The jobs are kept for %d month, then the plant is reviewed.", "The jobs are kept for %d months, then the plant is reviewed.", term) % term


static func _closure_label(loader, option: Dictionary) -> String:
	match String(option["kind"]):
		"close":
			return Strings.t("Let it close")
		"buyer":
			return Strings.t("Find a buyer")
		"rescue":
			return Strings.t("Rescue the plant")
	var action = _action(loader, String(option["id"]))
	return Strings.row_name("company-actions", action) if action != null else String(option["id"])


static func _action(loader, id: String):
	for a in loader.company_actions:
		if String(a.id) == id:
			return a
	return null
