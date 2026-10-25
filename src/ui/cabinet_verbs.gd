extends VBoxContainer

## The cabinet's two verbs, Government > Politics -- V5.2 b+ R4 (the author: "i
## cant revoke ministers"; docs/design/v5.2-bplus-spec.md "R4", the command is
## Systems' Removal). A portfolio and a coalition party picked, then Reassign
## (the office to that party) or Dismiss (the holder out at once, the office
## vacant). Taken out of government_panel.gd, which is at its size baseline.
##
## A removal -- Dismiss, or a Reassign that takes the office from a party -- asks
## first, on the confirm card: the party, its leader's feeling after the pulse in
## R11's words, and the party's loyalty to the government. Filling a vacancy
## takes from nobody and acts at once. A refusal is the sim's reason, shown.
##
## Reads sim state; the commands are Removal's.

## `title` names the effect card: what happened, a reassignment or a dismissal.
signal reassigned(before: Dictionary, title: String)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const Trends = preload("res://src/ui/trends.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const ConfirmCard = preload("res://src/ui/confirm_card.gd")
const Removal = preload("res://src/sim/removal.gd")
const President = preload("res://src/sim/president.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const K = preload("res://src/sim/calendar_constants.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")

var reassign_button: Button
var _portfolio: OptionButton
var _party: OptionButton
var _party_ids: Array[String] = []
var _status: Label
var _state
var _loader
var _confirm
var _asked := {}  # the open card's {portfolio, question, yes, run, text}


## The Diary's booking of a Reassign: refused at booking when Removal would refuse
## it on its day (the limit), so the booking and the act cannot disagree (#142).
static func book(state, entry: Dictionary) -> Dictionary:
	if String(entry.get("kind", "")) == K.KIND_RESHUFFLE:
		var why := Removal.why_not(state, state.player(), String(entry.get("portfolio", "")), String(entry.get("party_id", "")))
		if why != "":
			return {"ok": false, "error": why}
	return Calendar.book(state, entry)


func _init() -> void:
	name = "CabinetVerbs"  # i18n: ok a node name, found by tests
	add_theme_constant_override("separation", 4)


func _ready() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_portfolio = OptionButton.new()
	for f in CK.PORTFOLIO_KEYS:
		_portfolio.add_item(Labels.portfolio(f))
	row.add_child(_portfolio)
	_party = OptionButton.new()
	row.add_child(_party)
	reassign_button = PanelKit.sized(Button.new())
	reassign_button.text = tr("Reassign")
	reassign_button.pressed.connect(_on_reassign)
	row.add_child(reassign_button)
	var dismiss := PanelKit.sized(Button.new())
	dismiss.name = "Dismiss"  # i18n: ok a node name, found by tests
	dismiss.text = tr("Dismiss")
	dismiss.tooltip_text = tr("Remove the selected portfolio's holder at once; the office stays vacant until you reassign it.")
	dismiss.pressed.connect(_on_dismiss)
	row.add_child(dismiss)
	_status = Label.new()
	_status.theme_type_variation = UiTheme.CAPTION
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_status)


## Coalition parties only -- Cabinet refuses everything else. Rebuilt on every
## refresh: the coalition can change between one election and the next.
func sync(state, loader) -> void:
	_state = state
	_loader = loader
	var ns = state.player()
	var keep := _party_ids[_party.selected] if _party.selected >= 0 and _party.selected < _party_ids.size() else ""
	_party.clear()
	_party_ids.clear()
	var ordered: Array = ns.coalition_party_ids.duplicate()
	ordered.sort_custom(func(a, b): return int(ns.seats_by_party.get(a, 0)) > int(ns.seats_by_party.get(b, 0)))
	for pid in ordered:
		var party = _party_of(String(pid))
		if party != null:
			_party.add_item(String(party.party_name))
			_party_ids.append(String(pid))
	if _party_ids.has(keep):
		_party.select(_party_ids.find(keep))


func select_portfolio(portfolio: String) -> void:
	_portfolio.select(CK.PORTFOLIO_KEYS.find(portfolio))


func status_text() -> String:
	return _status.text


func _selected() -> String:
	var i := _portfolio.selected
	return CK.PORTFOLIO_KEYS[i] if i >= 0 and i < CK.PORTFOLIO_KEYS.size() else ""


func _on_reassign() -> void:
	var portfolio := _selected()
	var i := _party.selected
	if portfolio == "" or i < 0 or i >= _party_ids.size():
		return
	var party_id := _party_ids[i]
	var run := func() -> Dictionary: return Removal.reassign(_state, _loader, portfolio, party_id)
	var from := String(_state.player().cabinet.get(portfolio, ""))
	if from == "" or from == party_id:
		_act(run, tr("Cabinet reassigned"))
		return
	_ask(portfolio, party_id, Strings.t("Give %s to %s, taking it from %s?") % [Labels.portfolio(portfolio), _name(party_id), _name(from)], tr("Reassign"), run)


func _on_dismiss() -> void:
	var portfolio := _selected()
	if portfolio == "":
		return
	var run := func() -> Dictionary: return Removal.dismiss(_state, _loader, portfolio)
	_ask(portfolio, "", Strings.t("Dismiss %s's minister for %s?") % [_name(String(_state.player().cabinet.get(portfolio, ""))), Labels.portfolio(portfolio)],
		tr("Dismiss"), run)


## The confirm card with the removal's price, unless the sim refuses it now
## (`party_id` "" is Dismiss, as Removal.why_not reads it).
func _ask(portfolio: String, party_id: String, question: String, yes: String, run: Callable) -> void:
	var why := Removal.why_not(_state, _state.player(), portfolio, party_id)
	if why != "":
		_refused(why)
		return
	if _confirm == null:
		_confirm = ConfirmCard.on_stack(self)
		if _confirm == null:
			return
		_confirm.confirmed.connect(_on_yes)
	_asked = {"portfolio": portfolio, "party_id": party_id, "question": question, "yes": yes, "run": run, "text": "%s %s" % [question, _price(portfolio)]}
	_confirm.ask(String(_asked["text"]), yes)


## The clock runs behind the card: a price that changed under it (a leader
## replaced, a grudge that moved bands) is asked again, never paid unseen.
func _on_yes() -> void:
	var now := "%s %s" % [_asked["question"], _price(String(_asked["portfolio"]))]
	if now != String(_asked["text"]):
		_asked["text"] = now
		_confirm.ask(now, String(_asked["yes"]))
		return
	_act(_asked["run"], tr("Minister dismissed") if String(_asked["party_id"]) == "" else tr("Cabinet reassigned"))


## The leader's feeling after the pulse (R11's words) and the party's loyalty.
func _price(portfolio: String) -> String:
	var ns = _state.player()
	var price := Removal.price(_state, ns, _loader, portfolio)
	if price.is_empty():
		return ""
	var parts := PackedStringArray()
	var leader := String(price["leader_id"])
	var pulse := float(price["grudge_after"]) - float(price["grudge_before"])
	# No pulse: the leader is the president's own, or unknown (then nothing is said).
	if pulse >= Feelings.MOVED:
		var feel := Feelings.promised(Feelings.of(ns, leader), {"grudge": pulse})
		parts.append(Strings.t("%s, its leader: %s.") % [_loader.person_name(leader), ", ".join(feel)])
	elif leader == President.leader_id(ns):
		parts.append(Strings.t("Its leader is your own: no grudge, but the party still feels the loss."))
	if float(price["loyalty_after"]) < float(price["loyalty_before"]) - 1e-9:
		parts.append(Strings.t("%s grows less loyal to the government: more of its seats may break ranks.") % _name(String(price["party_id"])))
	return " ".join(parts)


func _act(run: Callable, title: String) -> void:
	var before := Trends.snapshot_now(_state)
	var result: Dictionary = run.call()
	if not bool(result.get("ok", false)):
		_refused(String(result.get("error", "")))
		return
	_status.theme_type_variation = UiTheme.CAPTION
	_status.text = ""
	reassigned.emit(before, title)


## The sim's reason, its English the msgid (#142: tr() on the refusal).
func _refused(why: String) -> void:
	_status.theme_type_variation = UiTheme.BAD_TEXT
	_status.text = Strings.t(why) if why != "" else ""  # i18n: row-ok the sim's reason, its English the msgid


func _name(party_id: String) -> String:
	var party = _party_of(party_id)
	return String(party.party_name) if party != null else party_id


func _party_of(party_id: String):
	for p in _loader.parties.get(String(_state.player().id), []):
		if String(p.id) == party_id:
			return p
	return null
