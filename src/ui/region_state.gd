extends RefCounted

## The Regions tab's per-game state: what the player opened and set in THIS game, which a load
## discards (region_panel.gd holds one as `_game`; regions_shell.gd resets it on a load). Its
## own file so the reset is the state's job, not another file writing the panel's private
## fields (AGENTS.md rule 3, the #391 review's T5).

## The region opened under its row, "" for none.
var open_region := ""
## "" is the region list; a city id is that city's detail.
var city_id := ""
## The development fund's two sums (region_fund.gd), held across rebuilds.
var fund_share := 0.0
var fund_years := 0
## The last Go or Stop the finance bill refused, said under it across the rebuild the press
## asks for ("" once a press tables, or another region opens).
var fund_refusal := ""
## The map's measure the rail's chips picked (region_tint.gd).
var measure := "jobless"


## A load. The measure too: "change" held over a save with under two months sampled would
## tint nothing behind a chip that is pressed and disabled at once.
func reset() -> void:
	open_region = ""
	city_id = ""
	fund_share = 0.0
	fund_years = 0
	fund_refusal = ""
	measure = "jobless"
