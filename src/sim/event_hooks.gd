extends RefCounted

## The event hook emitters, split out of events.gd (which was past the size the
## architecture rules allow). Behaviour is unchanged; Events._hook_fired became
## EventHooks.fired.

const OrgsK = preload("res://src/sim/orgs_constants.gd")


## Whether the happening a hook names occurred, for THIS nation, this month. One
## function per vocabulary entry, and events_constants.ON_ACTIONS' comment is the
## contract: a name on that list without a branch here fails tests/test_events.gd's
## `_test_the_hook_vocabulary_is_swept` (which reads both directions) rather than
## shipping as a silent never-firing hook.
static func fired(state, ns, loader, hook: String, month_index: int) -> bool:
	match hook:
		"law_passed":
			# PURE ONE-MONTH LAG, minister_resigned's shape below: the ledger
			# stamps at APPLY time, and the player's Propose/Force routes apply
			# at COMMAND time (month M), which this machine first reads at M+1
			# -- so a same-month read could never fire for them (measured: the
			# hook stayed false at M+1 and fired only at M). The lag fires once,
			# one month after a passage lands, for every passage the LEDGER
			# records -- and that is why the same-month leg is dropped rather
			# than kept beside it: with both legs, an in-tick passage (held-bill
			# release, referendum settlement) fires twice, at M on the == leg
			# and at M+1 on the lag. The ledger records only passages that moved
			# a ledgered channel by a non-zero amount (Legislature._record_ledger
			# returns early otherwise), so a passage that writes no ledgered
			# channel (for example a purely institutional Act, or a pure repeal)
			# never fires it, and one happening can fire two
			# hooks: a carried private member's bill fires member_bill_passed at
			# M and law_passed at M+1. Assembly bills are a DISTINCT hook
			# (member_bill_passed below) reading its own stamp,
			# assembly_bill_passed_month, which Cabinet-side ordering does not
			# delay. No shipped event binds law_passed (docs/someday.md carries
			# the gap).
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
			# Reads its OWN stamp, written where an assembly bill comes into
			# force (Statute's passing division, Legislature's held-bill release
			# for origin "assembly") -- never last_law_result, which every later
			# division of the month overwrites: a release at M was erased by a
			# same-month private member's bill that failed, and the hook never
			# saw it. A defeated, blocked or HELD division writes no stamp, so
			# "passed" stays part of the name.
			return ns.assembly_bill_passed_month == month_index
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
			# An EDGE: Commodities stamps the month a good's price crossed UP
			# through its high line (commodity_constants.HIGH_PRICE_RATIO of base),
			# the one place both sides of the update are in hand, and this reads
			# that stamp. It was a LEVEL read ("is any price at or above the
			# line"), and the world vector drifts to its clamp within a few
			# months, so the hook was true almost every month and flooded the
			# desk. Commodities ticks before Events in every pinned harness
			# (_EVENTS_READS_AFTER), so the same-month stamp is readable.
			return ns.commodity_high_month == month_index
		"accession_won":
			# The UNION's accession. The stamp is org-generic (`_flip_membership`
			# writes it for NATO, the eurozone, Schengen and the climate accord
			# too), but the hook's only consumer is the Commission-and-treaty
			# card, and a `once` event that burns its mark on a NATO accession is
			# a card about the wrong institution -- so the org is tested HERE, at
			# the emitter, rather than widening the hook vocabulary with a
			# parameter nothing else needs.
			return String(ns.last_accession.get("org", "")) == OrgsK.UNION_ORG_ID \
				and int(ns.last_accession.get("month_index", -1)) == month_index
		# V5.2c: an exposure is armed through the chain door (Events.arm), which waits
		# on a full desk; this door skips for good, so it never fires one.
		"exposure":
			return false
	return false


# Same one-liner as Events._absolute_month; a private copy so this file does not
# preload events.gd (events.gd preloads this one).
static func _absolute_month(year: int, month: int) -> int:
	return year * 12 + month
