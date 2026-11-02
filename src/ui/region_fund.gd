extends RefCounted

## The opened region's decision half -- V5.3 a + b, docs/design/v5.3-ab.md 3.3 (a), the
## author's "i dont understand regions panel, only informative but no decisions
## inside" (G6). What the player reads before acting, in this order: the region's ONE
## problem (Regions.problem(): its worst figure against the nation, in one line),
## then the development fund (#263) as a verb with its strip and a Go.
##
## Every figure is the sim's: the strip is RegionFunds.estimate() at the sums the two
## controls hold -- the money a year, the blocs it moves (national, scaled by the
## region's people), the region's unemployment now and with the fund. A fund the
## register refuses (the cap of open funds, a fund already running here) greys its Go
## and prints RegionFunds.refusal()'s line under it, read before any press (A5's
## grammar, the Industry tab's).
##
## The two sums live on the panel (`_fund_eur`, `_fund_years`), so a rebuild keeps
## them; a drag redraws only the strip, never the panel, so the slider keeps the mouse.

const Regions = preload("res://src/sim/regions.gd")
const RegionFunds = preload("res://src/sim/region_funds.gd")
const Migration = preload("res://src/sim/migration.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const IndustryVerbs = preload("res://src/ui/industry_verbs.gd")


## The problem line, then the fund, at the top of `box` (the opened region).
static func build(panel, box: Control, ns, region, regions: Array, access: Dictionary) -> void:
	var state = panel._state
	var sited: Dictionary = state.project_sited_pct.get(ns.id, {})
	var p: Dictionary = Regions.problem(ns, regions, region.id, access, sited, Migration.region_share(ns, region.id))
	var line := PanelKit.plain_line(box, problem_text(p), PanelKit.Tone.PLAIN)
	line.set_meta("problem", true)
	# The tone follows the ratio as printed: "1.0 times" is never flagged.
	if float(p["ratio"]) >= 1.05:
		line.theme_type_variation = UiTheme.WARN_TEXT
	var rule := RegionFunds.limits(panel._loader)
	if rule.is_empty():
		return
	PanelKit.heading(box, Strings.t("Development fund"))
	for row in RegionFunds.open_funds(ns):
		if String(row["region_id"]) == String(region.id):
			_running(panel, box, ns, row)
			return
	_verb(panel, box, ns, region, rule)


## "Unemployment 11.2 %, 1.5 times the nation's 7.4 %." / "Output per head 82 % of the
## nation's." The same sentence when the region is better than the nation: the ratio
## says so (0.8 times), the line invents no problem.
static func problem_text(p: Dictionary) -> String:
	if String(p["kind"]) == "unemployment":
		return Strings.t("Unemployment %s %%, %s times the nation's %s %%.") % [
			Num.f(float(p["value"]), 1), Num.f(float(p["ratio"]), 1), Num.f(float(p["nation"]), 1)]
	return Strings.t("Output per head %s %% of the nation's.") % Num.f(100.0 * float(p["value"]), 0)


## A fund already running here: what it pays and for how long, and its Stop.
static func _running(panel, box: Control, ns, row: Dictionary) -> void:
	var months := int(row["months_left"])
	var flow := PanelKit.buttons(box)
	var stop := PanelKit.sized(Button.new())
	stop.text = Strings.t("Stop")
	stop.set_meta("fund_id", String(row["id"]))
	stop.pressed.connect(func() -> void:
		RegionFunds.stop(panel._state, ns, String(row["id"]))
		panel.mark_dirty())
	flow.add_child(stop)
	PanelKit.plain_line(flow, Strings.tn("%s a year, %d month left.", "%s a year, %d months left.", months) % [
		EffectsStrip.money_text(-float(row["eur_bn_per_year"])), months], PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_OFF
	# What Stop costs, read before the press: RegionFunds.stop() takes back part of
	# what each pleased bloc gained, so those blocs are the ones it angers.
	var angered := {}
	for bloc in row["bloc_offset"]:
		if float(row["bloc_offset"][bloc]) > 0.0:
			angered[bloc] = -1.0
	var who := EffectsStrip.who_text(angered)
	if who != "":
		var angers := PanelKit.plain_line(flow, who)
		angers.autowrap_mode = TextServer.AUTOWRAP_OFF
		stop.set_meta("who_label", angers)


## The verb: two sums, the strip they price, the Go, and the refusal line.
static func _verb(panel, box: Control, ns, region, rule: Dictionary) -> void:
	var lo_eur := float(rule["eur_bn"][0])
	var lo_years := int(rule["years"][0])
	if float(panel._fund_eur) <= 0.0:
		panel._fund_eur = lo_eur
	if int(panel._fund_years) <= 0:
		panel._fund_years = lo_years
	var sums := PanelKit.buttons(box)
	var eur := _slider(sums, Strings.t("bn a year"), lo_eur, float(rule["eur_bn"][1]), 0.5, float(panel._fund_eur), "fund_eur")
	var years := _slider(sums, Strings.t("years"), float(lo_years), float(rule["years"][1]), 1.0, float(panel._fund_years), "fund_years")
	var strip := EffectsStrip.new()
	# The Industry strip's reading measure: the money beside its caption, not at the
	# window's far edge (the first frame).
	strip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	strip.custom_minimum_size.x = IndustryVerbs.STRIP_WIDTH
	box.add_child(strip)
	var go := PanelKit.sized(Button.new())
	# Not "Go": the opened region's sites already carry a Go, which opens their tab.
	go.text = Strings.t("Start the fund")
	go.set_meta("go", true)
	box.add_child(go)
	var refusal := PanelKit.plain_line(box, "")
	refusal.set_meta("refusal", true)
	ResultTone.tint(refusal, ResultTone.BLOCKED)
	var redraw := func() -> void:
		_price(panel, ns, region, strip, go, refusal)
	eur.value_changed.connect(func(v: float) -> void:
		panel._fund_eur = v
		redraw.call())
	years.value_changed.connect(func(v: float) -> void:
		panel._fund_years = int(v)
		redraw.call())
	go.pressed.connect(func() -> void:
		RegionFunds.start(panel._state, ns, panel._loader, String(region.id), float(panel._fund_eur), int(panel._fund_years))
		panel.mark_dirty())
	redraw.call()


## The strip, the Go and the refusal line for the sums the controls hold now.
static func _price(panel, ns, region, strip, go: Button, refusal: Label) -> void:
	var eur := float(panel._fund_eur)
	var years := int(panel._fund_years)
	var est: Dictionary = RegionFunds.estimate(panel._state, ns, panel._loader, String(region.id), eur, years)
	var ok := bool(est.get("ok", false))
	go.disabled = not ok
	refusal.text = "" if ok else Strings.t(String(est.get("reason", "")))  # i18n: row-ok the sim's reason, its English the msgid
	refusal.visible = not ok
	strip.visible = ok
	if not ok:
		return
	strip.show_lines(Strings.t("Treasury"),
		Strings.tn("%s a year for %d year", "%s a year for %d years", years) % [EffectsStrip.money_text(-eur), years], -eur,
		EffectsStrip.who_text(est["bloc_offset"]),
		Strings.t("Unemployment here: %s %% now, %s %% with the fund. Paid from next month; the lift to demand reverses when it ends.") % [
			Num.f(float(est["unemployment_now"]), 1), Num.f(float(est["unemployment_after"]), 1)])


static func _slider(parent: Control, caption: String, lo: float, hi: float, step: float, value: float, meta: String) -> HSlider:
	PanelKit.plain_line(parent, caption, PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_OFF
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.x = 140
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.set_meta(meta, true)
	parent.add_child(slider)
	var shown := PanelKit.plain_line(parent, Num.f(value, 1 if step < 1.0 else 0), PanelKit.Tone.PLAIN)
	shown.autowrap_mode = TextServer.AUTOWRAP_OFF
	slider.value_changed.connect(func(v: float) -> void: shown.text = Num.f(v, 1 if step < 1.0 else 0))
	return slider
