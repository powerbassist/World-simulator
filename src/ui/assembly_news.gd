extends RefCounted

## The assembly's own events -- a bill tabled, a division, a release -- as cards.
##
## Out of main.gd at V5.1c (the reflection's D2: main.gd was the shell, the card
## writer, the pause and half the game's wiring). Moved whole: the wording, the
## memories and the order of pushes are the ones main.gd had. Holds no game
## state of its own beyond what it has already announced; `setup()` hands it the
## live state (again on a load) and the card column it pushes to.

const Bills = preload("res://src/sim/bills.gd")
const Strings = preload("res://src/ui/strings.gd")
const DataLoader = preload("res://src/core/data_loader.gd")

var _state
var _loader: DataLoader
var _stack


func setup(state, loader, stack) -> void:
	_state = state
	_loader = loader
	_stack = stack


## V4.2 T6: the assembly's own events, as cards -- _announce_industry_events's
## idiom whole. The announced-state memory is main-side (the sim stays free of
## the card stack); dismissal never answers (an unendorsed bill still divides);
## and a tabling card is TAKEN AWAY when its bill resolves, its replacement
## being the division card and not a stale offer to endorse a bill the house
## has already settled.
var _announced_assembly_bills := {}
var _assembly_cards := {}         # bill_id -> its LIVE tabling card
var _assembly_result_month := -1  # absolute month whose division card was pushed
var _assembly_release_month := -1  # absolute month whose release card was pushed

func announce(assembly_release: Dictionary = {}) -> void:
	var ns = _state.player()
	if ns == null:
		return
	var live_ids := {}
	for bill_id in ns.assembly_bills.keys():
		live_ids[bill_id] = true
	for announced_id in _announced_assembly_bills.keys():
		if not live_ids.has(announced_id):
			_announced_assembly_bills.erase(announced_id)
	for bill_id in _assembly_cards.keys():
		if not live_ids.has(bill_id):
			_stack.dismiss(String(_assembly_cards[bill_id]))
			_assembly_cards.erase(bill_id)
	for bill_id in ns.assembly_bills.keys():
		var entry: Dictionary = ns.assembly_bills[bill_id]
		var body := _assembly_bill_body(entry)
		if _announced_assembly_bills.has(bill_id):
			if _assembly_cards.has(bill_id):
				_stack.set_body(String(_assembly_cards[bill_id]), body)
			continue
		_announced_assembly_bills[bill_id] = true
		var backed := String(entry.get("backer_firm", "")) != ""
		var card_id: String = _stack.push(
			tr("A chief before the assembly") if backed else tr("Private member's bill"), body)
		_assembly_cards[bill_id] = card_id
	# The release card, handed in from _on_month_step. The capture there is
	# what lets a COLLISION month -- a PMB dividing the same tick an
	# assembly-origin hold releases -- push both cards: the register read
	# below holds only the last writer. The release keeps its OWN memory slot
	# because both results of a collision carry the same
	# assembly_division_month stamp; one shared var would swallow the second
	# card of the pair exactly as the shared register did.
	if not assembly_release.is_empty() \
			and int(assembly_release.get("assembly_division_month", -1)) != _assembly_release_month:
		_assembly_release_month = int(assembly_release.get("assembly_division_month", -1))
		_stack.push(tr("The assembly divides"), _assembly_result_body(assembly_release))
	# The division card. The assembly_bill marker on ns.last_law_result says
	# the last division was the assembly's; the memory keys the DIVISION'S OWN
	# MONTH -- the assembly_division_month stamp the machine writes into the
	# result -- and not the current month, which is what made a quiet month
	# whose tick merely found the old result still on the register re-announce
	# it every month until a new law event overwrote it. The released flag is
	# excluded since the pass-4 capture: a release that stayed on the register
	# (a month where the assembly's tick divided nothing) arrives through the
	# parameter above, and firing here too would push the same card twice.
	# The in-tray keeps no history, so the stamp is the one per-division fact
	# left once the entry is erased.
	var result: Dictionary = ns.last_law_result
	if bool(result.get("assembly_bill", false)) \
			and not bool(result.get("released", false)) \
			and int(result.get("assembly_division_month", -1)) != _assembly_result_month:
		_assembly_result_month = int(result.get("assembly_division_month", -1))
		_stack.push(tr("The assembly divides"), _assembly_result_body(result))

func _assembly_bill_body(entry: Dictionary) -> String:
	var law_name := _law_title(String(entry.get("law_id", "")))
	var months := int(entry.get("months_left", 0))
	var firm_id := String(entry.get("backer_firm", ""))
	# The endorsement transition inside the bill's life -- the card must not
	# keep offering a stand the sim now refuses (the panel drops its button
	# for the same reason).
	if float(entry.get("endorse_bonus", 0.0)) > 0.0:
		return tr_n("%s reaches the floor in %d month. The president's stand is on the record -- endorsed.", "%s reaches the floor in %d months. The president's stand is on the record -- endorsed.", months) % [
			law_name, months]
	if firm_id != "":
		var chief := _loader.person_name(String(entry.get("backer_chief", "")))
		var firm := _loader.firm_name(_state.player_nation_id, firm_id)
		if chief == "":
			return tr_n("%s's chief backs %s. The assembly divides in %d month; whether the president stands behind it is the president's to take.", "%s's chief backs %s. The assembly divides in %d months; whether the president stands behind it is the president's to take.", months) % [
				firm, law_name, months]
		return tr_n("%s's chief %s backs %s. The assembly divides in %d month; whether the president stands behind it is the president's to take.", "%s's chief %s backs %s. The assembly divides in %d months; whether the president stands behind it is the president's to take.", months) % [
			firm, chief, law_name, months]
	return tr_n("%s reaches the floor in %d month. Endorse it, or let the backbench stand alone.", "%s reaches the floor in %d months. Endorse it, or let the backbench stand alone.", months) % [
		law_name, months]

func _assembly_result_body(result: Dictionary) -> String:
	var law_name := _law_title(String(result.get("law_id", "")))
	# A COURT STRIKE outranks every other wording, and it is checked FIRST
	# (law_panel's own order) because it fires on BOTH paths that reach this
	# builder: a release the court stopped still carries released/assembly_bill,
	# and a struck division still carries its tally. "Comes into force" and
	# "defeated, N ayes" against a bill the court stopped are both the card
	# contradicting the state it announces; the court sentence prints alone.
	if bool(result.get("struck_down", false)):
		return tr("The court has struck %s down.") % law_name
	# A SUSPENSIVE REFUSAL IS A HOLD, not a defeat (law_panel's own reading --
	# one word for different things is the readout bug this project keeps
	# finding), and a blocked one was beaten somewhere the lower-house tally
	# below does not show. Both wordings come off the outcome keys the result
	# actually carries; only the bare false reads "defeated".
	if bool(result.get("held_by_upper", false)):
		return tr("The assembly carried %s and the %s has suspended it — it comes into force in %d months.") % [
			law_name, String(result.get("upper_chamber", tr("second chamber"))), int(result.get("held_months", 0))]
	if bool(result.get("blocked_by_upper", false)):
		return tr("The assembly carried %s and the %s has blocked it.") % [
			law_name, String(result.get("upper_chamber", tr("second chamber")))]
	# The held bill's release: the coming-into-force event, not a division --
	# the release result carries no seat tally, and printing zeroes beside
	# "carried" would contradict its own numbers.
	if bool(result.get("released", false)):
		return tr("The %s's hold has run out — %s comes into force.") % [
			String(result.get("upper_chamber", tr("second chamber"))), law_name]
	return (tr("The assembly has carried %s, %d ayes to %d noes.") if bool(result.get("passed", false)) else tr("The assembly has defeated %s, %d ayes to %d noes.")) % [
		law_name, int(result.get("yes_seats", 0)), int(result.get("no_seats", 0))]

func _law_title(law_id: String) -> String:
	return Strings.law_name(_law_by_id(law_id), law_id)


## Bills.by_id: an authored law or an ownership bill rebuilt from its id (R14).
func _law_by_id(id: String):
	return Bills.by_id(_loader, id)


## At a load: the two maps belong to the discarded game, and each month memory takes
## the loaded stamp for its own shape of result (main.gd's load path says why).
func forget(loaded_result: Dictionary) -> void:
	_announced_assembly_bills.clear()
	_assembly_cards.clear()
	var carries_bill := bool(loaded_result.get("assembly_bill", false))
	var released_load := bool(loaded_result.get("released", false))
	var loaded_stamp := int(loaded_result.get("assembly_division_month", -1))
	_assembly_result_month = loaded_stamp if carries_bill and not released_load else -1
	_assembly_release_month = loaded_stamp if carries_bill and released_load else -1
