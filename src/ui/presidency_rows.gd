extends RefCounted

## The Presidency page's worded rows (presidency_page.gd draws them): the majority's line,
## the state's own reads, an issue, a past decision. Static, read-only over GameState, beside
## the page so the page keeps to its layout. The msgids are the Overview's where the words
## are its words, so their French carried over when the Overview went (rework 2, slice 1).

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const Trends = preload("res://src/ui/trends.gd")
const DateText = preload("res://src/ui/date_text.gd")
const EffectsLedger = preload("res://src/ui/effects_ledger.gd")
const Government = preload("res://src/sim/government.gd")
const Defence = preload("res://src/sim/defence.gd")
const Society = preload("res://src/sim/society.gd")
const SocietyK = preload("res://src/sim/society_constants.gd")
const K = preload("res://src/sim/opinion_constants.gd")

## A satisfaction inside this band reads as neither pleased nor angry (the Overview's band).
const SATISFACTION_BAND := 0.15
## Per past decision, the figures it names: its worst movers (the Overview's U4 number).
const EFFECT_FIGURES_SHOWN := 2


## Which start this game was begun under, after the nation's name; empty for the standard one.
static func start_suffix(state, loader) -> String:
	if state.scenario_id == "" or loader == null:
		return ""
	var scenario = loader.scenarios.get(state.scenario_id)
	return "" if scenario == null else " · %s" % scenario.display_name


## The majority, every read the Overview's Government column gave it: the seats, the standing
## and the line a majority must clear, what a censure would do today at ordinary hostility,
## and Article 49.3 where the constitution has it. [text, tone] pairs, one per line.
static func majority(ns, loader) -> Array:
	var word := standing_word(ns)
	var seats := "%d / %d %s" % [int(ns.coalition_seats), int(ns.assembly_seats), Strings.t("seats held")]
	var out: Array = [["%s · %s" % [seats, Strings.t("%s — a majority needs more than %d.") % [
		word.substr(0, 1).to_upper() + word.substr(1), Government.majority_seats(ns)]], PanelKit.Tone.PLAIN]]
	if ns.censure_rule == "none" or loader == null:
		out.append([Strings.t("No censure procedure."), PanelKit.Tone.DIM])
	else:
		# The Overview's tones: a censure that would fail is good news, one that would carry bad.
		var censure: Dictionary = Government.resolve_censure(ns, loader.parties.get(ns.id, []), false)
		var carried := bool(censure["carried"])
		var said := Strings.t("A censure motion would carry: %d of %d.") if carried else Strings.t("A censure motion would fail: %d of %d.")
		out.append([said % [int(censure["for_seats"]), int(censure["threshold"])], PanelKit.Tone.BAD if carried else PanelKit.Tone.GOOD])
	# Only where the constitution has it: a nation without it says nothing rather than "unavailable".
	if ns.formation_method == "presidential_appointment":
		if Government.can_force(ns):
			out.append([Strings.t("Article 49.3 available."), PanelKit.Tone.DIM])
		else:
			out.append([Strings.t("Article 49.3 in %s.") % Trends.months_text(int(ns.force_cooldown_months)), PanelKit.Tone.DIM])
	return out


## The state's own reads, which no other tab prints (the Overview's Government column, kept
## when the column went; the parent's call (a)): capability with the price it sets, an
## alliance only when there is one, a service's delivery and the press only once the player
## has moved them. [text, tone, window] rows: defence opens Diplomacy, the services and the
## administration Finances (their spending lines), the press the Legislature (its laws set it).
static func state_lines(state, ns) -> Array:
	var out: Array = [[Strings.t("Military capability %s — a deployment costs %s%% of GDP.") % [
		Num.f(ns.military_capability, 2), Num.f(Defence.deployment_cost_pct_gdp(ns), 2)], PanelKit.Tone.PLAIN, "diplomacy"]]
	var allies: Array = Defence.allies(state, ns.id)
	if not allies.is_empty():
		var deployed := Defence.deployment_count(state, ns.id)
		if deployed == 0:
			out.append([Strings.t("Allied with %s.") % ", ".join(allies), PanelKit.Tone.DIM, "diplomacy"])
		else:
			out.append([Strings.tn("Allied with %s; %d deployment running.", "Allied with %s; %d deployments running.", deployed) % [
				", ".join(allies), deployed], PanelKit.Tone.BAD, "diplomacy"])
	for key in SocietyK.QUALITY_KEYS:
		var deviation: float = Society.quality_deviation(ns, key)
		# Under half a hundredth prints as a signed zero: too small to print is not a line.
		if absf(deviation) >= 0.005:
			out.append([Strings.t("%s delivery %s on baseline.") % [K.ISSUE_LABEL.get(key, key), Num.fs(deviation, 2)],
				PanelKit.Tone.BAD if deviation < 0.0 else PanelKit.Tone.DIM, "finances"])
	if not is_zero_approx(ns.corruption):
		var delivery: float = Society.delivery_factor(ns)
		out.append([Strings.t("Administration delivers %.0f%% of funding.") % (delivery * 100.0),
			PanelKit.Tone.BAD if delivery < 1.0 else PanelKit.Tone.DIM, "finances"])
	if not is_zero_approx(ns.press_freedom):
		var oversight: bool = ns.press_freedom < 0.0
		var text := Strings.t("Press under state oversight (%s).") if oversight else Strings.t("Press independence guaranteed (%s).")
		out.append([text % Num.fs(ns.press_freedom, 2), PanelKit.Tone.BAD if oversight else PanelKit.Tone.DIM, "legislature"])
	return out


## An issue the country weighs: its name, its weight, and how the country feels about it.
static func issue_text(issue: String, weight: float, sat: float) -> String:
	return "%s · %s · %s" % [K.ISSUE_LABEL.get(issue, issue), Strings.t("%.0f%% of what people weigh") % (weight * 100.0), satisfaction_word(sat)]  # i18n: row-ok ISSUE_LABEL is translated at its source


## A past decision with the figures it moved most -- never every watched figure.
static func effect_row(effect: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "%s — %s %d:" % [String(effect["label"]), DateText.month_long(int(effect["month"])), int(effect["year"])]  # i18n: row-ok an effect's label, routed when queued
	label.theme_type_variation = UiTheme.CAPTION
	row.add_child(label)
	var ranked: Array = EffectsLedger.moved(effect)
	if ranked.is_empty():
		# One line: a wrapping label in an HBox is given no width and stacks one letter wide.
		PanelKit.plain_line(row, Strings.t("nothing moved")).autowrap_mode = TextServer.AUTOWRAP_OFF
	for i in mini(EFFECT_FIGURES_SHOWN, ranked.size()):
		var m: Dictionary = ranked[i]
		var figure := Label.new()
		figure.text = "%s %s" % [String(m["label"]), Trends.change_text(float(m["change"]), String(m["unit"]))]  # i18n: row-ok Trends translates its labels
		figure.theme_type_variation = UiTheme.BAD_TEXT if float(m["severity"]) > 0.0 else UiTheme.GOOD_TEXT
		row.add_child(figure)
	return row


static func standing_word(ns) -> String:
	if ns.is_cohabitation:
		return Strings.t("cohabitation")
	if ns.is_minority:
		return Strings.t("minority government")
	return Strings.t("majority government")


static func satisfaction_word(sat: float) -> String:
	if sat > SATISFACTION_BAND:
		return Strings.t("satisfied")
	if sat < -SATISFACTION_BAND:
		return Strings.t("dissatisfied")
	return Strings.t("neither pleased nor angry")


## Three tones, not two: an electorate neither pleased nor angry is not bad news.
static func satisfaction_tone(sat: float) -> int:
	if sat > SATISFACTION_BAND:
		return PanelKit.Tone.GOOD
	if sat < -SATISFACTION_BAND:
		return PanelKit.Tone.BAD
	return PanelKit.Tone.DIM
