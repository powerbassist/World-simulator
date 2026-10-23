extends RefCounted

## The inbox note that answers a proposal the player just made. It moved out of
## main.gd (at its size ratchet) when the held bill needed its own wording: a bill
## the Assembly carried and the second chamber only HOLDS is not "Failed" -- the
## Legislature, the verdict window and the assembly news all say held (one word
## for different things is the readout bug this project keeps finding).

const Strings = preload("res://src/ui/strings.gd")


static func body(result: Dictionary) -> String:
	if bool(result.get("refused", false)):
		if bool(result.get("referendum_in_flight", false)):
			return Strings.t("A referendum is already in flight.")
		return Strings.t("The assembly would not take it.")
	if bool(result.get("withdrawn", false)):
		return Strings.t("Withdrawn.")
	if bool(result.get("referendum_route", false)):
		return Strings.t("To the country -- the vote is scheduled.")
	var yes := int(result.get("yes_seats", 0))
	var no := int(result.get("no_seats", 0))
	var chamber := String(result.get("upper_chamber", Strings.t("second chamber")))
	if bool(result.get("held_by_upper", false)):
		var months := int(result.get("held_months", 0))
		return Strings.tn("Carried by the assembly, yes %d, no %d. The %s holds it; it comes into force in %d month.", "Carried by the assembly, yes %d, no %d. The %s holds it; it comes into force in %d months.", months) % [yes, no, chamber, months]
	if bool(result.get("blocked_by_upper", false)):
		return Strings.t("Carried by the assembly, yes %d, no %d. The %s has blocked it.") % [yes, no, chamber]
	return (Strings.t("Passed. Yes %d, No %d.") if bool(result.get("passed", false)) else Strings.t("Failed. Yes %d, No %d.")) % [yes, no]
