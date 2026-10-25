extends PanelContainer

## A yes-or-no before a verb that cannot be taken back -- V5.2 b+ (the #135
## follow-up, the parent's call: "Dissolve the Assembly? An election follows on
## <date>." with Dissolve and Cancel). The asker words the question and the yes;
## Cancel and Escape put the card away and do nothing.
##
## It sits on the screen stack (SYSTEM, dimmed), found by the stack's group, so a
## verb that asks needs no route through main.gd or the panel that carries it.
## Emits intent and owns nothing: the asker runs the command on `confirmed`.

signal confirmed

const PanelKit = preload("res://src/ui/panel_kit.gd")
const ScreenStack = preload("res://src/ui/screen_stack.gd")

var _question: Label
var _yes: Button
var _no: Button


## A card on the stack of `from`'s tree, hidden until asked; null with no stack
## (a panel shown outside the game screen).
static func on_stack(from: Node):
	var stack = from.get_tree().get_first_node_in_group(ScreenStack.GROUP)
	if stack == null:
		push_error("confirm_card: no screen stack in the tree")
		return null
	var card := new()
	stack.add(ScreenStack.SYSTEM, card, true, card.hide)
	return card


func _ready() -> void:
	name = "ConfirmCard"  # i18n: ok a node name, found by tests
	custom_minimum_size = Vector2(360, 0)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	_question = Label.new()
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_question)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	_no = PanelKit.sized(Button.new())
	_no.name = "Cancel"  # i18n: ok a node name, found by tests
	_no.text = tr("Cancel")
	_no.pressed.connect(hide)
	row.add_child(_no)
	_yes = PanelKit.sized(Button.new())
	_yes.name = "Confirm"  # i18n: ok a node name, found by tests
	_yes.pressed.connect(_on_yes)
	row.add_child(_yes)
	# Hidden until asked; hiding here also takes the stack's dim and holder down.
	hide()


## Show the card: `question` whole, `yes` the verb's own name on its button. The
## keyboard starts on Cancel, so an Enter that was meant for something else
## cannot take an irreversible step.
func ask(question: String, yes: String) -> void:
	_question.text = question
	_yes.text = yes
	_yes.show()
	_no.text = tr("Cancel")
	show()
	_no.grab_focus()


## The card as a notice: why the asked act cannot happen now, and only Close --
## a confirm the sim refused must not end in silence (#152's RECORD 1).
func tell(reason: String) -> void:
	_question.text = reason
	_yes.hide()
	_no.text = tr("Close")
	show()
	_no.grab_focus()


func _on_yes() -> void:
	hide()
	confirmed.emit()
