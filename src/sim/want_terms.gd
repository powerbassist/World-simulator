extends RefCounted

## How a want is priced, and whether a region's is served. Split out of characters.gd when
## the `region:` family (V5.3 b, step 6) met that file's 300-line cap. A leaf like it, constants
## only (tests/test_characters.gd): the fund's row is read off NationState, no system preloaded.

const CharacterK = preload("res://src/sim/character_constants.gd")
const CK = preload("res://src/sim/character_act_constants.gd")
const FK = preload("res://src/sim/region_fund_constants.gd")


## A STANDING want's object: a condition the government holds month by month (a
## meter's level, a programme entry's presence on the register). Everything else
## -- the `office:` family, a region's fund -- is a discrete holding, charged once at
## the turn. A fund is the second kind because it ends by design: billed monthly, every
## fund that ran its term would charge its figure for the rest of the game.
static func is_standing(object: String) -> bool:
	return object.begins_with("meter:") or object.begins_with("programme:")


## The author's call 2 B (2026-11-28): whether a word on `object` promises something the player
## DOES -- a bill brought (`law:`), a post given, a region's fund opened, a measure lifted, a plant
## answered. A programme's place on the register, a meter's level, the premiership (the largest
## party's) and a party's leadership (the party's) are not the player's to do: no word is given on
## them. Words already written on them (an older save) are judged as they were given.
const ACTS := ["law:", "office:portfolio:", "region:", "measure:", "firm:"]


static func is_act(object: String) -> bool:
	for prefix in ACTS:
		if object.begins_with(prefix):
			return true
	return false


## The want-shaped half of a grudge pulse. FERVENT amplifies a METER want's
## denial for the collective kinds, and only there: the meter IS a union
## leader's or an activist's lever (14.4), so being denied at the meter is
## being denied in their own register rather than at one of a politician's
## many objects. A fervent politician gets nothing here, which is the
## distinction the trait's own wording draws.
static func denial_factor(person, object: String) -> float:
	if person.traits.has("fervent") and object.begins_with("meter:"):
		if CharacterK.KIND_COLLECTIVE.has(String(person.kind)):
			return CK.FERVENT_METER_FACTOR
	return 1.0


## A `region:<id>` want is served while the region has a development fund open.
static func fund_open(ns, region_id: String) -> bool:
	for row in ns.region_funds:
		if String(row["region_id"]) == region_id and String(row["status"]) == FK.STATUS_OPEN:
			return true
	return false


## The author's rule (d) (Gameplay's card A2, 2026-11-14): a HOLDING want asks once. Refused --
## declined, lapsed, a no-show -- its figure asks no more about that object until it turns:
## served (the fund opens, the post is given), which clears the mark, then lost again. A
## standing want is not marked: it goes on asking, as the declined always did. The mark lives
## in `person_want_state` beside the edge-trigger's two keys ("pid|object", "pid|!object") as
## "pid|?object" (Characters.refuse_holding writes it, the register's one writer); absent reads
## "not refused", so a save from before the rule re-asks once (absent_ok, no bump).
## A reshuffle that moves or vacates a post turns it too (Gameplay's card A3): its wanters
## are invited once more the month after (AudienceTriggers.invitations), marked or not; the
## mark still holds on the hazard.
static func refused_key(pid: String, object: String) -> String:
	return pid + "|?" + object


static func refused(ns, pid: String, object: String) -> bool:
	return ns.person_want_state.has(refused_key(pid, object))


## Party id -> its authored leader's person id: the leaders the want ladder's office reads
## compare against (Characters.want_served's `authored_leaders`). One loop for every reader
## (the request lane, its overtaken close, the commitments' judge, the want settle).
static func authored_leaders(loader, nation_id: String) -> Dictionary:
	var out := {}
	for party in loader.parties.get(nation_id, []):
		out[party.id] = party.leader_person_id
	return out
