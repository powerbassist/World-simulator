extends RefCounted

## The second chamber: its composition, and what its refusal does to a bill.
##
## Built at V1.1e, the last session of the V1 tier, and it discharges a stopgap declared
## in the DATA rather than in the code: data/nations/DEU.json's government.amendment._note
## carried "Only the Bundestag half is modelled -- there is no Bundesrat in this game"
## from V1.2c until this session. Four more citations were already sitting in the nation
## files for a mechanic that did not exist -- FRA Art. 89's "must pass both chambers in
## identical terms", FRA Art. 12's "the presidents of both chambers", ITA's "each
## chamber", and src/sim/referendum.gd's own header, written one session ago, quoting
## Art. 89's first stage while modelling only the second.
##
## The model and both constants are docs/upper-house-model.md.
##
## ============================================================================
## A LEAF, AND tests/test_upper_house.gd READS THIS FILE TO SAY SO
## ============================================================================
## This file preloads its own constants, election_constants and electoral_systems, and
## nothing else. It does not know a law exists, it does not know a vote exists, and it
## never calls legislature.gd -- src/sim/legislature.gd calls IN, resolves the second
## chamber's division with the same spatial_support() it already owns, and acts on the
## verdict. src/sim/calendar.gd's and src/sim/referendum.gd's property, for the same
## reason: vote resolution is one file's job and it is not this one's.
##
## ============================================================================
## NOT A SECOND ELECTION, AND THE NATION FILES ARE WHY
## ============================================================================
## NOT ONE of V1.1e's ten upper houses but Italy's is elected nationally. France's Senat
## is returned by about 162 000 grands electeurs who are overwhelmingly councillors of
## small communes; Germany's Bundesrat is delegated by Land governments; the Lords are
## appointed; the Dutch Eerste Kamer is chosen by provincial councils; Spain's Senado
## seats four per province regardless of population; Switzerland's Standerat seats two
## per canton. Only Italy's Senato is elected by the same electorate on the same day
## as its lower house -- which is why Italian bicameralism is called "perfect" and
## reproduces the Camera's majority.
##
## The 41-nation roster adds Poland's Senat (same day, first-past-the-post) and Romania's
## Senatul (the same list vote), and they are lagged like Italy's: the trade and its cost
## are docs/upper-house-model.md section 2.
##
## So a second chamber is the LOWER CHAMBER, LAGGED, and Elections.vote_share() is
## never called with a different weighting. An ideological tilt on top of the lag was
## designed, swept and deleted; chambers_constants.gd carries both versions and why
## each failed, and what makes this a check instead.

const CK = preload("res://src/sim/chambers_constants.gd")
const ElectoralSystems = preload("res://src/sim/electoral_systems.gd")


## Copy the five static facts off the nation and seat the chamber for the first time.
## Runs for all ten, same as Opinion/Elections/Government/Legislature.init_nation -- a
## second playable nation is then a data change, not a change here.
##
## The FIRST seating takes the target share outright rather than stepping toward it
## from nothing: the Senate exists on frame one and has for two centuries, so a renewal
## lag applied at new game would model a chamber that had just been invented. It is
## still a check from month one, because it votes unwhipped -- see target_share().
static func init_nation(ns, nation, party_list: Array) -> void:
	ns.has_upper_house = nation.has_upper_house
	ns.upper_chamber_name = nation.upper_chamber_name
	ns.upper_seats = nation.upper_seats
	ns.upper_ordinary = nation.upper_ordinary
	ns.upper_amendment = nation.upper_amendment
	ns.upper_share = {}
	ns.held_bills = {}
	if not ns.has_upper_house:
		return
	ns.upper_share = target_share(ns, party_list)


## Where the chamber WOULD sit if it were renewed in full today: the lower chamber's
## own seat distribution, as a share.
##
## NO TILT, and the two that were tried are written up in chambers_constants.gd. What
## makes this chamber a check is not its composition but its vote:
## src/sim/legislature.gd resolves it on `spatial_support()` where the lower house
## votes on `support()`, and the difference between those is the coalition bonus. A
## whipped majority does not exist here.
static func target_share(ns, party_list: Array) -> Dictionary:
	var total := 0.0
	for party in party_list:
		total += float(ns.seats_by_party.get(party.id, 0))
	var share := {}
	for party in party_list:
		share[party.id] = 0.0 if total <= 0.0 else float(ns.seats_by_party.get(party.id, 0)) / total
	return share


## Renew part of the chamber. Called by Elections._tick_nation() at every legislative
## election and by nothing else.
##
## THIS IS WHAT MAKES A SECOND CHAMBER A CHECK RATHER THAN A MIRROR. Without a lag a
## landslide sweeps both chambers on the same day and the upper house agrees with the
## lower one by construction; France's Senat is a check precisely because it survived
## 2012 and 2017 -- half of it is renewed every three years on a six-year term, which is
## the real arrangement UPPER_RENEWAL abstracts.
##
## A first-order step on the SHARE and not on the seats: seats are integers and a partial
## renewal of them is a rounding rule pretending to be a model. Renormalised on the way
## out, because a party that lost every seat leaves the two dictionaries with different
## keys and a lerp over a missing key would quietly shrink the chamber.
static func renew(ns, party_list: Array) -> void:
	if not ns.has_upper_house:
		return
	var target := target_share(ns, party_list)
	var blended := {}
	var total := 0.0
	for party_id in target:
		var was: float = float(ns.upper_share.get(party_id, 0.0))
		var now: float = float(target[party_id])
		var value: float = was + (now - was) * CK.UPPER_RENEWAL
		blended[party_id] = value
		total += value
	if total <= 0.0:
		ns.upper_share = target
		return
	for party_id in blended:
		blended[party_id] = float(blended[party_id]) / total
	ns.upper_share = blended


## The chamber, in seats. DERIVED at every read rather than stored, so `upper_share` is
## the one record of one fact -- Defence.allies()'s shape, where the set of your allies
## is derived from the pacts rather than mirrored beside them.
##
## pr_national at a zero threshold is a pure largest-remainder allocation of the share,
## which is what a chamber whose composition IS a share needs. No nation's upper house is
## elected on the nation's own electoral system -- most are not elected at all -- so
## reading `ns.election_system` here would be a borrowed rule rather than a modelled one.
static func seats(ns) -> Dictionary:
	if not ns.has_upper_house:
		return {}
	return ElectoralSystems.pr_national(ns.upper_share, ns.upper_seats, 0.0)


## What this chamber does to a bill of this class, one of chambers_constants'
## KNOWN_VERDICTS. A nation with no second chamber sees every bill as VERDICT_NONE, so
## the caller needs no `has_upper_house` branch of its own.
##
## TWO ROWS BECAUSE THE REAL DISTINCTION IS BETWEEN CLASSES OF BILL. France's Senat
## delays an ordinary bill and cannot be overridden on a revision; Germany's Bundesrat is
## the same shape; Belgium's Senate does not see an ordinary bill at all since 2014 and
## keeps full competence under Art. 195. A single-valued enum could not say that without
## values meaning "the first thing here and the second thing there", which is two facts
## wearing one name.
static func power_over(ns, law) -> String:
	if not ns.has_upper_house:
		return CK.VERDICT_NONE
	return ns.upper_amendment if law.constitutional else ns.upper_ordinary
