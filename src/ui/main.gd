extends Control

const DataLoader = preload("res://src/core/data_loader.gd")
const Nation = preload("res://src/core/nation.gd")

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
