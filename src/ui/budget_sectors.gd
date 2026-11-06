extends RefCounted

## A spending line's tile on the Budget -- V5.3 a + b, docs/design/v5.3-ab.md 3.1
## "What the player reads before acting" (#255's data/domains, #258's reads): the
## line's total, its sectors as bars with their quantity, and the one verb a line's
## sectors have, move a share between two of them, with its strip.
##
## Every figure is the sim's: the shares are Sectors.shares(), each quantity
## Sectors.quantity(), and the strip is Sectors.move_share() run on a copy of the
## state -- both quantities after the move, and what it does to the channel the line
## feeds (Sectors.factor: society's quality, trend growth or capability). A move is a
## pure reallocation, so its money line says it costs nothing. A move the sim refuses
## (a sector under its floor, two picks alike) greys Move and prints the sim's line.
##
## A MOVE IS A DRAFT, like the levers (the parent's ruling on #278): Move puts it in
## the Budget's draft (`panel._share_moves`), the tile and the strip read the nation
## with the draft applied (on a copy), Commit books it (apply_moves) and Revert drops
## it. Committed with the levers, it is one decision with them.
##
## A figure is what the money buys against today's need, not a count of what stands, so
## its unit says so: 5.34 "beds per 1 000" falling must not read as beds closed (QA's
## RECORD on #288). A warned sector's mark, reason and answer: sector_warning_view.gd.
##
## Not here yet: the sector's staff (no query yet).

const Sectors = preload("res://src/sim/sectors.gd")
const DK = preload("res://src/sim/domains_constants.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const Forecast = preload("res://src/ui/budget_forecast.gd")
const SectorWarnings = preload("res://src/sim/sector_warnings.gd")
const SectorWarningView = preload("res://src/ui/sector_warning_view.gd")
const ChartKit = preload("res://src/ui/chart_kit.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

## A sector's bar, in px: the tile's widest share reads at a glance beside it.
const BAR_WIDTH := 100
## The share a move takes, in points of the line: one to ten.
const STEP := 0.01
## A sector's trend beside its figure, in px.
const SPARK_SIZE := Vector2(72, 18)
const MOST := 0.10

## What the line's money buys, as the strip names it.
const CHANNEL := {
	"health": "the health service's quality",  # i18n: msgid
	"pensions": "the pensions' quality",  # i18n: msgid
	"education": "trend growth",  # i18n: msgid
	"infrastructure": "trend growth",  # i18n: msgid
	"defence": "military capability",  # i18n: msgid
}


## A spending line's name in the lever grid, as the toggle that opens its tile. The
## region list's sub-row button: a padded button widened the window past its band
## under +35 % pseudo (1251 px of 1240).
static func line_toggle(panel, key: String, text: String) -> Button:
	var toggle := Button.new()
	toggle.text = text
	toggle.theme_type_variation = PanelKit.UiTheme.SUBROW_BUTTON
	toggle.toggle_mode = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.custom_minimum_size.x = 130
	toggle.set_meta("line", key)
	toggle.set_meta("line_name", text)
	toggle.pressed.connect(func() -> void:
		panel._open_line = "" if panel._open_line == key else key
		panel._dirty = true)
	return toggle


## The open line's tile, redrawn into the panel's box on each refresh.
static func refresh(panel, line_name: String, now: Dictionary) -> void:
	for child in panel._sector_box.get_children():
		child.queue_free()
	# One draft for the tile and the marks: the toggle and its tile read the same nation.
	var ns = panel._state.player()
	var dns = drafted(panel, ns)
	if panel._open_line != "":
		build(panel, panel._sector_box, ns, dns, panel._open_line, line_name, now)
	# The toggles are built once: each says whether its line is the open one (pass 1:
	# a second line opened left the first pressed).
	for toggle in panel.find_children("*", "Button", true, false):  # i18n: ok a class name
		if toggle.has_meta("line"):
			toggle.set_pressed_no_signal(String(toggle.get_meta("line")) == String(panel._open_line))
			# The mark that says which tile to open: a warning on a closed line is unseen.
			var slipping := not SectorWarningView.warned(dns, panel._loader, String(toggle.get_meta("line"))).is_empty()
			toggle.text = Strings.t("%s (!)") % String(toggle.get_meta("line_name")) if slipping else String(toggle.get_meta("line_name"))


static func build(panel, parent: Control, ns, dns, line: String, line_name: String, now: Dictionary) -> void:
	var loader = panel._loader
	var sectors: Array = Sectors.sectors_of(loader, line)
	if sectors.is_empty():
		return
	var tile := VBoxContainer.new()
	tile.add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	parent.add_child(tile)
	# The heading, the rows and the verb read the draft: the live nation with the drafted
	# levers and moves on it (the parent's ruling on #278: the tile says what the lever
	# above it says).
	var pct := float(dns.spending_pct_gdp.get(line, 0.0))
	PanelKit.heading(tile, Strings.t("%s: %s %% of GDP, %s bn") % [line_name, Num.f(pct, 1), Num.f(pct / 100.0 * float(dns.gdp_eur_bn), 0)])
	var shares := Sectors.shares(dns, loader, line)
	var why_of := SectorWarningView.warned(dns, loader, line)
	for sector in sectors:
		_sector_row(tile, dns, loader, line, sector, float(shares[String(sector["id"])]), why_of.has(String(sector["id"])))
	if not why_of.is_empty():
		SectorWarningView.build(panel, tile, ns, dns, line, sectors, why_of, now)
	# No sector can pay the warned one: the move would only ever be greyed (Systems'
	# measure on #288), so the line's raise above is the choice, and this says why.
	if not why_of.is_empty() and SectorWarningView.donor(dns, loader, line, sectors, why_of, String(why_of.keys()[0])) == "":
		PanelKit.plain_line(tile, Strings.t("No other sector of this line can pay."))
	else:
		_verb(panel, tile, dns, line, sectors)
	var moves: int = (panel._share_moves as Array).size()
	if moves > 0:
		PanelKit.plain_line(tile, Strings.tn("%d share move drafted: Commit books it, Revert drops it.", "%d share moves drafted: Commit books them, Revert drops them.", moves) % moves)


## The live nation with the Budget's drafted levers and share moves applied, on a copy.
static func drafted(panel, ns):
	var dns = ns.duplicate_state()
	dns.spending_pct_gdp = (panel._pending["spending_pct_gdp"] as Dictionary).duplicate()
	for m in panel._share_moves:
		Sectors.move_share(dns, panel._loader, String(m["line"]), String(m["from"]), String(m["to"]), float(m["amount"]))
	return dns


## The forecast's proposed budget: the drafted levers, and the drafted share moves
## riding with them (the parent's ruling on #278: the projection includes them, like
## the levers); budget_forecast.gd takes them off and applies them to a copy.
static func want_forecast(panel, pending: Dictionary, edited: bool) -> void:
	var wanted: Dictionary = pending
	if not (panel._share_moves as Array).is_empty():
		wanted = pending.duplicate()
		wanted[Forecast.MOVES_KEY] = (panel._share_moves as Array).duplicate(true)
	panel._forecast.want(wanted, edited or not (panel._share_moves as Array).is_empty())


## Commit: the drafted moves booked on the live nation, in the order they were drafted.
static func apply_moves(panel) -> void:
	var ns = panel._state.player()
	for m in panel._share_moves:
		Sectors.move_share(ns, panel._loader, String(m["line"]), String(m["from"]), String(m["to"]), float(m["amount"]))


static func _sector_row(tile: Control, ns, loader, line: String, sector: Dictionary, share: float, warned: bool) -> void:
	var id := String(sector["id"])
	var row := PanelKit.buttons(tile)
	var name := PanelKit.plain_line(row, Strings.t("%s (!)") % _name(sector) if warned else _name(sector), PanelKit.Tone.PLAIN)
	if warned:
		ResultTone.tint(name, ResultTone.RISKY)
	name.custom_minimum_size.x = 130
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.set_meta("sector", id)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(BAR_WIDTH, 12)
	bar.max_value = 100.0
	bar.value = 100.0 * share
	bar.show_percentage = false
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	name.set_meta("bar", bar)
	PanelKit.plain_line(row, Strings.t("%s %% · %s %s") % [Num.f(100.0 * share, 0),
		quantity_text(Sectors.quantity(ns, loader, line, id)), _unit(sector)], PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_OFF
	var trend := SectorWarnings.trend(ns, id)
	if trend.size() >= 2:
		ChartKit.spark(row, PackedFloat64Array(trend), []).custom_minimum_size = SPARK_SIZE


## The verb: from, to, how much, the strip, Move and the refusal line.
static func _verb(panel, tile: Control, ns, line: String, sectors: Array) -> void:
	if not _has(sectors, String(panel._move_from)):
		panel._move_from = String(sectors[0]["id"])
	if not _has(sectors, String(panel._move_to)) or panel._move_to == panel._move_from:
		panel._move_to = String(sectors[1]["id"])
	if float(panel._move_amount) <= 0.0:
		panel._move_amount = STEP
	if sectors.size() < 2:
		return  # a line of one sector has no share to move
	var picks := PanelKit.buttons(tile)
	PanelKit.plain_line(picks, Strings.t("Move"), PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_OFF
	var from := _picker(picks, sectors, String(panel._move_from), "from")
	PanelKit.plain_line(picks, Strings.t("to"), PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_OFF
	var to := _picker(picks, sectors, String(panel._move_to), "to")
	var amount := HSlider.new()
	amount.min_value = STEP
	amount.max_value = MOST
	amount.step = STEP
	amount.value = float(panel._move_amount)
	amount.custom_minimum_size.x = 120
	amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amount.set_meta("amount", "amount")
	picks.add_child(amount)
	var shown := PanelKit.plain_line(picks, "", PanelKit.Tone.PLAIN)
	shown.autowrap_mode = TextServer.AUTOWRAP_OFF
	var strip := EffectsStrip.new()
	strip.set_meta("sectors", true)
	strip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	strip.custom_minimum_size.x = 520
	tile.add_child(strip)
	var move := PanelKit.sized(Button.new())
	move.text = Strings.t("Draft the move")
	move.set_meta("move", "move")
	tile.add_child(move)
	var refusal := PanelKit.plain_line(tile, "")
	refusal.set_meta("refusal", "refusal")
	ResultTone.tint(refusal, ResultTone.BLOCKED)
	var redraw := func() -> void:
		shown.text = Strings.tn("%d point of the line", "%d points of the line", roundi(100.0 * float(panel._move_amount))) % roundi(100.0 * float(panel._move_amount))
		_price(panel, ns, line, sectors, strip, move, refusal)
	from.item_selected.connect(func(i: int) -> void:
		panel._move_from = String(from.get_item_metadata(i))
		redraw.call())
	to.item_selected.connect(func(i: int) -> void:
		panel._move_to = String(to.get_item_metadata(i))
		redraw.call())
	amount.value_changed.connect(func(v: float) -> void:
		panel._move_amount = v
		redraw.call())
	move.pressed.connect(func() -> void:
		panel._share_moves.append({"line": line, "from": String(panel._move_from), "to": String(panel._move_to),
			"amount": float(panel._move_amount)})
		panel._dirty = true)
	redraw.call()


## The strip for the picks as they stand: the move run on a copy of the state.
static func _price(panel, ns, line: String, sectors: Array, strip, move: Button, refusal: Label) -> void:
	var loader = panel._loader
	var from_id := String(panel._move_from)
	var to_id := String(panel._move_to)
	# The nation alone (Companies.preview's copy): the move reads no other nation, and a
	# world copy per drag step was a hitch on the Budget.
	var cns = ns.duplicate_state()
	var r: Dictionary = Sectors.move_share(cns, loader, line, from_id, to_id, float(panel._move_amount))
	var ok := bool(r.get("ok", false))
	move.disabled = not ok
	refusal.text = "" if ok else Strings.t(String(r.get("reason", "")))  # i18n: row-ok the sim's reason, its English the msgid
	refusal.visible = not ok
	strip.visible = ok
	if not ok:
		return
	var parts := PackedStringArray()
	for id in [from_id, to_id]:
		var sector := _sector(sectors, id)
		parts.append(Strings.t("%s %s -> %s %s.") % [_name(sector), quantity_text(Sectors.quantity(ns, loader, line, id)),
			quantity_text(Sectors.quantity(cns, loader, line, id)), _unit(sector)])
	var change := 100.0 * (Sectors.factor(cns, line) / maxf(Sectors.factor(ns, line), 0.000001) - 1.0)
	strip.show_lines(Strings.t("Treasury"), EffectsStrip.cost_text(0.0), 0.0, " ".join(parts),
		Strings.t("Effect on %s, for the same money: %s %%.") % [Strings.t(String(CHANNEL.get(line, ""))), Num.fs(change, 1)])


## A quantity as the tile prints it: two decimals under ten (5.34 beds), one at or
## above (100.9, an index), so the figure that moved is the one the eye finds.
static func quantity_text(q: float) -> String:
	return Num.f(q, 2 if absf(q) < 10.0 else 1)


static func _picker(parent: Control, sectors: Array, selected: String, meta: String) -> OptionButton:
	var option := OptionButton.new()
	for i in sectors.size():
		option.add_item(_name(sectors[i]))
		option.set_item_metadata(i, String(sectors[i]["id"]))
		if String(sectors[i]["id"]) == selected:
			option.select(i)
	option.set_meta(meta, meta)
	parent.add_child(option)
	return option


static func _name(sector: Dictionary) -> String:
	return SectorWarningView.sector_name(sector)


static func _unit(sector: Dictionary) -> String:
	return Strings.t("%s, need-adjusted") % Strings.row("domains", String(sector["id"]), "quantity.unit", String(sector["quantity"]["unit"]))


static func _has(sectors: Array, id: String) -> bool:
	return not _sector(sectors, id).is_empty()


static func _sector(sectors: Array, id: String) -> Dictionary:
	for s in sectors:
		if String(s["id"]) == id:
			return s
	return {}
