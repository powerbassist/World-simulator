extends RefCounted

## The People roster's reader -- rework 1 (Gameplay's people-cabinet brief, the author's
## direction A "le tableau"). One table of the people the president deals with, a word
## before every figure, sorted by WHO NEEDS HIM: a request waiting, a word falling due,
## a grudge past "hostile, may leak", then standing. That rule was the six "Who matters
## now" cards' (people_now.gd); it is the sort now, and the cards are gone -- one
## readout, not two.
##
## Pure reads of state and content, no node: the panel draws what this returns, and a
## later surface (an audience's "talk about someone", H3) can list the same rows.
## Executives stay in Sectors (the brief: firm chiefs are not People's), and the
## president is never on their own roster.
##
## The government is ONE ROW PER PORTFOLIO, held by a party: the sim names no minister
## (docs/people-model.md 3, U6b's cut), so an office row carries the party, what the
## office delivers against an average party's par (Cabinet.effectiveness), the party's
## loyalty in a word and its share of offices.

const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Feelings = preload("res://src/ui/feelings.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const Words = preload("res://src/ui/lever_words.gd")
const DateText = preload("res://src/ui/date_text.gd")
const PK = preload("res://src/ui/priorities_constants.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Characters = preload("res://src/sim/characters.gd")
const President = preload("res://src/sim/president.gd")
const PresidentK = preload("res://src/sim/president_constants.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const Staff = preload("res://src/sim/staff.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AudienceLane = preload("res://src/sim/audience_lane.gd")

## The chips, in reading order: id, label. "needs" is the default view.
const CHIPS := [
	["needs", "Needs you"],  # i18n: msgid last
	["government", "Government"],  # i18n: msgid last
	["leaders", "Party leaders"],  # i18n: msgid last
	["politicians", "Politicians"],  # i18n: msgid last
	["regions", "Regions"],  # i18n: msgid last
	["press", "Press"],  # i18n: msgid last
	["unions", "Unions"],  # i18n: msgid last
	["bench", "The bench"],  # i18n: msgid last
	["activists", "Activists"],  # i18n: msgid last
	["abroad", "Abroad"],  # i18n: msgid last
]
## A chip that is one kind of the cast.
const CHIP_KIND := {"regions": "regional_figure", "press": "press_owner", "unions": "union_leader",
	"bench": "judge", "activists": "activist"}
## A promise is "due" when its date is this close (months), the briefing's own near.
const DUE_MONTHS := 2
## The need ranks, most pressing first; NONE is everyone else, by standing.
enum Need { REQUEST, DUE, GRUDGE, NONE }
## An office's delivery against par (Cabinet.effectiveness, 1.0 an average party): at or
## past STRONG it is strong, under WEAK weak, about par between.
const STRONG := 1.05
const WEAK := 0.9
## How well the president knows them (President.knowledge_band), as the column says it.
const KNOWN := {"known": "well", "acquaintance": "a little", "stranger": "barely"}  # i18n: msgid


## The rows of one chip, the need rule's order; `query` (a name, a party, an office)
## searches every group instead.
static func rows(state, loader, chip: String, query: String) -> Array:
	var ns = state.player()
	var out: Array = []
	var q := query.strip_edges().to_lower()
	for pid in _pool(state, loader, chip if q == "" else ""):
		var row := _row(state, loader, ns, pid)
		if q != "" and not ("%s %s %s" % [row["name"], row["side"], row["holds"]]).to_lower().contains(q):  # i18n: row-ok the reader's own row, matched against what the player typed
			continue
		if q == "" and chip == "needs" and int(row["rank"]) == Need.NONE:
			continue
		out.append(row)
	out.sort_custom(func(a, b) -> bool:
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) < int(b["rank"])
		if float(a["standing"]) != float(b["standing"]):
			return float(a["standing"]) > float(b["standing"])
		return String(a["name"]) < String(b["name"]))  # i18n: row-ok the reader's own row, a tie-break
	return out


## Everyone a chip can list, by id: the played nation's cast (no executives, not the
## president), and for Abroad, or a search, every other nation's leader.
static func _pool(state, loader, chip: String) -> Array:
	var ns = state.player()
	var president := President.leader_id(ns)
	var leaders := _leaders(loader, ns)
	var out: Array = []
	if chip != "abroad":
		for person in loader.people.get(String(ns.id), []):
			var pid := String(person.id)
			if pid == president:
				continue
			# Firm chiefs stay in Sectors -- except on "Needs you" and in a search: one who
			# asks to see the president counts in the title bar's requests (pass 2 on #388).
			if String(person.kind) == "executive" and not (chip == "" or chip == "needs"):
				continue
			if _in_chip(ns, loader, person, chip, leaders):
				out.append(pid)
	if chip == "abroad" or chip == "" or chip == "needs":
		var ids: Array = state.nations.keys()
		ids.sort()
		for id in ids:
			if String(id) != String(ns.id) and loader.nations.has(id):
				var who := President.leader_id(state.nations[id])
				if who != "" and loader.person_by_id.has(who):
					out.append(who)
	return out


static func _in_chip(ns, loader, person, chip: String, leaders: Dictionary) -> bool:
	var pid := String(person.id)
	match chip:
		"", "needs":
			return true
		"government":
			return pid == String(ns.pm_person_id) or Staff.is_staff(loader, pid) \
				or (String(person.kind) == "politician" and ns.coalition_party_ids.has(_party_id(ns, loader, person)))
		"leaders":
			return leaders.has(pid)
		"politicians":
			return String(person.kind) == "politician" and not leaders.has(pid)
	return String(person.kind) == String(CHIP_KIND.get(chip, ""))


## One person's row: {id, name, side, holds, feels, feels_tone, wants, wants_tone, owe,
## known, rank, standing, request_id, booked}.
static func _row(state, loader, ns, pid: String) -> Dictionary:
	var person = loader.person_by_id.get(pid)
	var now := int(state.year) * 12 + int(state.month)
	var row := {"id": pid, "name": String(person.person_name), "side": _side(state, loader, ns, person),
		"holds": _holds(state, loader, ns, person), "rank": Need.NONE, "request_id": "", "booked": false,
		"standing": float(ns.person_standing.get(pid, 0.0)), "wants": "—", "wants_tone": "", "owe": "—",
		"known": Strings.t(String(KNOWN[President.knowledge_band(ns, pid)]))}  # i18n: row-ok a band id, its word the msgid
	var feel := Feelings.of(ns, pid)
	var grudge := Feelings.word("grudge", float(feel["grudge"]))
	row["feels"] = grudge if grudge != "" else Feelings.word("rapport", float(feel["rapport"]))
	row["feels_tone"] = UiTheme.BAD_TEXT if grudge != "" else ""
	if float(feel["grudge"]) >= PK.HOSTILE_GRUDGE:
		row["rank"] = Need.GRUDGE
	# The president's own words only: a pledge or a silence is THEIR word to him.
	var owed: Array = President.commitments_with(ns, pid).filter(func(c): return not PresidentK.OWED_KINDS.has(String(c["kind"])))
	owed.sort_custom(func(a, b): return int(a["due_month"]) < int(b["due_month"]))
	if not owed.is_empty():
		var first: Dictionary = owed[0]
		row["owe"] = Strings.t("%s, due %s") % [PersonCard.object_text(loader, ns, String(first["object"]), first, true), Words.when_long(int(first["due_month"]))]
		if int(first["due_month"]) - now <= DUE_MONTHS:
			row["rank"] = mini(int(row["rank"]), Need.DUE)
	var request := _open_request(ns, pid)
	if not request.is_empty():
		row["rank"] = Need.REQUEST
		row["request_id"] = String(request["id"])
		var about := PersonCard.object_text(loader, ns, String(request["object"]), request, true)
		if String(request["status"]) == AK.STATUS_BOOKED and not (request["date"] as Dictionary).is_empty():
			var d: Dictionary = request["date"]
			row["booked"] = true
			row["wants"] = Strings.t("Sees you on %s about %s") % [DateText.day_month(int(d["day"]), int(d["month"])), about]
		else:
			# The inbox card's own date (Audiences.answer_by), never a second reading of it.
			# Short: the row sits under "Needs you" in the waiting tone, so the ask goes unsaid
			# (the prose budget's long-sentence ceiling, 10 words on the tab).
			row["wants"] = Strings.t("Answer by %s: %s") % [Words.when_long(Audiences.answer_by(request)), about]
			row["wants_tone"] = UiTheme.WARN_TEXT
	else:
		var want := _first_unserved(state, loader, ns, person)
		if not want.is_empty():
			row["wants"] = "%s %s" % [Strings.t(PersonCard.stance_label(String(want["stance"]))),  # i18n: row-ok a stance id, its word the msgid
				PersonCard.object_text(loader, ns, String(want["object"]), want, true)]
	return row


## The office or role they hold, in words: the head of government, a party's lead, the
## chief of staff, a foreign leader's title, else their kind.
static func _holds(state, loader, ns, person) -> String:
	var pid := String(person.id)
	if not pid.begins_with("%s_" % ns.id):
		for id in state.nations:
			if President.leader_id(state.nations[id]) == pid and loader.nations.has(id):
				return "%s, %s" % [President.leader_title(state.nations[id]), String(loader.nations[id].nation_name)]
	if pid == String(ns.pm_person_id):
		return String(ns.head_of_government_title)
	if pid == String(ns.head_of_state_person_id):
		return String(ns.head_of_state_title)
	# The party itself is the name's second line; the cell says what they hold in it.
	if _leaders(loader, ns).has(pid):
		return Strings.t("Party leader")
	return Strings.t(String(PersonCard.KIND_LABEL.get(String(person.kind), String(person.kind))))  # i18n: row-ok a kind id, its label the msgid


## Their party (an override first), or their nation abroad, else their kind as a word.
static func _side(state, loader, ns, person) -> String:
	var pid := String(person.id)
	if not pid.begins_with("%s_" % ns.id):
		return String(loader.nations[pid.get_slice("_", 0)].nation_name) if loader.nations.has(pid.get_slice("_", 0)) else ""
	var party = _party_of(loader, ns, _party_id(ns, loader, person))
	if party != null:
		return String(party.party_name)
	return Strings.t(String(PersonCard.KIND_LABEL.get(String(person.kind), String(person.kind))))  # i18n: row-ok a kind id, its label the msgid


## The person's party as the panel always read it: the override, the authored edge, or
## the party they lead.
static func _party_id(ns, loader, person) -> String:
	var party_id := String(ns.person_party_override.get(person.id, person.party_id))
	if party_id != "":
		return party_id
	for p in loader.parties.get(String(ns.id), []):
		if Characters.party_leader(ns, p.id, {p.id: p.leader_person_id}) == String(person.id):
			return String(p.id)
	return ""


## Leader id -> party name, for every party of the nation.
static func _leaders(loader, ns) -> Dictionary:
	var out := {}
	for p in loader.parties.get(String(ns.id), []):
		out[Characters.party_leader(ns, p.id, {p.id: p.leader_person_id})] = String(p.party_name)
	return out


static func _party_of(loader, ns, party_id: String):
	for p in loader.parties.get(String(ns.id), []):
		if String(p.id) == party_id:
			return p
	return null


## The person's open request (pending or booked), Audiences' own view, or {}.
static func _open_request(ns, pid: String) -> Dictionary:
	# A summons is not a request (#432 pass 2, TAKE 1): the lane's one read leaves it out.
	var row := AudienceLane.open_request(ns, pid)
	return {} if row.is_empty() else Audiences.request(ns, String(row["id"]))


## The first want the world is not giving them, the machine's own read
## (Characters.want_satisfied, as the old panel's count had it); {} when all are served.
static func _first_unserved(state, loader, ns, person) -> Dictionary:
	if person.wants.is_empty():
		return {}
	var meters := {"grievance": float(ns.unrest_pct), "press_freedom": float(ns.press_freedom),
		"judicial_independence": float(Judiciary.independence_deviation(ns))}
	var leaders := {}
	for party in loader.parties.get(String(ns.id), []):
		leaders[party.id] = party.leader_person_id
	for want in person.wants:
		var served := Characters.want_satisfied(ns, person, want, meters, leaders)
		if (not served) if String(want["stance"]) != "oppose" else served:
			return want
	return {}


## The month `portfolio` fell vacant, or -1 unknown: the latest of the events that empty
## an office -- a dismissal (Removal's stamp), a reshuffle that left it empty
## (Cabinet.vacate's), a resignation (ns.last_resignation) -- since a stamp is never
## cleared when the office is filled again (pass 2 on #388: a two-year-old dismissal
## dated a fresh resignation).
static func _vacated(ns, portfolio: String) -> int:
	var at := int(ns.portfolio_removed_month.get(portfolio, -1))
	if String(ns.reshuffle_portfolio) == portfolio:
		at = maxi(at, int(ns.reshuffle_month))
	var resigned: Dictionary = ns.last_resignation
	if String(resigned.get("portfolio", "")) == portfolio:
		at = maxi(at, int(resigned.get("year", 0)) * 12 + int(resigned.get("month", 0)))
	return at


## One row per portfolio: {portfolio, office, party_id, party, leader_id, vacant,
## delivers, delivers_tone, feels, feels_tone, owe, owe_tone, seats}.
static func offices(state, loader) -> Array:
	var ns = state.player()
	var held := {}
	for f in ns.cabinet:
		var holder := String(ns.cabinet[f])
		if holder != "":
			held[holder] = int(held.get(holder, 0)) + 1
	var out: Array = []
	for f in CK.PORTFOLIO_KEYS:
		var party = _party_of(loader, ns, String(ns.cabinet.get(f, "")))
		var row := {"portfolio": f, "office": Labels.portfolio(f), "party_id": "", "party": "", "leader_id": "",
			"vacant": party == null, "delivers": "", "delivers_tone": "", "feels": "", "feels_tone": "", "owe": "—", "owe_tone": "",
			"seats": "—"}
		if party == null:
			var since := _vacated(ns, f)
			row["party"] = Strings.t("Vacant since %s") % Words.when_long(since) if since >= 0 else ""
			row["delivers"] = Strings.t("Counts half until you fill it")
			row["delivers_tone"] = UiTheme.BAD_TEXT
			out.append(row)
			continue
		row["party_id"] = String(party.id)
		row["party"] = String(party.party_name)
		var seats := int(ns.seats_by_party.get(party.id, 0))
		row["seats"] = Strings.tn("%d seat", "%d seats", seats) % seats
		row["leader_id"] = Characters.party_leader(ns, party.id, {party.id: party.leader_person_id})
		var eff := Cabinet.effectiveness(ns, f)
		var pct := "%d%%" % roundi(eff * 100.0)
		# Par is an average party's 100 %; the bands either side are this file's cut, wide
		# enough that 96 % does not read as failing (the first frame's all-red column).
		if eff >= STRONG:
			row["delivers"] = Strings.t("Delivers %s: the party is strong here") % pct
			row["delivers_tone"] = UiTheme.GOOD_TEXT
		elif eff < WEAK:
			row["delivers"] = Strings.t("Delivers %s: the party is weak here") % pct
			row["delivers_tone"] = UiTheme.BAD_TEXT
		else:
			row["delivers"] = Strings.t("Delivers %s, about par") % pct
		# The resignation check's own signal against its own threshold (cabinet.gd);
		# "restless" is past half of it -- the one cut this file adds.
		var signal_ := Cabinet.resignation_signal(ns, party)
		if signal_ >= CK.RESIGNATION_THRESHOLD:
			row["feels"] = Strings.t("ready to resign")
			row["feels_tone"] = UiTheme.BAD_TEXT
		elif signal_ >= CK.RESIGNATION_THRESHOLD * 0.5:
			row["feels"] = Strings.t("restless")
			row["feels_tone"] = UiTheme.WARN_TEXT
		else:
			row["feels"] = Strings.t("loyal")
		var ent := int(ns.cabinet_entitlement.get(party.id, 0))
		var has := int(held.get(String(party.id), 0))
		if has < ent:
			row["owe"] = Strings.tn("Holds %d of its %d office", "Holds %d of its %d offices", ent) % [has, ent]
			row["owe_tone"] = UiTheme.WARN_TEXT
		out.append(row)
	return out
