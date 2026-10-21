extends SceneTree

## Headless test: godot --headless --script res://tests/test_i18n_lint.gd
## Non-zero exit on any failure.
##
## V5.1b. A text a player reads goes through tr() -- by the CALLER: PanelKit and the
## other helpers never translate what they are handed, or a string would be
## translated twice and the lint could not tell a wrapped literal from a forgotten
## one. This fails on a bare English literal at a text sink in src/ui:
##
##   .text = "..."   tooltip_text = "..."   placeholder_text = "..."   .title = "..."
##     -- and on such a line the branches of a ternary (`else "..."`), a `+ "..."`
##     and the English default of `.get("key", "...")` too
##   PanelKit.<row builder>(...)   <windows>.register(id, "...")   add_item("...")
##   the settings/menu/action-bar builders (_add_row, _add_entry, add_cluster, the
##   drawer's _entry), and the message stack's push(title, body): the FIRST argument
##   and any argument after a comma, or an element of an array literal -- never an
##   index (`_columns["government"]` is a key, not text), a dictionary key or a nested
##   call's argument
##
## and says where. It reads one line at a time, so a literal on a continuation
## line is not seen -- the coverage is the patterns above, not "every string".
## dev_*.gd (the developer console) is English by design. A line that holds a
## literal that is not prose (a glyph, a unit) carries `# i18n: ok`.

const ROOT := "res://src/ui"
const OK_MARK := "# i18n: ok"
## Builders whose first argument is text, and builders whose first argument is an id
## (the drawer's _entry(id, label) and add_cluster(id, label, ...)): the lint reads
## every argument of the first kind and every one after the first of the second.
const TEXT_FIRST := r"(?:PanelKit\.\w+|_add_row|_add_entry|message_stack\.push|_param_slider)"
const ID_FIRST := r"(?:\.add_cluster|(?<![\w.])_entry)"

var _failures: Array[String] = []
var _text_re: RegEx
var _sinks: Array[RegEx] = []
var _assign_re: RegEx
var _rhs_sinks: Array[RegEx] = []
var _index_re: RegEx
var _builder_re: RegEx
var _else_re: RegEx
var _wrapped_re: RegEx


func _init() -> void:
	_text_re = RegEx.create_from_string("[A-Za-z]{2,}")
	for pattern in [
		r"(?:\.text|tooltip_text|placeholder_text|\.title)\s*(?<![!<>=])=(?!=)\s*\(*\s*$",
		TEXT_FIRST + r"\(\s*$",
		"(?:" + TEXT_FIRST + "|" + ID_FIRST + r")\((?:[^()]|\([^()]*\))*(?:,\s*|(?<![\w\])])\[\s*)$",
		r"\.register\(\"[^\"]*\",\s*$",
		r"\.add_item\($",
	]:
		_sinks.append(RegEx.create_from_string(pattern))
	# On a line that assigns to a text property, the rest of the right-hand side.
	_assign_re = RegEx.create_from_string(r"(?:\.text|tooltip_text|placeholder_text|\.title)\s*(?<![!<>=])=(?!=)")
	for pattern in [r"\belse\s*\(*\s*$", r"\+\s*$", r"\.get\(\s*\"[^\"]*\"\s*,\s*$"]:
		_rhs_sinks.append(RegEx.create_from_string(pattern))
	_builder_re = RegEx.create_from_string("(?:" + TEXT_FIRST + "|" + ID_FIRST + r")\(")
	_else_re = RegEx.create_from_string(r"\belse\s*\(*\s*$")
	_index_re = RegEx.create_from_string(r"(?<=[\w\])])\[\s*$")
	_wrapped_re = RegEx.create_from_string(r"(?<![\w])(?:tr|Strings\.t)\($")
	var names := Array(DirAccess.get_files_at(ROOT))
	names.sort()
	var scanned := 0
	for name in names:
		if not String(name).ends_with(".gd") or String(name).begins_with("dev_"):
			continue
		scanned += 1
		_scan("%s/%s" % [ROOT, name])
	if scanned < 80:
		_fail("only %d files scanned under %s" % [scanned, ROOT])
	_finish()
	quit(1 if not _failures.is_empty() else 0)


func _scan(path: String) -> void:
	var number := 0
	for line in FileAccess.get_file_as_string(path).split("
"):
		number += 1
		if line.strip_edges().begins_with("#") or line.contains(OK_MARK):
			continue
		for literal in _literals(line):
			if not _text_re.search(literal["text"]):
				continue
			var before: String = line.substr(0, literal["start"])
			if _is_sink(before):
				_fail("%s:%d: bare literal at a text sink, wrap it in tr(): \"%s\"" % [path.get_file(), number, literal["text"]])


## Whether a literal that follows `before` on its line sits at a text sink.
func _is_sink(before: String) -> bool:
	# Already wrapped: the call that holds the literal is tr( or Strings.t(.
	if _wrapped_re.search(before):
		return false
	# An index into something is a key, not text.
	if _index_re.search(before):
		return false
	for sink in _sinks:
		if sink.search(before):
			return true
	if _assign_re.search(before):
		for sink in _rhs_sinks:
			if sink.search(before):
				return true
	# A ternary branch inside a builder's argument is text too (a `+` there is as
	# likely to be a path as a word, so only `else` counts).
	if _builder_re.search(before) and _else_re.search(before):
		return true
	return false


## The string literals of one line, comments skipped: [{start, text}].
func _literals(line: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := 0
	while i < line.length():
		var c := line[i]
		if c == "#":
			break
		if c == "\"":
			var start := i
			i += 1
			var text := ""
			while i < line.length() and line[i] != "\"":
				if line[i] == "\\" and i + 1 < line.length():
					text += line[i]
					i += 1
				text += line[i]
				i += 1
			out.append({"start": start, "text": text})
		i += 1
	return out


func _fail(message: String) -> void:
	if _failures.size() < 200:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_i18n_lint: all checks passed")
	else:
		for f in _failures:
			printerr(f)
