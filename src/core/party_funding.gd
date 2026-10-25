extends RefCounted

## V5.2 C6: a nation's public party funding and its legal ceiling on a campaign's
## spending, read from `data/nations/*.json` (docs/design/v5.2-c6-party-campaigns.md
## sections 4-5). Read beside Nation.from_dict() by the DataLoader rather than inside
## it, because nation.gd is at its size baseline and these two facts are the party
## purse's, not the constitution's.
##
## The data, both optional:
##   "party_funding": {"vote_pot_eur_m_year": >= 0, "seat_pot_eur_m_year": >= 0,
##                     "opposition_only": bool (absent = false), "_note"/"_source"...}
##   "campaign_spending_cap_eur_m": > 0 (absent = no ceiling: Germany's case)
##
## Returns {} for a nation with neither, else every key filled:
## {vote_pot_eur_m_year, seat_pot_eur_m_year, opposition_only, cap_eur_m (-1.0 = none)}.
## Funding is national law (France shares its political system with five nations
## whose laws differ), so it is a per-nation field and never a per-system one.

const POTS := ["vote_pot_eur_m_year", "seat_pot_eur_m_year"]


static func read(d: Dictionary, filename: String, errors: Array[String]) -> Dictionary:
	if not d.has("party_funding") and not d.has("campaign_spending_cap_eur_m"):
		return {}
	var out := {"vote_pot_eur_m_year": 0.0, "seat_pot_eur_m_year": 0.0, "opposition_only": false, "cap_eur_m": -1.0}
	var raw = d.get("party_funding", {})
	if typeof(raw) != TYPE_DICTIONARY:
		# Reported, and the ceiling below is still read: one bad block must not hide a
		# second fact's error or drop a valid ceiling with it.
		errors.append("%s: party_funding must be an object" % filename)
		raw = {}
	for key in raw.keys():
		var k := String(key)
		if k.begins_with("_"):
			continue
		if k == "opposition_only":
			if typeof(raw[k]) != TYPE_BOOL:
				errors.append("%s: party_funding.opposition_only must be a boolean" % filename)
			else:
				out[k] = raw[k]
		elif POTS.has(k):
			if not (typeof(raw[k]) == TYPE_INT or typeof(raw[k]) == TYPE_FLOAT) or float(raw[k]) < 0.0:
				errors.append("%s: party_funding.%s must be a number at or above 0" % [filename, k])
			else:
				out[k] = float(raw[k])
		else:
			errors.append("%s: party_funding.%s is not a recognised field (%s, opposition_only)" % [filename, k, str(POTS)])
	if d.has("campaign_spending_cap_eur_m"):
		var cap = d["campaign_spending_cap_eur_m"]
		if not (typeof(cap) == TYPE_INT or typeof(cap) == TYPE_FLOAT) or float(cap) <= 0.0:
			errors.append("%s: campaign_spending_cap_eur_m must be a number above 0 (absent means no ceiling)" % filename)
		else:
			out["cap_eur_m"] = float(cap)
	return out
