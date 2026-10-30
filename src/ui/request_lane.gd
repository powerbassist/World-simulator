extends RefCounted

## The inbox's REQUESTS lane -- V5.2b. People of the played nation ask to see the
## president (docs/design/v5.2-spec.md, "An audience request"); each pending request
## is one card here, and the lane shows exactly the sim's register
## (`Audiences.pending(ns)`): the sim caps it, so this file never drops one.
##
## A request is a card that NEVER holds the clock (the author's answer 2 in
## docs/design/decision-surfaces.md): it sits in its own lane, carries its three
## answers -- book a day, delegate, decline -- and the price of saying no in words
## (B3), and a lapse is a decline the sim prices on its own. The card only asks:
## each answer is a signal, and the command behind it is the sim's
## (Audiences.book / delegate / decline), called by whoever wired the lane.
##
## It takes ROWS, not the register: `show_requests()` is handed one dictionary per
## pending request, already read off the sim (the wiring's job), so this file never
## reads or writes a NationState.

signal book_requested(request_id: String)
signal delegate_requested(request_id: String)
signal decline_requested(request_id: String)
signal call_requested(request_id: String)
## The player has seen the request: its card clicked, answered or closed.
signal seen(request_id: String)

const Strings = preload("res://src/ui/strings.gd")
const PartyChip = preload("res://src/ui/party_chip.gd")

## The answers, in the card's order: the index card_action() carries.
const BOOK := 0
const DELEGATE := 1
const DECLINE := 2
const CALL := 3

var _inbox
var _card_of := {}     # request id -> card id
var _request_of := {}  # card id -> request id
var _answers_of := {}  # request id -> the answers its card was put up with


func attach(inbox) -> void:
	_inbox = inbox
	inbox.card_action.connect(_on_action)
	inbox.card_activated.connect(_on_seen)
	inbox.card_closed.connect(_on_seen)
	inbox.card_dismissed.connect(func(card_id: String) -> void: _forget(card_id))


## One card per row, the cards of answered or lapsed requests taken down. A row is
## {id, person (shown name), ask (what they want, in words), by (the deadline, in
## words), price (declining's cost, in words), book, delegate, decline}, the last
## three the sim's answers() entries {ok, reason}.
func show_requests(rows: Array) -> void:
	var live := {}
	for row in rows:
		live[String(row["id"])] = true
	for request_id in _card_of.keys():
		if not live.has(request_id):
			_inbox.dismiss(String(_card_of[request_id]))
	for row in rows:
		var request_id := String(row["id"])
		var answers: Array = [
			_answer(Strings.t("Book a day…"), row.get("book", {})),
			_answer(Strings.t("Delegate"), row.get("delegate", {})),
			_answer(Strings.t("Decline"), row.get("decline", {})),
		] + ([_answer(Strings.t("Call them…"), row["call"])] if row.has("call") else [])
		# Same answers: the body is rewritten in place. Changed (a day now taken, the
		# month's call spent): the card is put up again, since the inbox rewrites a
		# body but not its buttons.
		if _card_of.has(request_id) and _answers_of.get(request_id) == answers:
			_inbox.set_body(String(_card_of[request_id]), _body(row))
			continue
		if _card_of.has(request_id):
			_inbox.dismiss(String(_card_of[request_id]))
		var card_id: String = _inbox.push(Strings.t("%s asks to see you") % String(row["person"]), _body(row), answers, null, false, _inbox.REQUESTS)
		# V5.2 close R3: whom you would be seeing, by party, under the name.
		if row.has("party"):
			_inbox.add_under_title(card_id, PartyChip.make(row["party"]))
		_card_of[request_id] = card_id
		_request_of[card_id] = request_id
		_answers_of[request_id] = answers


func request_ids() -> Array:
	return _card_of.keys()


func card_of(request_id: String) -> String:
	return String(_card_of.get(request_id, ""))


## A refused answer stays on the card, disabled, its reason on the hover: when
## every offered day is taken the player still sees why Book is out and that the
## other two stand (B2).
static func _answer(label: String, answer: Dictionary) -> Dictionary:
	var ok := bool(answer.get("ok", true))
	return {"label": label, "disabled": not ok, "tooltip": String(answer.get("reason", "")) if not ok else ""}


static func _body(row: Dictionary) -> String:
	var body := "%s\n%s\n%s" % [String(row.get("wants", row.get("ask", ""))),
		Strings.t("Answer by %s; unanswered, it counts as a refusal.") % String(row.get("by", "")),
		Strings.t("Declining: %s.") % String(row.get("price", ""))]
	# c1c: why this refusal costs more (its price above already counts it).
	if bool(row.get("broken_word", false)):
		body += " " + Strings.t("They hold something on you. Refusing them breaks your word.")
	return body


func _on_seen(card_id: String) -> void:
	if _request_of.has(card_id):
		seen.emit(String(_request_of[card_id]))


func _on_action(card_id: String, index: int) -> void:
	if not _request_of.has(card_id):
		return
	var request_id := String(_request_of[card_id])
	# Book a day STARTS an answer: the picker it opens keeps the slowed clock, and
	# the booking's end is what counts as seen (the parent's call on QA's #207).
	if index != BOOK:
		seen.emit(request_id)
	match index:
		BOOK:
			book_requested.emit(request_id)
		DELEGATE:
			delegate_requested.emit(request_id)
		DECLINE:
			decline_requested.emit(request_id)
		CALL:
			call_requested.emit(request_id)


func _forget(card_id: String) -> void:
	if _request_of.has(card_id):
		_card_of.erase(_request_of[card_id])
		_answers_of.erase(_request_of[card_id])
		_request_of.erase(card_id)
