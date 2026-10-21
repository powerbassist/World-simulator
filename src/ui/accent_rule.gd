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
## - DISTANCE from the semantic hues. The interface already uses red for bad news
##   and green for good news, and a marker that is the same colour as an alert
##   reads as one. The flags' reds sit 3-15 degrees from the alert red and the
##   next hue family up -- an orange or a gold -- sits 31 degrees or more away, so
##   MIN_HUE_DISTANCE = 24 falls in the empty gap between them; the greens (1-11
##   degrees from the good-news green) fail the same test and nothing else comes
##   close to either. DEU's red and POL's crimson therefore fail; DEU's next band,
##   gold, passes and POL has none left.
## - CONTRAST. The accent is drawn as text and as thin lines on graphite, so it
##   must hold WCAG AA (4.5:1) there. A flag blue is far too dark for that, so the
##   band is lifted: lightness raised in HSL with hue and saturation kept, which
##   leaves a brighter blue rather than a washed-out one. The surface is the
##   lightest graphite (a hovered row), the worst case the accent is read on.
##
## No band passing is a real outcome, not an error: the caller's named fallback
## applies. Pure functions over colours, with the surface and the tones to avoid
## passed in, so this file never has to know the palette (and cannot cycle with
## ui_theme.gd, which calls it).

const MIN_CHROMA := 0.25
const MIN_HUE_DISTANCE := 24.0
const MIN_CONTRAST := 4.5


## The accent for a flag. `bands` is the flag's colours in file order; `avoid` the
## semantic colours the accent must not resemble; `surface` what it is drawn on.
static func pick(bands: Array, surface: Color, avoid: Array, fallback: Color) -> Color:
	for band in bands:
		var c: Color = band
		if chroma(c) < MIN_CHROMA:
			continue
		var too_near := false
		for tone in avoid:
			if hue_distance(c.h * 360.0, (tone as Color).h * 360.0) < MIN_HUE_DISTANCE:
				too_near = true
				break
		if not too_near:
			return lift(c, surface)
	return fallback


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
