extends SceneTree

## Measures what the menu plate costs at boot: DataLoader.load_all() alone vs
## load_all() + GameState.new_game(). The V3.6 plan declared the degrade
## threshold BEFORE this ran: if new_game() adds more than 300 ms on this
## machine, the plate degrades to the Blue Marble raster alone and the number
## is recorded beside the decision. Run:
##   godot --headless --script res://tools/menu_boot_probe.gd

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var loader := DataLoader.new()
	loader.load_all()
	var t1 := Time.get_ticks_msec()
	var _state = GameState.new_game(loader, "FRA")
	var t2 := Time.get_ticks_msec()
	print("load_all: %d ms" % (t1 - t0))
	print("new_game: %d ms" % (t2 - t1))
	print("total:    %d ms" % (t2 - t0))
	quit(0)
