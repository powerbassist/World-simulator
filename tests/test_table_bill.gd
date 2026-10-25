extends SceneTree

## Headless test: godot --headless --script res://tests/test_table_bill.gd
## Non-zero exit on any failure.
##
## V5.2 b+ R14's interface half (docs/design/v5.2-bplus-spec.md "R14"; Systems'
## #146 built Bills): nationalising or privatising is a law, so the companies panel
## offers "Table a bill" for each ownership bill a firm has, and a press opens
## that bill's briefing -- the one propose path. The bill's name is the verb's own
## row (translated) and the firm's name; the assembly's cards and the Diary find
## an ownership bill by its id (Bills.by_id), not by scanning loader.laws.

const Bills = preload("res://src/sim/bills.gd")
const Companies = preload("res://src/sim/companies.gd")
const Strings = preload("res://src/ui/strings.gd")
const DiaryDriver = preload("res://src/ui/diary_driver.gd")
const Click = preload("res://tests/click.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _bill
var _target: Control


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_find_bill()
			if _bill == null:
				return _end()
			_check_names()
			_main._windows.open("companies")
		6:
			for b in _main._companies_panel.find_children("TableBill", "Button", true, false):
				if String(b.get_meta("law_id", "")) == String(_bill.id):
					_target = b
			if _target == null or not _target.is_visible_in_tree():
				_fail("the companies panel offers no 'Table a bill' for %s" % _bill.id)
				return _end()
			_press(true)
		9:
			_press(false)
		12:
			var briefing = _main._briefing
			if not briefing.is_visible_in_tree() or briefing._law == null or String(briefing._law.id) != String(_bill.id):
				_fail("'Table a bill' did not open the bill's briefing")
			briefing.hide()
			# A lost vote's cooldown: the bill is not proposable, so it is not offered
			# (the Legislature's own list reads Legislature.available the same way).
			_main._state.player().law_cooldown_months[String(_bill.id)] = 6
			_main._companies_panel.mark_dirty()
		15:
			for b in _main._companies_panel.find_children("TableBill", "Button", true, false):
				if String(b.get_meta("law_id", "")) == String(_bill.id):
					_fail("a bill under its cooldown is still offered as 'Table a bill'")
			return _end()
	return false


func _find_bill() -> void:
	var state = _main._state
	var ns = state.player()
	for company in Companies.firms_of(_main._loader, ns.id):
		var bills := Bills.ownership(state, ns, _main._loader, String(company.id))
		if not bills.is_empty():
			_bill = bills[0]
			return
	_fail("premise: no firm of the played nation has an ownership bill")


## The name: the verb's row through Strings (so French reads French) and the firm.
func _check_names() -> void:
	var terms: Dictionary = _bill.effects["company_ownership"]
	var action = null
	for a in _main._loader.company_actions:
		if String(a.id) == String(terms["action_id"]):
			action = a
	var firm := String(_bill.law_name).split(": ", true, 1)[1]
	Strings.set_language("fr")
	var want := "%s: %s" % [Strings.row_name("company-actions", action), firm]
	var got := Strings.law_name(_bill)
	Strings.set_language("en")
	if got != want:
		_fail("an ownership bill's name under fr reads '%s', not the verb's own row '%s'" % [got, want])
	if _main._assembly_news._law_by_id(String(_bill.id)) == null or DiaryDriver._law_by_id(_main._loader, String(_bill.id)) == null:
		_fail("the assembly's cards or the Diary cannot find an ownership bill by its id")
	# The Legislature (result, held bill, referendum) and the Diary's own rows name
	# the bill, never its raw id.
	if _main._law_panel._find_law(String(_bill.id)) == null:
		_fail("the Legislature cannot find an ownership bill by its id")
	if _main._calendar_panel._law_name(String(_bill.id)) != Strings.law_name(_bill):
		_fail("the Diary names an ownership bill '%s'" % _main._calendar_panel._law_name(String(_bill.id)))


func _press(down: bool) -> void:
	Click.half(_main.get_viewport(), _target, down)


func _fail(message: String) -> void:
	_failures.append(message)


func _end() -> bool:
	if _failures.is_empty():
		print("test_table_bill: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
	return true
