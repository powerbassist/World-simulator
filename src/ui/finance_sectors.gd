extends VBoxContainer

## A spending line's sectors, under the line's row editor on the Finances page -- V5.3 Finances slice 5
## (docs/design/v5.3-ab.md 3.1, "What the player reads before acting", the Budget tab's tile re-homed when that tab
## went). A bar per sector with its figure and its trend, each slipping sector's reason once, the one raise as a chip,
## and the one verb a line's sectors have: move a share between two of them, with its strip.
##
## Every figure is the sim's: the shares are Sectors.shares(), each quantity Sectors.quantity(), and the strip is
## Sectors.move_share() run on a copy of the state: both quantities after the move, and what it does to the channel the
## line feeds (Sectors.factor). A move the sim refuses (a sector under its floor, two picks alike) greys Move and prints
## the sim's line.
##
## A MOVE IS A DRAFT BUT NOT OF THE BILL (Gameplay's ruling, finances-slice5-brief.md). It is held by the page's one
## draft (finance_draft.gd), so the bars, the strip and the forecast read the nation with it applied, but it costs no
## money and needs no vote: the footer's verb books it at once (FinanceMoves.apply). The footer says so; this tile does
## not repeat it, nor print the line's total, which the editor above it already says (the A6 cuts).
##
## A figure is what the money buys against today's need, not a count of what stands, so its unit says so: 5.34 "beds per
## 1 000" falling must not read as beds closed (QA's RECORD on #288).
##
## The raise is the editor's own slider moved to the figure that restores the slipping sectors: it writes the shared
## draft through `raise_to`, nothing of its own.

signal changed

const Sectors = preload("res://src/sim/sectors.gd")
const SectorWarnings = preload("res://src/sim/sector_warnings.gd")
const SectorWarningView = preload("res://src/ui/sector_warning_view.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")
const ChartKit = preload("res://src/ui/chart_kit.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const FinanceRows = preload("res://src/ui/finance_rows.gd")
const FinanceLever = preload("res://src/ui/finance_lever.gd")

## The share a move takes, in points of the line: one to ten.
const STEP := SectorWarningView.STEP
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

var _state
var _loader
var _draft
var _line := ""
## Moves the editor's slider to a figure (the editor writes the draft and says it moved).
var _raise_to: Callable
## The highest figure the editor's slider reaches, and its step: the chip names a figure on the slider's grid.
var _hi := 0.0
var _step := 0.1


func setup(state, loader, draft, line: String, raise_to: Callable, hi: float, step: float) -> void:
	_state = state
	_loader = loader
	_draft = draft
	_line = line
	_raise_to = raise_to
	_hi = hi
	_step = step
	add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	refresh()


## The spending lines with a sector in its bad band on the live nation: the closed row's mark.
static func slipping(ns, loader) -> Array:
	var out := []
	for line in ns.spending_pct_gdp:
		if not SectorWarningView.warned(ns, loader, String(line)).is_empty():
			out.append(String(line))
	return out


## Whether a line has sectors to show at all.
static func has_sectors(loader, line: String) -> bool:
	return not Sectors.sectors_of(loader, line).is_empty()


## The tile again from the draft as it stands (a slider moved, a move drafted): the rows are rebuilt, the picks kept.
func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var sectors: Array = Sectors.sectors_of(_loader, _line)
	if sectors.is_empty():
		return
	var dns = drafted(_state, _loader, _draft)
	var shares := Sectors.shares(dns, _loader, _line)
	var why_of := SectorWarningView.warned(dns, _loader, _line)
	for sector in sectors:
		_sector_row(dns, sector, float(shares[String(sector["id"])]), why_of.has(String(sector["id"])))
	if not why_of.is_empty():
		_reasons(sectors, dns, why_of)
	# The parent's ruling on #290: the move stays whenever any sector can pay, a warned one included (paying from one
	# is the tradeoff, and the strip shows it), beside the raise.
	if SectorWarningView.can_pay(dns, _loader, _line, sectors):
		_verb(dns, sectors, why_of)
	else:
		PanelKit.plain_line(self, Strings.t("No sector of this line can pay."))


## The live nation with the draft's spending levers and share moves on it, on a copy: what the tile, the strip and the
## marks all read (the tile says what the slider above it says).
static func drafted(state, loader, draft):
	var dns = state.player().duplicate_state()
	for key in dns.spending_pct_gdp.keys():
		dns.spending_pct_gdp[key] = draft.value(FinanceDraft.SPENDING, String(key))
	for m in draft.moves():
		Sectors.move_share(dns, loader, String(m["line"]), String(m["from"]), String(m["to"]), float(m["amount"]))
	return dns


## The sector's mark, name, bar, share, quantity and trend.
func _sector_row(dns, sector: Dictionary, share: float, warned: bool) -> void:
	var id := String(sector["id"])
	# Two lines, not one: the column the row sits in is narrow, and "5.34 per 1 000 inhabitants, need-adjusted" is the long
	# part, so it wraps under the mark, the bar and the share instead of running out of the page.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var name := PanelKit.plain_line(row, Strings.t("%s (!)") % SectorWarningView.sector_name(sector) if warned else SectorWarningView.sector_name(sector), PanelKit.Tone.PLAIN)
	if warned:
		ResultTone.tint(name, ResultTone.RISKY)
	name.custom_minimum_size.x = FinanceRows.NAME_WIDTH * UiTheme.text_scale()
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.set_meta("sector", id)
	var figure := PanelKit.plain_line(row, Strings.t("%s %s") % [quantity_text(Sectors.quantity(dns, _loader, _line, id)), unit_text(sector)], PanelKit.Tone.DIM)
	figure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	figure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # a second line where the sheet is a column, never cut
	figure.tooltip_text = figure.text
	figure.mouse_filter = Control.MOUSE_FILTER_PASS
	var pct := PanelKit.plain_line(row, Strings.t("%s %% of the line") % Num.f(100.0 * share, 0), PanelKit.Tone.PLAIN)
	pct.autowrap_mode = TextServer.AUTOWRAP_OFF
	pct.custom_minimum_size.x = FinanceRows.PCT_WIDTH * UiTheme.text_scale()
	# The share as a bar in the line's own colour (decision 5: never the accent), on a 0-100 % scale: a locked lever.
	var bar := FinanceLever.new()
	bar.custom_minimum_size.x = FinanceRows.BAR_MIN * UiTheme.text_scale()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	bar.setup(1.0, 100.0, 100.0 * share, FinanceRows.line_color(_line))
	bar.step = 0.0  # the share as it is: a slider's step of 1 would round it
	bar.max_value = 100.0
	bar.value = 100.0 * share
	bar.lock()
	name.set_meta("bar", bar)
	var trend := SectorWarnings.trend(dns, id)
	if trend.size() >= 2:
		ChartKit.spark(row, PackedFloat64Array(trend), []).custom_minimum_size = SPARK_SIZE


## Each slipping sector's reason once with the sectors it names, then the raise as one chip.
func _reasons(sectors: Array, dns, why_of: Dictionary) -> void:
	var by_reason := {}
	for s in sectors:
		var id := String(s["id"])
		if why_of.has(id):
			(by_reason.get_or_add(String(why_of[id]), []) as Array).append(SectorWarningView.sector_name(s))
	for reason in by_reason:
		var said := PanelKit.plain_line(self, Strings.t("%s: %s") % [", ".join(PackedStringArray(by_reason[reason])), Strings.t(String(reason))])  # i18n: row-ok the sim's reason, its English the msgid
		said.set_meta("sector_warning", String(reason))
		ResultTone.tint(said, ResultTone.RISKY)
	_chip(dns, why_of)


## One raise for the line: the largest restore of those warned, as far as the editor's slider reaches. A raise holds the
## shares, so it lifts every sector of the line: one verb, not one per sector.
func _chip(dns, why_of: Dictionary) -> void:
	var need := 0.0
	var subjects := []
	for id in why_of:
		need = maxf(need, SectorWarnings.restore_pct_gdp(dns, _loader, _line, String(id)))
		subjects.append(SectorWarningView.subject_of(_line, String(id)))
	if need <= 0.0:
		return
	var drafted_pct := float(dns.spending_pct_gdp.get(_line, 0.0))
	# Up to the next step of the slider (QA's T2 on #373: 11.4876 was written under "Raise to 11.5 %"), so the figure the
	# chip names is the one it writes and the row, the box and the sheet read.
	var target := minf(snappedf(ceilf((drafted_pct + need) / _step - 0.0001) * _step, _step), _hi)
	if target <= drafted_pct:
		return  # the slider's reach is spent: its caption says where it ends
	var chip := PanelKit.sized(Button.new())
	chip.text = Strings.t("Raise to %s %%") % Num.f(target, 1)
	chip.set_meta("raise_line", _line)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ActsOn.tag(chip, subjects)
	chip.pressed.connect(func() -> void: _raise_to.call(target))
	add_child(chip)


## The verb: from, to, how much, the strip, Move and the refusal line.
func _verb(dns, sectors: Array, why_of: Dictionary) -> void:
	if sectors.size() < 2:
		return  # a line of one sector has no share to move
	var pick: Dictionary = _draft.pick
	var fresh := not _has(sectors, String(pick.get("from", ""))) or not _has(sectors, String(pick.get("to", "")))
	if not _has(sectors, String(pick.get("from", ""))):
		pick["from"] = String(sectors[0]["id"])
	if not _has(sectors, String(pick.get("to", ""))) or pick["to"] == pick["from"]:
		pick["to"] = String(sectors[1]["id"])
	# Opened on a warned line, the move's default aims as a briefing's Go does: from a sector that can pay into the one
	# slipping, not from the first row (QA on #290).
	if fresh and not why_of.is_empty():
		aim_pick(_draft, dns, _loader, _line, sectors, why_of, String(why_of.keys()[0]))
	if float(pick.get("amount", 0.0)) <= 0.0:
		pick["amount"] = STEP
	# A flow, so the three pickers and the slider wrap under each other where the column is narrow (the former 130 % text size).
	var picks := HFlowContainer.new()
	add_child(picks)
	PanelKit.plain_line(picks, Strings.t("Move"), PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_OFF
	var from := _picker(picks, sectors, String(pick["from"]), "from")
	PanelKit.plain_line(picks, Strings.t("to"), PanelKit.Tone.PLAIN).autowrap_mode = TextServer.AUTOWRAP_OFF
	var to := _picker(picks, sectors, String(pick["to"]), "to")
	var amount := HSlider.new()
	amount.min_value = STEP
	amount.max_value = MOST
	amount.step = STEP
	amount.value = float(pick["amount"])
	amount.custom_minimum_size.x = 120
	amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	amount.set_meta("amount", "amount")
	picks.add_child(amount)
	var shown := PanelKit.plain_line(picks, "", PanelKit.Tone.PLAIN)
	shown.autowrap_mode = TextServer.AUTOWRAP_OFF
	# One Move line (gate T3 on #443): the pickers, the amount and the verb together; what it does under it.
	var move := PanelKit.sized(Button.new())
	move.text = Strings.t("Draft the move")
	move.set_meta("move", "move")
	picks.add_child(move)
	var strip := EffectsStrip.new()
	strip.set_meta("sectors", true)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(strip)
	var refusal := PanelKit.plain_line(self, "")
	refusal.set_meta("refusal", "refusal")
	ResultTone.tint(refusal, ResultTone.BLOCKED)
	var redraw := func() -> void:
		shown.text = Strings.tn("%d point of the line", "%d points of the line", roundi(100.0 * float(pick["amount"]))) % roundi(100.0 * float(pick["amount"]))
		_price(dns, sectors, strip, move, refusal)
	from.item_selected.connect(func(i: int) -> void:
		pick["from"] = String(from.get_item_metadata(i))
		redraw.call())
	to.item_selected.connect(func(i: int) -> void:
		pick["to"] = String(to.get_item_metadata(i))
		redraw.call())
	amount.value_changed.connect(func(v: float) -> void:
		pick["amount"] = v
		redraw.call())
	move.pressed.connect(func() -> void:
		_draft.add_move(_line, String(pick["from"]), String(pick["to"]), float(pick["amount"]))
		refresh()
		changed.emit())
	redraw.call()


## The move aimed at a slipping sector: from one that can pay it (none, and the picks stay as they are), into it.
static func aim_pick(draft, dns, loader, line: String, sectors: Array, why_of: Dictionary, id: String) -> void:
	var from := SectorWarningView.donor(dns, loader, line, sectors, why_of, id)
	if from != "":
		draft.pick["from"] = from
		draft.pick["to"] = id


## A slipping sector's Go: the Books page on its line, the move aimed at that sector when one can pay.
static func aim(page, subject: String) -> void:
	var line := subject.get_slice("|", 0)
	var dns = drafted(page._state, page._loader, page.shared_draft())
	aim_pick(page.shared_draft(), dns, page._loader, line, Sectors.sectors_of(page._loader, line), SectorWarningView.warned(dns, page._loader, line), subject.get_slice("|", 1))
	page.open_row(FinanceDraft.SPENDING, line)


## The strip for the picks as they stand: the move run on a copy of the draft's nation.
func _price(dns, sectors: Array, strip, move: Button, refusal: Label) -> void:
	var pick: Dictionary = _draft.pick
	var from_id := String(pick["from"])
	var to_id := String(pick["to"])
	# The nation alone (Companies.preview's copy): the move reads no other nation, and a world copy per drag step was a
	# hitch on the Budget.
	var cns = dns.duplicate_state()
	var r: Dictionary = Sectors.move_share(cns, _loader, _line, from_id, to_id, float(pick["amount"]))
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
		parts.append(Strings.t("%s %s -> %s %s.") % [SectorWarningView.sector_name(sector), quantity_text(Sectors.quantity(dns, _loader, _line, id)),
			quantity_text(Sectors.quantity(cns, _loader, _line, id)), unit_text(sector)])
	# Paying from a warned sector is the tradeoff (the parent's ruling on #290): said here.
	if SectorWarnings.warning(dns, _loader, _line, from_id) != "":
		parts.append(Strings.t("Slipping too: %s.") % SectorWarningView.sector_name(_sector(sectors, from_id)))
	var change := 100.0 * (Sectors.factor(cns, _line) / maxf(Sectors.factor(dns, _line), 0.000001) - 1.0)
	strip.show_lines(Strings.t("Treasury"), EffectsStrip.cost_text(0.0), 0.0, " ".join(parts),
		Strings.t("Effect on %s, for the same money: %s %%.") % [Strings.t(String(CHANNEL.get(_line, ""))), Num.fs(change, 1)])


## A quantity as the tile prints it: two decimals under ten (5.34 beds), one at or above (100.9, an index), so the figure
## that moved is the one the eye finds.
static func quantity_text(q: float) -> String:
	return Num.f(q, 2 if absf(q) < 10.0 else 1)


static func unit_text(sector: Dictionary) -> String:
	return Strings.t("%s, need-adjusted") % Strings.row("domains", String(sector["id"]), "quantity.unit", String(sector["quantity"]["unit"]))


func _picker(parent: Control, sectors: Array, selected: String, meta: String) -> OptionButton:
	var option := OptionButton.new()
	for i in sectors.size():
		option.add_item(SectorWarningView.sector_name(sectors[i]))
		option.set_item_metadata(i, String(sectors[i]["id"]))
		if String(sectors[i]["id"]) == selected:
			option.select(i)
	option.set_meta(meta, meta)
	parent.add_child(option)
	return option


static func _has(sectors: Array, id: String) -> bool:
	return not _sector(sectors, id).is_empty()


static func _sector(sectors: Array, id: String) -> Dictionary:
	for s in sectors:
		if String(s["id"]) == id:
			return s
	return {}
