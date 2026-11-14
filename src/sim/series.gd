extends RefCounted

## V5.3 e PR B (docs/design/finance-bill.md section 13): the one rule of the screens'
## monthly series -- the world price ring (src/sim/goods_read.gd) and each region's
## sample (src/sim/region_read.gd). Twelve months kept, oldest first, the oldest
## dropped when a thirteenth arrives. A series starts empty and holds only months
## that were run: its size is what the reader says it holds, so a screen never
## draws a history the game did not have.

const MONTHS := 12


static func push(series: Array, value: float) -> void:
	series.append(value)
	while series.size() > MONTHS:
		series.pop_front()
