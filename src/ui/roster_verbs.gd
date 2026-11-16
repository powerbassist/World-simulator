extends RefCounted

## The People roster's verbs -- rework 1. One table of items per row, read by both the
## strip under the focused row and the right click's plate (verb_plate.gd), so the two
## cannot offer different verbs. An item is {id, text, enabled, reason, call}: a verb the
## sim would refuse stays on, greyed, with the sim's own reason (the brief: "no verb
## without its refusal reason before the press").
##
## A person: See (the request's first free offered day, booked through the Diary's own
## path) and Call (Phone.options' line). An office: Give it to / Fill with each
## government party, and Dismiss (Removal.why_not); the confirm card and the price stay
## cabinet_verbs.gd's. Every verb exists already; this file only places them.

const Strings = preload("res://src/ui/strings.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const Phone = preload("res://src/sim/phone.gd")
const Removal = preload("res://src/sim/removal.gd")


## `see` (request_id, date) books; `call` (person_id) opens the phone.
static func for_person(state, loader, row: Dictionary, see: Callable, call: Callable) -> Array:
	var ns = state.player()
	var pid := String(row["id"])
	var item := {"id": "see", "text": Strings.t("See them"), "enabled": false, "reason": "", "call": func() -> void: pass,
		"acts_on": [pid]}
	var request := String(row["request_id"])
	if request == "":
		item["reason"] = Strings.t("An audience answers a request; none is open.")
	elif bool(row["booked"]):
		item["reason"] = Strings.t("Already in your diary.")
	else:
		var day := first_free(state, request)
		if day.is_empty():
			item["reason"] = Strings.t("None of the days they offer is free in your diary.")
		else:
			item["text"] = Strings.t("See them on %s") % DateText.day_month(int(day["day"]), int(day["month"]))
			item["enabled"] = true
			# Read again at the press: days pass and fill with the tab open (pass 2 on #388).
			item["call"] = func() -> void:
				var now := first_free(state, request)
				see.call(request, now if not now.is_empty() else day)
	var why := String(Phone.options(state, ns, loader, pid)["why_not"])
	return [item, {"id": "call", "text": Strings.t("Call: no day, worse odds"), "enabled": why == "",
		"reason": Strings.t(why) if why != "" else "", "call": func() -> void: call.call(pid), "acts_on": [pid]}]  # i18n: row-ok the phone's reason, its English the msgid


## The first offered day the Diary can take, or {}.
static func first_free(state, request_id: String) -> Dictionary:
	for date in Audiences.offered_dates(state, state.player(), request_id):
		if bool(date.get("free", false)):
			return date
	return {}


## `verbs` is the panel's cabinet_verbs.gd (compact): its reassign() and dismiss().
static func for_office(state, loader, row: Dictionary, verbs) -> Array:
	var ns = state.player()
	var portfolio := String(row["portfolio"])
	var items: Array = []
	var ordered: Array = ns.coalition_party_ids.duplicate()
	ordered.sort_custom(func(a, b): return int(ns.seats_by_party.get(a, 0)) > int(ns.seats_by_party.get(b, 0)))
	for party_id in ordered:
		if String(party_id) == String(row["party_id"]):
			continue
		var party_name := String(party_id)
		for p in loader.parties.get(String(ns.id), []):
			if String(p.id) == String(party_id):
				party_name = String(p.party_name)
		var why := Removal.why_not(state, ns, portfolio, String(party_id))
		var to := String(party_id)
		items.append({"id": "fill" if bool(row["vacant"]) else "reassign",
			"text": (Strings.t("Fill with %s") if bool(row["vacant"]) else Strings.t("Give it to %s")) % party_name,
			"enabled": why == "", "reason": Strings.t(why) if why != "" else "",  # i18n: row-ok Removal's reason, its English the msgid
			"call": func() -> void: verbs.reassign(portfolio, to), "acts_on": ["seats"]})
	var out := Removal.why_not(state, ns, portfolio, "")
	items.append({"id": "dismiss", "text": Strings.t("Dismiss"), "enabled": out == "",
		"reason": Strings.t(out) if out != "" else "",  # i18n: row-ok Removal's reason, its English the msgid
		"call": func() -> void: verbs.dismiss(portfolio), "acts_on": ["seats"]})
	return items


## The strip under the focused row: a button per item, then one line with the reasons of
## the greyed ones -- read before the press, not after it.
static func strip(parent: Control, items: Array, indent: float) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	var pad := Control.new()
	pad.custom_minimum_size.x = indent
	box.add_child(pad)
	var reasons := PackedStringArray()
	for item in items:
		var button := PanelKit.sized(Button.new())
		button.text = String(item["text"])  # i18n: row-ok worded above
		button.disabled = not bool(item["enabled"])
		button.tooltip_text = String(item["reason"])  # i18n: row-ok worded above
		button.set_meta("verb", String(item["id"]))
		ActsOn.tag(button, item.get("acts_on", []))
		var call: Callable = item["call"]
		button.pressed.connect(func() -> void: call.call())
		box.add_child(button)
		var reason := String(item["reason"])
		# The sim's reasons are lower-case clauses; the line reads them as sentences.
		if button.disabled and reason != "":
			reason = reason.substr(0, 1).to_upper() + reason.substr(1) + ("" if reason.ends_with(".") else ".")
			if not reasons.has(reason):
				reasons.append(reason)
	var why := Label.new()
	why.name = "VerbWhy"  # i18n: ok a node name, found by tests
	why.theme_type_variation = UiTheme.CAPTION
	why.text = " ".join(reasons)  # i18n: row-ok worded above
	why.autowrap_mode = TextServer.AUTOWRAP_WORD
	why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(why)
	return box
