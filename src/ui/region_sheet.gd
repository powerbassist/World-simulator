extends RefCounted

## The opened region's sheet -- screen 6, Regions (Gameplay's regions brief, sections 3 and
## 5b; the regions card's rulings). The same sheet whatever leads the room beside it, in the
## order the player decides by:
##   1. what is wrong: the problem line (Regions.problem), three figures, and its 12 months
##      against the nation's, read from the region's own sample (RegionRead / region_history);
##   2. who speaks for it: the regional figure whose want names the region, and what their
##      voice is worth if a fund opens (region_voice.gd, the sim's own arithmetic);
##   3. what is happening there: where unrest lands and whether it costs now, people leaving
##      or coming;
##   4. the development fund (region_fund.gd), its strip carrying the other regions' loss and
##      the figure's voice.
## Cut from the old opened region, as the brief asks: the sector priority (it leaves the
## screen; the rule stays in the sim), Reach, Named jobs, the share of output.

const Regions = preload("res://src/sim/regions.gd")
const RegionRead = preload("res://src/sim/region_read.gd")
const Migration = preload("res://src/sim/migration.gd")
const CK = preload("res://src/sim/character_act_constants.gd")
const RegionFund = preload("res://src/ui/region_fund.gd")
const RegionVoice = preload("res://src/ui/region_voice.gd")
const RegionTint = preload("res://src/ui/region_tint.gd")
const WantTerms = preload("res://src/sim/want_terms.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

## The figure's face beside their line: the firm sheet's chief size.
const FACE := Vector2(40, 52)
## A migration under this many people in the sample says nothing: noise, not a story.
const MIGRATION_SHOWN := 50.0


static func build(panel, box: Control, ns, region, regions: Array, access: Dictionary) -> void:
	var state = panel._state
	var sited: Dictionary = state.project_sited_pct.get(ns.id, {})
	var share := Migration.region_share(ns, region.id)
	var p: Dictionary = Regions.problem(ns, regions, region.id, access, sited, share)
	var line := PanelKit.plain_line(box, RegionFund.problem_text(p), PanelKit.Tone.PLAIN)
	line.set_meta("problem", true)
	# The tone follows the ratio as printed: "1.0 times" is never flagged.
	if float(p["ratio"]) >= 1.05:
		line.theme_type_variation = UiTheme.WARN_TEXT
	var figures := HBoxContainer.new()
	figures.add_theme_constant_override("separation", 24)
	box.add_child(figures)
	var jobless := Regions.unemployment_pct(ns, regions, region.id, access, sited)
	# One-word captions: a figure's box is as wide as its value, and a longer caption wraps
	# to a column of words (the first frame). The nation's figures are in the problem line.
	PanelKit.figure(figures, "%s %%" % Num.f(jobless, 1), Strings.t("Jobless"))
	PanelKit.figure(figures, "%s %%" % Num.f(Regions.gdp_per_head_index(ns, regions, region.id, share) * 100.0, 0), Strings.t("Per head"))
	PanelKit.figure(figures, PanelKit.pop_text(float(ns.population) * share), Strings.t("People"))
	_trend(box, ns, regions, String(region.id))
	PanelKit.heading(box, Strings.t("Who speaks for it"))
	_voice(box, ns, panel._loader, String(region.id))
	var happening := _happening(state, ns, String(region.id))
	if not happening.is_empty():
		PanelKit.heading(box, Strings.t("Happening here"))
		for text in happening:
			PanelKit.plain_line(box, text, PanelKit.Tone.PLAIN)
	RegionFund.build(panel, box, ns, region, regions, access)


## "Jobless over 12 months: -0.3 point here, -0.1 in the nation." The nation's change is the
## regions' own, weighted by their people, so the two figures are one measure. Said only once
## the sample holds two months: a change of one month is not a change.
static func _trend(box: Control, ns, regions: Array, region_id: String) -> void:
	var moved := RegionTint.changes(ns, regions)
	if not (moved["here"] as Dictionary).has(region_id):
		return
	var held := RegionRead.months_held(ns)
	var text := Strings.tn("Jobless over %d month: %s points here, %s in the nation.", "Jobless over %d months: %s points here, %s in the nation.", held) % [
		held, Num.fs(float(moved["here"][region_id]), 1), Num.fs(float(moved["nation"]), 1)]
	PanelKit.plain_line(box, text, PanelKit.Tone.DIM).set_meta("trend", true)


## The regional figure: face, name, and what their voice is worth if a fund opens here.
static func _voice(box: Control, ns, loader, region_id: String) -> void:
	var voices := RegionVoice.of(ns, loader, region_id)
	if voices.is_empty():
		PanelKit.plain_line(box, Strings.t("Nobody speaks for this region."), PanelKit.Tone.DIM).set_meta("voice", true)
		return
	for v in voices:
		var person = v["person"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		row.add_child(Portrait.control_for(String(person.id), FACE))
		var text: String
		# QA's T1 on #383: the voice fires when the want TURNS served (Characters._settle_wants),
		# and a region holds one fund: while one runs, the sheet promises nothing more.
		if WantTerms.fund_open(ns, region_id):
			text = Strings.t("%s asked for a development fund here, and it runs.") % person.person_name
		elif bool(v["hostile"]):
			text = Strings.t("%s wants a development fund here, but bears you a grudge and would not speak for you.") % person.person_name
		elif RegionFund.in_bill(ns, "start", region_id):
			text = Strings.t("%s wants a development fund here. If the finance bill passes, %s speaks for you once: %s +%s points, half of it gone in %d months.") % [
				person.person_name, person.person_name, RegionVoice.blocs_text(), Num.f(float(v["points"]), 1), CK.ACT_OFFSET_HALF_LIFE_MONTHS]
		else:
			text = Strings.t("%s wants a development fund here. Open one and %s speaks for you once: %s +%s points, half of it gone in %d months.") % [
				person.person_name, person.person_name, RegionVoice.blocs_text(), Num.f(float(v["points"]), 1), CK.ACT_OFFSET_HALF_LIFE_MONTHS]
		var label := PanelKit.plain_line(row, text, PanelKit.Tone.PLAIN)
		# Wrapped in the narrow dock: a label in an HBox is as wide as its text otherwise.
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 1
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.set_meta("voice", true)


## What the sim has to say about the region this month: where unrest lands, people moving.
static func _happening(state, ns, region_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var site: Dictionary = RegionRead.unrest_site(state, ns)
	if String(site.get("region_id", "")) == region_id:
		if float(site.get("opinion_load", 0.0)) > 0.0:
			out.append(Strings.t("Unrest gathers in %s, and weighs on your approval.") % String(site["city_name"]))
		else:
			out.append(Strings.t("Where unrest would land: %s. None this month.") % String(site["city_name"]))
	var moved := 0.0
	var series: Array = ns.region_history.get(region_id, {}).get("migration", [])
	for m in series:
		moved += float(m)
	if absf(moved) >= MIGRATION_SHOWN:
		# pop_text is for millions ("0 k" for 300); a few hundred is said to the ten.
		var people := PanelKit.pop_text(absf(moved)) if absf(moved) >= 10000.0 else Num.f(snappedf(absf(moved), 10.0), 0)
		if moved < 0.0:
			out.append(Strings.tn("%s people left for other regions in %d month.", "%s people left for other regions in %d months.", series.size()) % [people, series.size()])
		else:
			out.append(Strings.tn("%s people came from other regions in %d month.", "%s people came from other regions in %d months.", series.size()) % [people, series.size()])
	return out
