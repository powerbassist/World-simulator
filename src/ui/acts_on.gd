extends RefCounted

## V5.3-0, band RF3 (docs/design/v5.3-0-readability.md 2.4): every briefing "Go"
## lands on a control that acts on its priority. A control says what it acts on
## with a meta tag, `acts_on`, holding the subject ids the ranking emits
## (priorities.gd: a law id, a bloc key, "seats", "deficit", an event id, a
## request id, a programme entry id, a person id, "unrest").
##
## An Array rather than one id: a Propose button under the bloc filter acts on
## the law AND on the bloc the filter is for. tests/test_briefing_go.gd reads the
## tags through find() -- a Go whose tab carries no enabled tagged control is the
## dead end the band exists to catch.

const META := &"acts_on"


## Adds `subjects` to the control's tags and returns the control, so a builder
## can tag inline.
static func tag(control: Control, subjects: Array) -> Control:
	var have: Array = control.get_meta(META, [])
	for s in subjects:
		if not have.has(String(s)):
			have.append(String(s))
	control.set_meta(META, have)
	return control


static func acts_on(control: Node, subject: String) -> bool:
	return (control.get_meta(META, []) as Array).has(subject)


## The first control under `root` that is shown, enabled and tagged with
## `subject`, or null.
static func find(root: Node, subject: String) -> Control:
	for child in root.get_children():
		if child is Control and not (child as Control).visible:
			continue
		if child is Control and acts_on(child, subject) and not (child is BaseButton and (child as BaseButton).disabled) \
				and not (child is Range and not (child as Range).editable):
			return child
		var below := find(child, subject)
		if below != null:
			return below
	return null
