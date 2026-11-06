extends RefCounted

## A plant closure's row on the Industry tab's In progress strip (#251, #285): announced,
## its answers side by side and the buyer's counters; searching, its months left; a buyer
## that came back (OFFERED), one month's re-ask at the old sweetener.

const Closures = preload("res://src/sim/closures.gd")
const Region = preload("res://src/core/region.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")
const CounterChips = preload("res://src/ui/counter_chips.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## One answer's column on a closure card, in px: three fit a docked window.
const ANSWER_WIDTH := 300
## A re-ask's sale (#285), its button and its Answered line.
const SELL_OLD := "Sell at the old price"  # i18n: msgid


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
	var closing := Strings.tn("%s will close its plant in %s: %s jobs, in %d month.", "%s will close its plant in %s: %s jobs, in %d months.", due) % [firm, place, jobs, due]
	if offered:
		# Ruling (b) on #280: the buyer came back at the old sweetener, for one month.
		closing = Strings.t("The buyer came back for %s's plant in %s: %s jobs, at the old price.") % [firm, place, jobs]
	elif due == 0:
		# Drawn in its due month, before the tick lands it (a load, a redraw).
		closing = Strings.t("%s will close its plant in %s: %s jobs, this month.") % [firm, place, jobs]
	var head := PanelKit.plain_line(box, closing, PanelKit.Tone.PLAIN)
	head.theme_type_variation = UiTheme.WARN_TEXT
	if offered and row.has("answer"):
		PanelKit.plain_line(box, Strings.t("Answered: %s.") % Strings.t(SELL_OLD))
		return
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
			strip.show_lines(Strings.t("Treasury"), Strings.t("%s at the sale") % EffectsStrip.sum_text(sale), sale, "",
				Strings.t("The buyer keeps the %s jobs next month.") % jobs)
			button.text = Strings.t(SELL_OLD)
		else:
			var sums: Array = money(option)
			strip.show_lines(Strings.t("Treasury"), String(sums[0]), float(sums[1]),
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
			return [EffectsStrip.cost_text(0.0), 0.0]
		"buyer", "negotiate":
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
static func jobs_text(option: Dictionary) -> String:
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


static func label(option: Dictionary) -> String:
	match String(option["kind"]):
		"close":
			return Strings.t("Let it close")
		"buyer":
			return Strings.t("Find a buyer")
	return Strings.t("Rescue the plant")


## A closure's counter on the strip (#285): the search and the cut sweetener, then what
## a buyer that was found may answer: yes, back at the old sweetener, or gone.
static func _strip(strip, option: Dictionary) -> void:
	var sums: Array = money(option)
	strip.show_lines(Strings.t("Treasury"), String(sums[0]), float(sums[1]), "",
		Strings.t("A %d %% chance a buyer is found, in %d to %d months, else %s jobs are lost. It accepts at %d to %d %%; refused, it returns at the old %s, or walks and the jobs are lost: %d %% of refusals.") % [
			roundi(100.0 * float(option["chance"])), int(option["months"]), int(option["months_hi"]),
			CompanyVerb.thousands(float(option["jobs_lost"])),
			roundi(100.0 * float(option["odds_lo"])), roundi(100.0 * float(option["odds_hi"])),
			EffectsStrip.sum_text(-float(option["back_sweetener_eur_bn"])), roundi(100.0 * float(option["walk"]))])
