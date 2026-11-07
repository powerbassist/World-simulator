extends RefCounted

## The address to the nation on an open bill: V5.3 b, docs/design/v5.3-ab.md 4.3. A verb that
## opens the strip Address.estimate fills and the button that goes on air. It stands apart from the page's other
## verbs, because a tabled bill greys those and a tabled bill is what an address is most for.
##
## THE STRIP PRINTS WHAT THE ADDRESS MOVES, NOT WHERE THE DIVISION LANDS. estimate() reads the
## exact division, and the page's forecast is blurred on purpose (law_panel.gd): printing "311
## for, 266 against" here would give the whip count away for nothing. The seats it moves are
## what the player is deciding on, and the bar above carries the rest.
##
## On the tabled bill estimate() takes the row: it reads that grade itself, and a graded copy
## would grade twice.

const Address = preload("res://src/sim/address.gd")
const LawGrade = preload("res://src/ui/law_grade.gd")
const AddressK = preload("res://src/sim/address_constants.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

const FOLD_META := "address_fold"
const GO_META := "address_go"
const STRIP_META := "address_strip"


static func build(list, box: Control, ns, law) -> void:
	var state = list._panel._state
	# The press's answer takes the verb's place: the day is gone, and a strip under a grey
	# button would read as what just happened.
	if list.aired.get("key", "") == _aired_key(state, law):
		PanelKit.heading(box, Strings.t("Address to the nation"))
		PanelKit.plain_line(box, Strings.t("On air today: %s.") % String(list.aired["seats"]), PanelKit.Tone.PLAIN)
		return
	# Folded at rest, the Industry verbs' rule (spec 3.2): one strip, for the verb the player
	# has opened. Open on the tabled bill, the one with a division coming.
	var open: bool = String(ns.tabled_bill.get("law_id", "")) == String(law.id) or list.address_open == String(law.id)
	var fold := PanelKit.sized(Button.new())
	fold.text = Strings.t("Address the nation")
	fold.toggle_mode = true
	fold.button_pressed = open
	fold.set_meta(FOLD_META, true)
	fold.pressed.connect(_fold.bind(list, law), CONNECT_DEFERRED)
	box.add_child(fold)
	if not open:
		return
	var est := _estimate(list, ns, law)
	var strip := EffectsStrip.new()
	strip.set_meta(STRIP_META, true)
	box.add_child(strip)
	var moved: Array = moved_seats(est)
	strip.show_lines(Strings.t("The division"), seats_text(est), float(int(moved[0]) - int(moved[1])),
		EffectsStrip.who_text(est["shifts"]), _cost_text(float(est["worth"])))
	var go := PanelKit.sized(Button.new())
	go.text = Strings.t("Go on air")
	go.set_meta(GO_META, true)
	var reason := Address.refusal(state, String(law.id))
	go.disabled = reason != ""
	box.add_child(go)
	go.pressed.connect(give.bind(list, law), CONNECT_DEFERRED)
	if reason != "":
		PanelKit.plain_line(box, Strings.t("Not today: %s.") % Strings.t(reason))  # i18n: row-ok the sim's reason, its English the msgid


static func _fold(list, law) -> void:
	list.address_open = "" if list.address_open == String(law.id) else String(law.id)
	list.select(String(law.id))
	for button in list._detail.find_children("*", "Button", true, false):  # i18n: ok a class name
		if button.has_meta(FOLD_META):
			button.grab_focus()


## The press: the seats it moved are read as the strip read them, then the page redraws, and
## the bar redrawn is the answer. A stale press the diary refuses leaves no mark and no line.
static func give(list, law) -> void:
	var state = list._panel._state
	var est := _estimate(list, state.player(), law)
	if bool(Address.give(state, list._panel._loader, String(law.id))["ok"]):
		list.aired = {"key": _aired_key(state, law), "seats": seats_text(est)}
	list._panel.mark_dirty()


## The division the page is reading: an open bill at the player's pick, as the forecast above.
## The tabled bill goes as the row, whose grade estimate() reads itself.
static func _estimate(list, ns, law) -> Dictionary:
	return Address.estimate(list._panel._state, ns, list._panel._loader, LawGrade.read(ns, law, list.grade(law)))


## The day and the bill, so the line goes when the day does.
static func _aired_key(state, law) -> String:
	return "%d-%d-%d-%s" % [int(state.year), int(state.month), int(state.day), String(law.id)]


## [yes, no], the seats an estimate moves.
static func moved_seats(est: Dictionary) -> Array:
	return [int(est["after"]["yes_seats"]) - int(est["before"]["yes_seats"]), int(est["after"]["no_seats"]) - int(est["before"]["no_seats"])]


static func seats_text(est: Dictionary) -> String:
	var moved := moved_seats(est)
	return delta_text(int(moved[0]), int(moved[1]))


## "+8 for, -11 against"; a division it leaves alone says so.
static func delta_text(yes: int, no: int) -> String:
	if yes == 0 and no == 0:
		return Strings.t("no seat moves")
	return Strings.t("%s for, %s against") % [Num.fs(float(yes), 0), Num.fs(float(no), 0)]


## The diary, the fade, and a repeat's discount when there is one.
static func _cost_text(worth: float) -> String:
	if worth >= 1.0:
		return Strings.t("Takes today. Fades over %d months.") % AddressK.FADE_MONTHS
	return Strings.t("Takes today. Fades over %d months. Worth %d %% of the first.") % [AddressK.FADE_MONTHS, roundi(100.0 * worth)]
