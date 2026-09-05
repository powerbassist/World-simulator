extends SceneTree
const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Demography = preload("res://src/sim/demography.gd")
const Society = preload("res://src/sim/society.gd")
const Unrest = preload("res://src/sim/unrest.gd")
func _init() -> void:
	var loader = DataLoader.new(); loader.load_all()
	var state = GameState.new_game(loader, "FRA")
	state.year = 2026; state.month = 1
	var ns = state.player()
	var lines := {}
	for pair in [["health", -2.5], ["education", -2.0], ["defence", -1.0], ["pensions", -3.5], ["infrastructure", -2.0]]:
		lines[pair[0]] = maxf(float(ns.start_spending_pct_gdp.get(pair[0], 0.0)) + float(pair[1]), 0.0)
	Budget.commit(state, {"spending_pct_gdp": lines, "tax_rates_pct": {
		"income": float(ns.start_tax_rates_pct["income"]) + 6.0,
		"corporate": float(ns.start_tax_rates_pct["corporate"]) + 5.0,
		"vat": float(ns.start_tax_rates_pct["vat"]) + 4.0 }})
	var peak := 0.0
	for i in range(96):
		state.year = 2026 + int(i / 12); state.month = (i % 12) + 1
		Economy.tick_month(state); Budget.tick_month(state); Opinion.tick_month(state)
		Demography.tick_month(state); Society.tick_month(state); Unrest.tick_month(state)
		peak = maxf(peak, float(ns.unrest_pct))
	print("AUSTERITY_PEAK %.2f" % peak)
	quit(0)
