extends SceneTree

## V5.3 b, step 6 (docs/design/v5.3-ab.md section 5, option 1, the author's "Un marchandage
## concret"): an audience is a deal on one ask. Headless.
##
##   - THE ASK is a real object: a bill a programme entry names, a portfolio, else a dated word.
##   - THE OFFER is real: a vote on the next bill, else silence, which stops a brief.
##   - GRANT pays the ask and takes the offer, with no roll. BARGAIN is one of three priced
##     approaches and wins the smaller grant for the same offer. REFUSE is a decline.
##   - THE DEAL IS TWO ROWS of ns.commitments, judged at their dates, each releasing the other.
##   - THE MONEY shows its evidence and its risk before it is taken, and a principled person
##     never offers any.
##
## The band's numbers are written here as literals, never read from the constants.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const Person = preload("res://src/core/person.gd")
const ProgrammeLoader = preload("res://src/core/loaders/programme_loader.gd")
const Deal = preload("res://src/sim/deal.gd")
const Levers = preload("res://src/sim/levers.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const AK = preload("res://src/sim/audience_constants.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const President = preload("res://src/sim/president.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Division = preload("res://src/sim/division.gd")
const DivisionTerms = preload("res://src/sim/division_terms.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalK = preload("res://src/sim/calendar_constants.gd")
const Characters = preload("res://src/sim/characters.gd")
const CK = preload("res://src/sim/character_act_constants.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const LeverOdds = preload("res://src/sim/lever_odds.gd")
const Offers = preload("res://src/sim/offers.gd")
const Shadows = preload("res://src/sim/shadows.gd")
const Exposure = preload("res://src/sim/exposure.gd")
const Delegation = preload("res://src/sim/delegation.gd")
const Removal = preload("res://src/sim/removal.gd")
const PeopleNow = preload("res://src/ui/people_now.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const Strings = preload("res://src/ui/strings.gd")

const PLAYER := "FRA"
const METERS := {"press_freedom": 50.0, "judicial_independence": 50.0, "grievance": 30.0}
const PLAYABLE := ["FRA", "DEU", "GBR", "POL"]

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_a_sponsor_asks_for_the_first_open_law_the_entry_names()
	_check_an_entry_with_no_law_is_a_word_at_the_next_term()
	_check_the_term_word_is_after_the_vote_in_every_playable_nation()
	_check_an_open_register_answers_next_month()
	_check_an_oppose_is_a_word_too()
	_check_a_meter_is_a_word_a_year_on()
	_check_a_portfolio_is_a_post()
	_check_a_party_outside_the_coalition_cannot_be_granted_a_post()

	_check_the_offer_is_a_vote_on_the_tabled_bill()
	_check_the_offer_is_a_vote_on_the_bill_in_the_diary()
	_check_no_bill_means_silence()
	_check_no_party_means_silence()
	_check_someone_who_pledged_offers_silence()

	_check_grant_writes_the_two_rows()
	_check_grant_on_a_post_seats_the_party()
	_check_grant_spends_no_attempt_and_survives_spent_attempts()
	_check_a_refused_grant_writes_nothing()
	_check_grant_takes_up_a_word_in_flight()
	_check_grant_on_a_post_pays_the_removal()
	_check_a_post_too_recently_moved_is_greyed()
	_check_someone_under_a_deal_does_not_ask_again()
	_check_answers_after_the_deal_read_the_deal()

	_check_three_approaches_and_no_more()
	_check_a_win_is_the_smaller_grant_for_the_same_offer()
	_check_a_win_on_a_post_is_a_word_not_a_seat()
	_check_a_promise_win_is_the_named_date()
	_check_a_promise_not_believed_binds_and_strikes_nothing()
	_check_refuse_is_a_decline()
	_check_answers_write_nothing()

	_check_a_bill_brought_keeps_the_word_whatever_the_verdict()
	_check_a_bill_not_brought_breaks_the_word_and_releases_them()
	_check_a_forced_bill_is_brought_and_voids_the_pledge()
	_check_their_broken_pledge_voids_my_word()
	_check_a_kept_pledge_leaves_the_word_standing()
	_check_a_pledge_never_voted_lapses_unpriced()
	_check_silence_stops_a_brief_then_ends_unpriced()

	_check_what_they_owe_is_not_the_presidents_word()
	_check_the_people_panel_reads_no_pledge_as_a_promise()
	_check_a_word_on_a_bill_reads_the_bills_name()
	_check_a_deal_survives_a_save()
	_check_a_row_from_before_the_deal_is_judged_as_it_was()

	_check_the_money_shows_its_risk_first()
	_check_a_principled_person_never_offers()

	_check_the_loader_reads_an_entrys_laws()

	_finish()


# --- The ask ----------------------------------------------------------------------------

func _check_a_sponsor_asks_for_the_first_open_law_the_entry_names() -> void:
	var f := _held_on_want("programme:", "sponsor")
	var entry := _entry(f["object"])
	var open := _open_laws(f, 2)
	entry["laws"] = [open[0], open[1]]
	f["ns"].law_cooldown_months[open[0]] = 5
	var ask: Dictionary = Deal.ask_of(f["state"], f["ns"], _loader, Audiences.request(f["ns"], f["id"]))
	entry.erase("laws")
	if String(ask.get("kind", "")) != "law" or String(ask.get("object", "")) != "law:%s" % open[1]:
		_fail("a sponsor asks for the first open law its entry names, got %s" % [ask])
	var now := _now(f)
	if int(ask.get("due_month", 0)) != now + 6 or int(ask.get("smaller_due_month", 0)) != now + 18:
		_fail("a law is due in 6 months, 18 for the smaller grant, got %s" % [ask])


func _check_an_entry_with_no_law_is_a_word_at_the_next_term() -> void:
	var f := _held_on_want("programme:", "sponsor")
	var ns = f["ns"]
	var ask: Dictionary = Deal.ask_of(f["state"], ns, _loader, Audiences.request(ns, f["id"]))
	var vote: int = int(ns.next_executive_year) * 12 + int(ns.next_executive_month)
	if String(ask.get("kind", "")) != "word" or String(ask.get("object", "")) != String(f["object"]):
		_fail("an entry with no law is a word on the want itself, got %s" % [ask])
	# The register opens in the month of the vote, after that month's judge has run, so
	# the word cannot be judged before the next month's.
	if int(ask.get("due_month", 0)) != vote + 1:
		_fail("a programme word falls due the month after the vote: %d, got %s" % [vote + 1, ask])
	if int(ask.get("smaller_due_month", 0)) != vote + 13:
		_fail("the smaller grant is a year on from it, got %s" % [ask])


func _check_the_term_word_is_after_the_vote_in_every_playable_nation() -> void:
	for id in PLAYABLE:
		var state = GameState.new_game(_loader, id)
		var ns = state.player()
		var now: int = int(state.year) * 12 + int(state.month)
		var ask: Dictionary = Deal.ask_of(state, ns, _loader, {"object": "programme:prog_jobs_first", "stance": "sponsor", "person_id": "%s_nobody" % id})
		if int(ask.get("due_month", 0)) <= now:
			_fail("%s: a programme word must fall due after today, got %s" % [id, ask])


func _check_an_open_register_answers_next_month() -> void:
	var f := _held_on_want("programme:", "sponsor")
	var ns = f["ns"]
	ns.months_in_term = 0
	var row := Audiences.request(ns, f["id"])
	if int(Deal.ask_of(f["state"], ns, _loader, row).get("due_month", 0)) != _now(f) + 1:
		_fail("in the register's own month the word is judged next month")
	ns.programme_chosen_term = int(ns.terms_served)
	var vote: int = int(ns.next_executive_year) * 12 + int(ns.next_executive_month)
	if int(Deal.ask_of(f["state"], ns, _loader, row).get("due_month", 0)) != vote + 1:
		_fail("a register already chosen waits for the next term")


func _check_an_oppose_is_a_word_too() -> void:
	var f := _held_on_want("programme:", "oppose")
	var entry := _entry(f["object"])
	entry["laws"] = _open_laws(f, 1)
	var ask: Dictionary = Deal.ask_of(f["state"], f["ns"], _loader, Audiences.request(f["ns"], f["id"]))
	entry.erase("laws")
	if String(ask.get("kind", "")) != "word" or String(ask.get("object", "")) != String(f["object"]):
		_fail("an entry someone opposes is no bill to bring, it stays a word, got %s" % [ask])


func _check_a_meter_is_a_word_a_year_on() -> void:
	var f := _held_on_want("meter:", "")
	var ask: Dictionary = Deal.ask_of(f["state"], f["ns"], _loader, Audiences.request(f["ns"], f["id"]))
	var now := _now(f)
	if String(ask.get("kind", "")) != "word" or int(ask.get("due_month", 0)) != now + 12 or int(ask.get("smaller_due_month", 0)) != now + 24:
		_fail("a meter is a word 12 months on, 24 for the smaller grant, got %s" % [ask])


func _check_a_portfolio_is_a_post() -> void:
	var f := _held_on_post(true)
	var ask: Dictionary = f["session"]["ask"]
	if String(ask.get("kind", "")) != "post" or String(ask.get("why_not", "x")) != "":
		_fail("a coalition party's portfolio is a post it can be granted, got %s" % [ask])
	if String(ask.get("party_id", "")) != String(f["party_id"]):
		_fail("the post goes to the person's party, got %s" % [ask])


func _check_a_party_outside_the_coalition_cannot_be_granted_a_post() -> void:
	var f := _held_on_post(false)
	var answers: Dictionary = Deal.answers(f["state"], f["ns"], _loader, f["session"])
	if bool(answers["grant"]["ok"]) or String(answers["grant"]["why_not"]) != "not a member of the governing coalition":
		_fail("Grant is greyed with the cabinet's own reason, got %s" % [answers["grant"]])
	var before: Dictionary = f["ns"].cabinet.duplicate()
	if bool(Deal.grant(f["state"], f["ns"], _loader, f["session"]).get("ok", true)):
		_fail("a greyed Grant was accepted")
	if f["ns"].cabinet != before:
		_fail("a refused Grant moved the cabinet")


# --- The offer --------------------------------------------------------------------------

func _check_the_offer_is_a_vote_on_the_tabled_bill() -> void:
	var f := _held_on_want("programme:", "sponsor", true)
	var ns = f["ns"]
	var law_id: String = _open_laws(f, 1)[0]
	ns.tabled_bill = {"law_id": law_id}
	var offer: Dictionary = Deal.offer_of(f["state"], ns, _loader, f["person_id"])
	if String(offer.get("kind", "")) != "vote" or String(offer.get("law_id", "")) != law_id:
		_fail("a party person offers a vote on the tabled bill, got %s" % [offer])
	if int(offer.get("due_month", 0)) != _now(f) + 1:
		_fail("a tabled bill divides at the next month's close, got %s" % [offer])
	# The strip's seats are the division's: strike it and read them back.
	var result := Deal.grant(f["state"], ns, _loader, f["session"])
	if not bool(result.get("ok", false)):
		_fail("Grant refused: %s" % [result])
		return
	var party = _party(ns, String(offer["party_id"]))
	if int(offer["seats"]) <= 0 or int(offer["seats"]) != DivisionTerms.pledged_seats(ns, party, _law(law_id)):
		_fail("the strip's %d seats are not the division's %d" % [int(offer["seats"]), DivisionTerms.pledged_seats(ns, party, _law(law_id))])


func _check_the_offer_is_a_vote_on_the_bill_in_the_diary() -> void:
	var f := _held_on_want("programme:", "sponsor", true)
	var state = f["state"]
	var law_id: String = _open_laws(f, 1)[0]
	var month: int = 1 if int(state.month) == 12 else int(state.month) + 1
	var year: int = int(state.year) + 1 if int(state.month) == 12 else int(state.year)
	if not bool(Calendar.book(state, Calendar.make_entry(CalK.KIND_LAW, year, month, 15, "", "", law_id)).get("ok", false)):
		_fail("the fixture's bill did not book")
		return
	var offer: Dictionary = Deal.offer_of(state, f["ns"], _loader, f["person_id"])
	if String(offer.get("kind", "")) != "vote" or String(offer.get("law_id", "")) != law_id:
		_fail("a bill in the diary is what they vote on, got %s" % [offer])
	if int(offer.get("due_month", 0)) != year * 12 + month + 1:
		_fail("the pledge stands until the month after the bill's day, got %s" % [offer])
	var date: Dictionary = offer.get("date", {})
	if int(date.get("day", 0)) != 15 or int(date.get("month", 0)) != month:
		_fail("the strip names the bill's day, got %s" % [offer])


func _check_no_bill_means_silence() -> void:
	var f := _held_on_want("programme:", "sponsor", true)
	var offer: Dictionary = Deal.offer_of(f["state"], f["ns"], _loader, f["person_id"])
	if String(offer.get("kind", "")) != "silence" or int(offer.get("months", 0)) != 12:
		_fail("with no bill to vote on, the offer is 12 months of silence, got %s" % [offer])
	if int(offer.get("due_month", 0)) != _now(f) + 12:
		_fail("silence is dated, got %s" % [offer])


func _check_no_party_means_silence() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	var law_id := String(Legislature.available(ns, _loader.laws)[0].id)
	ns.tabled_bill = {"law_id": law_id}
	var partyless := ""
	for person in _loader.people.get(PLAYER, []):
		if President.party_id_of(ns, _loader, person.id) == "":
			partyless = person.id
			break
	if partyless == "":
		_fail("no partyless person in the fixture")
		return
	if String(Deal.offer_of(state, ns, _loader, partyless).get("kind", "")) != "silence":
		_fail("someone with no party has no seats to bring")


func _check_someone_who_pledged_offers_silence() -> void:
	var f := _held_on_want("programme:", "sponsor", true)
	var ns = f["ns"]
	var law_id: String = _open_laws(f, 1)[0]
	ns.tabled_bill = {"law_id": law_id}
	if not President.pledge(f["state"], ns, _loader, f["person_id"], law_id, _now(f) + 1):
		_fail("the fixture's pledge was refused")
		return
	if String(Deal.offer_of(f["state"], ns, _loader, f["person_id"]).get("kind", "")) != "silence":
		_fail("a second word on one bill is refused, so it is not on offer")


# --- Grant ------------------------------------------------------------------------------

func _check_grant_writes_the_two_rows() -> void:
	var f := _law_deal(true)
	var ns = f["ns"]
	var pid: String = f["person_id"]
	var loyalty := float(ns.person_loyalty.get(pid, 0.0))
	var other := _someone_else(ns, pid)
	if not President.commit(f["state"], ns, _loader, "promise", other, "law:%s" % f["law_id"], _now(f) + 6):
		_fail("the fixture's other word was refused")
	var result := Deal.grant(f["state"], ns, _loader, f["session"])
	if not bool(result.get("ok", false)):
		_fail("Grant refused: %s" % [result])
		return
	var word := _word_row(ns, pid, "law:%s" % f["law_id"])
	var pledge := _owed_row(ns, pid, "pledge")
	if _word_row(ns, other, "law:%s" % f["law_id"]).has("deal"):
		_fail("a deal marked someone else's word on the same bill")
	if word.is_empty() or int(word["due_month"]) != _now(f) + 6:
		_fail("Grant writes the president's dated word, got %s" % [word])
	if pledge.is_empty() or String(pledge["object"]) != "law:%s" % f["bill_id"]:
		_fail("Grant writes their pledge on the bill, got %s" % [pledge])
	if String(word.get("deal", "")) != String(f["id"]) or String(pledge.get("deal", "")) != String(f["id"]):
		_fail("the two rows are one deal, got %s and %s" % [word, pledge])
	if not is_equal_approx(float(ns.person_loyalty.get(pid, 0.0)) - loyalty, 0.05):
		_fail("a deal buys what a win buys, loyalty 0.05")
	if String(Audiences.request(ns, f["id"]).get("status", "")) != AK.STATUS_HELD:
		_fail("Grant does not end the scene by itself")
	var closed := Levers.close(f["state"], ns, _loader, f["session"])
	if String(closed.get("outcome", "")) != AK.STATUS_PROMISED or not (closed.get("price", {}) as Dictionary).is_empty():
		_fail("a Grant that gives a word closes as promised, at no price, got %s" % [closed])


func _check_grant_on_a_post_seats_the_party() -> void:
	var f := _held_on_post(true)
	var ns = f["ns"]
	var result := Deal.grant(f["state"], ns, _loader, f["session"])
	if not bool(result.get("ok", false)):
		_fail("Grant on a post refused: %s" % [result])
		return
	var portfolio := String(f["session"]["ask"]["portfolio"])
	if String(ns.cabinet.get(portfolio, "")) != String(f["party_id"]):
		_fail("Grant on a post seats the party in it")
	if not _word_row(ns, f["person_id"], String(f["object"])).is_empty():
		_fail("a post paid now leaves no word to keep")
	# No word stands in the way here, so this is the audience's own one-deal rule.
	if bool(Deal.grant(f["state"], ns, _loader, f["session"]).get("ok", true)):
		_fail("one audience strikes one deal")
	if bool(Deal.bargain(f["state"], ns, _loader, f["session"], "argue").get("ok", true)):
		_fail("a deal struck leaves nothing to bargain")
	if String(Levers.close(f["state"], ns, _loader, f["session"]).get("outcome", "")) != AK.STATUS_SETTLED:
		_fail("a post paid now closes as settled")


func _check_grant_spends_no_attempt_and_survives_spent_attempts() -> void:
	var f := _law_deal(false)
	f["session"]["attempts_left"] = 0
	var result := Deal.grant(f["state"], f["ns"], _loader, f["session"])
	if not bool(result.get("ok", false)):
		_fail("three failed attempts must leave Grant open: %s" % [result])
	if int(f["session"]["attempts_left"]) != 0:
		_fail("Grant spent an attempt")
	var again := Deal.grant(f["state"], f["ns"], _loader, f["session"])
	if bool(again.get("ok", true)):
		_fail("one audience strikes one deal")


func _check_a_refused_grant_writes_nothing() -> void:
	var f := _law_deal(false)
	var ns = f["ns"]
	var over: Dictionary = (f["session"] as Dictionary).duplicate(true)
	over["closed"] = true
	var before := _snapshot(ns, f["person_id"])
	if bool(Deal.grant(f["state"], ns, _loader, over).get("ok", true)):
		_fail("a closed audience took a Grant")
	if _snapshot(ns, f["person_id"]) != before:
		_fail("a refused Grant wrote the registers")


## A promise not believed still binds, and spent attempts must not leave Refuse alone on the
## table. Grant takes it up, at the ask's date if that is nearer: Grant is the full price.
func _check_grant_takes_up_a_word_in_flight() -> void:
	for named in [9, 3]:
		var f := _law_deal(false)
		var ns = f["ns"]
		var object := "law:%s" % f["law_id"]
		if not President.commit(f["state"], ns, _loader, "promise", f["person_id"], object, _now(f) + int(named)):
			_fail("the fixture's promise was refused")
			return
		f["session"]["attempts_left"] = 0
		if not bool(Deal.answers(f["state"], ns, _loader, f["session"])["grant"]["ok"]):
			_fail("a word in flight must leave Grant open")
		if not bool(Deal.grant(f["state"], ns, _loader, f["session"]).get("ok", false)):
			_fail("Grant over a word in flight was refused")
		var rows := 0
		for row in President.commitments(ns):
			if String(row["person_id"]) == String(f["person_id"]) and String(row["object"]) == object:
				rows += 1
		if rows != 1:
			_fail("one word on one ask, got %d rows" % rows)
		var word := _word_row(ns, f["person_id"], object)
		if int(word.get("due_month", 0)) != _now(f) + mini(int(named), 6) or String(word.get("deal", "")) != String(f["id"]):
			_fail("a word named at %d months: Grant holds it to the nearer of that and 6, on the deal, got %s" % [int(named), word])


func _check_grant_on_a_post_pays_the_removal() -> void:
	var f := _post_held_by_a_partner()
	var ns = f["ns"]
	var portfolio := String(f["session"]["ask"]["portfolio"])
	var holder := String(ns.cabinet[portfolio])
	var shown: Dictionary = Deal.answers(f["state"], ns, _loader, f["session"])["grant"].get("removal", {})
	if String(shown.get("party_id", "")) != holder:
		_fail("the strip names the party that loses the post, %s, got %s" % [holder, shown])
	if not bool(Deal.grant(f["state"], ns, _loader, f["session"]).get("ok", false)):
		_fail("Grant on a partner's post was refused")
		return
	if int(ns.portfolio_removed_month.get(portfolio, -1)) != _now(f):
		_fail("taking a post from a partner is a removal, and pays as one")
	var after := float(ns.person_grudges.get(String(shown["leader_id"]), 0.0))
	if after <= float(shown["grudge_before"]) or not is_equal_approx(after, float(shown["grudge_after"])):
		_fail("the partner's leader takes it badly, as the strip said: %f against %s" % [after, shown])


func _check_a_post_too_recently_moved_is_greyed() -> void:
	var f := _post_held_by_a_partner()
	var ns = f["ns"]
	ns.portfolio_removed_month[String(f["session"]["ask"]["portfolio"])] = _now(f)
	var why := String(Deal.ask_of(f["state"], ns, _loader, Audiences.request(ns, f["id"])).get("why_not", ""))
	if why != "this portfolio changed hands too recently to change again":
		_fail("the ask reads Removal's own refusal, got '%s'" % why)


func _check_someone_under_a_deal_does_not_ask_again() -> void:
	var f := _law_deal(false)
	var ns = f["ns"]
	var want := String(f["object"])
	if Delegation.heard(ns, f["person_id"], want, _now(f)):
		_fail("nothing agreed yet, so the want is not heard")
	Deal.grant(f["state"], ns, _loader, f["session"])
	if not Delegation.heard(ns, f["person_id"], want, _now(f)):
		_fail("a word stands on this want: they do not ask again and pay a decline for it")
	Levers.close(f["state"], ns, _loader, f["session"])
	_advance_to(f, _now(f) + 6)
	Levers.tick_month(f["state"], _loader, METERS)
	if Delegation.heard(ns, f["person_id"], want, _now(f)):
		_fail("the word broken, an aggrieved person asks again")


func _check_answers_after_the_deal_read_the_deal() -> void:
	var f := _law_deal(true)
	var ns = f["ns"]
	for row in ns.audience_requests:
		if String(row["id"]) == String(f["id"]):
			row["offer"] = {"currency": "party_money", "amount_eur_m": 1.0}
	Deal.grant(f["state"], ns, _loader, f["session"])
	var answers: Dictionary = Deal.answers(f["state"], ns, _loader, f["session"])
	if String(answers["offer"].get("kind", "")) != "vote":
		_fail("after the deal the card reads the offer it took, got %s" % [answers["offer"]])
	if not (answers["money"] as Dictionary).is_empty():
		_fail("after the deal the money is no longer on the table, got %s" % [answers["money"]])


# --- Bargain ----------------------------------------------------------------------------

func _check_three_approaches_and_no_more() -> void:
	var f := _law_deal(false)
	var answers: Dictionary = Deal.answers(f["state"], f["ns"], _loader, f["session"])
	var names: Array = []
	for row in answers["bargain"]["approaches"]:
		names.append(String(row["lever"]))
	if names != ["argue", "promise_date", "pressure"]:
		_fail("Bargain offers argue, a date and pressure, got %s" % [names])
	var before := _snapshot(f["ns"], f["person_id"])
	if bool(Deal.bargain(f["state"], f["ns"], _loader, f["session"], "flatter").get("ok", true)):
		_fail("flatter is not an approach")
	if _snapshot(f["ns"], f["person_id"]) != before or int(f["session"]["attempts_left"]) != 3:
		_fail("a refused approach wrote something")


func _check_a_win_is_the_smaller_grant_for_the_same_offer() -> void:
	var f := _law_deal(true)
	var ns = f["ns"]
	_seed_for(f, "argue", true)
	var result := Deal.bargain(f["state"], ns, _loader, f["session"], "argue")
	if not bool(result.get("success", false)):
		_fail("the seeded argue did not win: %s" % [result])
		return
	var word := _word_row(ns, f["person_id"], "law:%s" % f["law_id"])
	if word.is_empty() or int(word["due_month"]) != _now(f) + 18:
		_fail("a win is the same word, 12 months later, got %s" % [word])
	if _owed_row(ns, f["person_id"], "pledge").is_empty():
		_fail("the smaller grant takes the same offer")
	if String(word.get("deal", "")) != String(f["id"]):
		_fail("a bargained word is on the deal, got %s" % [word])
	if String(Levers.close(f["state"], ns, _loader, f["session"]).get("outcome", "")) != AK.STATUS_PROMISED:
		_fail("a bargained word closes as promised")


func _check_a_win_on_a_post_is_a_word_not_a_seat() -> void:
	var f := _held_on_post(true)
	var ns = f["ns"]
	var before: Dictionary = ns.cabinet.duplicate()
	_seed_for(f, "argue", true)
	var result := Deal.bargain(f["state"], ns, _loader, f["session"], "argue")
	if not bool(result.get("success", false)):
		_fail("the seeded argue did not win: %s" % [result])
		return
	if ns.cabinet != before:
		_fail("the smaller grant of a post seats nobody now")
	var word := _word_row(ns, f["person_id"], String(f["object"]))
	if word.is_empty() or int(word["due_month"]) != _now(f) + 12:
		_fail("the smaller grant of a post is the word within a year, got %s" % [word])


func _check_a_promise_win_is_the_named_date() -> void:
	var f := _law_deal(true)
	var ns = f["ns"]
	var due := _now(f) + 9
	_seed_for(f, "promise_date", true)
	var result := Deal.bargain(f["state"], ns, _loader, f["session"], "promise_date", {"due_month": due})
	if not bool(result.get("success", false)):
		_fail("the seeded promise did not win: %s" % [result])
		return
	var rows := 0
	for row in President.commitments(ns):
		if String(row["person_id"]) == String(f["person_id"]) and String(row["kind"]) == "promise":
			rows += 1
	if rows != 1:
		_fail("a promise that wins is the one word, got %d rows" % rows)
	var word := _word_row(ns, f["person_id"], "law:%s" % f["law_id"])
	if int(word.get("due_month", 0)) != due or String(word.get("deal", "")) != String(f["id"]):
		_fail("the word is on the ask at the named date, in the deal, got %s" % [word])
	if _owed_row(ns, f["person_id"], "pledge").is_empty():
		_fail("the promise takes the same offer")


func _check_a_promise_not_believed_binds_and_strikes_nothing() -> void:
	var f := _law_deal(true)
	var ns = f["ns"]
	_seed_for(f, "promise_date", false)
	var result := Deal.bargain(f["state"], ns, _loader, f["session"], "promise_date", {"due_month": _now(f) + 9})
	if not bool(result.get("ok", false)) or bool(result.get("success", true)):
		_fail("the seeded promise did not fail: %s" % [result])
		return
	var word := _word_row(ns, f["person_id"], "law:%s" % f["law_id"])
	if word.is_empty() or word.has("deal"):
		_fail("a word not believed still binds (the author's 'parole donnee'), on no deal, got %s" % [word])
	if not _owed_row(ns, f["person_id"], "pledge").is_empty():
		_fail("a failed attempt takes no offer")
	if int(f["session"]["attempts_left"]) != 2:
		_fail("an attempt is what a failure spends")


func _check_refuse_is_a_decline() -> void:
	var f := _law_deal(false)
	var ns = f["ns"]
	var shown: Dictionary = Deal.answers(f["state"], ns, _loader, f["session"])["refuse"]
	var closed := Levers.close(f["state"], ns, _loader, f["session"])
	if String(closed.get("outcome", "")) != AK.STATUS_DECLINED:
		_fail("Refuse closes as a decline, got %s" % [closed])
	if not is_equal_approx(float(shown["grudge"]), float(closed["price"]["grudge"])):
		_fail("the price shown is the price paid: %s against %s" % [shown, closed["price"]])


func _check_answers_write_nothing() -> void:
	var f := _law_deal(true)
	var before := _snapshot(f["ns"], f["person_id"])
	var session_before: Dictionary = (f["session"] as Dictionary).duplicate(true)
	Deal.answers(f["state"], f["ns"], _loader, f["session"])
	Deal.ask_of(f["state"], f["ns"], _loader, Audiences.request(f["ns"], f["id"]))
	Deal.offer_of(f["state"], f["ns"], _loader, f["person_id"])
	if _snapshot(f["ns"], f["person_id"]) != before or f["session"] != session_before:
		_fail("a read wrote something")


# --- The judge --------------------------------------------------------------------------

func _check_a_bill_brought_keeps_the_word_whatever_the_verdict() -> void:
	var f := _law_deal(false)
	var ns = f["ns"]
	Deal.grant(f["state"], ns, _loader, f["session"])
	Levers.close(f["state"], ns, _loader, f["session"])
	var rapport := President.rapport(ns, f["person_id"])
	ns.tabled_bill = {"law_id": f["law_id"]}
	Division.divide(f["state"], _loader)
	if not bool(_word_row(ns, f["person_id"], "law:%s" % f["law_id"]).get("brought", false)):
		_fail("a division on the bill marks the word brought, whatever the vote says")
	_advance_to(f, _now(f) + 6)
	var judged := Levers.tick_month(f["state"], _loader, METERS)
	if (judged["kept"] as Array).size() != 1:
		_fail("a bill brought keeps the word, got %s" % [judged])
	if not is_equal_approx(President.rapport(ns, f["person_id"]) - rapport, 0.25):
		_fail("a word kept in person is worth 0.25 of regard")


func _check_a_bill_not_brought_breaks_the_word_and_releases_them() -> void:
	var f := _law_deal(false)
	var ns = f["ns"]
	# Earlier in the register than this deal's row, as an older deal's would be.
	if not President.commit(f["state"], ns, _loader, "silence", f["person_id"], "silence:an_older_deal", _now(f) + 24):
		_fail("the fixture's older silence was refused")
	Deal.grant(f["state"], ns, _loader, f["session"])
	Levers.close(f["state"], ns, _loader, f["session"])
	if President.owed(ns).size() != 2:
		_fail("the fixture's offer should be silence, got %s" % [President.owed(ns)])
	# Another bill reaches the floor, and that keeps no word on this one.
	ns.tabled_bill = {"law_id": _open_laws(f, 2)[1]}
	Division.divide(f["state"], _loader)
	if bool(_word_row(ns, f["person_id"], "law:%s" % f["law_id"]).get("brought", false)):
		_fail("a division on another bill marked this word brought")
	var rapport := President.rapport(ns, f["person_id"])
	_advance_to(f, _now(f) + 6)
	var judged := Levers.tick_month(f["state"], _loader, METERS)
	if (judged["broken"] as Array).size() != 1:
		_fail("a bill never brought breaks the word, got %s" % [judged])
	if not is_equal_approx(President.rapport(ns, f["person_id"]) - rapport, -0.5):
		_fail("a broken word in person is a lie revealed, -0.5 of regard")
	var left: Array = President.owed(ns).map(func(row: Dictionary) -> String: return String(row["object"]))
	if left != ["silence:an_older_deal"]:
		_fail("the president's word broken, this deal's silence is off and no other, got %s" % [left])


func _check_a_forced_bill_is_brought_and_voids_the_pledge() -> void:
	var f := _law_deal(true)
	var ns = f["ns"]
	Deal.grant(f["state"], ns, _loader, f["session"])
	var law = _law(String(f["bill_id"]))
	ns.tabled_bill = {}
	var forced := Legislature.propose(f["state"], _loader, law, true)
	if not bool(forced.get("forced", false)) or bool(forced.get("refused", false)):
		_fail("premise: the forced road was not taken: %s" % [forced])
	if not President.pledges_on(ns, law.id).is_empty():
		_fail("a forced bill takes no vote, so the pledge leaves the live register")
	if President.pledge_verdict(ns, f["person_id"], law.id) != "void":
		_fail("no vote was taken, so the pledge is void, got %s" % President.pledge_verdict(ns, f["person_id"], law.id))
	if _word_row(ns, f["person_id"], "law:%s" % f["law_id"]).is_empty():
		_fail("a pledge void breaks nothing: the president's word stands")
	var g := _law_deal(false)
	Deal.grant(g["state"], g["ns"], _loader, g["session"])
	var word_forced := Legislature.propose(g["state"], _loader, _law(String(g["law_id"])), true)
	if not bool(word_forced.get("forced", false)) or bool(word_forced.get("refused", false)):
		_fail("premise: the forced road was not taken: %s" % [word_forced])
	if not bool(_word_row(g["ns"], g["person_id"], "law:%s" % g["law_id"]).get("brought", false)):
		_fail("a forced bill is a bill brought")


func _check_their_broken_pledge_voids_my_word() -> void:
	var f := _law_deal(true)
	var ns = f["ns"]
	Deal.grant(f["state"], ns, _loader, f["session"])
	Levers.close(f["state"], ns, _loader, f["session"])
	var elsewhere := "programme:an_older_deal"
	if not President.commit(f["state"], ns, _loader, "promise", f["person_id"], elsewhere, _now(f) + 24):
		_fail("the fixture's older word was refused")
	President.mark_rows(ns, elsewhere, "deal", "an_older_deal", f["person_id"])
	ns.person_party_override[f["person_id"]] = ""
	ns.tabled_bill = {"law_id": f["bill_id"]}
	Division.divide(f["state"], _loader)
	if _word_row(ns, f["person_id"], elsewhere).is_empty():
		_fail("a broken pledge releases its own deal's word and no other")
	President.withdraw_commitment(ns, "promise", f["person_id"], elsewhere)
	if President.pledge_verdict(ns, f["person_id"], f["bill_id"]) != "broken":
		_fail("the fixture's pledge should break, got %s" % President.pledge_verdict(ns, f["person_id"], f["bill_id"]))
	# At the vote and not at the word's date: the judged register forgets in 12 months, and a
	# word on a programme can fall due long after that.
	if not _word_row(ns, f["person_id"], "law:%s" % f["law_id"]).is_empty():
		_fail("they broke first, so the word leaves the register at the vote")
	var rapport := President.rapport(ns, f["person_id"])
	_advance_to(f, _now(f) + 6)
	var judged := Levers.tick_month(f["state"], _loader, METERS)
	if (judged["broken"] as Array).size() != 0 or (judged["kept"] as Array).size() != 0:
		_fail("they broke first, so my word is off, unpriced, got %s" % [judged])
	if not is_equal_approx(President.rapport(ns, f["person_id"]), rapport):
		_fail("a word they released costs nothing")


func _check_a_kept_pledge_leaves_the_word_standing() -> void:
	var f := _law_deal(true)
	var ns = f["ns"]
	Deal.grant(f["state"], ns, _loader, f["session"])
	ns.tabled_bill = {"law_id": f["bill_id"]}
	Division.divide(f["state"], _loader)
	if President.pledge_verdict(ns, f["person_id"], f["bill_id"]) != "kept":
		_fail("the fixture's pledge should be kept, got %s" % President.pledge_verdict(ns, f["person_id"], f["bill_id"]))
	if _word_row(ns, f["person_id"], "law:%s" % f["law_id"]).is_empty():
		_fail("they kept their half, so the president still owes the word")


func _check_a_pledge_never_voted_lapses_unpriced() -> void:
	var f := _law_deal(true)
	var ns = f["ns"]
	Deal.grant(f["state"], ns, _loader, f["session"])
	Levers.close(f["state"], ns, _loader, f["session"])
	ns.tabled_bill = {}
	var rapport := President.rapport(ns, f["person_id"])
	_advance_to(f, _now(f) + 1)
	var judged := Levers.tick_month(f["state"], _loader, METERS)
	if (judged["void"] as Array).size() != 1 or (judged["broken"] as Array).size() != 0:
		_fail("a pledge on a bill that never came lapses as void, got %s" % [judged])
	if not is_equal_approx(President.rapport(ns, f["person_id"]), rapport):
		_fail("nobody broke anything: no price")


func _check_silence_stops_a_brief_then_ends_unpriced() -> void:
	var f := _law_deal(false)
	var ns = f["ns"]
	var person = _loader.person_by_id[f["person_id"]]
	Deal.grant(f["state"], ns, _loader, f["session"])
	Levers.close(f["state"], ns, _loader, f["session"])
	ns.person_grudges[f["person_id"]] = CK.GRUDGE_BRIEF_THRESHOLD + 0.1
	if Characters._fire_act(f["state"], ns, _loader, person, "brief_against", METERS, [], {}):
		_fail("silence given, the person does not brief")
	var rapport := President.rapport(ns, f["person_id"])
	_advance_to(f, _now(f) + 12)
	# The word on the bill falls due first and is kept or broken on its own; only the
	# silence's own row is read here.
	President.withdraw_commitment(ns, "promise", f["person_id"], "law:%s" % f["law_id"])
	var judged := Levers.tick_month(f["state"], _loader, METERS)
	if (judged["void"] as Array).size() != 1 or (judged["kept"] as Array).size() + (judged["broken"] as Array).size() != 0:
		_fail("silence ends unjudged, got %s" % [judged])
	if not is_equal_approx(President.rapport(ns, f["person_id"]), rapport):
		_fail("silence ending costs nothing")
	if not Characters._fire_act(f["state"], ns, _loader, person, "brief_against", METERS, [], {}):
		_fail("silence over, the grudge briefs again")


func _check_what_they_owe_is_not_the_presidents_word() -> void:
	var f := _law_deal(true)
	var ns = f["ns"]
	Deal.grant(f["state"], ns, _loader, f["session"])
	for row in President.commitments(ns):
		if String(row["kind"]) == "pledge" or String(row["kind"]) == "silence":
			_fail("a row they owe reads in the president's word: %s" % [row])
	if President.owed(ns).size() != 1 or String(President.owed(ns)[0]["kind"]) != "pledge":
		_fail("President.owed lists what they owe, got %s" % [President.owed(ns)])
	DivisionTerms.judge_pledges(ns, _law(String(f["bill_id"])), _now(f))
	for row in President.judged_commitments(ns):
		if String(row["kind"]) == "pledge":
			_fail("a judged pledge reads as the president's word: %s" % [row])
	if President.pledge_verdict(ns, f["person_id"], f["bill_id"]) != "kept":
		_fail("the pledge's own mark still reads through pledge_verdict")


func _check_the_people_panel_reads_no_pledge_as_a_promise() -> void:
	var f := _held_on_want("programme:", "sponsor", true)
	var ns = f["ns"]
	if not President.pledge(f["state"], ns, _loader, f["person_id"], _open_laws(f, 1)[0], _now(f) + 1):
		_fail("the fixture's pledge was refused")
		return
	ns.audience_requests.clear()
	var said := str(PeopleNow.chosen(f["state"], _loader, func(_person) -> String: return ""))
	if said.contains(Strings.t("A promise falls due")):
		_fail("the president owes nothing here, and the panel says a promise falls due")


func _check_a_word_on_a_bill_reads_the_bills_name() -> void:
	var f := _law_deal(false)
	var words := PersonCard.object_text(_loader, f["ns"], "law:%s" % f["law_id"], {})
	if words != Strings.law_name(_law(String(f["law_id"])), String(f["law_id"])) or words.begins_with("law:"):
		_fail("the Diary's words for a word on a bill are '%s'" % words)


func _check_a_deal_survives_a_save() -> void:
	var f := _law_deal(true)
	var ns = f["ns"]
	Deal.grant(f["state"], ns, _loader, f["session"])
	DivisionTerms.judge_pledges(ns, _law(String(f["law_id"])), _now(f), true)
	var dict: Dictionary = JSON.parse_string(JSON.stringify(ns.to_dict()))
	var back = NationState.from_dict(dict)
	var word := _word_row(back, f["person_id"], "law:%s" % f["law_id"])
	if String(word.get("deal", "")) != String(f["id"]) or not bool(word.get("brought", false)):
		_fail("a word's deal and its mark must survive a save, got %s" % [word])
	if String(_owed_row(back, f["person_id"], "pledge").get("deal", "")) != String(f["id"]):
		_fail("a pledge's deal must survive a save")
	if not Delegation.heard(back, f["person_id"], String(f["object"]), _now(f)):
		_fail("the want a word answers must survive a save, or the person asks again after a load")


func _check_a_row_from_before_the_deal_is_judged_as_it_was() -> void:
	var f := _held_on_want("programme:", "sponsor")
	var ns = f["ns"]
	if not President.commit(f["state"], ns, _loader, "promise", f["person_id"], String(f["object"]), _now(f) + 3):
		_fail("the fixture's promise was refused")
		return
	_advance_to(f, _now(f) + 3)
	var judged := Levers.tick_month(f["state"], _loader, METERS)
	if (judged["broken"] as Array).size() != 1:
		_fail("a promise with no deal key is judged on its want, got %s" % [judged])


# --- The money --------------------------------------------------------------------------

func _check_the_money_shows_its_risk_first() -> void:
	var f := _law_deal(false)
	var ns = f["ns"]
	if not (Deal.answers(f["state"], ns, _loader, f["session"])["money"] as Dictionary).is_empty():
		_fail("no offer of money, no money line")
	for row in ns.audience_requests:
		if String(row["id"]) == String(f["id"]):
			row["offer"] = {"currency": "party_money", "amount_eur_m": 1.0}
	var money: Dictionary = Deal.answers(f["state"], ns, _loader, f["session"])["money"]
	if String(money.get("currency", "")) != "party_money" or not is_equal_approx(float(money.get("amount_eur_m", 0.0)), 1.0):
		_fail("the strip names the money, got %s" % [money])
	if not is_equal_approx(float(money.get("evidence", 0.0)), 1.0):
		_fail("the strip names the evidence it leaves, got %s" % [money])
	var month := Exposure.hazard_if(f["state"], ns, _loader, "party_money", f["person_id"], 1.0)
	var clear := 1.0
	for i in range(12):
		clear *= 1.0 - month
	if month <= 0.0 or not is_equal_approx(float(money.get("found_in_a_year", 0.0)), 1.0 - clear):
		_fail("the strip names the chance it is found within a year, %f, got %s" % [1.0 - clear, money])
	var taken := Shadows.accept_offer(f["state"], ns, _loader, f["session"])
	if not is_equal_approx(float(taken.get("evidence", 0.0)), float(money["evidence"])):
		_fail("the evidence shown is the evidence left: %s against %s" % [money, taken])


func _check_a_principled_person_never_offers() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	var plain = Person.new()
	plain.id = "FRA_plain"
	plain.kind = "politician"
	var principled = Person.new()
	principled.id = "FRA_plain"
	principled.kind = "politician"
	var traits: Array[String] = ["principled"]
	principled.traits = traits
	var plain_offers := 0
	for now in range(24000, 24600):
		if not Offers.offer_for(ns, plain, now).is_empty():
			plain_offers += 1
		if not Offers.offer_for(ns, principled, now).is_empty():
			_fail("a principled person came with money")
			return
	if plain_offers == 0:
		_fail("the same person without the trait must offer sometimes")


# --- The data ---------------------------------------------------------------------------

func _check_the_loader_reads_an_entrys_laws() -> void:
	var entry: Dictionary = _loader.programme[0].duplicate(true)
	var law_id := String(_loader.laws[0].id)
	entry["laws"] = [law_id]
	var loader = DataLoader.new()
	loader.programme = [entry]
	loader.laws = _loader.laws
	ProgrammeLoader.validate_laws(loader)
	if not loader.errors.is_empty():
		_fail("a law that exists must load, got %s" % [loader.errors])
	entry["laws"] = ["no_such_law"]
	ProgrammeLoader.validate_laws(loader)
	if loader.errors.is_empty():
		_fail("a programme entry naming no law must be a load error")
	loader.errors.clear()
	entry["laws"] = law_id
	ProgrammeLoader.validate_laws(loader)
	if loader.errors.size() != 1 or not String(loader.errors[0]).contains("must be a list"):
		_fail("`laws` must be a list, got %s" % [loader.errors])


# --- Fixtures ---------------------------------------------------------------------------

## A France game with an audience held on one of this person's real wants, `prefix` its
## family and `stance` its stance ("" for any). `with_seats` asks for a person whose party
## holds seats. {state, ns, id, person_id, object, session}.
func _held_on_want(prefix: String, stance: String, with_seats := false) -> Dictionary:
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	state.day = 1
	var ns = state.player()
	var leader := President.leader_id(ns)
	for person in _loader.people.get(PLAYER, []):
		if person.id == leader or (with_seats and int(ns.seats_by_party.get(President.party_id_of(ns, _loader, person.id), 0)) <= 0):
			continue
		for want in person.wants:
			if String(want["object"]).begins_with(prefix) and (stance == "" or String(want["stance"]) == stance) and not String(want["object"]).begins_with("office:party_leadership:"):
				return _held(state, ns, person.id, want)
	_fail("no person of %s holds a %s want" % [PLAYER, prefix])
	return {}


func _held_on_post(in_coalition: bool) -> Dictionary:
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	state.day = 1
	var ns = state.player()
	var leader := President.leader_id(ns)
	for person in _loader.people.get(PLAYER, []):
		var party := President.party_id_of(ns, _loader, person.id)
		if person.id == leader or party == "" or ns.coalition_party_ids.has(party) != in_coalition:
			continue
		for want in person.wants:
			if String(want["object"]).begins_with("office:portfolio:") and String(ns.cabinet.get(String(want["object"]).substr(17), "")) != party:
				var f := _held(state, ns, person.id, want)
				f["party_id"] = party
				return f
	# Nobody authored the case: a coalition party's person is given the want by the fixture.
	for person in _loader.people.get(PLAYER, []):
		var party := President.party_id_of(ns, _loader, person.id)
		if person.id == leader or party == "" or ns.coalition_party_ids.has(party) != in_coalition:
			continue
		for portfolio in ns.cabinet:
			if String(ns.cabinet[portfolio]) != party:
				var want := {"object": "office:portfolio:%s" % portfolio, "stance": "want"}
				var f := _held(state, ns, person.id, want)
				f["party_id"] = party
				return f
	_fail("no %s person to ask for a post" % ("coalition" if in_coalition else "opposition"))
	return {}


func _held(state, ns, person_id: String, want: Dictionary) -> Dictionary:
	var asked := Audiences.invite(state, ns, _loader, person_id, String(want["object"]), String(want["stance"]))
	if not bool(asked.get("ok", false)):
		_fail("the fixture's request was refused: %s" % [asked])
		return {}
	var id := String(asked["request"]["id"])
	var row := {}
	for r in ns.audience_requests:
		if String(r["id"]) == id:
			row = r
	# Past the register's month: a new game reads as a term's first, with the register open.
	ns.months_in_term = 6
	var date := {"year": 2026, "month": 2, "day": 3}
	row["status"] = AK.STATUS_BOOKED
	row["date"] = date
	state.year = 2026
	state.month = 2
	state.day = 3
	var session: Dictionary = Deal.open(state, ns, _loader, id)
	if session.is_empty():
		_fail("a booked audience on its day did not open")
		return {}
	return {"state": state, "ns": ns, "id": id, "person_id": person_id, "object": String(want["object"]), "session": session}


## An audience on a post another coalition party holds.
func _post_held_by_a_partner() -> Dictionary:
	var f := _held_on_post(true)
	var ns = f["ns"]
	var portfolio := String(f["session"]["ask"]["portfolio"])
	# Not the president's own party, whose leader is the president, who feels no removal.
	for party in ns.coalition_party_ids:
		if String(party) != String(f["party_id"]) and String(party) != String(ns.incumbent_party_id):
			ns.cabinet[portfolio] = String(party)
			return f
	_fail("no partner in the fixture's coalition")
	return f


## An audience on a programme want whose entry names a law, so the ask is that law; with
## `bill`, a second law tabled, so the offer is a vote on it, else the offer is silence.
func _law_deal(bill: bool) -> Dictionary:
	var f := _held_on_want("programme:", "sponsor", true)
	var open := _open_laws(f, 2)
	var entry := _entry(f["object"])
	entry["laws"] = [open[0]]
	if bill:
		f["ns"].tabled_bill = {"law_id": open[1]}
		f["bill_id"] = open[1]
	f["law_id"] = open[0]
	f["session"] = _reopen(f)
	entry.erase("laws")
	return f


## The session again, with the fixture's `laws` in the entry: an ask is read as it opens.
func _reopen(f: Dictionary) -> Dictionary:
	var ns = f["ns"]
	for row in ns.audience_requests:
		if String(row["id"]) == String(f["id"]):
			row["status"] = AK.STATUS_BOOKED
	return Deal.open(f["state"], ns, _loader, f["id"])


func _open_laws(f: Dictionary, n: int) -> Array:
	var out := []
	for law in Legislature.available(f["ns"], _loader.laws):
		# Article 49.3 cannot force a constitutional bill, and two checks force these.
		if not law.constitutional and Legislature.open_law(f["state"], f["ns"], _loader, String(law.id)) != null:
			out.append(String(law.id))
		if out.size() == n:
			break
	if out.size() < n:
		_fail("fewer than %d open laws" % n)
	return out


func _entry(object: String) -> Dictionary:
	var id := object.substr("programme:".length())
	for entry in _loader.programme:
		if String(entry["id"]) == id:
			return entry
	_fail("no programme entry '%s'" % id)
	return {}


func _law(id: String):
	for law in _loader.laws:
		if String(law.id) == id:
			return law
	_fail("no law '%s'" % id)
	return null


func _party(ns, id: String):
	for party in _loader.parties.get(ns.id, []):
		if String(party.id) == id:
			return party
	_fail("no party '%s'" % id)
	return null


func _word_row(ns, pid: String, object: String) -> Dictionary:
	for row in President.commitments(ns):
		if String(row["person_id"]) == pid and String(row["object"]) == object:
			return row
	return {}


func _owed_row(ns, pid: String, kind: String) -> Dictionary:
	for row in President.owed(ns):
		if String(row["person_id"]) == pid and String(row["kind"]) == kind:
			return row
	return {}


## A draw seed under which this attempt's roll lands as `want`, read the way Levers rolls it.
func _seed_for(f: Dictionary, lever: String, want: bool) -> void:
	var ns = f["ns"]
	var session: Dictionary = f["session"]
	var p := LeverOdds.odds(_loader.person_by_id[f["person_id"]], lever, Levers.cell(f["state"], ns, _loader, session))
	var index := LK.ATTEMPTS - int(session["attempts_left"])
	for s in range(1, 2000):
		var roll := Cycle.unit_pair(String(session["request_id"]), Cycle.salted("%s:%s:%d" % [LK.SALT_ROLL, lever, index], s), _now(f))
		if (roll < p) == want:
			ns.draw_seed = s
			return
	_fail("no seed lands %s as %s" % [lever, want])


## Another person of this nation the president deals with.
func _someone_else(ns, pid: String) -> String:
	var leader := President.leader_id(ns)
	for person in _loader.people.get(PLAYER, []):
		if person.id != pid and person.id != leader:
			return String(person.id)
	_fail("nobody else in the fixture")
	return ""


func _advance_to(f: Dictionary, month: int) -> void:
	var state = f["state"]
	state.year = floori((month - 1) / 12.0)
	state.month = month - int(state.year) * 12
	state.day = 1


func _now(f: Dictionary) -> int:
	return int(f["state"].year) * 12 + int(f["state"].month)


func _snapshot(ns, pid: String) -> Dictionary:
	return {
		"rapport": ns.person_rapport.duplicate(),
		"grudge": float(ns.person_grudges.get(pid, 0.0)),
		"loyalty": float(ns.person_loyalty.get(pid, 0.0)),
		"commitments": ns.commitments.duplicate(true),
		"requests": ns.audience_requests.duplicate(true),
		"cabinet": ns.cabinet.duplicate(),
		"evidence": ns.exposure_evidence.duplicate(true),
	}


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_deal: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
