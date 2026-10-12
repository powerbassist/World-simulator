extends RefCounted

## Events -- V1.8 built the occasion, the menu and the deadline; V4.4 makes the
## world watch back. Weighted draws inside nine categories, severity ordering the
## desk, on_action hooks that fire BECAUSE something happened, chains a choice can
## arm at a delay, and a chooser so the other twenty-eight nations have politics
## that happen to them. The model and every number is docs/events-model.md, whose
## V4.4 sections were rewritten in the same commits as this machinery.
##
## ============================================================================
## THE DESK IS A QUEUE NOW, AND THE QUIET MOVED DOWN A LEVEL
## ============================================================================
## V1.8 argued ONE pending slot was what "the matter on your desk" meant, and at
## nine events that held. At a hundred and two it does not: a draw skipped for
## want of a slot is an occasion the world considered and withdrew for no reason
## the content can see. ns.event_queue holds up to QUEUE_MAX entries ordered
## severity-descending then arrival; each entry carries its own countdown and
## expires on its own default. The quiet period followed the slot down: a
## delivery quiets THAT EVENT'S CATEGORY for CATEGORY_QUIET_MONTHS (a resolution
## re-arms the countdown), because one resolution in fiscal silencing scandal
## forever was the global quiet's defect at scale. The per-event cooldown V1.8
## designed and cut -- cut on the grounds that the slot already bounded
## repetition, an argument that died with the slot -- is back as
## `cooldown_months`, a sparse until-month register.
##
## ============================================================================
## NO RANDOMNESS, STILL. THE DRAW IS A PURE FUNCTION, TWICE OVER
## ============================================================================
## The hazard is unchanged arithmetic: a hash of (nation, event, absolute month)
## against the authored likelihood, so an event's arrival month is fixed before
## the game starts and a save reloaded on the arrival month receives the same
## crisis. The V4.4 addition is the weighted pick INSIDE a pulsing category --
## Cycle.unit over (nation, category, sorted eligible roster, month) against the
## cumulative authored weights -- which is a pure function the same way. There is
## still no stored draw anywhere, and tests/test_save_load.gd still pins that
## absence; what the
## hooks added is a stamp per hook of the month it last fired, which is not RNG
## state but the reload-safety of an edge whose source (a register another
## machine wrote) is not itself month-pure.
##
## ============================================================================
## THE AI GETS EVENTS, AND THE SIXTH "NO AI CHOOSER" NOTE CLOSES HERE
## ============================================================================
## V1.8 fired events for the player alone because a choice needs somebody to make
## it and the nine had no decider. The decider exists now: a minimal chooser
## scoring each choice against the NATION'S OWN position (approval-weighted bloc
## response, plus fiscal, corruption and unrest terms), applied through
## Legislature.apply_effects() like every choice the player makes. An AI nation
## receives and resolves in the same tick -- it has no desk, so it has no queue;
## its resolved history is the visible trace. Deterministic like everything here:
## same state, same choice, and ties go to content order. docs/events-model.md
## §11's limitation is rewritten at the rule in this file's own commit.
##
## ============================================================================
## NOT A LEAF, AND PLAYER-ONLY READS ARE GONE BUT THE ONE APPLIER IS NOT
## ============================================================================
## This file PRELOADS legislature.gd (the single applier of every effect channel
## an event choice carries -- the leaf alternative would make eleven harnesses
## each apply, V1.5d's forgotten-tick failure times ten) and opinion_constants.gd
## (a constants file, for the chooser's bloc sizes). It reads registers other
## machines write for its hooks -- the law ledger's months, the cabinet's
## resignation stamp, the firm entries' bid and failure stamps, the commodity
## price level, the accession stamp -- and the dependency stays one way: nothing
## in those files names this one.
##
## WRITES ns.event_queue, ns.event_fired, ns.event_category_quiet,
## ns.event_cooldowns, ns.event_armed, ns.event_hook_fired and ns.event_history,
## and nothing else. Every effect a choice carries is written by
## Legislature.apply_effects(), which stays the single writer of all six channels.

const K = preload("res://src/sim/events_constants.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")


## Runs for every nation so the register shape is uniform and duplicate_state()
## has nothing conditional to copy -- Unrest.init_nation()'s call and reason.
## The three typed arrays (queue, armed, history) clear rather than take a
## fresh `[]`: an untyped empty literal assigned through an untyped reference
## fails the Array[Dictionary] property's type check at runtime (from_dict's
## rebuild idiom, one block over).
static func init_nation(ns) -> void:
	ns.event_queue.clear()
	ns.event_fired = {}
	ns.event_category_quiet = {}
	ns.event_cooldowns = {}
	ns.event_armed.clear()
	ns.event_hook_fired = {}
	ns.event_history.clear()


# --- Reads -------------------------------------------------------------------------

## The head of the desk: the entry the V1.8-era surfaces still address. Severity
## ordering makes it the worst thing on the desk, which is the correct default
## answer to "what is in front of me" now that several things are.
static func head_entry(ns) -> Dictionary:
	if ns.event_queue.is_empty():
		return {}
	return ns.event_queue[0]


static func is_pending(ns) -> bool:
	return not ns.event_queue.is_empty()


static func pending_event_id(ns) -> String:
	return String(head_entry(ns).get("event_id", ""))


static func pending_event_name(ns) -> String:
	return String(head_entry(ns).get("event_name", ""))


## Whether ANY entry on the desk carries the interrupt flag. V2.4b's contract --
## an event nobody could reasonably ignore pauses the clock -- becomes an any-read
## rather than the-one-read, which is the whole of what the queue changes about it.
static func interrupt_pending(ns) -> bool:
	for entry in ns.event_queue:
		if bool(entry.get("interrupt", false)):
			return true
	return false


static func event_by_id(loader, event_id: String):
	for ev in loader.events:
		if String(ev.id) == event_id:
			return ev
	return null


## The head event, or null. The V1.8 read, kept for the surfaces that mean it.
static func pending_event(ns, loader):
	if not is_pending(ns):
		return null
	return event_by_id(loader, pending_event_id(ns))


# --- The tick ----------------------------------------------------------------------

## One month, every nation. The player queues; the AI resolves in place. Order
## inside one nation's tick: expiries first (the desk clears what the clock
## already decided), then armed chains (a consequence arrives before the calendar
## gets a say), then hooks (the world's happenings), then the hazard draws.
static func tick_month(state, loader) -> void:
	var month_index := _absolute_month(int(state.year), int(state.month))
	for nation_id in state.nations:
		var ns = state.nations[nation_id]
		var is_player: bool = String(nation_id) == String(state.player_nation_id)
		_tick_nation(state, ns, loader, month_index, is_player)


static func _tick_nation(state, ns, loader, month_index: int, is_player: bool) -> void:
	_tick_quiet(ns, month_index)
	if is_player and not ns.event_queue.is_empty():
		_tick_countdowns(state, ns, loader, month_index)

	for armed in ns.event_armed.duplicate():
		if int(armed.get("due_index", 0)) > month_index:
			continue
		var ev = event_by_id(loader, String(armed.get("event_id", "")))
		# A consequence whose target already fired (once) or is cooling down dies
		# silently: the chain owed the player a follow-up, not a specific one --
		# and an armed entry pointing at content this build no longer defines is
		# the V1.8 clear-an-entry-whose-content-has-gone case, one register over.
		if ev == null or not _gates_pass(ns, ev, month_index) or not _cooldown_ok(ns, ev, month_index):
			ns.event_armed.erase(armed)
			continue
		# The armed entry is erased ONLY on a delivered consequence: a door that
		# finds the desk full returns false and the chain waits a month, due
		# again -- erasing before the delivery attempt was losing the chain the
		# player paid for on a full-desk month.
		if _deliver(state, ns, loader, ev, month_index, is_player):
			ns.event_armed.erase(armed)

	for hook in K.ON_ACTIONS:
		if int(ns.event_hook_fired.get(hook, -1)) == month_index:
			continue
		if not _hook_fired(state, ns, loader, hook, month_index):
			continue
		ns.event_hook_fired[hook] = month_index
		for ev in loader.events:
			if ev.on_action != hook:
				continue
			if not _gates_pass(ns, ev, month_index) or not _cooldown_ok(ns, ev, month_index):
				continue
			if Cycle.unit("%s|%s|hook" % [ns.id, ev.id], month_index) >= ev.likelihood:
				continue
			_deliver(state, ns, loader, ev, month_index, is_player)
			# ONE hook event per happening, per nation, per month: the desk
			# argument at hook scale. A second law_passed event waits for the
			# next passage -- which the ledger will stamp, and the hook will
			# see, because it fires again next month the register says so.
			# A full desk (the return ignored above) skips FINALLY, like the
			# hazard door: the happening is stamped, and the next happening
			# re-fires the hook -- a hook is not banked against the desk.
			break

	# The standing hazard: group the month's draws by category, then one weighted
	# winner per pulsing category. Sorted category order so the iteration is
	# reproducible from state alone -- dictionary order is not.
	var fired_by_category := {}
	for ev in loader.events:
		if ev.on_action != "":
			continue
		if not _gates_pass(ns, ev, month_index):
			continue
		if not _cooldown_ok(ns, ev, month_index):
			continue
		if int(ns.event_category_quiet.get(ev.category, 0)) > 0:
			continue
		if not hazard_passes(ns.id, ev.id, _year_of(month_index), _month_of(month_index), float(ev.likelihood)):
			continue
		if not fired_by_category.has(ev.category):
			fired_by_category[ev.category] = []
		fired_by_category[ev.category].append(ev)
	var categories: Array = fired_by_category.keys()
	categories.sort()
	for category in categories:
		if is_player and ns.event_queue.size() >= K.QUEUE_MAX:
			# Kept as the loop's CHEAP EARLY-OUT: the authoritative bound lives
			# in _deliver, where the chain and hook doors pass too -- this break
			# only spares the draw and the weighted pick when the desk is
			# already full. A draw that does not fit is skipped, not banked: the
			# hazard is a function of the month, so next month is a fresh draw
			# rather than a backlog. WHICH category loses a same-month collision
			# is the sorted-name order above, not content order: alphabetically
			# later categories lose first, a fixed bias only a nearly-full desk
			# exposes (recorded in docs/someday.md; E5's spread was swept with it).
			break
		var winner = _weighted_pick(ns, fired_by_category[category], month_index)
		if winner != null:
			_deliver(state, ns, loader, winner, month_index, is_player)


static func _tick_quiet(ns, month_index: int) -> void:
	for category in ns.event_category_quiet.keys().duplicate():
		var left: int = int(ns.event_category_quiet[category]) - 1
		if left <= 0:
			ns.event_category_quiet.erase(category)
		else:
			ns.event_category_quiet[category] = left
	# Cooldowns are until-months, not countdowns: cleaning is a filter, and the
	# register stays sparse -- entries exist only while they bind.
	for event_id in ns.event_cooldowns.keys().duplicate():
		if int(ns.event_cooldowns[event_id]) <= month_index:
			ns.event_cooldowns.erase(event_id)


## Every entry ages one month; the ones that hit zero are answered by their own
## defaults, in queue order (worst first), each through the same _resolve the
## player's own answers go through.
static func _tick_countdowns(state, ns, loader, month_index: int) -> void:
	var expired: Array = []
	for entry in ns.event_queue:
		entry["months_left"] = int(entry.get("months_left", 0)) - 1
		if int(entry["months_left"]) <= 0:
			expired.append(entry)
	for entry in expired:
		var ev = event_by_id(loader, String(entry.get("event_id", "")))
		if ev == null:
			ns.event_queue.erase(entry)
			continue
		_resolve(state, ns, loader, ev, ev.default_choice(), true, entry)


static func hazard_passes(nation_id: String, event_id: String, year: int, month: int, likelihood: float) -> bool:
	if likelihood <= 0.0:
		return false
	var index: int = (
		_absolute_month(year, month)
		- _absolute_month(K.EVENT_EPOCH_YEAR, K.EVENT_EPOCH_MONTH)
	)
	return Cycle.unit("%s|%s" % [nation_id, event_id], index) < likelihood


static func _absolute_month(year: int, month: int) -> int:
	return year * 12 + month


static func _year_of(month_index: int) -> int:
	return int(month_index / 12)


static func _month_of(month_index: int) -> int:
	return month_index % 12


## The weighted winner inside one pulsing category. One hash per (nation,
## category, sorted eligible roster, month) walked against the cumulative authored
## weights -- a pure function like the hazard, so a reload mid-month picks the
## same winner. The key carries the SORTED roster of eligible ids, not the
## category alone (the category is in the key too): what the roster adds is a
## RE-KEY whenever the eligible set changes as gates open and close, so a
## category's winners do not ride one stream through a changing book -- with no
## stored draw anywhere, which is the pin test_save_load.gd holds.
static func _weighted_pick(ns, fired: Array, month_index: int):
	var total := 0.0
	var roster: Array[String] = []
	for ev in fired:
		total += float(ev.weight)
		roster.append(String(ev.id))
	if total <= 0.0:
		return fired[0]
	roster.sort()
	var draw: float = Cycle.unit(
		"%s|%s|draw|%s" % [ns.id, String(fired[0].category), "|".join(roster)],
		month_index
	) * total
	for ev in fired:
		draw -= float(ev.weight)
		if draw < 0.0:
			return ev
	return fired[fired.size() - 1]


static func _gates_pass(ns, ev, month_index: int) -> bool:
	if ev.once and ns.event_fired.has(ev.id):
		return false
	return Legislature.preconditions_met(ns, ev.preconditions)


static func _cooldown_ok(ns, ev, month_index: int) -> bool:
	return int(ns.event_cooldowns.get(ev.id, -1)) <= month_index


# --- The hooks: the emitters are reads off registers the machines write ---------

## Whether the happening a hook names occurred, for THIS nation, this month. One
## function per vocabulary entry, and events_constants.ON_ACTIONS' comment is the
## contract: a name on that list without a branch here fails tests/test_events.gd's
## `_test_the_hook_vocabulary_is_swept` (which reads both directions) rather than
## shipping as a silent never-firing hook.
static func _hook_fired(state, ns, loader, hook: String, month_index: int) -> bool:
	match hook:
		"law_passed":
			# PURE ONE-MONTH LAG, minister_resigned's shape below: the ledger
			# stamps at APPLY time, and the player's Propose/Force routes apply
			# at COMMAND time (month M), which this machine first reads at M+1
			# -- so a same-month read could never fire for them (measured: the
			# hook stayed false at M+1 and fired only at M). The lag fires EVERY
			# passage exactly once, one month after it lands -- and that is why
			# the same-month leg is dropped rather than kept beside it: with
			# both legs, an in-tick passage (held-bill release, referendum
			# settlement) fires twice, at M on the == leg and at M+1 on the lag.
			# In-tick passages are covered too, one month late, which a
			# consequence event wants anyway. Assembly bills are a DISTINCT hook
			# (member_bill_passed below) reading the division stamp, which
			# Cabinet-side ordering does not delay.
			for law_id in ns.law_ledger:
				var months: Array = ns.law_ledger[law_id].get("months", [])
				if not months.is_empty() and int(months[months.size() - 1]) == month_index - 1:
					return true
			return false
		"law_repealed":
			# V4.4's stamp: the ledger ERASE is silent in the V4.2 machine, so
			# the repeal's month is written beside it (one line, one writer).
			# PURE ONE-MONTH LAG, law_passed's shape above: the stamp lands at
			# APPLY time and the player's Propose/Force repeals apply at COMMAND
			# time, which this machine first reads at M+1 -- so a same-month read
			# could never fire for them. The same-month leg is dropped for the
			# sibling's reason: with both legs an in-tick repeal fires twice.
			for law_id in ns.repealed_at:
				if int(ns.repealed_at[law_id]) == month_index - 1:
					return true
			return false
		"member_bill_passed":
			# `passed` is part of the name: every division stamps assembly_bill and
			# its month, a defeated, blocked or HELD bill included (a held bill's
			# division carries passed=false; its release writes a fresh passed=true
			# result), so the stamp alone fired this hook for a bill the house had
			# just killed.
			var result: Dictionary = ns.last_law_result
			return bool(result.get("assembly_bill", false)) \
				and bool(result.get("passed", false)) \
				and int(result.get("assembly_division_month", -1)) == month_index
		"minister_resigned":
			# Cabinet writes the stamp AFTER this machine's slot in the month
			# handler, so the readable window is LAST month's resignation -- the
			# same one-month lag the character acts carry, and for the same
			# reason. The register holds only the last resignation of a month,
			# which makes this the one-hook-per-happening the break below wants.
			var stamp: Dictionary = ns.last_resignation
			if stamp.is_empty():
				return false
			return _absolute_month(int(stamp.get("year", 0)), int(stamp.get("month", 0))) == month_index - 1
		"takeover_bid":
			for company_id in ns.companies:
				if int(ns.companies[company_id].get("bid_month", -1)) == month_index:
					return true
			return false
		"firm_failed":
			for company_id in ns.companies:
				if int(ns.companies[company_id].get("failed_month", -1)) == month_index:
					return true
			return false
		"commodity_price_high":
			# A LEVEL read, not an edge: the register keeps no price history
			# (commodities-model's own record), so "spiked" is honestly "is
			# high" -- at or above HOOK_PRICE_RATIO of base. Repetition is
			# bounded by the event's own likelihood and cooldown, not by a
			# crossing the machine cannot see.
			var prices: Dictionary = ns.commodity_state.get("price", {})
			for good_id in prices:
				var base := _base_price_of(loader, String(good_id))
				if base > 0.0 and float(prices[good_id]) / base >= K.HOOK_PRICE_RATIO:
					return true
			return false
		"accession_won":
			return int(ns.last_accession.get("month_index", -1)) == month_index
	return false


static func _base_price_of(loader, good_id: String) -> float:
	var good: Dictionary = loader.commodity_goods.get(good_id, {})
	return float(good.get("base_price", 0.0))


# --- Delivery ----------------------------------------------------------------------


## Put the occasion in front of whoever it belongs to: the player's desk, or an
## AI nation's same-tick decision.
##
## THE MARKS ARE MADE HERE, at DELIVERY, and neither in announce() nor at
## resolution -- the one place this differs from Legislature.apply()'s
## `passed_law_ids`. An event HAS HAPPENED the moment it is delivered; the choice
## is the response to it, not the event, and marking at resolution would mean a
## save reloaded mid-crisis could see the same revelation announced twice.
## Delivery, not announce(), is also what makes the marks bind for the AI: the AI
## branch resolves directly and never calls announce(), so marks inside announce()
## were player-only -- the once event recurred for the other twenty-eight nations
## and no cooldown ever bound on one. announce() stays the raw staging primitive
## the test sweep and the screenshot harness drive repeatedly, and a sweep calling
## it forty-eight times must not accumulate cooldown state: state belongs to
## delivery, not to staging.
##
## Returns whether the occasion LANDED -- true for an AI resolution, a player
## announce, and the dedupe skip (the event's presence is already on the desk,
## which is delivery in the only sense left); false only when the desk is full.
## Every door reads the false: the armed chain WAITS a month (the entry survives,
## due again), the hook and the hazard skip finitely (next happening, next month).
static func _deliver(state, ns, loader, ev, month_index: int, is_player: bool) -> bool:
	# THE BOUND LIVES HERE, at the one function every delivery door passes: the
	# chain, hook and hazard doors all deliver through here, so one gate is
	# every door's -- gating any single caller loop let the other two push the
	# desk past QUEUE_MAX (reproduced at six: chain + hook on a full desk).
	# BEFORE the marks, deliberately: a full-desk month writes NOTHING -- no
	# once mark, no cooldown, no quiet -- or a waiting once-flagged chain would
	# come back next month and die at its own gates, marked for an occasion
	# nobody ever saw. The false sends the caller to its own wait-or-skip
	# semantics; nothing is banked.
	if is_player and ns.event_queue.size() >= K.QUEUE_MAX:
		return false
	# Written BEFORE the desk's dedupe skip rather than after it: a skipped
	# duplicate arrives with the same month_index, and every write below is a
	# function of that month, so the second write is the first write.
	ns.event_category_quiet[ev.category] = K.CATEGORY_QUIET_MONTHS
	if ev.cooldown_months > 0:
		ns.event_cooldowns[ev.id] = month_index + int(ev.cooldown_months)
	if ev.once:
		ns.event_fired[ev.id] = true
	if is_player:
		# The same occasion twice is not two occasions: a draw landing while the
		# desk still holds its event (a long deadline outliving the category
		# quiet) adds nothing -- the entry already on the desk IS the event's
		# presence. Skipped rather than merged: two entries with one id would
		# answer twice through two cards, which is the deadline charging double.
		# Checked HERE and not inside announce() so announce stays the raw
		# primitive the test sweep and the screenshot harness drive month by
		# month -- they mean "put this in front of me", not "run the desk".
		for entry in ns.event_queue:
			if String(entry.get("event_id", "")) == ev.id:
				return true
		announce(
			ns, ev, month_index,
			region_names(ns, loader)
		)
		return true
	var choice := _choose(ns, ev)
	_resolve(state, ns, loader, ev, choice, false, {})
	return true


## The region a sited event strikes: floor(unit(hash(nation|event|site), month) x n).
## Uniform over the nation's sorted region ids -- NOT population-weighted, because
## a weighted draw is Ile-de-France for ever in France (the static-site finding,
## V2.6b1) and a disaster that cannot move is a decoration. Pure, like the hazard:
## same inputs, same place, reload-safe. One region takes index 0 -- the CYP, EST,
## LTU, LVA and MLT bound named at V3.3: a nation of one region cannot differ from
## itself, so the draw is national by construction there and a hash would be a
## second answer to a question with one response.
static func _site_index(nation_id: String, event_id: String, month_index: int, n_regions: int) -> int:
	if n_regions <= 1:
		return 0
	return int(Cycle.unit("%s|%s|site" % [nation_id, event_id], month_index) * float(n_regions))


## id -> name for one nation's own regions, read off the loader's region content --
## the per-nation array every UI helper that names a region already scans. Built per
## announcement and handed to announce(), which stores the NAME it needs; nothing
## keeps the map, so there is no second index of the loader to drift.
static func region_names(ns, loader) -> Dictionary:
	var out := {}
	for region in loader.regions.get(ns.id, []):
		out[String(region.id)] = String(region.region_name)
	return out


## Put the event on the player's desk, ordered severity-first. The raw staging
## primitive: this writes THE QUEUE AND NOTHING ELSE.
##
## `event_name` is COPIED IN, not looked up at read time, for Referendum.announce()'s
## reason: src/sim/calendar.gd draws a diary row off this register and preloads nothing,
## so the register has to carry its own label. It is also what lets the tick above
## clear an entry whose content has gone without needing to name it.
##
## THE REGISTERS ARE NOT WRITTEN HERE. The `once` mark, the per-event cooldown and
## the category quiet are first stamped at DELIVERY -- _deliver(), the tick's door --
## and not at announcement (a resolution later RE-ARMS the category quiet, see
## _resolve), which is the one place that differs
## from Legislature.apply()'s `passed_law_ids`: an event HAS HAPPENED the moment it
## is delivered, and marking at resolution would mean a save reloaded mid-crisis
## could see the same revelation announced twice. Delivery is also what makes the
## marks bind for the AI, whose branch never calls this function; and the sweeps
## that drive this primitive month after month must leave no cooldown state behind.
static func announce(ns, ev, month_index: int, region_by_id: Dictionary) -> void:
	var entry := {
		"event_id": ev.id,
		"event_name": ev.event_name,
		"months_left": int(ev.respond_months),
		"interrupt": bool(ev.interrupt),
		"severity": int(ev.severity),
		"category": ev.category,
	}
	# V3.5: the place is drawn at announcement and stored BOTH WAYS -- the id, and
	# the name beside it, because the calendar draws its diary row off this register
	# and preloads nothing (the reason `event_name` above is copied in rather than
	# looked up, one key over). Stored rather than re-derived at read time because
	# the register carries no announcement month: months_left only counts down, so a
	# save reloaded mid-crisis cannot reconstruct which month drew which place. A
	# non-sited event gains NO keys -- an old save's register reads exactly as it
	# did. A name that fails to resolve stores empty, and every reader appends only
	# on non-empty, so the failure is a missing label and never a dangling dash --
	# and tests/test_events.gd sweeps all 29 nations to pin the map complete.
	if ev.sited:
		var ids: Array = ns.region_pop_share.keys()
		ids.sort()
		var region_id: String = ids[_site_index(ns.id, ev.id, month_index, ids.size())]
		entry["region_id"] = region_id
		entry["region_name"] = String(region_by_id.get(region_id, ""))
	ns.event_queue.append(entry)
	_order_queue(ns)


## Worst first, and within one severity in arrival order. A hand insertion sort
## and not sort_custom: Godot documents sort_custom as UNSTABLE, so equal
## severities were ordered only by the accident that a four-entry array takes the
## engine's insertion path -- and which entry is head_entry() depends on it. The
## desk is bounded by QUEUE_MAX, so the quadratic walk costs nothing.
static func _order_queue(ns) -> void:
	if ns.event_queue.size() < 2:
		return
	var ordered: Array = []
	for entry in ns.event_queue:
		var at := ordered.size()
		while at > 0 and int(ordered[at - 1].get("severity", 1)) < int(entry.get("severity", 1)):
			at -= 1
		ordered.insert(at, entry)
	ns.event_queue.clear()
	for entry in ordered:
		ns.event_queue.append(entry)


# --- The verbs ---------------------------------------------------------------------

## The player answers the HEAD of the desk. V1.8's signature, kept for harnesses,
## tests and tools that answer "the thing in front of me" -- the cards answer by
## id through answer() now; answering a specific entry is answer() below.
static func choose(state, loader, choice_id: String) -> Dictionary:
	var ns = state.player()
	if ns == null or not is_pending(ns):
		return {}
	return answer(state, loader, pending_event_id(ns), choice_id)


## The player answers a SPECIFIC entry -- the queue's own verb, and what the
## surfaces route through now that several things can be in front of them at once.
## Returns the record that was written, or {} if no such entry or choice.
static func answer(state, loader, event_id: String, choice_id: String) -> Dictionary:
	var ns = state.player()
	if ns == null:
		return {}
	for entry in ns.event_queue:
		if String(entry.get("event_id", "")) != event_id:
			continue
		var ev = event_by_id(loader, event_id)
		if ev == null:
			ns.event_queue.erase(entry)
			return {}
		var choice: Dictionary = ev.choice_by_id(choice_id)
		if choice.is_empty():
			return {}
		return _resolve(state, ns, loader, ev, choice, false, entry)
	return {}


## The AI's desk is the same tick it announced in: score every choice against the
## nation's own position and take the best. Minimal by events-model §5's closure
## note -- approval-seeking on the size-weighted bloc response, a fiscal term
## that prefers balance when the deficit is high, a cleanliness term when
## corruption is high, a concession term when unrest is high -- and the terms
## TRADE, which is the point: a deficit-running government in unrest prefers the
## concession a balanced one refuses. Deterministic; ties go to content order.
static func _choose(ns, ev) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	for choice in ev.choices:
		var score := _score_choice(ns, choice)
		if score > best_score:
			best_score = score
			best = choice
	return best


static func _score_choice(ns, choice: Dictionary) -> float:
	var effects: Dictionary = choice.get("effects", {})
	var score := 0.0

	var blocs: Dictionary = effects.get("bloc_offset", {})
	var weighted := 0.0
	var weight_sum := 0.0
	for bloc in blocs:
		var size: float = float(OpinionK.BLOC_SIZE.get(bloc, 0.0))
		weighted += size * float(blocs[bloc])
		weight_sum += size
	if weight_sum > 0.0:
		score += weighted / weight_sum

	# Fiscal: revenue-raising and spending-cutting effects improve the balance by
	# exactly what they say, so the term is one number from two channels and the
	# sign is the register's own (a shortfall is POSITIVE -- E0's finding).
	if float(ns.deficit_pct_gdp) > K.CHOOSER_DEFICIT_FLOOR:
		var balance_delta := 0.0
		for tax_key in effects.get("tax_rates_pct", {}):
			balance_delta += float(effects["tax_rates_pct"][tax_key])
		for spend_key in effects.get("spending_pct_gdp", {}):
			balance_delta -= float(effects["spending_pct_gdp"][spend_key])
		score += balance_delta * K.CHOOSER_FISCAL_WEIGHT

	if float(ns.corruption) > K.CHOOSER_CORRUPTION_FLOOR:
		# Corruption's better direction is unambiguous (E3's fourth axis), so a
		# dirty government still prefers to clean up when the voters can see it.
		score -= float(effects.get("society", {}).get("corruption", 0.0)) * K.CHOOSER_CORRUPTION_WEIGHT

	if float(ns.unrest_pct) > K.CHOOSER_UNREST_FLOOR:
		# A concession is new spending; settlement_stance has no better
		# direction by design (E3's own argument), so the money is the honest
		# proxy for what an unrestful country's government reaches for.
		for spend_key in effects.get("spending_pct_gdp", {}):
			score += float(effects["spending_pct_gdp"][spend_key]) * K.CHOOSER_UNREST_WEIGHT

	return score


# --- The resolution ----------------------------------------------------------------

## The shared core: apply through the one applier, retire the entry, quiet the
## category, arm whatever the choice arms, record. `entry` is the queue entry for
## a player resolution and {} for an AI's (nothing to retire).
##
## There is no cost to answering EARLY and none to answering late beyond the
## default itself, and that is not an oversight: the deadline is the pressure, and
## a second price on the timing would need a number solved against the default's,
## which is what src/core/investment_action.gd refuses as one strength written
## twice. What waiting actually buys is information -- another month of the
## figures the choice is about -- and what it risks is the default arriving first.
static func _resolve(state, ns, loader, ev, choice: Dictionary, defaulted: bool, entry: Dictionary) -> Dictionary:
	Legislature.apply_effects(state, ns, choice.get("effects", {}), loader)

	# The place is read BEFORE the register is cleared: a past act's site cannot be
	# re-derived once the shares have moved (V2.6b1's record argument) -- and the
	# register carries no announcement month to reconstruct the shares it moved
	# from, which is why the place itself is stored rather than re-derived.
	var region_name := String(entry.get("region_name", ""))
	if not entry.is_empty():
		ns.event_queue.erase(entry)
	ns.event_category_quiet[ev.category] = K.CATEGORY_QUIET_MONTHS

	# V4.4: the chain. A choice that arms a follow-up schedules it at an absolute
	# due month -- content's say, at a delay the schema bounds. The armed entry
	# survives the save (a consequence the player paid for must not evaporate),
	# and its arrival next month runs through the same gates as any draw.
	var arms: Dictionary = choice.get("arms", {})
	if not arms.is_empty():
		var month_index := _absolute_month(int(state.year), int(state.month))
		ns.event_armed.append({
			"event_id": String(arms.get("event_id", "")),
			"due_index": month_index + int(arms.get("delay_months", 1)),
			"source_id": ev.id,
		})

	var record := {
		"event_id": ev.id,
		"event_name": ev.event_name,
		"choice_id": String(choice.get("id", "")),
		"choice_label": String(choice.get("label", "")),
		"defaulted": defaulted,
		"year": int(state.year),
		"month": int(state.month),
		"category": ev.category,
	}
	# Only for a sited event, and only when the name resolved: an absent key is what
	# every record before V3.5 carried, and a missing figure is an em dash, never "".
	if region_name != "":
		record["region_name"] = region_name
	# A DISPLAY RECORD AND NOT A MEMORY. Nothing in src/sim/ reads this back, and
	# tests/test_events.gd asserts the
	# ledger property by reading every file in the directory -- V1.3e's *no grievance
	# ledger* property and V1.3f's own `foreign_acts` check, in the one session most
	# likely to be tempted to build the ledger literally. What an event remembers
	# about a previous event is exactly what `event_fired` says and nothing more.
	ns.event_history.push_front(record)
	while ns.event_history.size() > K.EVENTS_KEPT:
		ns.event_history.remove_at(ns.event_history.size() - 1)
	return record
