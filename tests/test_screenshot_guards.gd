extends SceneTree

## Headless test: godot --headless --script res://tests/test_screenshot_guards.gd
## Non-zero exit on any failure.
##
## tools/screenshot.gd --text took any number (Igor shot 130, a size no player can pick). It now
## refuses what the Settings row does not offer; the sizes are read from SettingsPanel.TEXT_SCALES,
## so a size the game adds is accepted without touching the tool. The other half of the same fix,
## screenshot_all.py refusing a size folder that lies about --interface-size, is `python
## tools/screenshot_all.py --selftest` (the gate and CI run it).

const Shot = preload("res://tools/screenshot.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	for scale in SettingsPanel.TEXT_SCALES:
		var pct := str(roundi(scale * 100.0))
		if Shot.text_pct_refusal(pct) != "":
			_failures.append("--text %s is a size the game offers but was refused" % pct)
	for raw in ["130", "115", "0", "-5", "101", "1.0", "abc", "", "100 "]:
		var message: String = Shot.text_pct_refusal(raw)
		if message == "":
			_failures.append("--text '%s' is not a size the game offers but was accepted" % raw)
		elif not message.contains("90, 100)"):
			_failures.append("--text '%s': the refusal does not list the allowed sizes: %s" % [raw, message])
	for failure in _failures:
		push_error("FAIL " + failure)
	print("test_screenshot_guards: %d failures" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
