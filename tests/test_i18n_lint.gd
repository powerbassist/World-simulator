extends SceneTree

## Headless test: godot --headless --script res://tests/test_i18n_lint.gd
## Non-zero exit on any failure.
##
## V5.1b. A text a player reads goes through tr() -- by the CALLER: PanelKit and the
## other helpers never translate what they are handed, or a string would be
## translated twice and the lint could not tell a wrapped literal from a forgotten
## one. This fails on a bare English literal in src/ui in either of two ways, and
## says where.
##
## 1. AT A TEXT SINK (V5.1b): the sinks are known by their shape, so even a single
##    lowercase word is text there.
##
##      .text = "..."   tooltip_text = "..."   placeholder_text = "..."   .title = "..."
##        -- and on such a line the branches of a ternary (`else "..."`), a `+ "..."`
##        and the English default of `.get("key", "...")` too
##      PanelKit.<row builder>(...)   <windows>.register(id, "...")   add_item("...")
##      the settings/menu/action-bar builders (_add_row, _add_entry, add_cluster, the
##        drawer's _entry), and the message stack's push(title, body): the FIRST
##        argument and any argument after a comma, or an element of an array literal
##        -- never an index (`_columns["government"]` is a key, not text), a
##        dictionary key or a nested call's argument
##
## 2. ANYWHERE (V5.1b2): a literal that reads as prose -- it holds a space between
##    words, or is a capitalised word, or an all-capitals heading -- wherever it
##    stands: a return, an append, an argument, a continuation line, a var. A literal
##    that is a key or an id is never prose by this test (no space, lower case), and
##    these contexts are not text at all and are skipped: a comparison (`== "..."`),
##    `match`, a call that takes a name (`get_node`, `connect`, `has`, `get_meta`,
##    `begins_with` ...), a log call (`push_error`, `print`), a dictionary key.
##    A const cannot call tr(): keep the English in it, end the line `# i18n: msgid`
##    (tools/i18n_extract.py lists it) and wrap at the use site.
##
## It reads one line at a time. dev_*.gd (the developer console) and vendor/ are English
## by design. A line that holds a literal that is not prose to a player (a node name,
## a developer message) carries `# i18n: ok`; a marked const table carries
## `# i18n: msgid`.

const ROOT := "res://src/ui"
const OK_MARK := "# i18n: ok"
## Files with no text a player reads: grade.gd is a shader (its const holds GLSL, where
## an end-of-line marker would be code).
const NO_TEXT := ["grade.gd"]
const MSGID_MARK := "# i18n: msgid"
## Builders whose first argument is text, and builders whose first argument is an id
## (the drawer's _entry(id, label) and add_cluster(id, label, ...)): the lint reads
## every argument of the first kind and every one after the first of the second.
const TEXT_FIRST := r"(?:PanelKit\.\w+|_add_row|_add_entry|inbox\.push|_param_slider)"
## Helpers whose FIRST argument is text and the rest are ids, numbers or flags.
const FIRST_ONLY := r"(?:(?<![\w.])_line|(?<![\w.])_reading|(?<![\w.])_reading_lines|(?<![\w.])_out|(?<![\w.])_row|_queue_effect|_fiscal_committed|\.report)"
const ID_FIRST := r"(?:\.add_cluster|(?<![\w.])_entry)"
## What a literal is NOT text in: compared, matched, named, logged.
const NOT_TEXT := r"(?:(?:==|!=)\s*$|\b(?:match|in)\s*\[?\s*$|(?<![\w])(?:begins_with|ends_with|contains|find|rfind|has|has_all|get_meta|has_meta|set_meta|erase|find_child|get_node|get_node_or_null|has_node|connect|call|call_deferred|callv|emit_signal|add_to_group|is_in_group|get|get_theme_\w+|add_theme_\w+|has_theme_\w+|set_type_variation|split|replace|trim_prefix|trim_suffix|path_join|file_exists|open|is_action_pressed|is_action)\(\s*$|\b(?:push_error|push_warning|print|printerr|print_rich|assert|load|preload|StringName|NodePath|class_name)\(\s*$|(?:theme_type_variation|\.name|\.type|\.kind|\.mode)\s*=\s*$|\bextends\b)"

var _failures: Array[String] = []
var _text_re: RegEx
var _sinks: Array[RegEx] = []
var _assign_re: RegEx
var _rhs_sinks: Array[RegEx] = []
var _index_re: RegEx
var _builder_re: RegEx
var _else_re: RegEx
var _wrapped_re: RegEx
var _not_text_re: RegEx
var _prose_words_re: RegEx
var _placeholder_prose_re: RegEx
var _dash_prose_re: RegEx
var _unit_re: RegEx
var _float_re: RegEx
var _caps_re: RegEx
var _capitalised_re: RegEx
var _camel_re: RegEx
var _key_after_re: RegEx
var _const_re: RegEx
var _fragment_re: RegEx
var _split_plural_re: RegEx
var _format_arg_re: RegEx


func _init() -> void:
	_text_re = RegEx.create_from_string("[A-Za-z]{2,}")
	for pattern in [
		r"(?:\.text|tooltip_text|placeholder_text|\.title)\s*(?<![!<>=])=(?!=)\s*\(*\s*$",
		"(?:" + TEXT_FIRST + "|" + FIRST_ONLY + r")\(\s*$",
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
	# tr( / Strings.t( hold one literal; tr_n( / Strings.tn( hold the singular and the plural.
	_wrapped_re = RegEx.create_from_string(r"(?<![\w])(?:(?:tr|Strings\.t)\(|(?:tr_n|Strings\.tn)\((?:\"(?:[^\"\\]|\\.)*\"\s*,\s*)?)$")
	_not_text_re = RegEx.create_from_string(NOT_TEXT)
	# Prose: a space and a word of two letters or more anywhere (a lone unit or id has no
	# space). V5.1b3: it once wanted two such words side by side, and "A resignation",
	# "Answering a grievance." and " (you)" walked through. ...
	_prose_words_re = RegEx.create_from_string(r"^(?=.*\s)(?=.*[A-Za-z]{2,})")
	# ... an all-capitals heading, ...
	# A word and a placeholder with a space somewhere ("Saved '%s'.", "%d pending").
	_placeholder_prose_re = RegEx.create_from_string(r"^(?=.*%)(?=.*[A-Za-z]{3,})(?=.*\s).*$")
	# A dash and a word ("— clear", the figure a reading shows when nothing is wrong).
	_dash_prose_re = RegEx.create_from_string(r"^[—–\-·]\s*[A-Za-z]{3,}")
	# A placeholder and a unit word ("%d mo", "%.0f Bn", "%+.2f pts"): the unit is text.
	_unit_re = RegEx.create_from_string(r"%[-+#0]*\d*(?:\.\d+)?[dsf]\s?[A-Za-z]{2,}")
	# A float with decimals in a format string: the decimal separator is the language's, so
	# the figure goes through Num.f / Num.fs and the format keeps a %s.
	_float_re = RegEx.create_from_string(r"%[-+ #0]*\d*\.(?:[1-9]|\*)f")
	_caps_re = RegEx.create_from_string(r"^[A-Z][A-Z'\-]{4,}$")
	# ... or one capitalised word.
	_capitalised_re = RegEx.create_from_string(r"^[A-Z][a-z]{3,}[.:!?]?$")
	_camel_re = RegEx.create_from_string(r"[a-z][A-Z]")
	_key_after_re = RegEx.create_from_string(r"^\s*:")
	# A ternary of two SHORT literals with no placeholder in either ("Raises" if up else
	# "Lowers"), wrapped or not: a fragment to be spliced into a sentence.
	_fragment_re = RegEx.create_from_string(r"(?:(?:tr|Strings\.t)\()?\"([^\"%]{1,30})\"\)?\s+if\s+[^\"]+?\s+else\s+\(?(?:(?:tr|Strings\.t)\()?\"([^\"%]{1,30})\"")
	# ... inside the argument of a format operator: `"..." % [` or `) % (` on this line or
	# at the end of the line before.
	_format_arg_re = RegEx.create_from_string(r"[\"\)]\s*%\s*[\[\(]")
	# tr_n( / Strings.tn( whose plural literal is not on the same line as the singular: the
	# extractor reads one line at a time and would list the msgid with no plural.
	_split_plural_re = RegEx.create_from_string(r"(?<![\w])(?:tr_n|Strings\.tn)\(\s*\"(?:[^\"\\]|\\.)*\"\s*,(?!\s*\")")
	_const_re = RegEx.create_from_string(r"^(?:const|static var|enum)\b")
	_self_check()
	var names := Array(DirAccess.get_files_at(ROOT))
	names.sort()
	var scanned := 0
	for name in names:
		if not String(name).ends_with(".gd") or String(name).begins_with("dev_") or name in NO_TEXT:
			continue
		scanned += 1
		_scan("%s/%s" % [ROOT, name])
	if scanned < 80:
		_fail("only %d files scanned under %s" % [scanned, ROOT])
	_finish()
	quit(1 if not _failures.is_empty() else 0)


func _scan(path: String) -> void:
	var number := 0
	var is_const := false
	var previous := ""
	for line in FileAccess.get_file_as_string(path).split("
"):
		number += 1
		# Inside a class-level const / static var / enum -- its first line and every
		# line until the next unindented one -- a tr() call is not allowed.
		if _const_re.search(line):
			is_const = true
		elif line != "" and not line.begins_with("#") and not line[0] in [" ", "	", ")", "]", "}"]:
			is_const = false
		for message in _check_line(line, is_const, previous):
			_fail("%s:%d: %s" % [path.get_file(), number, message])
		previous = line


## The complaints one line earns.
func _check_line(line: String, is_const: bool, previous := "") -> Array[String]:
	var out: Array[String] = []
	if line.strip_edges().begins_with("#") or line.contains(OK_MARK) or line.contains(MSGID_MARK):
		return out
	if _split_plural_re.search(line):
		out.append("tr_n / Strings.tn: singular and plural literals on one line (the extractor reads one line at a time)")
	# A fragment spliced into a sentence cannot be translated: make the sentence whole
	# (one per branch, or tr_n for a count).
	if _fragment_re.search(line) and (_format_arg_re.search(line) or _format_arg_re.search(previous.strip_edges().right(8))):
		out.append("a ternary of short fragments inside a format argument: write a whole sentence per branch (tr_n for a count)")
	for literal in _literals(line):
		var text: String = literal["text"]
		if _float_re.search(text) and not _not_text_re.search(line.substr(0, literal["start"])):
			out.append("raw %%.Nf: route the figure through Num.f / Num.fs and keep a %%s in the format (the decimal separator is the language's): \"%s\"" % text)
		if not _text_re.search(text):
			continue
		var before: String = line.substr(0, literal["start"])
		if _is_sink(before):
			out.append("bare literal at a text sink, wrap it in tr(): \"%s\"" % text)
		elif _is_prose_anywhere(text, before, line.substr(int(literal["end"]) + 1), line):
			if is_const:
				out.append("prose in a const, end the line `# i18n: msgid` and wrap at the use site: \"%s\"" % text)
			else:
				out.append("bare prose literal, wrap it in tr(): \"%s\"" % text)
	return out


## The lint's own shapes, pinned: a regex that silently stopped matching (an escape
## eaten on the way into the file did it once) would otherwise read as a clean tree.
func _self_check() -> void:
	var flagged := {
		"label.text = \"Hello\"": 1,
		"label.text = \"Hello world\"": 1,
		"tip.tooltip_text = x if y else \"closed\"": 1,
		"_hud.inbox.push(\"Your term\", body)": 1,
		"_entry(\"overview\", \"Overview\")": 1,
		"PanelKit.line(_body, \"no deadline yet\")": 1,
		"return \"no deadline\"": 1,
		"return \"Raises\"": 1,
		"parts.append(\"%d months left\" % n)": 1,
		"text = \"Saved '%s'.\"": 1,
		"var text := \"— clear\"": 1,
		"var text := cond if a else \"other thing\"": 1,
		"x.text = d.get(\"k\", \"Unknown\")": 1,
		"_line(tip, \"coalition\")": 0,
		"_line(\"Surplus\", \"coalition\")": 1,
		"\"A sentence of prose\" + x": 1,
		"x = \"%.2f\" % v": 1,
		"x = tr(\"Rate %+.1f%%\") % v": 1,
		"x = \"%5.1f\" % v": 1,
		"x = \"%.*f\" % [places, v]": 1,
		"return tr(\"%s the press laws.\") % (tr(\"Loosens\") if up else tr(\"Tightens\"))": 1,
		# V5.1b3: prose whose words alternate with one-letter ones (no two 2+-letter
		# words side by side) escaped the old test -- 42 sites at #37's head.
		"title = \"A resignation\"": 1,
		"K.KIND_LAW: \"Propose a law\",": 1,
		"ForeignPolicy.ACT_REASON_GRIEVANCE: return \"Answering a grievance.\"": 1,
		"\"three_fifths\": return \"3/5 majority\"": 1,
		"var mark := \" (you)\" if is_viewer(a, b) else \"\"": 1,
		"return \"1 month\"": 1,
		"		tr(\"Raises\") if v > 0.0 else tr(\"Lowers\"), absf(v)])": 0,
	}
	var clean := [
		"label.text = tr(\"Hello world\")",
		"label.text = Strings.t(\"Hello world\")",
		"x = tr(\"Rate %s%%\") % Num.f(v, 1)",
		"x = \"%.0f\" % v",
		"push_error(\"bad %.2f\" % v)",
		"label.text = tr(\"Leave office\") if defeated else tr(\"Continue\")",
		"b.text = (tr(\"Put first: %s\") if chairing else tr(\"Table: %s\")) % name",
		"return tr_n(\"%d month left\", \"%d months left\", n) % n",
		"x = tr_n(\"%d day\", \"%d days\", n) % [n, y]",
		"x = Strings.tn(\"%d day\", \"%d days\", n) % n",
		"PanelKit.figure(_columns[\"government\"], tr(\"x\"))",
		"if kind == \"Not available\":",
		"x = dict[\"Some key\"]",
		"var n = get_node(\"Main Panel\")",
		"push_error(\"Something went wrong\")",
		"\"seats\": 1,",
		"theme.set_type_variation(x, \"Label\")  # i18n: ok",
		"for t in [\"a\", \"b\"]:",
		"var cid := \"room:\" + org.id",
		"match kind:",
		"\"ordinary_law\": return tr(\"ordinary majority\")",
	]
	for line in flagged:
		var got := _check_line(line, false).size()
		if got != int(flagged[line]) and not (int(flagged[line]) == 1 and got >= 1):
			_fail("self-check: `%s` should be flagged %d time(s), was %d" % [line, flagged[line], got])
	for line in clean:
		if not _check_line(line, false).is_empty():
			_fail("self-check: `%s` should be clean, was flagged" % line)
	if _check_line("x = tr_n(\"%d day\",", false).is_empty():
		_fail("self-check: a plural split across lines should be flagged")
	# A fragment ternary on the line AFTER a format operator is the same defect.
	if _check_line("		tr(\"Raises\") if v > 0.0 else tr(\"Lowers\"), absf(v)])", false, "out.append(tr(\"%s %.1f.\") % [").is_empty():
		_fail("self-check: a fragment ternary inside a format argument list should be flagged")
	if _check_line("const NAMES := [\"Alpha Beta\"]", true).is_empty():
		_fail("self-check: prose in a const should be flagged")
	if not _check_line("const NAMES := [\"Alpha Beta\"]  # i18n: msgid", true).is_empty():
		_fail("self-check: a marked const line should be clean")


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


## Whether a literal that is not at a known sink still reads as prose (see the header).
func _is_prose_anywhere(text: String, before: String, after: String, line: String) -> bool:
	if _wrapped_re.search(before) or _index_re.search(before) or _not_text_re.search(before):
		return false
	# A dictionary key, or the pattern line of a match branch.
	if _key_after_re.search(after):
		return false
	if line.strip_edges().begins_with("\"") and line.strip_edges().ends_with(":") and before.strip_edges() == "":
		return false
	# A literal that is the right of `in`/`==` further along is a comparison.
	if _camel_re.search(text) and not text.contains(" "):
		return false
	if _prose_words_re.search(text) or _placeholder_prose_re.search(text) or _dash_prose_re.search(text) or _unit_re.search(text) or _caps_re.search(text) or _capitalised_re.search(text):
		return true
	return false


## The string literals of one line, comments skipped: [{start, end, text}].
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
			out.append({"start": start, "end": i, "text": text})
		i += 1
	return out


func _fail(message: String) -> void:
	if _failures.size() < 1500:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_i18n_lint: all checks passed")
	else:
		print("%d literals" % _failures.size())
		for f in _failures:
			printerr(f)
