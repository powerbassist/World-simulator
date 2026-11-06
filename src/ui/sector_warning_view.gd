extends RefCounted

## A sector slipping, read and answered -- V5.3 a + b, band B7, #288's reads
## (src/sim/sector_warnings.gd). A figure drifts on its own, so a held line slips into its
## bad band: the tile marks the sector and says why, and offers the answer that exists.
##
## TWO ANSWERS, SIDE BY SIDE (the parent's ruling on #290). Systems measured that a warned
## sector rarely has an un-warned one to pay it, so the tile offers one raise for the line,
## priced by the Budget's own books, beside the move. The move stays whenever the sim
## accepts it, a warned sector paying included: that is the tradeoff, and its strip shows
## it. A raise holds the shares, so it lifts every sector of the line: one verb, the largest
## restore of those warned, not one per sector.
##
## ARRIVALS SPEND NO STOP (decision-surfaces.md, 4 + 6 a year): a crossing is a line on the
## monthly briefing, which holds the clock anyway (Priorities._sectors), or a note on a
## month the briefing does not show. Several in a month, as a sharp fall brings, fold into
## that one line or note (QA's RECORD on #288: France's GDP down 5 % warns 7 at once).

const Sectors = preload("res://src/sim/sectors.gd")
const SectorWarnings = preload("res://src/sim/sector_warnings.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## The share a move takes, in points of the line: the tile's smallest, and what "can pay"
## tries.
const STEP := 0.01


## {sector id: reason msgid} for the line's sectors in their bad band.
static func warned(ns, loader, line: String) -> Dictionary:
	var out := {}
	for s in Sectors.sectors_of(loader, line):
		var why := SectorWarnings.warning(ns, loader, line, String(s["id"]))
		if why != "":
			out[String(s["id"])] = why
	return out


## The tile's half under its bars: each reason once with the sectors it names, the raise
## and its strip. `ns` is the live nation (what the books price from), `dns` the draft.
static func build(panel, tile: Control, ns, dns, line: String, sectors: Array, why_of: Dictionary, now: Dictionary) -> void:
	var by_reason := {}
	for s in sectors:
		var id := String(s["id"])
		if why_of.has(id):
			(by_reason.get_or_add(String(why_of[id]), []) as Array).append(sector_name(s))
	for reason in by_reason:
		var said := PanelKit.plain_line(tile, Strings.t("%s: %s") % [", ".join(PackedStringArray(by_reason[reason])), Strings.t(String(reason))])  # i18n: row-ok the sim's reason, its English the msgid
		said.set_meta("sector_warning", String(reason))
		ResultTone.tint(said, ResultTone.RISKY)
	_raise(panel, tile, ns, dns, line, why_of, now)


## One raise for the line: the largest restore of those warned, inside this commit's span.
static func _raise(panel, tile: Control, ns, dns, line: String, why_of: Dictionary, now: Dictionary) -> void:
	var need := 0.0
	var subjects := []
	for id in why_of:
		need = maxf(need, SectorWarnings.restore_pct_gdp(dns, panel._loader, line, String(id)))
		subjects.append(subject_of(line, String(id)))
	if need <= 0.0:
		return
	var drafted := float(dns.spending_pct_gdp.get(line, 0.0))
	var target := minf(drafted + need, panel.lever_span(line).y)
	if target <= drafted:
		# The span spent or the line at its ceiling: still warned, so say what opens next.
		PanelKit.plain_line(tile, Strings.t("This line can rise no further in this Commit."))
		return
	# What this raise adds on top of the draft: the words count from the drafted line.
	# The drafted line's figure is priced already, just before this draw (0 at its live
	# value): pricing it again was one more preview on each frame of a drag (QA on #290).
	var gain := _books(panel, ns, line, target, now) - float(panel._effects.get(line, 0.0))
	var strip := EffectsStrip.new()
	strip.set_meta("raise_strip", true)
	tile.add_child(strip)
	strip.show_lines("", Strings.t("%s a year") % EffectsStrip.money_text(gain), gain, "",
		(Strings.t("Up %s points of GDP restores the figures; its other sectors gain too.") if target >= drafted + need
			else Strings.t("Up %s points of GDP, part of the way; the rest takes a second Commit.")) % Num.f(target - drafted, 1))
	var go := PanelKit.sized(Button.new())
	go.text = Strings.t("Draft the raise")
	go.set_meta("raise_line", line)
	ActsOn.tag(go, subjects)
	go.pressed.connect(func() -> void:
		panel._set_lever(line, target, false)
		panel._on_lever_changed(target, line))
	tile.add_child(go)


## The balance, EUR bn a year, with `line` alone at `value`: the Budget's own lever figure.
static func _books(panel, ns, line: String, value: float, now: Dictionary) -> float:
	if value == float(ns.spending_pct_gdp.get(line, 0.0)):
		return 0.0
	var alone := {"spending_pct_gdp": ns.spending_pct_gdp.duplicate()}
	alone["spending_pct_gdp"][line] = value
	var key := "raise|%s|%s" % [line, value]
	return float(EffectsStrip.per_key(panel._fx_cache, panel._state, now, {key: alone}, panel._pending, {})[key])


## Whether the sim would let any sector of the line pay another: the move's floor, asked
## of the sim, so "cannot pay" is said only where it refuses.
static func can_pay(ns, loader, line: String, sectors: Array) -> bool:
	for s in sectors:
		for other in sectors:
			if String(s["id"]) != String(other["id"]):
				if bool(Sectors.move_share(ns.duplicate_state(), loader, line, String(s["id"]), String(other["id"]), STEP).get("ok", false)):
					return true
				break
	return false


## The first sector that can pay `to_id` a share and is not itself warned, "" for none:
## what a Go aims the move from, not what decides whether the move is offered.
static func donor(ns, loader, line: String, sectors: Array, why_of: Dictionary, to_id: String) -> String:
	for s in sectors:
		var id := String(s["id"])
		if id != to_id and not why_of.has(id) and bool(Sectors.move_share(ns.duplicate_state(), loader, line, id, to_id, STEP).get("ok", false)):
			return id
	return ""


## A warning's Go: the Budget on the line, the move aimed at that sector when one can pay.
static func aim(panel, subject: String) -> void:
	var line := subject.get_slice("|", 0)
	var id := subject.get_slice("|", 1)
	var ns = panel._state.player()
	panel._open_line = line
	var from := donor(ns, panel._loader, line, Sectors.sectors_of(panel._loader, line), warned(ns, panel._loader, line), id)
	if from != "":
		panel._move_from = from
		panel._move_to = id
	panel._dirty = true


## A warned line's tile opened by its toggle: aimed at its first warned sector.
static func aim_first(panel, line: String) -> void:
	var why_of := warned(panel._state.player(), panel._loader, line)
	if not why_of.is_empty():
		aim(panel, subject_of(line, String(why_of.keys()[0])))


## A month the briefing does not show: the crossings, folded into one note.
static func note_cards(ns, loader, now: int) -> Array:
	var arrivals := SectorWarnings.arrivals(ns, loader, now)
	if arrivals.is_empty():
		return []
	var parts := PackedStringArray()
	for a in arrivals:
		parts.append(name_of(loader, String(a["line"]), String(a["id"])))
	return [{"title": Strings.t("Sectors slipping"), "tone": ResultTone.RISKY,
		"body": Strings.t("%s: the figures have slipped. See the Budget.") % ", ".join(parts)}]


## A priority's subject: its line, then its sector.
static func subject_of(line: String, id: String) -> String:
	return "%s|%s" % [line, id]


static func name_of(loader, line: String, id: String) -> String:
	for s in Sectors.sectors_of(loader, line):
		if String(s["id"]) == id:
			return sector_name(s)
	return id


static func sector_name(sector: Dictionary) -> String:
	return Strings.row("domains", String(sector["id"]), "name", String(sector["name"]))
