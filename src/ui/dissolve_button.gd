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

signal dissolved(before: Dictionary)

const Dissolution = preload("res://src/sim/dissolution.gd")
const Trends = preload("res://src/ui/trends.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")

## The rules with no executive command behind them: no button at all.
const NO_COMMAND := ["none", "confidence_failure", "self_dissolution"]

var _state


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


## The player's command: the sim's, with the state before it for the effect card.
func _on_pressed() -> void:
	var ns = _state.player() if _state != null else null
	if ns == null:
		return
	var before := Trends.snapshot_now(_state)
	Dissolution.dissolve(_state, ns)
	dissolved.emit(before)
