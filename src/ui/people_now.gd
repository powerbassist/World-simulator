extends RefCounted

## "Who matters now" -- the top of the People tab, V5.3-0 (b), docs/design/
## v5.3-0-readability.md 3.4 (closing gate R14, "people subpanel is shit"). Up to
## six cards, a face, a name and ONE reason in words, chosen by the priority rule's
## own person inputs: a request waiting, a promise falling due, a grudge past
## "hostile, may leak"; then, to fill the row, the cast's standing. The table below
## stays the register; this row is what the player opens the tab for.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Strings = preload("res://src/ui/strings.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const PK = preload("res://src/ui/priorities_constants.gd")
const President = preload("res://src/sim/president.gd")

const MAX_CARDS := 6
const FACE := Vector2(48, 64)
const CARD_WIDTH := 210.0
## A promise is "due" when its date is this close (months), the briefing's own near.
const DUE_MONTHS := 2
## Feelings' "neutral" rapport band, closed at both ends.
const NEUTRAL: float = Feelings.BANDS["rapport"][2][0]


## [{id, reason, tone}] in order: requests, promises due, hostile grudges, then the
## politicians by standing. Each person once, at their first reason; `tone` is a
## UiTheme text variation. `side` (person) -> String names a filler's party or kind,
## where a feeling word would only say "neutral". The president is not on their own
## list.
static func chosen(state, loader, side: Callable) -> Array:
	var ns = state.player()
	var out: Array = []
	var seen := {President.leader_id(ns): true}
	var now := int(state.year) * 12 + int(state.month)
	for request in Audiences.pending(ns):
		_add(out, seen, String(request.get("person_id", "")), Strings.t("Asks to see you"), UiTheme.WARN_TEXT, String(request.get("id", "")))
	for row in ns.commitments:
		if int(row.get("due_month", now + 99)) - now <= DUE_MONTHS:
			_add(out, seen, String(row.get("person_id", "")), Strings.t("A promise falls due"), UiTheme.WARN_TEXT)
	var grudges: Array = ns.person_grudges.keys()
	grudges.sort_custom(func(a, b): return float(ns.person_grudges[a]) > float(ns.person_grudges[b]))
	for pid in grudges:
		var g := float(ns.person_grudges[pid])
		if g >= PK.HOSTILE_GRUDGE:
			_add(out, seen, String(pid), Feelings.word("grudge", g), UiTheme.BAD_TEXT)
	var cast: Array = (loader.people.get(String(ns.id), []) as Array).filter(func(p): return String(p.kind) == "politician")
	cast.sort_custom(func(a, b): return float(ns.person_standing.get(a.id, 0.0)) > float(ns.person_standing.get(b.id, 0.0)))
	for person in cast:
		var rapport := float(Feelings.of(ns, String(person.id))["rapport"])
		# The neutral band says nothing a card needs; the side says who they are.
		var word: String = side.call(person) if absf(rapport) <= NEUTRAL else Feelings.word("rapport", rapport)
		_add(out, seen, String(person.id), word, UiTheme.CAPTION)
	return out.slice(0, MAX_CARDS)


static func _add(out: Array, seen: Dictionary, pid: String, reason: String, tone: String, request_id := "") -> void:
	if pid == "" or seen.has(pid) or out.size() >= MAX_CARDS:
		return
	seen[pid] = true
	out.append({"id": pid, "reason": reason, "tone": tone, "request": request_id})


## The row of cards under `parent`; `hover` is the panel's person-card hook
## (person_id) -> void, `call` its call request, `answer` raises a request's card
## (request_id) -> void.
static func build(parent: Control, state, loader, side: Callable, hover: Callable, unhover: Callable, call: Callable, answer: Callable) -> void:
	var picks := chosen(state, loader, side)
	if picks.is_empty():
		return
	PanelKit.heading(parent, Strings.t("Who matters now"))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 16)
	row.add_theme_constant_override("v_separation", 8)
	parent.add_child(row)
	for pick in picks:
		var pid := String(pick["id"])
		var card := HBoxContainer.new()
		card.add_theme_constant_override("separation", 8)
		card.custom_minimum_size.x = CARD_WIDTH * UiTheme.text_scale()
		row.add_child(card)
		var face: Control = Portrait.framed_for(pid, FACE)
		face.custom_minimum_size = FACE
		card.add_child(face)
		var words := VBoxContainer.new()
		words.add_theme_constant_override("separation", 0)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(words)
		var name := PanelKit.plain_line(words, loader.person_name(pid), PanelKit.Tone.PLAIN)
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name.autowrap_mode = TextServer.AUTOWRAP_OFF
		if String(pick["reason"]) != "":
			var reason := PanelKit.plain_line(words, String(pick["reason"]))
			reason.theme_type_variation = String(pick["tone"])
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_entered.connect(hover.bind(pid))
		card.mouse_exited.connect(unhover)
		card.gui_input.connect(func(event: InputEvent) -> void:
			if not (event is InputEventMouseButton and event.pressed):
				return
			if event.button_index == MOUSE_BUTTON_RIGHT:
				call.call(pid)
			# A left click does the reason's verb: a request's card comes up to be
			# answered; anyone else's person card opens.
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if String(pick["request"]) != "":
					answer.call(String(pick["request"]))
				else:
					hover.call(pid))
