extends VBoxContainer

## The deal on the audience's table -- V5.3 b, step 6 (docs/design/v5.3-ab.md section 5): what
## they want, what they give, and Grant with what it costs, read before anything is pressed.
## Bargain's rows are audience_verbs.gd's and Refuse is the scene's way out, each with its price
## beside it. Words only: deal_words.gd reads the sim, this draws what it is handed.

signal granted

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")

var _want: Label
var _want_stake: Label
var _give: Label
var _give_stake: Label
var _grant: Button
var _grant_cost: Label
var _bargain: Label


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	add_child(columns)
	var left := _column(columns, tr("They want"))
	_want = _line(left, "Want", "")  # i18n: ok a node name, found by tests
	_want_stake = _line(left, "WantStake", UiTheme.CAPTION)
	var right := _column(columns, tr("They give"))
	_give = _line(right, "Give", "")  # i18n: ok a node name, found by tests
	_give_stake = _line(right, "GiveStake", UiTheme.CAPTION)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	_grant = PanelKit.sized(Button.new())
	_grant.name = "Grant"  # i18n: ok a node name, found by tests
	_grant.text = tr("Grant")
	_grant.pressed.connect(func() -> void: granted.emit())
	row.add_child(_grant)
	_grant_cost = _line(row, "GrantCost", UiTheme.CAPTION)
	_grant_cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grant_cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bargain = _line(self, "BargainHead", UiTheme.CAPTION)


## `card` is DealWords.card()'s, {} for a view with no deal (a test's): nothing is shown.
func show_card(card: Dictionary) -> void:
	visible = not card.is_empty()
	if card.is_empty():
		return
	_want.text = String(card["want"])
	_want_stake.text = String(card["want_stake"])
	_give.text = String(card["give"])
	_give_stake.text = String(card["give_stake"])
	_give_stake.theme_type_variation = UiTheme.GOOD_SMALL if bool(card["give_good"]) else UiTheme.CAPTION
	_grant.disabled = not bool(card["grant_ok"])
	_grant.tooltip_text = String(card["grant_why"])
	# Refused, the reason is what the line says: the price of a Grant nobody can press is noise.
	var refused := not bool(card["grant_ok"]) and not bool(card["struck"]) and String(card["grant_why"]) != ""
	_grant_cost.text = String(card["grant_why"]) if refused else String(card["grant_cost"])
	# Once struck there is no less to bargain for.
	_bargain.visible = not bool(card["struck"])
	_bargain.text = String(card["bargain"])


func _column(into: Control, title: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	into.add_child(column)
	PanelKit.heading(column, title)
	return column


static func _line(into: Control, node_name: String, variation: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = variation
	into.add_child(label)
	return label
