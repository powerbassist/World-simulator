extends Button

## The Dissolve verb, one button with two homes -- V5.2 b+ (R3, gate b: "button
## disolve should be in parliament ? i looked in parliament but was in gov").
## Government > Politics has carried it since V1.1c; the Legislature carries the
## same button now, read off the same rule, so the two cannot disagree.
##
## Three ways, as V1.1c set them: absent where the rule forbids the command
## outright, disabled with the sim's reason where it does not apply right now, and
## live with its price on the hover. The owner calls sync() from its refresh and
## relays `dissolved`, which main.gd turns into the effect card.
##
## A press asks first (the #135 follow-up, the parent's call): the dissolution
## cannot be taken back, so a card names the election's date and the command runs
## only on its Dissolve. Player-initiated, so outside the 4+6 budget of holds.

signal dissolved(before: Dictionary)

const Dissolution = preload("res://src/sim/dissolution.gd")
const Trends = preload("res://src/ui/trends.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const ConfirmCard = preload("res://src/ui/confirm_card.gd")
const Words = preload("res://src/ui/lever_words.gd")

## The rules with no executive command behind them: no button at all.
const NO_COMMAND := ["none", "confidence_failure", "self_dissolution"]

var _state
var _confirm  # the card this button asks on, made at the first press
var _asked_due := 0  # the election month the open question named


func _init() -> void:
	name = "Dissolve"  # i18n: ok a node name, found by tests
	text = tr("Dissolve")
	PanelKit.sized(self)
	pressed.connect(_on_pressed)


func sync(state, ns) -> void:
	_state = state
	visible = not NO_COMMAND.has(String(ns.dissolution_rule))
	disabled = not Dissolution.can_dissolve(state, ns)
	if disabled:
		tooltip_text = Dissolution.refusal_reason(state, ns)
		return
	# The price rides the verb, where the decision is made (Gameplay's move).
	var price := tr("Costs public patience on every call, and locks out further use for %d months once the new assembly is seated.") % ns.dissolution_lockout_months
	tooltip_text = "\n".join(PackedStringArray([tr("Call a snap election. No seat forecast -- read the polls, not a projection."), price]))


## The question first: the election falls `dissolution_notice_months` on, the date
## Dissolution.dissolve() will set.
func _on_pressed() -> void:
	var ns = _state.player() if _state != null else null
	if ns == null:
		return
	if _confirm == null:
		_confirm = ConfirmCard.on_stack(self)
		if _confirm == null:
			return
		_confirm.confirmed.connect(_on_confirmed)
	_asked_due = _due(ns)
	_confirm.ask(tr("Dissolve the Assembly? An election follows on %s.") % Words.when(_asked_due), tr("Dissolve"))


func _due(ns) -> int:
	return int(_state.year) * 12 + int(_state.month) + int(ns.dissolution_notice_months)


## The player's command: the sim's, with the state before it for the effect card --
## announced only when the sim took it (QA's #135-1: a month may have turned the
## rule against it while the card was up, and dissolve() refuses silently).
func _on_confirmed() -> void:
	var ns = _state.player() if _state != null else null
	if ns == null:
		return
	# The clock runs behind the card: a month turned under it moved the date, so
	# the player is asked again rather than held to a date the card did not name.
	if _due(ns) != _asked_due:
		_on_pressed()
		return
	var called := int(ns.dissolutions_called)
	var before := Trends.snapshot_now(_state)
	Dissolution.dissolve(_state, ns)
	if int(ns.dissolutions_called) > called:
		dissolved.emit(before)
