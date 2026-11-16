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
## The two sums live on the panel (`_fund_share`, `_fund_years`), so a rebuild keeps
## them; a drag redraws only the strip, never the panel, so the slider keeps the mouse.

const RegionFunds = preload("res://src/sim/region_funds.gd")
## V5.3 e (section 12): Go and Stop table rows of the finance bill, applied at the month's end.
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const ProposalNote = preload("res://src/ui/proposal_note.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const IndustryVerbs = preload("res://src/ui/industry_verbs.gd")
const RegionVoice = preload("res://src/ui/region_voice.gd")
const DateText = preload("res://src/ui/date_text.gd")


## The fund, under the sheet's problem line and voice (region_sheet.gd).
static func build(panel, box: Control, ns, region, _regions: Array, _access: Dictionary) -> void:
	var rule := RegionFunds.limits(panel._loader)
	if rule.is_empty():
		return
	PanelKit.heading(box, Strings.t("Development fund"))
	for row in RegionFunds.open_funds(ns):
		if String(row["region_id"]) == String(region.id):
			if in_bill(ns, "stop", String(row["id"])):
				_in_bill_line(box, ns, Strings.t("Stopping it is in the finance bill: it divides on %s."))
				return
			_running(panel, box, ns, row)
			return
	# QA's T3 on #383: a press tables a row and the sheet said nothing. Once the fund is a row of
	# the tabled bill, the sheet says so with the vote's date, and there is no Go to press twice.
	if in_bill(ns, "start", String(region.id)):
		_in_bill_line(box, ns, Strings.t("The fund is in the finance bill: it divides on %s."))
		return
	_verb(panel, box, ns, region, rule)


## Whether the tabled finance bill carries a fund row on `side`: a start names its region, a
## stop its fund's id (FinanceRows' rows, as table() merged them).
static func in_bill(ns, side: String, key: String) -> bool:
	var funds: Dictionary = (ns.tabled_bill.get("finance", {}) as Dictionary).get("funds", {})
	for row in funds.get(side, []):
		if (side == "start" and String(row.get("region_id", "")) == key) or (side == "stop" and String(row) == key):
			return true
	return false


## The bill's line, its vote date read off the tabled register, and the verb greyed in its place.
static func _in_bill_line(box: Control, ns, text: String) -> void:
	var bill: Dictionary = ns.tabled_bill
	var when := DateText.day_month(int(bill.get("vote_day", 1)), int(bill.get("vote_month", 1)))
	PanelKit.plain_line(box, text % when, PanelKit.Tone.PLAIN).set_meta("in_bill", true)
	var greyed := PanelKit.sized(Button.new())
	greyed.text = Strings.t("In the finance bill")
	greyed.disabled = true
	PanelKit.buttons(box).add_child(greyed)


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
	flow.add_child(stop)
	# A refused Stop says why, as a refused Go does (QA's T2 on #345: a law in the slot
	# made the press do nothing, silently).
	var refusal := PanelKit.plain_line(box, String(panel._fund_refusal))
	refusal.set_meta("stop_refusal", true)
	refusal.visible = String(panel._fund_refusal) != ""
	ResultTone.tint(refusal, ResultTone.BLOCKED)
	stop.pressed.connect(func() -> void:
		_pressed(panel, FinanceBill.table(panel._state, panel._loader, {"funds": {"stop": [String(row["id"])]}})))
	PanelKit.plain_line(flow, Strings.tn("%s a year, %d month left.", "%s a year, %d months left.", months) % [
		EffectsStrip.money_text(-float(row["eur_bn_per_year"])), months], PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_OFF
	# What the money has done: the figure the month it began against now. A fund opened
	# before the snapshot existed has none, and says nothing rather than a wrong change.
	if row.has("unemployment_at_start"):
		var since := PanelKit.plain_line(box, Strings.t("Unemployment here since it began: %s -> %s %%.") % [
			Num.f(float(row["unemployment_at_start"]), 1), Num.f(RegionFunds.unemployment_here(panel._state, ns, String(row["region_id"])), 1)], PanelKit.Tone.PLAIN)
		since.set_meta("fund_since", true)
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
	var lo_share := float(rule["share_pct"][0])
	var lo_years := int(rule["years"][0])
	if float(panel._fund_share) <= 0.0:
		panel._fund_share = lo_share
	if int(panel._fund_years) <= 0:
		panel._fund_years = lo_years
	# One sum a line, each value with its unit beside its own control (QA's TAKE 1 on
	# #269: in one flow, "0.5" ran into the next caption and read "0.5 years"). The share
	# says what it costs too, the sim's estimate at that level (#316's ask): a share of
	# output is not a sum a player can weigh until it is money.
	var share := _slider(PanelKit.buttons(box), lo_share, float(rule["share_pct"][1]), 0.5, float(panel._fund_share), "fund_share",
		func(v: float) -> String: return _share_text(panel, ns, region, v))
	var years := _slider(PanelKit.buttons(box), float(lo_years), float(rule["years"][1]), 1.0, float(panel._fund_years), "fund_years",
		func(v: float) -> String: return Strings.tn("%d year", "%d years", int(v)) % int(v))
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
	share.value_changed.connect(func(v: float) -> void:
		panel._fund_share = v
		redraw.call())
	years.value_changed.connect(func(v: float) -> void:
		panel._fund_years = int(v)
		redraw.call())
	go.pressed.connect(func() -> void:
		_pressed(panel, FinanceBill.table(panel._state, panel._loader, {"funds": {"start": [
			{"region_id": String(region.id), "share_pct": float(panel._fund_share), "years": int(panel._fund_years)}]}})))
	redraw.call()


## A Go or a Stop pressed: its refusal kept on the panel, so the line still says it after
## the rebuild the press asks for (a line set on the old controls was wiped by it).
static func _pressed(panel, tabling: Dictionary) -> void:
	panel._fund_refusal = "" if bool(tabling.get("tabled", false)) else ProposalNote.body(tabling)
	panel.mark_dirty()


## The strip, the Go and the refusal line for the sums the controls hold now: the sim's
## reason the sums cannot open, else the last press's refusal.
static func _price(panel, ns, region, strip, go: Button, refusal: Label) -> void:
	var share := float(panel._fund_share)
	var years := int(panel._fund_years)
	var est: Dictionary = RegionFunds.estimate(panel._state, ns, panel._loader, String(region.id), share, years)
	var ok := bool(est.get("ok", false))
	go.disabled = not ok
	refusal.text = String(panel._fund_refusal) if ok else Strings.t(String(est.get("reason", "")))  # i18n: row-ok the sim's reason, its English the msgid
	refusal.visible = refusal.text != ""
	strip.visible = ok
	if not ok:
		return
	var eur := float(est["eur_bn_per_year"])
	# The figure's voice leads who it moves (brief 5b): the one channel a region's size does
	# not dilute. The other regions' loss is the tradeoff's hidden half (#316's RECORD 3): the
	# fund moves growth between regions, it adds none.
	var who := EffectsStrip.who_text(est["bloc_offset"])
	for v in RegionVoice.of(ns, panel._loader, String(region.id)):
		if not bool(v["hostile"]):
			who = Strings.t("%s speaks for you: %s +%s points.") % [v["person"].person_name, RegionVoice.blocs_text(), Num.f(float(v["points"]), 1)] + " " + who
	strip.show_lines(Strings.t("Treasury"),
		Strings.tn("%s a year for %d year", "%s a year for %d years", years) % [EffectsStrip.money_text(-eur), years], -eur,
		who,
		Strings.t("Unemployment here: %s %% now, %s %% with the fund. The other regions lose %s of output a year. Paid from next month; the lift to demand reverses when it ends.") % [
			Num.f(float(est["unemployment_now"]), 1), Num.f(float(est["unemployment_after"]), 1),
			Strings.t("%s bn") % Num.f(absf(float(est.get("others_eur_bn", 0.0))), EffectsStrip.MONEY_PLACES)])


## The share beside its slider, with the money it costs a year at that level, unsigned
## (a cost beside its control; the strip below carries the Treasury's sign). A level
## the register refuses has no estimate, and reads the share alone.
static func _share_text(panel, ns, region, share: float) -> String:
	var est: Dictionary = RegionFunds.estimate(panel._state, ns, panel._loader, String(region.id), share, int(panel._fund_years))
	if not bool(est.get("ok", false)):
		return Strings.t("%s %% of the region's output a year") % Num.f(share, 1)
	return Strings.t("%s %% of the region's output: %s a year") % [Num.f(share, 1),
		Strings.t("%s bn") % Num.f(float(est["eur_bn_per_year"]), EffectsStrip.MONEY_PLACES)]


## A sum's control: the slider, then its value printed with its unit by `text`.
static func _slider(parent: Control, lo: float, hi: float, step: float, value: float, meta: String, text: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.x = 140
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.set_meta(meta, true)
	parent.add_child(slider)
	var shown := PanelKit.plain_line(parent, String(text.call(value)), PanelKit.Tone.PLAIN)
	shown.autowrap_mode = TextServer.AUTOWRAP_OFF
	slider.set_meta("value_label", shown)
	slider.value_changed.connect(func(v: float) -> void: shown.text = String(text.call(v)))
	return slider
