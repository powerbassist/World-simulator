extends SceneTree

## Headless probe: godot --headless --path "<repo>" --script res://tools/delegation_probe.gd -- --json=PATH [--seeds=0-19] [--months=96] [--keep-cabinet]
## Dev-only, never ships. Run it isolated (APPDATA="$(mktemp -d)").
##
## V5.3-0 gate (the author, 2026-11-01: delegated words broken 8 times in 9 in QA's
## play, "cela ne doit pas etre la norme"). How often is a delegated word kept, and
## WHY: which rule, which inputs. A France game through src/sim/world_month.gd --
## the game's own month, never a copy -- in which the player:
##   - chooses a programme entry at every term start (the entry at `seed` modulo the
##     offer, so the seeds spread over the register, the way players differ);
##   - DELEGATES every request waiting, each month before the month's tick (the
##     player answers inside the month the request arrived in);
##   - commits no budget, books nothing, declines nothing;
##   - with `--keep-cabinet`, refills every vacant portfolio each month through the
##     player's own command (Removal.reassign) with the coalition party most
##     competent for it. Without it the cabinet is the world's: an unpopular
##     government's ministers resign and an idle player leaves the seats empty (at
##     1d3d7485 every seat is vacant in most seeds from about month 45).
## Every delegated word is captured at delegation (the person, the object's family
## and stance, the cabinet's numbers a minister carries and, where
## src/sim/delegation.gd exists, its odds) and followed to its verdict in the
## month's `commitments` report, with the months its want was served on the way.
## The seeds are President.seed_draws (who asks, when). The same file runs on a
## checkout without delegation.gd (the base), which is why it is loaded, not preloaded.
##
## Months are numbered from 1, the first month the game ticks (January 2026).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const Programme = preload("res://src/sim/programme.gd")
const Characters = preload("res://src/sim/characters.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const President = preload("res://src/sim/president.gd")
const Coercion = preload("res://src/sim/coercion.gd")
const Removal = preload("res://src/sim/removal.gd")
const CabinetK = preload("res://src/sim/cabinet_constants.gd")

const PLAYER := "FRA"
const DELEGATION_PATH := "res://src/sim/delegation.gd"

var _loader
var _keep_cabinet := false
var _delegation = null


func _init() -> void:
	var json_path := ""
	var seeds: Array = [0]
	var months := 96
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("--json="):
			json_path = a.substr(7)
		elif a.begins_with("--seeds="):
			var span := a.substr(8).split("-")
			seeds = range(int(span[0]), int(span[span.size() - 1]) + 1)
		elif a.begins_with("--months="):
			months = int(a.substr(9))
		elif a == "--keep-cabinet":
			_keep_cabinet = true
	if ResourceLoader.exists(DELEGATION_PATH):
		_delegation = load(DELEGATION_PATH)
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("delegation_probe: data did not load: %s" % [_loader.errors])
		quit(1)
		return
	var rows: Array = []
	for s in seeds:
		rows.append_array(_run(int(s), months))
	var out := {"schema": 1, "months": months, "seeds": seeds, "keep_cabinet": _keep_cabinet, "summary": _summary(rows), "rows": rows}
	print(JSON.stringify(out["summary"], " ", true))
	if json_path != "":
		var f := FileAccess.open(json_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(out, " ", true) + "\n")
		f.close()
	quit(0)


func _run(draw_seed: int, months: int) -> Array:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	if draw_seed != 0:
		President.seed_draws(state, draw_seed)
	var open := {}   # "pid|object|made" -> row
	var done: Array = []
	for i in range(months):
		var month := i + 1
		state.year = 2026 + i / 12
		state.month = i % 12 + 1
		state.day = 1
		var offer: Array = Programme.available(state, ns, _loader)
		if not offer.is_empty():
			Programme.choose(state, ns, String(offer[draw_seed % offer.size()]["id"]), _loader)
		if _keep_cabinet:
			_refill(state, ns)
		for req in Audiences.pending(ns):
			var row := _capture(state, ns, req, month, draw_seed)
			var r: Dictionary = Audiences.delegate(state, ns, _loader, String(req["id"]))
			if bool(r.get("ok", false)):
				open["%s|%s|%d" % [row["person_id"], row["object"], int(row["made_month"])]] = row
		var report: Dictionary = WorldMonth.tick_month(state, _loader)
		var meters := WorldMonth.character_meters(state)
		for key in open:
			var row: Dictionary = open[key]
			if _served(state, ns, String(row["person_id"]), String(row["object"]), meters):
				(row["served_months"] as Array).append(month)
		for verdict in ["kept", "broken", "void"]:
			for c in report["commitments"].get(verdict, []):
				if String(c["kind"]) != "delegated":
					continue
				var key := "%s|%s|%d" % [String(c["person_id"]), String(c["object"]), int(c["made_month"])]
				if open.has(key):
					var row: Dictionary = open[key]
					row["verdict"] = verdict
					row["judged_loop_month"] = month
					done.append(row)
					open.erase(key)
	for key in open:
		var row: Dictionary = open[key]
		row["verdict"] = "pending"
		done.append(row)
	return done


func _capture(state, ns, req: Dictionary, month: int, draw_seed: int) -> Dictionary:
	var pid := String(req["person_id"])
	var person = _loader.person_by_id.get(pid)
	var object := String(req["object"])
	var party := Characters._party_of(ns, person) if person != null else ""
	var parts := object.split(":")
	var family := parts[0]
	if family == "office" or family == "meter":
		family = "%s:%s" % [parts[0], parts[1]]
	var effs: Array = []
	var loyalties: Array = []
	for f in ns.cabinet:
		effs.append(Cabinet.effectiveness(ns, f))
	for p in _loader.parties.get(ns.id, []):
		if ns.coalition_party_ids.has(p.id):
			loyalties.append(Cabinet.loyalty(ns, p))
	return {
		"seed": draw_seed, "person_id": pid, "kind": String(person.kind) if person != null else "",
		"party": party, "in_coalition": ns.coalition_party_ids.has(party),
		"visitor": not pid.begins_with("%s_" % ns.id),
		"object": object, "family": family, "stance": String(req.get("stance", "")),
		"made_loop_month": month, "made_month": int(state.year) * 12 + int(state.month),
		"person_loyalty": float(ns.person_loyalty.get(pid, 0.0)),
		"person_grudge": float(ns.person_grudges.get(pid, 0.0)),
		"cabinet_mean_effectiveness": _mean(effs), "coalition_mean_loyalty": _mean(loyalties),
		"odds": {} if _delegation == null else _delegation.odds(ns, _loader, object, String(req.get("stance", ""))),
		"served_months": [],
	}


## The player who keeps a cabinet: each vacant portfolio to the coalition party most
## competent for it, through the command the Government panel issues.
func _refill(state, ns) -> void:
	for f in CabinetK.PORTFOLIO_KEYS:
		if String(ns.cabinet.get(f, "")) != "":
			continue
		var best := ""
		var best_c := -1.0
		for p in _loader.parties.get(ns.id, []):
			if ns.coalition_party_ids.has(p.id) and Cabinet.competence(p, f) > best_c:
				best = p.id
				best_c = Cabinet.competence(p, f)
		if best != "":
			Removal.reassign(state, _loader, f, best)


## Whether the want behind a delegated word is served now, by the judge's own two
## doors: the measure read for a visitor's ask, Characters.want_served for the rest.
func _served(state, ns, pid: String, object: String, meters: Dictionary) -> bool:
	if object.begins_with("measure:"):
		return Coercion.own_measure(state, object.substr("measure:".length())) == null
	var person = _loader.person_by_id.get(pid)
	if person == null:
		return false
	var leaders := {}
	for party in _loader.parties.get(ns.id, []):
		leaders[party.id] = party.leader_person_id
	for w in person.wants:
		if String(w["object"]) == object:
			return Characters.want_served(ns, person, w, meters, leaders)
	return false


func _mean(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var t := 0.0
	for x in xs:
		t += float(x)
	return t / float(xs.size())


func _summary(rows: Array) -> Dictionary:
	var total := {"kept": 0, "broken": 0, "void": 0, "pending": 0}
	var by_family := {}
	var ever_served := {"kept": 0, "broken": 0}
	var served_at_delegation := 0
	for r in rows:
		var v := String(r["verdict"])
		total[v] = int(total[v]) + 1
		var key := "%s/%s" % [String(r["family"]), String(r["stance"])]
		if not by_family.has(key):
			by_family[key] = {"kept": 0, "broken": 0, "void": 0, "pending": 0}
		by_family[key][v] = int(by_family[key][v]) + 1
		if (v == "kept" or v == "broken") and not (r["served_months"] as Array).is_empty():
			ever_served[v] = int(ever_served[v]) + 1
	var judged := int(total["kept"]) + int(total["broken"])
	return {
		"delegated": rows.size(), "verdicts": total,
		"kept_share": float(total["kept"]) / maxf(1.0, float(judged)),
		"by_family_stance": by_family,
		"judged_with_want_served_some_month": ever_served,
	}
