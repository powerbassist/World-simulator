extends RefCounted

## The opened region's sector priority -- V5.3 a, docs/design/v5.3-ab.md 3.3 (a) 1
## (#267): "put hospitals first in Hauts-de-France". Under the development fund, the
## region's second verb: the priorities it holds, each with its term and an End, then
## a sector picker, its strip and "Put first here".
##
## Every figure is the sim's: the strip is Sectors.priority_estimate() for the pick --
## the sector's quantity here and in the other regions, the region's unemployment now
## and with the priority, the term and how often it may still be renewed. A priority
## moves no money (the same spending, shared differently), so the money line says so.
##
## THE RULES ARE READ BEFORE THE PRESS (the parent's go on #267, A5's grammar): at most
## two per region, a term renewable once, then a rest per sector. A pick the sim
## refuses keeps its verb on screen, greyed, with the sim's own line under it, and a
## resting sector says the month it is free again -- never a dead click. A sector
## another region holds is not refused: the strip names the region that loses it,
## since taking it is the choice (one region per sector).
##
## The pick lives on the panel (`_priority_pick`, "line|sector"), so a rebuild keeps
## it; a new pick redraws only the strip.

const Sectors = preload("res://src/sim/sectors.gd")
const DK = preload("res://src/sim/domains_constants.gd")
const BudgetSectors = preload("res://src/ui/budget_sectors.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const IndustryVerbs = preload("res://src/ui/industry_verbs.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")
const BudgetPanel = preload("res://src/ui/budget_panel.gd")


## The section, at the end of `box` (the opened region). Nothing without sector data.
static func build(panel, box: Control, ns, region) -> void:
	var picks := _picks(panel._loader)
	if picks.is_empty():
		return
	PanelKit.heading(box, Strings.t("Sector priority"))
	for key in picks:
		var parts := String(key).split("|")
		if Sectors.priority_of(ns, parts[1]) == String(region.id):
			_held(panel, box, ns, parts[0], parts[1])
	if not picks.has(String(panel._priority_pick)):
		panel._priority_pick = String(picks[0])
	_verb(panel, box, ns, region, picks)


## Every sector of every spending line, as "line|sector", in the data's order.
static func _picks(loader) -> Array:
	var out := []
	for line in loader.domains:
		for s in Sectors.sectors_of(loader, String(line)):
			out.append("%s|%s" % [line, s["id"]])
	return out


## A priority this region holds: its sector, the months left, whether it may still be
## renewed, and its End (which starts the sector's rest here, the sim's rule).
static func _held(panel, box: Control, ns, line: String, sector_id: String) -> void:
	var row: Dictionary = ns.sector_priorities[sector_id]
	var months := int(row["months_left"])
	var flow := PanelKit.buttons(box)
	var end := PanelKit.sized(Button.new())
	end.text = Strings.t("End")
	end.set_meta("priority_clear", sector_id)
	end.pressed.connect(func() -> void:
		Sectors.clear_priority(panel._state, ns, sector_id)
		panel.mark_dirty())
	flow.add_child(end)
	var name := _name(panel._loader, line, sector_id)
	var text := Strings.tn("%s first here, %d month left, renewable once.", "%s first here, %d months left, renewable once.", months) % [name, months]
	if int(row.get("renewals", 0)) >= DK.PRIORITY_MAX_RENEWALS:
		text = Strings.tn("%s first here, %d month left, not renewable.", "%s first here, %d months left, not renewable.", months) % [name, months]
	# What End costs, read before the press (the fund's Stop names the blocs it angers).
	text += " " + Strings.tn("Ending it rests the sector here %d month.", "Ending it rests the sector here %d months.",
		DK.PRIORITY_REST_MONTHS) % DK.PRIORITY_REST_MONTHS
	var held := PanelKit.plain_line(flow, text, PanelKit.Tone.PLAIN)
	held.autowrap_mode = TextServer.AUTOWRAP_OFF
	end.set_meta("held_label", held)


## The verb: the sector picker, the strip, the press, and the refusal lines.
static func _verb(panel, box: Control, ns, region, picks: Array) -> void:
	var option := OptionButton.new()
	for i in picks.size():
		var parts := String(picks[i]).split("|")
		option.add_item(_name(panel._loader, parts[0], parts[1]))
		option.set_item_metadata(i, String(picks[i]))
		if String(picks[i]) == String(panel._priority_pick):
			option.select(i)
	option.set_meta("priority_sector", true)
	PanelKit.buttons(box).add_child(option)
	var strip := EffectsStrip.new()
	strip.set_meta("priority", true)
	strip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	strip.custom_minimum_size.x = IndustryVerbs.STRIP_WIDTH
	box.add_child(strip)
	var go := PanelKit.sized(Button.new())
	go.set_meta("priority_go", true)
	box.add_child(go)
	var refusal := PanelKit.plain_line(box, "")
	refusal.set_meta("priority_refusal", true)
	ResultTone.tint(refusal, ResultTone.BLOCKED)
	var free := PanelKit.plain_line(box, "")
	free.set_meta("priority_free", true)
	var redraw := func() -> void:
		_price(panel, ns, region, strip, go, refusal, free)
	option.item_selected.connect(func(i: int) -> void:
		panel._priority_pick = String(option.get_item_metadata(i))
		redraw.call())
	go.pressed.connect(func() -> void:
		var parts := String(panel._priority_pick).split("|")
		# The world may have moved since the strip was drawn (a month ended under it): a
		# refused press redraws at once, greyed with the sim's line, never a silent no-op.
		if bool(Sectors.set_priority(panel._state, ns, panel._loader, parts[0], parts[1], String(region.id)).get("ok", false)):
			panel.mark_dirty()
		else:
			redraw.call())
	redraw.call()


## The strip, the verb and the refusal lines for the pick the control holds now.
static func _price(panel, ns, region, strip, go: Button, refusal: Label, free: Label) -> void:
	var parts := String(panel._priority_pick).split("|")
	var line := parts[0]
	var sector_id := parts[1]
	var first := Sectors.priority_of(ns, sector_id)
	go.text = Strings.t("Renew here") if first == String(region.id) else Strings.t("Put first here")
	var est: Dictionary = Sectors.priority_estimate(panel._state, ns, panel._loader, line, sector_id, String(region.id))
	var ok := bool(est.get("ok", false))
	go.disabled = not ok
	refusal.text = "" if ok else Strings.t(String(est.get("reason", "")))  # i18n: row-ok the sim's reason, its English the msgid
	refusal.visible = not ok
	strip.visible = ok
	# A resting sector: the month it is free again, from the sim's own register.
	var until := Sectors.rest_until(ns, sector_id, String(region.id))
	var resting := not ok and int(panel._state.year) * 12 + int(panel._state.month) < until
	free.text = Strings.t("Free again from %s.") % DateText.month_year((until - 1) % 12 + 1, floori((until - 1) / 12.0)) if resting else ""
	free.visible = resting
	if not ok:
		return
	var unit := _unit(panel._loader, line, sector_id)
	var quantity := Strings.t("%s, here %s -> %s %s; other regions %s.") % [_name(panel._loader, line, sector_id),
		BudgetSectors.quantity_text(float(est["region_before"])), BudgetSectors.quantity_text(float(est["region_after"])), unit,
		BudgetSectors.quantity_text(float(est["others_after"]))]
	var rest := int(est["rest_months"])
	if first != "" and first != String(region.id):
		quantity = Strings.tn("Takes it from %s, which then waits %d month.", "Takes it from %s, which then waits %d months.", rest) % [
			_region_name(panel, ns, first), rest] + " " + quantity
	var term := Strings.tn("For %d month, renewable once.", "For %d months, renewable once.", DK.PRIORITY_MONTHS) % DK.PRIORITY_MONTHS
	if int(est["renewals_left"]) <= 0:
		term = Strings.tn("For %d month, not renewable.", "For %d months, not renewable.", DK.PRIORITY_MONTHS) % DK.PRIORITY_MONTHS
	term += " " + Strings.tn("Then %d month of rest.", "Then %d months of rest.", rest) % rest
	strip.show_lines(Strings.t("Treasury"), EffectsStrip.cost_text(0.0), 0.0, quantity,
		Strings.t("Unemployment here: %s %% now, %s %% with the priority; other regions %s %% -> %s %%.") % [
			Num.f(float(est["unemployment_now"]), 1), Num.f(float(est["unemployment_after"]), 1),
			Num.f(float(est["others_unemployment_now"]), 1), Num.f(float(est["others_unemployment_after"]), 1)] + " " + term)


static func _sector(loader, line: String, sector_id: String) -> Dictionary:
	for s in Sectors.sectors_of(loader, line):
		if String(s["id"]) == sector_id:
			return s
	return {}


## "Defence: Equipment": the spending line's name as the Budget's lever grid prints it,
## then the sector's, since two lines may name a sector alike.
static func _name(loader, line: String, sector_id: String) -> String:
	var s := _sector(loader, line, sector_id)
	return Strings.t("%s: %s") % [Strings.t(String(BudgetPanel.LEVER_LABELS.get(line, line))),
		Strings.row("domains", sector_id, "name", String(s.get("name", sector_id)))]


static func _unit(loader, line: String, sector_id: String) -> String:
	return BudgetSectors.unit_text(_sector(loader, line, sector_id))


static func _region_name(panel, ns, region_id: String) -> String:
	for region in panel._loader.regions.get(ns.id, []):
		if String(region.id) == region_id:
			return String(region.region_name)
	return region_id
