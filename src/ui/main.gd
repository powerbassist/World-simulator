extends Control

const DataLoader = preload("res://src/core/data_loader.gd")
const Nation = preload("res://src/core/nation.gd")

@onready var _clock: Node = $Clock
@onready var _hud: Label = $HUD

const MONTH_NAMES: Array[String] = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]


func _ready() -> void:
	var loader := DataLoader.new()
	loader.load_all()

	if not loader.errors.is_empty():
		for e in loader.errors:
			push_error(e)
		return

	var ids := loader.nations.keys()
	ids.sort()
	for id in ids:
		var n: Nation = loader.nations[id]
		var pop_m := n.population / 1_000_000.0
		print("%s %-15s pop %5.1fM   GDP EUR %5.0fbn   debt %5.1f%%" % [
			n.id, n.nation_name, pop_m, n.gdp_eur_bn, n.debt_to_gdp_pct
		])

	_clock.day_advanced.connect(_on_day_advanced)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_SPACE:
			_clock.toggle_pause()
			_update_hud()
		KEY_1:
			_clock.set_speed(1)
			_update_hud()
		KEY_2:
			_clock.set_speed(2)
			_update_hud()
		KEY_3:
			_clock.set_speed(3)
			_update_hud()


func _on_day_advanced(_year: int, _month: int, _day: int) -> void:
	_update_hud()


func _update_hud() -> void:
	var month_name: String = MONTH_NAMES[_clock.month - 1]
	var state := "paused" if _clock.paused else "speed %d" % _clock.speed
	_hud.text = "%s %d, %d — %s" % [month_name, _clock.day, _clock.year, state]
