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
const Legislature = preload("res://src/sim/legislature.gd")
const Chambers = preload("res://src/sim/chambers.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const LK = preload("res://src/sim/legislature_constants.gd")

## The share of a chamber's seats inside which its forecast is "too close to call" (law_panel.gd's
## FORECAST_UNCERTAIN_BAND, the Assembly's own blur).
const BAND := 0.15


## [{slot, title, word, tone, glyph, note}] in the order the law meets them. `counts` are the
## Assembly's forecast at the grade the sheet picked (law_list.counts_of).
static func steps(ns, party_list: Array, law, counts: Dictionary) -> Array:
	var out: Array = []
	var seats := int(counts["yes"]) + int(counts["no"]) + int(counts["undecided"])
	var simple := String(law.majority) == "simple"
	var verdict: Array = verdict_of(counts, seats_to_pass(majority_share(ns, law), seats), simple)
	out.append({"slot": "assembly", "title": Strings.t("Assembly"), "word": verdict[0], "tone": verdict[1],
		"note": Strings.t("%d for, %d against") % [counts["yes"], counts["no"]]})
	var power: String = Chambers.power_over(ns, law)
	if power != ChambersK.VERDICT_NONE:
		var upper := Legislature.resolve_upper(ns, party_list, law)
		var margin: int = int(upper["yes_seats"]) - int(upper["no_seats"])
		var step := {"slot": "upper", "title": String(ns.upper_chamber_name)}
		if absi(margin) <= int(float(upper["seats_total"]) * BAND):
			step.merge({"word": Strings.t("too close to call"), "tone": UiTheme.WARN_TEXT, "note": Strings.t("its reading is not settled")})
		elif bool(upper["passed"]):
			step.merge({"word": Strings.t("expected to agree"), "tone": UiTheme.GOOD_SMALL, "note": Strings.t("%d for, %d against") % [upper["yes_seats"], upper["no_seats"]]})
		elif power == ChambersK.VERDICT_ABSOLUTE:
			step.merge({"word": Strings.t("blocks it"), "tone": UiTheme.BAD_SMALL, "note": Strings.t("expected to refuse, and it cannot be overridden")})
		else:
			step.merge({"word": Strings.t("holds it"), "tone": UiTheme.WARN_TEXT, "note": Strings.t("expected to refuse, holding it %d months") % ChambersK.UPPER_HOLD_MONTHS})
		out.append(step)
	if Judiciary.reviews(ns, law):
		var tolerance: float = Judiciary.tolerance(ns)
		var note := Strings.t("it reaches %s; the court allows %s") % [Num.f(law.reach, 2), Num.f(tolerance, 2)]
		if Judiciary.strikes_down(ns, law):
			out.append({"slot": "court", "title": Strings.t("Constitutional court"), "word": Strings.t("would strike it down"), "tone": UiTheme.BAD_SMALL, "note": note})
		else:
			out.append({"slot": "court", "title": Strings.t("Constitutional court"), "word": Strings.t("would let it stand"), "tone": UiTheme.GOOD_SMALL, "note": note})
	return out


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


static func _step(n: int, step: Dictionary) -> Control:
	var tile := PanelContainer.new()
	tile.theme_type_variation = UiTheme.TILE_PANEL
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	tile.add_child(col)
	var head := Label.new()
	head.text = "%d · %s" % [n, String(step["title"]).to_upper()]
	head.theme_type_variation = UiTheme.MICRO
	col.add_child(head)
	var word := Label.new()
	word.text = String(step["word"])
	word.theme_type_variation = step["tone"]
	word.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(word)
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
		return [Strings.t("passes"), UiTheme.GOOD_SMALL]
	if (simple and no >= yes + open) or (not simple and yes + open < needed):
		return [Strings.t("fails"), UiTheme.BAD_SMALL]
	return [Strings.t("too close to call"), UiTheme.WARN_TEXT]
