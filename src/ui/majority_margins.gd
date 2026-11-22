extends RefCounted

## "What the numbers allow" -- G3 S5, Majority (the author's pick: A's chamber with B's two
## margins). Three tiles on one sheet, each a figure, its caption and the sentence behind it:
## the seats the government holds above a majority (with the members who may break ranks), the
## seats censure lacks, and what a bill forced under Article 49.3 would meet today. The first two
## carry a seat strip (seat_strip.gd): a margin is a length, which a half circle shows as a wedge.
## The sentences are the ones this tab printed as lines before S5, moved here.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Government = preload("res://src/sim/government.gd")
const SeatStrip = preload("res://src/ui/seat_strip.gd")


## `parts`: the chamber's parts in its order, government first: [{value, color, gov}].
static func build(parent: Control, ns, party_list: Array, parts: Array, breakable: int) -> void:
	var box := VBoxContainer.new()
	box.name = "Margins"  # i18n: ok a node name, found by tests
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	PanelKit.heading(box, Strings.t("What the numbers allow"))

	var need := Government.majority_seats(ns) + 1
	var seats: int = int(ns.assembly_seats)
	var held: int = int(ns.coalition_seats)
	var tile := _margin(box, "%+d" % (held - need), Strings.t("seats above the %d of a majority") % need if held >= need
		else Strings.t("seats short of the %d of a majority") % need)
	var lit_government: Array = []
	for part in parts:
		lit_government.append({"value": part["value"], "color": part["color"], "lit": part["gov"]})
	_strip(tile, lit_government, seats, need, held - breakable, held)
	if breakable > 0:
		# The margin that is left, not the seats to subtract from (Design's T6 on #449).
		var left := held - breakable - need
		PanelKit.line(tile, (Strings.t("Up to %d may break ranks; still %d above the line") % [breakable, left]) if left >= 0
			else (Strings.t("Up to %d may break ranks; that would leave it %d short of the line") % [breakable, -left]), PanelKit.Tone.PLAIN)

	if ns.censure_rule == "none":
		return
	var needed := Government.censure_seats(ns)
	var against := seats - held
	if against >= needed:
		tile = _margin(box, Strings.t("Enough"), Strings.t("%d of the %d censure takes") % [against, needed], PanelKit.Tone.BAD)
	else:
		tile = _margin(box, Strings.t("%d short") % (needed - against), Strings.t("%d of the %d censure takes") % [against, needed])
	# The opposition first on this strip: it is the side the censure count is read from.
	var lit_opposition: Array = []
	for part in parts:
		if not part["gov"]:
			lit_opposition.append({"value": part["value"], "color": part["color"], "lit": true})
	for part in parts:
		if part["gov"]:
			lit_opposition.append({"value": part["value"], "color": part["color"], "lit": false})
	_strip(tile, lit_opposition, seats, needed, against, needed)
	if against >= needed:
		PanelKit.line(tile, Strings.t("The opposition could bring this government down on its own."), PanelKit.Tone.PLAIN)

	# Only a constitution with Article 49.3 has this tally: the same gate as Government.can_force.
	# Resolved through the real resolver (V1.1b: a motion collects seats from parties whose line is against it).
	if ns.formation_method != "presidential_appointment":
		return
	var forced := Government.resolve_censure(ns, party_list, true)
	var rebels := 0
	for pid in forced["party_rebels"]:
		rebels += int(forced["party_rebels"][pid])
	var word := Strings.t("Survives")
	var tone := PanelKit.Tone.GOOD
	if ns.force_cooldown_months > 0:
		word = Strings.t("Unavailable")
		tone = PanelKit.Tone.PLAIN
	elif forced["carried"]:
		word = Strings.t("Falls")
		tone = PanelKit.Tone.BAD
	# The figure says what a forced bill meets; the line under it says how many seats would vote to censure.
	tile = _margin(box, word, "", tone)
	var why := PanelKit.rich(tile, Strings.t("Under [g=article_49_3]Article 49.3[/g] today: %d seats would move to censure%s.") % [
		forced["for_seats"],
		Strings.t(", %d of them against their own party's line") % rebels if rebels > 0 else "",
	], PanelKit.Tone.PLAIN)
	if ns.force_cooldown_months > 0:
		PanelKit.line(tile, Strings.t("Article 49.3 unavailable for %d months.") % ns.force_cooldown_months, PanelKit.Tone.PLAIN)


## A margin: PanelKit's figure tile, its figure in the tone, the strip and sentences under it.
static func _margin(parent: Control, figure: String, caption: String, tone := PanelKit.Tone.PLAIN) -> VBoxContainer:
	var plate := PanelKit.figure_tile(parent, figure, caption)
	var body := PanelKit.tile_body(plate).get_child(0) as VBoxContainer
	body.add_theme_constant_override("separation", 6)
	if tone != PanelKit.Tone.PLAIN:
		(body.get_child(0) as Label).theme_type_variation = UiTheme.FIGURE_GOOD if tone == PanelKit.Tone.GOOD else UiTheme.FIGURE_ALERT
	if caption == "":
		body.get_child(1).hide()
	return body


static func _strip(parent: Control, parts: Array, total: int, line_at: int, box_from: int, box_to: int) -> void:
	var strip := SeatStrip.new()
	parent.add_child(strip)
	strip.setup(parts, total, line_at, box_from, box_to)
	strip.line_label = str(line_at)  # the number over the tick: the player reads it, never subtracts to it
