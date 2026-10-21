extends RefCounted

## The month's news of the world as cards: foreign acts, the player's own unrest,
## the bench's acts, and an alliance obligation opening.
##
## Out of main.gd at V5.1c (the reflection's D2: main.gd was the shell, the card
## writer, the pause and half the game's wiring). Moved whole: the wording, the
## memories and the order of pushes are the ones main.gd had. Holds no game
## state of its own beyond what it has already announced; `setup()` hands it the
## live state (again on a load) and the card column it pushes to.

const Defence = preload("res://src/sim/defence.gd")
const DefenceK = preload("res://src/sim/defence_constants.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")
const ForeignPolicyK = preload("res://src/sim/foreign_policy_constants.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Num = preload("res://src/ui/num.gd")
const Strings = preload("res://src/ui/strings.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const DataLoader = preload("res://src/core/data_loader.gd")

var _state
var _loader: DataLoader
var _stack


func setup(state, loader, stack) -> void:
	_state = state
	_loader = loader
	_stack = stack


## The player's obliged deployments, right now. Only the obliged ones: a chosen
## deployment is a command the player just issued and does not need a card telling
## them they issued it.
func obliged_count() -> int:
	if _state == null:
		return 0
	var n := 0
	for ally_id in Defence.deployments_of(_state, _state.player_nation_id).keys():
		if Defence.deployment_kind(_state, _state.player_nation_id, String(ally_id)) == DefenceK.DEPLOYMENT_OBLIGED:
			n += 1
	return n


## V1.3g. An alliance obligation opening is the one thing in this game that puts a
## standing charge on the player's budget with no command behind it, so it is
## exactly the thing that must not arrive silently -- the player would otherwise see
## a deficit move for a reason nothing on screen names, which is the class of
## failure docs/trade-model.md's unread `refused_by_partner` belongs to.
func card_obligations(before: int) -> void:
	if _stack == null:
		return
	var now := obliged_count()
	if now <= before:
		return

	var ns = _state.player()
	_stack.push(
		tr("Alliance obligation"),
		tr("Forces are committed under a defensive pact. The budget carries %s%% of GDP for as long as it stands, and only abandoning the pact ends it.") % Num.f((
			0.0 if ns == null else ns.deployment_bill_pct_gdp
		), 2),
	)


## Put this month's foreign acts in the message column. V1.3f, and the first thing
## in the game that ever calls message_stack.push().
##
## U5a shipped that column as furniture with a stated reason -- the thing that
## fills it is events, which docs/tiers/v1.md schedules at V1.8, and wiring it to
## invented content would have cost that argument. An act by a simulated nation is
## not invented content; it is state src/sim/ just wrote. So this spends nothing:
## V1.8 still adds calls rather than a column.
##
## The sim writes the record and the UI decides what is worth showing, which is the
## data -> sim -> ui direction engine-decision.md rule 2 states. src/sim/ never
## touches this file and GameState.foreign_acts is never read back inside src/sim/
## -- tests/test_foreign_policy.gd asserts that, because a decision consulting it
## would be the grievance ledger docs/foreign-policy-model.md is built without.
##
## Filtered, and it has to be: nine nations on a cadence produce more acts than the
## column's six slots, and an unfiltered feed would push a sanction aimed at the
## player off the bottom before they read it. Anything aimed AT the player always
## cards; anything between two other nations needs the player to have a real stake
## in the actor. The threshold reuses the model's own stake vector rather than
## inventing a second notion of "relevant".
func card_foreign_acts(year: int, month: int) -> void:
	if _stack == null:
		return

	var player_id: String = _state.player_nation_id
	var floor_share: float = ForeignPolicy.even_share(_state, player_id) * ForeignPolicyK.CARD_MIN_STAKE_SHARE
	var news_of_others := SettingsPanel.foreign_news()

	# Oldest first, so the newest act ends up at the top of the column: push()
	# appends and the stack drops from the front when it overflows.
	var fresh: Array = []
	for act in _state.foreign_acts:
		if int(act["year"]) != year or int(act["month"]) != month:
			break
		fresh.push_front(act)

	# Grouped by action, V2.9: four allies state-visiting in one month is ONE
	# piece of news, not four cards -- five near-identical cards were pushing
	# decisions off a six-slot column (playtest 2026-09-05). The filters below
	# are the original stake-floor gates, unchanged; only the carding is grouped.
	var by_action: Dictionary = {}
	for act in fresh:
		var actor_id := String(act["actor_id"])
		var target_id := String(act["target_id"])
		if actor_id == player_id:
			continue
		# V5.1-0c: news between two other nations is the player's to ask for.
		if target_id != player_id and (not news_of_others or ForeignPolicy.stake(_state, player_id, actor_id) < floor_share):
			continue

		var key := Strings.record_action_name(act)
		if not by_action.has(key):
			by_action[key] = {"aimed": [], "elsewhere": []}
		if target_id == player_id:
			by_action[key]["aimed"].append({
				"actor": _loader.nation_name(actor_id),
				"reason": String(act["reason"]),
			})
		else:
			by_action[key]["elsewhere"].append({
				"actor": _loader.nation_name(actor_id),
				"body": "%s: %s." % [key, _loader.nation_name(target_id)],
			})

	for action_name in by_action:
		var slot: Dictionary = by_action[action_name]
		var aimed: Array = slot["aimed"]
		if not aimed.is_empty():
			# An act aimed at the player names the player in the TITLE and not
			# again in the body: "Austria -> you / State Visit: France" reads as
			# though France were a third country involved somehow.
			var title: String = (
				tr("%s → you") % String(aimed[0]["actor"]) if aimed.size() == 1
				else tr("%d× %s → you") % [aimed.size(), action_name]
			)
			var who: String = (
				"%s." % String(aimed[0]["actor"]) if aimed.size() == 1
				else "%s." % ", ".join(aimed.map(func(a): return String(a["actor"])))
			)
			# The model computes a reason and this is the only place it is ever
			# read. Shipping the key unread would be V1.3b's `refused_by_partner`
			# a third time -- a field src/sim/ fills in and no surface shows,
			# which this block has now recorded twice and fixed once. The first
			# act's reason stands for the group: same action, same month.
			_stack.push(title, "%s %s %s" % [
				action_name, who, _act_reason_text(String(aimed[0]["reason"])),
			])
		else:
			for line in slot["elsewhere"]:
				_stack.push(String(line["actor"]), String(line["body"]))


## V1.5c. What the unions did this month, as a card.
##
## No filter, unlike _card_foreign_acts() above, and the asymmetry is the content rather
## than an oversight: nine nations on a cadence produce more acts than the column has
## slots, where the player's own country strikes at most once a year. Every act is
## aimed at the player by definition, so there is nothing to be relevant ABOUT.
##
## The LABEL is read here and nowhere in src/sim/ -- unrest_constants.ACT_LABELS carries
## `protest` and `strike`, the sim picks one off the stock, and this file owns the
## wording. That is the same split nation_panel.gd has for a refusal and
## _act_reason_text() below has for a reason, and it is what makes one machine with two
## names honest rather than two machines wearing the row's vocabulary.
func card_unrest_acts(year: int, month: int) -> void:
	if _stack == null:
		return
	for act in _state.unrest_acts:
		if int(act["year"]) != year or int(act["month"]) != month:
			continue
		if String(act["nation_id"]) != _state.player_nation_id:
			continue
		# V2.6b1. The card names the PLACE, and it reads it off the act's own record
		# rather than re-deriving it: a past act's site cannot be recovered once the
		# shares have moved, which is why unrest.gd writes it down at the moment it
		# happens. Absent -- every act on a version-29 save, and every nation with no
		# site -- the sentence falls back to the national wording it has always had,
		# so an old save reads correctly rather than printing an empty place.
		var city := String(act.get("city_name", ""))
		var region := String(act.get("region_name", ""))
		var body := tr("Grievance stands at %.0f of 100. Output will carry it for months.") % float(act["unrest_pct"])
		if city != "" and region != "":
			body = tr("%s, %s. Grievance stands at %.0f of 100. Output will carry it for months.") % [
				city, region, float(act["unrest_pct"]),
			]
		_stack.push(_unrest_title(String(act["label"])), body)  # i18n: row-ok a key the title maps


## V4.3's interim surface: one card per act, named off the act's own record --
## the person's NAME is resolved here in the UI, never in src/sim/ (the
## re-key's law, still). T5's People-panel and hover-card surfaces build on
## the same records; this column's card exists so an act is never silent.
func card_character_acts(acts: Array) -> void:
	if _stack == null:
		return
	for act in acts:
		var who := _loader.person_name(String(act["person_id"]))
		var kind := String(act["act"])
		var detail: Dictionary = act.get("detail", {})
		var title := tr("The bench stirs")
		var body := tr("%s acts.") % who if who != "" else tr("Someone acts.")
		match kind:
			"resign":
				title = tr("A resignation")
				body = tr("%s resigns the premiership. The party holds the office; the government pays in standing.") % who
			"defect":
				title = tr("A defection")
				body = tr("%s crosses the floor. The seat stays with the whip.") % who
			"challenge":
				var deposed := _loader.person_name(String(detail.get("deposed", "")))
				title = tr("A leadership challenge")
				body = tr("%s takes the leadership. %s stands down.") % [who, deposed] if deposed != "" else tr("%s takes the leadership. The incumbent stands down.") % who
			"brief_against":
				title = tr("A leak")
				body = tr("%s briefs against the government.") % who
		_stack.push(title, body)


func _unrest_title(label: String) -> String:
	match label:
		"protest": return tr("Demonstrations")
		"strike": return tr("General strike")
	return tr("Industrial action")


## The sentence for a ForeignPolicy.ACT_REASON_* key. src/sim/ returns keys and
## src/ui/ owns the wording, the same split nation_panel.gd has for a refusal and
## orgs_panel.gd for a vote.
func _act_reason_text(key: String) -> String:
	match key:
		ForeignPolicy.ACT_REASON_INTEREST: return tr("Their interests run this way.")
		ForeignPolicy.ACT_REASON_GOODWILL: return tr("Mending what had soured.")
		ForeignPolicy.ACT_REASON_GRIEVANCE: return tr("Answering a grievance.")
	return ""


## A kept appointment is something that happened to the player's government with
## no button pressed that day, so it is exactly the class of event the message
## column exists for -- alongside an alliance obligation opening and a foreign
## act. An act that REFUSED on arrival matters more, not less: it is the one
## outcome the player could not have predicted when they booked it.
func card_appointment(entry: Dictionary, label: String, ok: bool) -> void:
	if _stack == null:
		return
	if label.is_empty():
		_stack.push(
			tr("Appointment lapsed"),
			tr("Something booked for today no longer exists to be done."),
		)
		return

	# One whole sentence per shape, the failure a sentence of its own.
	var booked := tr("%s, as booked.") % label
	if String(entry.get("kind", "")) == CalendarK.KIND_DIPLOMATIC:
		booked = tr("%s with %s, as booked.") % [label, _loader.nation_name(String(entry.get("target_id", "")))]
	if not ok:
		booked += " " + tr("It did not carry.")
	_stack.push(tr("Kept: %s") % label, booked)
