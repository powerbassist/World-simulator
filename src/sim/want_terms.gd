extends RefCounted

## How a want is priced, and whether a region's is served. Split out of characters.gd when
## the `region:` family (V5.3 b, step 6) met that file's 300-line cap.

const CharacterK = preload("res://src/sim/character_constants.gd")
const CK = preload("res://src/sim/character_act_constants.gd")
const RegionFunds = preload("res://src/sim/region_funds.gd")


## A STANDING want's object: a condition the government holds month by month (a
## meter's level, a programme entry's presence on the register). Everything else
## -- the `office:` family, a region's fund -- is a discrete holding, charged once at
## the turn. A fund is the second kind because it ends by design: billed monthly, every
## fund that ran its term would charge its figure for the rest of the game.
static func is_standing(object: String) -> bool:
	return object.begins_with("meter:") or object.begins_with("programme:")


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
		if String(row["region_id"]) == region_id and String(row["status"]) == RegionFunds.OPEN:
			return true
	return false
