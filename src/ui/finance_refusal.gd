extends RefCounted

## A finance tabling's refusal flag in words -- the one table the bill's rail (finance_foot.gd) and its sheet say,
## moved out of the rail at G3 S4 to keep that file under the size ratchet. The Assembly's verdict in words too.

const Strings = preload("res://src/ui/strings.gd")


## "✓ It carries: 348 for, 229 against." -- the Assembly's result as the sim's own division rule reads it now.
static func carries_text(vote: Dictionary) -> String:
	var counts := [int(vote["yes_seats"]), int(vote["no_seats"])]
	return ("✓ " + Strings.t("It carries: %d for, %d against.") % counts) if bool(vote.get("passed", false)) \
		else ("✗ " + Strings.t("It falls: %d for, %d against.") % counts)


## The refusal in words, for a page with no queue verb: another bill in the slot is said as it is.
static func reason(flag: String) -> String:
	if flag == "already_tabled":
		return Strings.t("Another bill holds this month's slot.")
	if flag == "autumn":
		return Strings.t("A tax is created or abolished only in the autumn month.")
	# The refusal flags Legislature.refusal and FinanceBill.refusal hand back, in words (moved
	# here from goal_rows.gd when the Bills second pass took the goal tiles off the tab).
	match flag:
		"finance_queued":
			return Strings.t("A budget text is already queued.")
		"referendum_in_flight":
			return Strings.t("A referendum is in flight.")
		"unavailable":
			return Strings.t("Not open to propose now.")
		"range":
			return Strings.t("Outside the tax's range.")
		"verb":
			return Strings.t("A row of the bill is not legal now.")
	return Strings.t("It cannot be tabled now.")
