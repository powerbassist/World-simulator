extends RefCounted

## A plant closure's row on the Industry tab's In progress strip (#251, #285): announced,
## its answers side by side and the buyer's counters; searching, its months left; a buyer
## that came back (OFFERED), one month's re-ask at the old sweetener.

const ActsOn = preload("res://src/ui/acts_on.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Closures = preload("res://src/sim/closures.gd")
const Region = preload("res://src/core/region.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")
const CounterChips = preload("res://src/ui/counter_chips.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const Num = preload("res://src/ui/num.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## One answer's column on a closure card, in px: three fit a docked window.
const ANSWER_WIDTH := 300
## The economy's clause in the card's reason: under this gap the figure prints as 0.0.
const GAP_SAID_PCT := 0.05
## A countered closure's result, the month it lands (the parent's ruling on #287,
## Closures.closed_last_month): the firm, the place, then the sum on a sale, the jobs.
const RESULT := {
	"accepted": "%s's plant in %s is sold at your counter, %s: %s jobs kept.",  # i18n: msgid
	"sold": "%s's plant in %s is sold at the old price, %s: %s jobs kept.",  # i18n: msgid
	"walked": "The buyer walked away from %s's plant in %s, and it closed: %s jobs lost.",  # i18n: msgid
	"no_buyer": "No buyer came for %s's plant in %s, and it closed: %s jobs lost.",  # i18n: msgid
	"closed": "%s's plant in %s closed, as you chose: %s jobs lost.",  # i18n: msgid
	"void": "%s failed before a buyer came for its plant in %s.",  # i18n: msgid
}
## A sale is GOOD and a plant lost to the counter BAD; the player's own closing and a
## firm that failed are plain, no verdict on an answer.
const RESULT_TONE := {"accepted": ResultTone.GOOD, "sold": ResultTone.GOOD, "walked": ResultTone.BAD, "no_buyer": ResultTone.BAD}

## A re-ask's sale (#285), its button and its Answered line.
const SELL_OLD := "Sell at the old price"  # i18n: msgid


## One toned line for one month: the sim's query says which closures, for how long.
static func result(box: Control, loader, ns, line: Dictionary) -> void:
	var outcome := String(line["outcome"])
	if not RESULT.has(outcome):
		push_error("closure_card: a result of unknown outcome '%s'" % outcome)
		return
	var firm: String = loader.firm_name(ns.id, String(line["company_id"]))
	var city = Region.find_city(loader.regions.get(ns.id, []), String(line["city_id"]))
	var place: String = String(city.city_name) if city != null else firm
	var jobs := CompanyVerb.thousands(float(line["jobs"]))
	var figures := [firm, place]
	match outcome:
		"accepted", "sold":
			figures.append_array([EffectsStrip.sum_text(-float(line["sweetener_eur_bn"])), jobs])
		"walked", "no_buyer", "closed":
			figures.append(jobs)
	var text: String = Strings.t(String(RESULT[outcome])) % figures  # i18n: row-ok the table's msgid
	var label := PanelKit.plain_line(box, text, PanelKit.Tone.PLAIN)
	label.set_meta("closure_result", outcome)
	if RESULT_TONE.has(outcome):
		ResultTone.tint(label, String(RESULT_TONE[outcome]))


## Why this plant, said as what the record kept the month it was announced: the firm's
## own output, and the economy when it ran below its potential (the author's call on
## #286: the reason is true).
static func reason(row: Dictionary) -> String:
	var months := int(row["window_months"])
	var fell := Strings.tn("Its output fell %s %% in %d month.", "Its output fell %s %% in %d months.", months) % [
		Num.f(100.0 * float(row["fall"]), 0), months]
	var gap := float(row.get("gap_pct", 0.0))
	if gap > -GAP_SAID_PCT:
		return fell
	return fell + " " + Strings.t("The economy was %s %% below its potential.") % Num.f(-gap, 1)


## A closure: announced, its card and answers; searching, its months left.
static func build(box: Control, state, loader, ns, row: Dictionary, closure: Callable) -> void:
	var firm: String = loader.firm_name(ns.id, String(row["company_id"]))
	var city = Region.find_city(loader.regions.get(ns.id, []), String(row["city_id"]))
	var place: String = String(city.city_name) if city != null else firm
	if String(row["status"]) == Closures.SEARCHING:
		var left := int(row["months_left"])
		var sought := Strings.tn("A buyer is sought for %s's plant in %s: %d month left.", "A buyer is sought for %s's plant in %s: %d months left.", left)
		PanelKit.plain_line(box, sought % [firm, place, left], PanelKit.Tone.PLAIN)
		if row.has("countered"):
			PanelKit.plain_line(box, Strings.t("Answered: %s.") % CounterChips.label(String(row["answer"])))
		return
	var offered := String(row["status"]) == Closures.OFFERED
	var due := maxi(int(row["due"]) - (int(state.year) * 12 + int(state.month)), 0)
	var jobs := CompanyVerb.thousands(float(row["jobs"]))
	var closing := Strings.tn("%s closes its %s plant in %d month: %s jobs.", "%s closes its %s plant in %d months: %s jobs.", due) % [firm, place, due, jobs]
	if offered:
		# Ruling (b) on #280: the buyer came back at the old sweetener, for one month.
		closing = Strings.t("The buyer came back for %s's plant in %s: %s jobs, at the old price.") % [firm, place, jobs]
	elif due == 0:
		# Drawn in its due month, before the tick lands it (a load, a redraw).
		closing = Strings.t("%s closes its %s plant this month: %s jobs.") % [firm, place, jobs]
	var head := PanelKit.plain_line(box, closing, PanelKit.Tone.PLAIN)
	head.theme_type_variation = UiTheme.WARN_TEXT
	if offered and row.has("answer"):
		PanelKit.plain_line(box, Strings.t("Answered: %s.") % Strings.t(SELL_OLD))
		return
	if not offered and row.has("window_months"):
		PanelKit.plain_line(box, reason(row), PanelKit.Tone.PLAIN)
	var flow := PanelKit.buttons(box)
	var what := "%s, %s" % [firm, place]
	var answers := Closures.answers(state, ns, loader, String(row["id"]))
	var make := func(id: String) -> void: closure.call(String(row["id"]), id, what)
	for option in answers:
		var id := String(option["id"])
		if String(option["kind"]) == "negotiate":
			continue
		var column := VBoxContainer.new()
		column.custom_minimum_size.x = ANSWER_WIDTH
		flow.add_child(column)
		var strip := EffectsStrip.new()
		column.add_child(strip)
		var button := PanelKit.sized(Button.new())
		if offered and String(option["kind"]) == "buyer":
			var sale := -float(option["sweetener_eur_bn"])
			strip.show_lines("", Strings.t("%s at the sale") % EffectsStrip.sum_text(sale), sale, "",
				Strings.t("The buyer keeps the %s jobs next month.") % jobs)
			button.text = Strings.t(SELL_OLD)
			ActsOn.tag(button, [String(row["id"])])
		else:
			var sums: Array = money(option)
			strip.show_lines("", String(sums[0]), float(sums[1]),
				EffectsStrip.who_text(option["bloc_offset"]), jobs_text(option))
			button.text = label(option)
		button.set_meta("closure_answer", id)
		button.set_meta("money_label", strip.money_label)
		button.pressed.connect(make.bind(id))
		column.add_child(button)
	var counters := answers.filter(func(o: Dictionary) -> bool: return String(o["kind"]) == "negotiate")
	if not counters.is_empty():
		CounterChips.build(box, String(row["id"]), counters, _strip, make, "closure_answer")
	PanelKit.plain_line(box, Strings.t("Unanswered, the plant is sold at the old price.") if offered else Strings.t("Unanswered, the plant closes."))


## [text, gain]: a close books nothing; a buyer search its losses now and the
## sweetener at a sale; a rescue the plant's price a year for its term (in millions
## when small, never "0.0 bn"), its tone on the whole term.
static func money(option: Dictionary) -> Array:
	match String(option["kind"]):
		"close":
			return [Strings.t("No cost."), 0.0]
		"buyer", "negotiate":
			var now_bn := -float(option["debt_eur_bn"])
			var sale_bn := -float(option["sweetener_eur_bn"])
			# The tone reads both sums: a search that costs little now still books
			# its sweetener at a sale (pass 1: a cost read as neutral).
			return [Strings.t("%s now, %s at a sale") % [EffectsStrip.sum_text(now_bn),
				EffectsStrip.sum_text(sale_bn)], now_bn + sale_bn]
		"rescue":
			var months := int(option["months"])
			return [Strings.tn("%s a year, %d month", "%s a year, %d months", months) % [EffectsStrip.sum_text(-float(option["debt_eur_bn_per_year"])), months],
				-float(option["total_eur_bn"])]
	_unknown(option)
	return ["", 0.0]


## The jobs, said for each answer: a buyer is a chance, not the default's loss
## (QA's note on #251: its jobs_lost carries the full cut either way).
static func jobs_text(option: Dictionary) -> String:
	var jobs := CompanyVerb.thousands(float(option["jobs_lost"]))
	match String(option["kind"]):
		"close":
			return Strings.t("%s jobs lost.") % jobs
		"buyer":
			var months := int(option["months"])
			return Strings.tn("A buyer keeps the jobs: %d %% chance, in %d month.", "A buyer keeps the jobs: %d %% chance, in %d months.", months) % [roundi(100.0 * float(option["chance"])), months]
		"rescue":
			var term := int(option["months"])
			return Strings.tn("Jobs kept %d month, then reviewed.", "Jobs kept %d months, then reviewed.", term) % term
	_unknown(option)
	return ""


static func label(option: Dictionary) -> String:
	match String(option["kind"]):
		"close":
			return Strings.t("Let it close")
		"buyer":
			return Strings.t("Find a buyer")
		"rescue":
			return Strings.t("Rescue the plant")
	_unknown(option)
	return String(option.get("id", ""))


## The parent's ruling on #287: a kind this card does not know is an error in the log
## and a blank on the card, never another answer's words or a crash (#285's first
## "negotiate" fell through to the rescue and read a field it does not carry).
static func _unknown(option: Dictionary) -> void:
	push_error("closure_card: an answer of unknown kind '%s'" % String(option.get("kind", "")))


## A closure's counter on the strip (#285): the search and the cut sweetener, then what
## a buyer that was found may answer: yes, back at the old sweetener, or gone.
static func _strip(strip, option: Dictionary) -> void:
	var sums: Array = money(option)
	# The chance of a buyer is the column beside it; the prose budget (at most 100 words
	# on the announced card, the parent's ruling) keeps this to what a counter adds.
	strip.show_lines("", String(sums[0]), float(sums[1]), "",
		Strings.t("In %d to %d months. It accepts at %d to %d %%; refused, it returns at %s, or walks (%d %% of refusals). No deal, the jobs are lost.") % [
			int(option["months"]), int(option["months_hi"]),
			roundi(100.0 * float(option["odds_lo"])), roundi(100.0 * float(option["odds_hi"])),
			EffectsStrip.sum_text(-float(option["back_sweetener_eur_bn"])), roundi(100.0 * float(option["walk"]))])
