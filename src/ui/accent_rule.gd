extends RefCounted

## The accent rule -- V5.1a. The interface's one accent colour is the played
## nation's own flag, chosen from the flag's bands (data/nations/*.json), so a
## nation that behaves differently is a data edit and never an `if nation_id`
## (AGENTS.md rule 1).
##
## A flag colour cannot be taken as it comes. Three floors, each measured on the
## 41 flags of the roster rather than guessed:
##
## - CHROMA. White, black and greys carry no hue, so a band under MIN_CHROMA
##   cannot be an accent. (DEU's black, POL's white.)
## - DISTANCE from the state tones. The interface already uses red for bad news,
##   green for good news and amber for attention, and a marker in the same colour
##   as an alert reads as one. The flags' reds sit 3-15 degrees from the alert red
##   and the next hue family up -- an orange or a gold -- 31 or more away, so
##   MIN_HUE_DISTANCE = 24 falls in the empty gap between them; the greens (1-11
##   degrees from the good-news green) land inside the same zone.
## - CONTRAST. The accent is drawn as text and as thin lines on graphite, so it
##   must hold WCAG AA (4.5:1) there. A flag blue is far too dark for that, so the
##   band is lifted: lightness raised in HSL with hue and saturation kept, which
##   leaves a brighter blue rather than a washed-out one. The surface is the
##   lightest graphite (a hovered row), the worst case the accent is read on.
##
## A band whose hue falls inside a state tone's zone is NOT skipped (the author's
## call, 2026-10-21: keep the flag's colour family, push it out of the state zone).
## Its hue is SHIFTED to the nearest edge of the zone plus SHIFT_MARGIN, saturation
## and lightness kept -- Polish crimson becomes raspberry, German gold a lime-leaning
## yellow -- and then lifted. If that edge lies in ANOTHER tone's zone the other edge
## is tried; if both are forbidden the band is passed over. The lifted colour is
## checked again (a dark saturated band can lift toward grey), and only a colour that
## still qualifies is returned. The fallback applies only when no band yields one,
## which in practice means a flag with no chroma at all. Which band is shifted is
## decided in pick(): the one that moves least.
##
## Pure functions over colours, with the surface and the tones passed in, so this
## file never has to know the palette (and cannot cycle with ui_theme.gd, which
## calls it).

const MIN_CHROMA := 0.25
const MIN_HUE_DISTANCE := 24.0
const MIN_CONTRAST := 4.5
## Beyond the zone's edge, so a shifted hue is clear of it by more than rounding.
const SHIFT_MARGIN := 4.0


## The accent for a flag. `bands` is the flag's colours in file order; `avoid` the
## state tones the accent must keep its distance from; `surface` what it is drawn on.
## Of the bands that qualify, the one that needs the SMALLEST hue shift wins, so the
## flag's colour family moves least (Germany's gold, 21 degrees, rather than its red,
## 25); a tie goes to file order. "First qualifying band" was the rejected rule: it
## shifted the most conspicuous band and left a nearer one unused.
static func pick(bands: Array, surface: Color, avoid: Array, fallback: Color) -> Color:
	var tones: Array[float] = []
	for tone in avoid:
		tones.append((tone as Color).h * 360.0)
	var best := fallback
	var best_shift := INF
	for band in bands:
		var c: Color = band
		if chroma(c) < MIN_CHROMA:
			continue
		var hue := clear_hue(c.h * 360.0, tones)
		if hue < 0.0:
			continue
		var shift := hue_distance(c.h * 360.0, hue)
		if shift >= best_shift:
			continue
		var hsl := _to_hsl(c)
		var lifted := lift(_from_hsl(hue / 360.0, hsl.y, hsl.z), surface)
		if _qualifies(lifted, tones):
			best = lifted
			best_shift = shift
	return best


## The hue itself if it is outside every tone's zone; else the nearest clear edge
## of the zone it is in (tried in order of distance); -1.0 when no edge is clear.
static func clear_hue(hue: float, tones: Array[float]) -> float:
	for tone in tones:
		if hue_distance(hue, tone) >= MIN_HUE_DISTANCE:
			continue
		var edges := [fposmod(tone - MIN_HUE_DISTANCE - SHIFT_MARGIN, 360.0), fposmod(tone + MIN_HUE_DISTANCE + SHIFT_MARGIN, 360.0)]
		edges.sort_custom(func(a: float, b: float) -> bool: return hue_distance(hue, a) < hue_distance(hue, b))
		for edge in edges:
			if _is_clear(edge, tones):
				return edge
		return -1.0
	return hue


static func _is_clear(hue: float, tones: Array[float]) -> bool:
	for tone in tones:
		if hue_distance(hue, tone) < MIN_HUE_DISTANCE:
			return false
	return true


## Still chromatic and still clear of every tone, after the lift.
static func _qualifies(c: Color, tones: Array[float]) -> bool:
	return chroma(c) >= MIN_CHROMA and _is_clear(c.h * 360.0, tones)


## Raises HSL lightness, hue and saturation kept, until `c` clears MIN_CONTRAST on
## `surface`. A colour that already clears it comes back untouched.
static func lift(c: Color, surface: Color) -> Color:
	if contrast(c, surface) >= MIN_CONTRAST:
		return c
	var hsl := _to_hsl(c)
	var l: float = hsl.z
	while l < 1.0:
		l += 0.01
		var lifted := _from_hsl(hsl.x, hsl.y, minf(l, 1.0))
		if contrast(lifted, surface) >= MIN_CONTRAST:
			return lifted
	return Color.WHITE


static func chroma(c: Color) -> float:
	return maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))


## Degrees apart on the hue circle, 0-180.
static func hue_distance(a: float, b: float) -> float:
	var d := fposmod(absf(a - b), 360.0)
	return minf(d, 360.0 - d)


## WCAG 2 contrast ratio, 1-21.
static func contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var lin := c.srgb_to_linear()
	return 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b


## Vector3(hue 0-1, saturation, lightness).
static func _to_hsl(c: Color) -> Vector3:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	var l := (mx + mn) / 2.0
	if is_equal_approx(mx, mn):
		return Vector3(0.0, 0.0, l)
	var d := mx - mn
	var s := d / (2.0 - mx - mn) if l > 0.5 else d / (mx + mn)
	return Vector3(c.h, s, l)


static func _from_hsl(h: float, s: float, l: float) -> Color:
	if s == 0.0:
		return Color(l, l, l)
	var q := l * (1.0 + s) if l < 0.5 else l + s - l * s
	var p := 2.0 * l - q
	return Color(_hue_to_channel(p, q, h + 1.0 / 3.0), _hue_to_channel(p, q, h), _hue_to_channel(p, q, h - 1.0 / 3.0))


static func _hue_to_channel(p: float, q: float, t: float) -> float:
	t = fposmod(t, 1.0)
	if t < 1.0 / 6.0:
		return p + (q - p) * 6.0 * t
	if t < 0.5:
		return q
	if t < 2.0 / 3.0:
		return p + (q - p) * (2.0 / 3.0 - t) * 6.0
	return p
