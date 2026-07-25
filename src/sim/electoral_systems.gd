extends RefCounted

## One pure function per real-world seat-allocation method, plus a dispatch on
## the `system` string a nation's data file names. No nation id anywhere in this
## file — engine-decision.md Rule 1 forbids `if nation_id == "FRA"`, and every
## method here is chosen by the data, not by which nation is asking.
##
## Every function takes a vote-share Dictionary (party id -> float, summing to
## 1.0) and a seat count, and returns a Dictionary (party id -> int) summing to
## exactly that seat count. No engine access, no randomness — same discipline as
## the rest of src/sim/. Argued in docs/electoral-systems.md.

const K = preload("res://src/sim/election_constants.gd")

const SYSTEM_KEYS := ["pr_dhondt", "pr_national", "fptp", "two_round", "parallel"]


## Route to the method a nation's election.system field names. Called by
## elections.gd; the only place in the sim that knows the string exists.
static func allocate(system: String, vote_share: Dictionary, seats: int, threshold_pct: float) -> Dictionary:
	match system:
		"pr_dhondt":
			return pr_dhondt(vote_share, seats, threshold_pct)
		"pr_national":
			return pr_national(vote_share, seats, threshold_pct)
		"fptp":
			return _power_law(vote_share, seats, K.FPTP_EXPONENT)
		"two_round":
			return _power_law(vote_share, seats, K.TWO_ROUND_EXPONENT)
		"parallel":
			return parallel(vote_share, seats, threshold_pct)
		_:
			push_error("electoral_systems: unknown system '%s'" % system)
			return {}


## D'Hondt highest-averages: each party's vote total is repeatedly divided by
## 1, 2, 3, ... and the `seats` largest quotients across all parties win a seat
## each. The standard method for Spain and Belgium.
static func pr_dhondt(vote_share: Dictionary, seats: int, threshold_pct: float) -> Dictionary:
	var eligible := _above_threshold(vote_share, threshold_pct)
	var result := _zeroed(vote_share)
	if eligible.is_empty() or seats <= 0:
		return result

	# One quotient per (party, divisor) pair, picked off in descending order —
	# equivalent to running the divisor series but avoids an unbounded loop.
	var quotients: Array = []
	for party in eligible:
		var v: float = eligible[party]
		for n in range(1, seats + 1):
			quotients.append([v / float(n), party])
	quotients.sort_custom(func(a, b): return a[0] > b[0])

	for i in range(mini(seats, quotients.size())):
		var party: String = quotients[i][1]
		result[party] = int(result[party]) + 1
	return result


## Largest remainder (Hare quota): each party gets floor(quota) seats outright,
## then the largest leftover fractions claim the remaining seats one each. Used
## by Germany, the Netherlands, Luxembourg, Switzerland and Austria — all
## national-list PR at MVP's level of detail. See docs/electoral-systems.md for
## what each real system's own method (MMP, Hagenbach-Bischoff, ...) reduces to
## here and why the reduction is honest.
static func pr_national(vote_share: Dictionary, seats: int, threshold_pct: float) -> Dictionary:
	var eligible := _above_threshold(vote_share, threshold_pct)
	var result := _zeroed(vote_share)
	if eligible.is_empty() or seats <= 0:
		return result

	var total := 0.0
	for v in eligible.values():
		total += float(v)
	if total <= 0.0:
		return result

	var quota := total / float(seats)
	var remainders: Array = []
	var allocated := 0
	for party in eligible:
		var raw: float = float(eligible[party]) / quota
		var whole: int = int(floor(raw))
		result[party] = whole
		allocated += whole
		remainders.append([raw - float(whole), party])

	remainders.sort_custom(func(a, b): return a[0] > b[0])
	var leftover := seats - allocated
	for i in range(mini(leftover, remainders.size())):
		var party: String = remainders[i][1]
		result[party] = int(result[party]) + 1
	return result


## Blend of proportional and single-member-plurality seats, at the weight
## Italy's Rosatellum splits them. Each share allocated independently — a party
## can win its PR seats and none of its plurality seats, or the reverse — then
## summed, so the total still lands exactly on `seats`.
static func parallel(vote_share: Dictionary, seats: int, threshold_pct: float) -> Dictionary:
	var pr_seats: int = int(round(float(seats) * K.PARALLEL_PR_WEIGHT))
	var maj_seats: int = seats - pr_seats

	var pr_result := pr_national(vote_share, pr_seats, threshold_pct)
	var maj_result := _power_law(vote_share, maj_seats, K.FPTP_EXPONENT)

	var result := _zeroed(vote_share)
	for party in result:
		result[party] = int(pr_result.get(party, 0)) + int(maj_result.get(party, 0))
	return result


## Single-member-plurality reduction with no constituency geography: seat share
## follows vote share raised to a power, then renormalised onto `seats` by the
## same largest-remainder step pr_national uses on the resulting "vote share".
## No threshold — a plurality system doesn't need one; a party that wins no
## constituency simply wins no seats, which the power law already produces at
## a small enough vote share.
static func _power_law(vote_share: Dictionary, seats: int, exponent: float) -> Dictionary:
	var result := _zeroed(vote_share)
	if seats <= 0:
		return result

	var powered := {}
	var total := 0.0
	for party in vote_share:
		var v: float = maxf(float(vote_share[party]), 0.0)
		var p: float = pow(v, exponent)
		powered[party] = p
		total += p
	if total <= 0.0:
		return result

	for party in powered:
		powered[party] = float(powered[party]) / total
	return pr_national(powered, seats, 0.0)


static func _above_threshold(vote_share: Dictionary, threshold_pct: float) -> Dictionary:
	var eligible := {}
	var threshold: float = threshold_pct / 100.0
	for party in vote_share:
		if float(vote_share[party]) >= threshold:
			eligible[party] = vote_share[party]
	return eligible


static func _zeroed(vote_share: Dictionary) -> Dictionary:
	var result := {}
	for party in vote_share:
		result[party] = 0
	return result
