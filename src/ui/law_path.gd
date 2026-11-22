extends RefCounted

## A law's path -- G3 S5, the author's pick for Bills, "C : le chemin de la loi". The hurdles a law
## meets after Propose, left to right, each a step with its forecast: the Assembly always, the
## second chamber only when it has a say on this law (Chambers.power_over), the court only when it
## reviews this law (Judiciary.reviews). The steps come from the same rules the division and the
## court apply, so a nation with fewer hurdles shows fewer steps, never an empty one. The second
## chamber's word is a FORECAST blurred like the Assembly's, because a chamber is people; the
## court's is not, because a court is a RULE (docs/judiciary-model.md).
##
## `steps()` is data, `build()` draws it, so a test can change the constitution and read the steps.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const Icon = preload("res://src/ui/icon.gd")
const ControlStyle = preload("res://src/ui/control_style.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Chambers = preload("res://src/sim/chambers.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const LK = preload("res://src/sim/legislature_constants.gd")

## The share of a chamber's seats inside which its forecast is "too close to call" (law_panel.gd's
## FORECAST_UNCERTAIN_BAND, the Assembly's own blur).
const BAND := 0.15

## What a step's tile holds its words in, px (Design's T1/T6: the head no longer sits on the tile's edge).


## [{slot, title, word, tone, glyph, note, fails, meter?}] in the order the law meets them. `counts`
## are the Assembly's forecast at the grade the sheet picked (law_list.counts_of). A verdict is
## one of three: a pass (the lead size in GOOD, with a check), a kill (BAD, with the alert
## triangle; `fails` is true and the tile takes a BAD outline) or plain (TEXT, no glyph): an
## unsettled reading and a held bill are not news the player acts on today, so neither is amber
## (Design's T2 on #449: amber is "this waits on you", always with a date).
static func steps(ns, party_list: Array, law, counts: Dictionary) -> Array:
	var out: Array = []
	var seats := int(counts["yes"]) + int(counts["no"]) + int(counts["undecided"])
	var simple := String(law.majority) == "simple"
	var verdict: Array = verdict_of(counts, seats_to_pass(majority_share(ns, law), seats), simple)
	out.append(_step_of("assembly", Strings.t("Assembly"), verdict[0], verdict[1],
		Strings.t("%d for, %d against") % [counts["yes"], counts["no"]]))
	var power: String = Chambers.power_over(ns, law)
	if power != ChambersK.VERDICT_NONE:
		var upper := Legislature.resolve_upper(ns, party_list, law)
		var margin: int = int(upper["yes_seats"]) - int(upper["no_seats"])
		var title := String(ns.upper_chamber_name)
		if absi(margin) <= int(float(upper["seats_total"]) * BAND):
			out.append(_step_of("upper", title, Strings.t("too close to call"), UiTheme.TEXT, Strings.t("its reading is not settled")))
		elif bool(upper["passed"]):
			out.append(_step_of("upper", title, Strings.t("expected to agree"), UiTheme.GOOD, Strings.t("%d for, %d against") % [upper["yes_seats"], upper["no_seats"]]))
		elif power == ChambersK.VERDICT_ABSOLUTE:
			out.append(_step_of("upper", title, Strings.t("blocks it"), UiTheme.BAD, Strings.t("expected to refuse, and it cannot be overridden")))
		else:
			out.append(_step_of("upper", title, Strings.t("holds it"), UiTheme.TEXT, Strings.t("expected to refuse, holding it %d months") % ChambersK.UPPER_HOLD_MONTHS))
	if Judiciary.reviews(ns, law):
		var tolerance: float = Judiciary.tolerance(ns)
		var note := Strings.t("it reaches %s; the court allows %s") % [Num.f(law.reach, 2), Num.f(tolerance, 2)]
		var court := Strings.t("Constitutional court")
		var step: Dictionary
		if Judiciary.strikes_down(ns, law):
			step = _step_of("court", court, Strings.t("would strike it down"), UiTheme.BAD, note)
		else:
			step = _step_of("court", court, Strings.t("would let it stand"), UiTheme.GOOD, note)
		# The court is a rule, so its step shows the rule: what the law reaches against what the
		# court allows (the table's meter, the tick at the limit), both figures written in the note.
		step["meter"] = {"value": float(law.reach), "mark": tolerance}
		out.append(step)
	return out


static func _step_of(slot: String, title: String, word: String, tone: Color, note: String) -> Dictionary:
	var glyph := "check" if tone == UiTheme.GOOD else ("warning" if tone == UiTheme.BAD else "")
	return {"slot": slot, "title": title, "word": word, "tone": tone, "glyph": glyph, "note": note, "fails": tone == UiTheme.BAD}


## The path as one row of steps, a chevron between them, under its heading.
static func build(box: VBoxContainer, ns, party_list: Array, law, counts: Dictionary) -> void:
	PanelKit.heading(box, Strings.t("Its path"))
	var row := HBoxContainer.new()
	row.name = "Path"  # i18n: ok a node name, found by tests
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var list := steps(ns, party_list, law, counts)
	for i in list.size():
		if i > 0:
			var arrow := Label.new()
			arrow.text = "›"  # i18n: ok a glyph between two steps
			arrow.theme_type_variation = UiTheme.CAPTION
			arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(arrow)
		row.add_child(_step(i + 1, list[i]))


## One hurdle's tile, 12 px inside: its number and name, the verdict at the lead size (with its
## glyph), the court's meter when it has one, the reason under it. A tile whose step kills the law
## wears a 1 px BAD outline, so the red hurdle is the loudest thing on the sheet.
static func _step(n: int, step: Dictionary) -> Control:
	var tile := PanelKit.padded_tile(ControlStyle.TILE_FAILS if bool(step["fails"]) else UiTheme.TILE_PANEL)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.name = "Step_%s" % step["slot"]  # i18n: ok a node name, found by tests
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	PanelKit.tile_body(tile).add_child(col)
	var head := Label.new()
	head.text = "%d · %s" % [n, String(step["title"]).to_upper()]
	head.theme_type_variation = UiTheme.MICRO
	col.add_child(head)
	var verdict := HBoxContainer.new()
	verdict.add_theme_constant_override("separation", 6)
	col.add_child(verdict)
	if String(step["glyph"]) != "":
		var picture := TextureRect.new()
		var px := roundi(UiTheme.SIZE_LEAD * UiTheme.text_scale())
		picture.name = "Glyph"  # i18n: ok a node name, found by tests
		picture.texture = Icon.load_icon("res://assets/icons/material/%s.svg" % step["glyph"], UiTheme.BAD if bool(step["fails"]) else UiTheme.GOOD, px)
		picture.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		picture.custom_minimum_size = Vector2(px, px)
		picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		verdict.add_child(picture)
	var word := Label.new()
	word.text = String(step["word"])
	word.theme_type_variation = UiTheme.LEAD
	word.add_theme_color_override("font_color", step["tone"])  # the verdict's tone: GOOD, BAD or plain TEXT
	word.autowrap_mode = TextServer.AUTOWRAP_WORD
	word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	verdict.add_child(word)
	if step.has("meter"):
		var m: Dictionary = step["meter"]
		var bar = PanelKit.meter(col, float(m["value"]), 1.0, float(m["mark"]))
		bar.name = "CourtMeter"  # i18n: ok a node name, found by tests
		bar.bad_past_mark = true
	var note := Label.new()
	note.text = String(step["note"])
	note.theme_type_variation = UiTheme.CAPTION
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(note)
	return tile


## The share of the seats the line marks, read the way legislature.gd's division reads law.majority
## (QA on #96: a two-thirds ordinary law drew its line at half). A simple majority needs more yes
## than no; half the seats is where that is sure.
static func majority_share(ns, law) -> float:
	match String(law.majority):
		"two_thirds":
			return LK.TWO_THIRDS_MAJORITY_FRACTION
		"amendment":
			return float(LK.AMENDMENT_RULE_FRACTIONS.get(String(ns.amendment_rule), LK.ABSOLUTE_MAJORITY_FRACTION))
	return LK.ABSOLUTE_MAJORITY_FRACTION


## The yes seats a division needs, read as division_terms.gd reads the bar: more than half is
## strictly above it, a larger share (two thirds, three fifths) is at or above it.
static func seats_to_pass(share: float, seats: int) -> int:
	var bar := share * float(seats)
	if share <= 0.5:
		return floori(bar) + 1
	return ceili(bar - 1e-6)


## The forecast's word and its tone, read off the counts the bar draws: carried only when the
## undecided cannot turn it, lost only when they cannot save it. A simple majority is more yes
## than no; any other is `needed` yes seats.
static func verdict_of(c: Dictionary, needed: int, simple: bool) -> Array:
	var yes := int(c["yes"])
	var no := int(c["no"])
	var open := int(c["undecided"])
	if (simple and yes > no + open) or (not simple and yes >= needed):
		return [Strings.t("passes"), UiTheme.GOOD]
	if (simple and no >= yes + open) or (not simple and yes + open < needed):
		return [Strings.t("fails"), UiTheme.BAD]
	return [Strings.t("too close to call"), UiTheme.TEXT]
