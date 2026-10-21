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


## The four playable nations, by what the rule must say about each. The ids are
## the TEST's data, not the rule's: the rule reads bands only.
func _check_real_flags() -> void:
	var fallback := UiTheme.ACCENT_FALLBACK
	var cases := {
		"FRA": "blue",      # first band is a blue
		"GBR": "blue",      # navy, lifted
		"DEU": "gold",      # black skipped, red too close to the alert red, gold clears
		"POL": "fallback",  # white has no chroma, crimson is 15 degrees from the alert red
	}
	for id in cases:
		var accent := _accent_of(id)
		match cases[id]:
			"fallback":
				if accent != fallback:
					_fail("%s should take the fallback, got %s" % [id, accent.to_html(false)])
			"gold":
				if accent == fallback or absf(accent.h * 360.0 - 48.0) > 12.0:
					_fail("%s should resolve to its gold band, got %s" % [id, accent.to_html(false)])
			"blue":
				if accent == fallback or absf(accent.h * 360.0 - 215.0) > 20.0:
					_fail("%s should resolve to its blue band, got %s" % [id, accent.to_html(false)])


## Every flag on the roster ends on a colour that is legible on the LIGHTEST graphite surface (SLATE: a hovered row, the open cluster, a pressed button -- where the accent is read as text) and is
## never mistaken for an alert or a good-news tone.
func _check_roster_invariants() -> void:
	var fallbacks := 0
	var ids := _nation_ids()
	if ids.size() < 40:
		_fail("only %d nation files found" % ids.size())
	for id in ids:
		var accent := _accent_of(id)
		if AccentRule.contrast(accent, UiTheme.SLATE) < AccentRule.MIN_CONTRAST - 0.01:
			_fail("%s accent %s is under the contrast floor" % [id, accent.to_html(false)])
		if accent == UiTheme.ACCENT_FALLBACK:
			fallbacks += 1
			continue
		for tone in [UiTheme.BAD, UiTheme.GOOD]:
			if AccentRule.hue_distance(accent.h * 360.0, tone.h * 360.0) < AccentRule.MIN_HUE_DISTANCE - 0.5:
				_fail("%s accent %s is too near the semantic tone %s" % [id, accent.to_html(false), tone.to_html(false)])
	# The rule is only worth having if most flags still get their own colour.
	if fallbacks > ids.size() / 2:
		_fail("%d of %d nations fell back -- the floors are too tight" % [fallbacks, ids.size()])


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
