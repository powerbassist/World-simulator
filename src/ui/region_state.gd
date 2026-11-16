extends RefCounted

## The Regions tab's per-game state: what the player opened and set in THIS game, which a load
## discards (region_panel.gd holds one as `_game` and makes a new one on a load, so a field
## added here cannot survive one). Its own file so no other file writes the panel's private
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
