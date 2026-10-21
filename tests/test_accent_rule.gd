extends SceneTree

## Headless test: godot --headless --script res://tests/test_accent_rule.gd
## Non-zero exit on any failure.
##
## V5.1a. The accent is the played nation's flag colour, chosen by a RULE over
## the flag's own bands (data/nations/*.json), never by nation id. The rule's
## three floors -- chroma, distance from the semantic hues, contrast against the
## panel -- are the thing under test, and they are tested against the REAL roster:
## the board's finding was that DEU's and POL's reds sit within a few degrees of
## the alert red, so "first coloured band" would have drawn their active-item
## marker in the colour of an error.

const AccentRule = preload("res://src/ui/accent_rule.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

var _failures: Array[String] = []


func _init() -> void:
	_check_helpers()
	_check_real_flags()
	_check_roster_invariants()
	_finish()
	quit(1 if not _failures.is_empty() else 0)


func _check_helpers() -> void:
	if not is_equal_approx(AccentRule.hue_distance(350.0, 10.0), 20.0):
		_fail("hue_distance does not wrap the circle (350 vs 10 should be 20)")
	if not is_equal_approx(AccentRule.contrast(Color.WHITE, Color.BLACK), 21.0):
		_fail("contrast(white, black) is not 21")
	var dark := Color("#0055A4")
	var lifted := AccentRule.lift(dark, UiTheme.SLATE)
	if AccentRule.contrast(lifted, UiTheme.SLATE) < AccentRule.MIN_CONTRAST:
		_fail("lift() left %s under the contrast floor" % lifted.to_html(false))
	if absf(lifted.h - dark.h) > 0.01:
		_fail("lift() changed the hue (%.3f -> %.3f)" % [dark.h, lifted.h])
	# A colour that already clears the floor is not touched.
	var gold := Color("#FFCE00")
	if AccentRule.lift(gold, UiTheme.SLATE) != gold:
		_fail("lift() altered a colour that already had contrast")

	# clear_hue(): a hue outside every forbidden zone is returned as it is; one
	# inside a zone goes to the nearest edge of that zone plus the margin; and a
	# hue boxed in by zones on both sides has no clear hue at all.
	var tones: Array[float] = [3.0, 41.0, 154.0]
	if not is_equal_approx(AccentRule.clear_hue(209.0, tones), 209.0):
		_fail("clear_hue moved a hue that was already clear")
	var crimson := AccentRule.clear_hue(348.0, tones)
	if absf(crimson - 335.0) > 0.01:
		_fail("a crimson 348 should shift down to 335 (the alert red's low edge less the margin), got %.2f" % crimson)
	# 48 is inside the attention tone's zone; its low edge (13) is inside the alert
	# red's zone, so the only clear edge is the high one.
	var gold_h := AccentRule.clear_hue(48.0, tones)
	if absf(gold_h - 69.0) > 0.01:
		_fail("a gold 48 should shift up to 69 (the attention tone's high edge), got %.2f" % gold_h)
	var boxed: Array[float] = [0.0, 40.0, 80.0, 120.0, 160.0, 200.0, 240.0, 280.0, 320.0]
	if AccentRule.clear_hue(20.0, boxed) != -1.0:
		_fail("a hue with both edges forbidden should have no clear hue")

	# pick(): the band that needs the SMALLEST hue shift wins, not the first one that
	# qualifies (the author's colour-family call). Ties go to file order.
	var red := Color("#DD0000")
	var yellow := Color("#FFCE00")
	var fixed := AccentRule.pick([red, yellow], UiTheme.SLATE, [UiTheme.BAD, UiTheme.GOOD, UiTheme.WARN], UiTheme.ACCENT_FALLBACK)
	if AccentRule.hue_distance(fixed.h * 360.0, 66.4) > 1.5:
		_fail("red then gold should pick the gold (21 degrees against 25), got hue %.1f" % (fixed.h * 360.0))
	var reversed := AccentRule.pick([yellow, red], UiTheme.SLATE, [UiTheme.BAD, UiTheme.GOOD, UiTheme.WARN], UiTheme.ACCENT_FALLBACK)
	if reversed != fixed:
		_fail("band order changed a pick that is not a tie")
	var untouched := AccentRule.pick([red, Color("#0055A4")], UiTheme.SLATE, [UiTheme.BAD, UiTheme.GOOD, UiTheme.WARN], UiTheme.ACCENT_FALLBACK)
	if AccentRule.hue_distance(untouched.h * 360.0, 209.0) > 1.5:
		_fail("a band that needs no shift should beat one that does, got hue %.1f" % (untouched.h * 360.0))
	var tie_a := Color("#0055A4")
	var tie_b := Color("#1166BB")  # same family, same zero shift: the first in file order
	var tie := AccentRule.pick([tie_a, tie_b], UiTheme.SLATE, [UiTheme.BAD, UiTheme.GOOD, UiTheme.WARN], UiTheme.ACCENT_FALLBACK)
	if tie != AccentRule.pick([tie_a], UiTheme.SLATE, [UiTheme.BAD, UiTheme.GOOD, UiTheme.WARN], UiTheme.ACCENT_FALLBACK):
		_fail("a tie should go to the earlier band")

	# No chroma anywhere is the one case that falls back.
	var greys := [Color.WHITE, Color.BLACK, Color("#808080")]
	if AccentRule.pick(greys, UiTheme.SLATE, [UiTheme.BAD], UiTheme.ACCENT_FALLBACK) != UiTheme.ACCENT_FALLBACK:
		_fail("a flag of greys should take the fallback")


## Real flags, by what the rule must say about each: the colour FAMILY of the first
## usable band survives, and only the hue is pushed out of a state tone's zone. The
## ids are the TEST's data, not the rule's: the rule reads bands only.
func _check_real_flags() -> void:
	# id -> expected hue in degrees (the band's own where no shift is needed).
	var cases := {
		"FRA": 209.0,  # blue, untouched
		"GBR": 222.0,  # navy, untouched
		"POL": 335.0,  # crimson (348) is 15 degrees from the alert red: raspberry
		"DEU": 66.4,  # black has no chroma; red needs 25 degrees, gold 21: gold, shifted up to a bright yellow
		"ITA": 335.0,  # green needs 24.5 degrees (150 -> 125), red 21.8 (357 -> 335): red, a raspberry
		"IRL": 181.0,  # green (154) is nearer the good-news green's high edge: 27 degrees, a turquoise; orange needs 49
	}
	for id in cases:
		var accent := _accent_of(id)
		if accent == UiTheme.ACCENT_FALLBACK:
			_fail("%s fell back although it has a chromatic band" % id)
			continue
		if AccentRule.hue_distance(accent.h * 360.0, float(cases[id])) > 1.5:
			_fail("%s resolved to hue %.1f, expected about %.0f (%s)" % [id, accent.h * 360.0, float(cases[id]), accent.to_html(false)])


## Every flag on the roster ends on a colour that is legible on the LIGHTEST graphite
## surface (SLATE: a hovered row, the open cluster, a pressed button -- where the
## accent is read as text), still chromatic, never within MIN_HUE_DISTANCE of a
## state tone (alert, good news, attention), and still in its band's colour family.
func _check_roster_invariants() -> void:
	var fallbacks := 0
	var ids := _nation_ids()
	if ids.size() < 40:
		_fail("only %d nation files found" % ids.size())
	for id in ids:
		var accent := _accent_of(id)
		if accent == UiTheme.ACCENT_FALLBACK:
			fallbacks += 1
			continue
		if AccentRule.contrast(accent, UiTheme.SLATE) < AccentRule.MIN_CONTRAST - 0.01:
			_fail("%s accent %s is under the contrast floor" % [id, accent.to_html(false)])
		if AccentRule.chroma(accent) < AccentRule.MIN_CHROMA:
			_fail("%s accent %s has gone grey after the lift" % [id, accent.to_html(false)])
		for tone in [UiTheme.BAD, UiTheme.GOOD, UiTheme.WARN]:
			if AccentRule.hue_distance(accent.h * 360.0, tone.h * 360.0) < AccentRule.MIN_HUE_DISTANCE - 0.5:
				_fail("%s accent %s is too near the state tone %s" % [id, accent.to_html(false), tone.to_html(false)])
		# The family survives: some chromatic band is within one zone-width (plus
		# the margin) of the final hue.
		var near := false
		for band in _bands_of(id):
			if AccentRule.chroma(band) >= AccentRule.MIN_CHROMA and AccentRule.hue_distance(accent.h * 360.0, band.h * 360.0) <= 2.0 * AccentRule.MIN_HUE_DISTANCE + AccentRule.SHIFT_MARGIN:
				near = true
		if not near:
			_fail("%s accent %s is in no band's colour family" % [id, accent.to_html(false)])
	# The fallback is for a flag with no chroma at all, and every roster flag has some.
	if fallbacks > 0:
		_fail("%d of %d nations fell back" % [fallbacks, ids.size()])


func _accent_of(id: String) -> Color:
	return UiTheme.accent_for(_bands_of(id))


func _bands_of(id: String) -> Array[Color]:
	var out: Array[Color] = []
	var file := FileAccess.open("res://data/nations/%s.json" % id, FileAccess.READ)
	if file == null:
		_fail("no nation file for %s" % id)
		return out
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_fail("%s.json does not parse" % id)
		return out
	for hex in parsed.get("flag", {}).get("bands", []):
		out.append(Color(String(hex)))
	return out


func _nation_ids() -> Array[String]:
	var ids: Array[String] = []
	for name in DirAccess.get_files_at("res://data/nations"):
		if name.ends_with(".json"):
			ids.append(name.get_basename())
	return ids


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_accent_rule: all checks passed")
	else:
		for f in _failures:
			printerr(f)
