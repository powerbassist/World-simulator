extends SceneTree

## V2.3 portrait recipe, duotone half. Run headless from the repo root:
##
##   godot --headless --script res://tools/portraits.gd
##
## Reads the raw photoreal generations from sources/portraits/raw/ (produced by
## tools/portraits_generate.py against a running ComfyUI), imposes the ONE look
## every portrait shares, and writes the committed assets to
## assets/portraits/<person_id>.png, each with a committed .import carrying
## importer="keep" -- the Blue Marble's rule, so the editor never spends an
## import pass on files nothing load()s.
##
## The look, and why it lives here rather than at generation: "navy shadows,
## brass highlights, one crop, one eyeline" is what stops a wall of generated
## photographs reading as stock pasted into a HUD (docs/tiers/v2.md §3). The
## generation prompt fixes the framing and the lighting; this pass is what
## actually unifies -- a posterized duotone on the theme's own three colours,
## the same crop rectangle and the same output size for every person, so any
## drift in the raw outputs is erased rather than shipped.
##
## Determinism: crop, resize, tone map and PNG encode are pure functions of the
## input bytes, so re-running over the same raws reproduces the same assets.
##
## Coverage, printed rather than enforced: a person with no raw portrait is
## BY DESIGN not an error -- the game falls back to the silhouette
## (src/ui/portrait.gd), which is what lets a session author a person before
## the art run catches up. A raw file nobody references IS worth refusing: that
## is stale art, the orphan precedent pointed at assets.

const DataLoader = preload("res://src/core/data_loader.gd")

const RAW_DIR := "res://sources/portraits/raw"
const OUT_DIR := "res://assets/portraits"
const CONTACT_PATH := "res://sources/portraits/contact.png"

## Source frames are 832x1216 (the workflow's EmptyLatentImage). The crop takes
## the full width and the upper 1140px -- 216:296's aspect -- starting below a
## small top margin, which lands the eyeline at a consistent height for the
## workflow's fixed head-and-shoulders prompt. Tuned against the contact sheet,
## not from taste.
const SOURCE_FRAME := Vector2i(832, 1216)
const CROP := Rect2i(0, 48, 832, 1140)
const OUT_W := 216
const OUT_H := 296

## The theme's duotone: INK in the shadows, SLATE in the midtones, brass at the
## top of the ramp -- the plate's own three colours, so a portrait reads as part
## of the HUD rather than sitting on it. Posterized to LEVELS steps: fewer
## gradient bands is both the look and a smaller committed PNG.
const INK := Color(0.039, 0.063, 0.125)
const SLATE := Color(0.106, 0.173, 0.290)
const ACCENT := Color(0.788, 0.635, 0.153)
const MIDPOINT := 0.55
const CONTRAST := 1.35
## Judged against the contact sheet, not taste: studio lighting leaves the jaw
## and mouth in the bottom fifth of the ramp, and at the card's 54x74 those are
## the first features to merge into the INK plate behind them. A small pre-ramp
## lift recovers them without washing out the shadows that make it a duotone.
const LIFT := 0.06
const LEVELS := 12


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		for e in loader.errors:
			printerr("load error: %s" % e)
		quit(1)
		return

	var raw_files: Array[String] = []
	for f in DirAccess.get_files_at(RAW_DIR):
		if f.ends_with(".png"):
			raw_files.append(f)

	var stale: Array[String] = []
	for f in raw_files:
		if not loader.person_by_id.has(f.get_basename()):
			stale.append(f)
	if not stale.is_empty():
		for f in stale:
			printerr("FAIL: raw portrait '%s' belongs to no person in the register" % f)
		quit(1)
		return

	var missing := 0
	for pid in loader.person_by_id:
		if not raw_files.has(pid + ".png"):
			missing += 1

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var thumbs: Array[Image] = []
	var bytes_total := 0
	for f in raw_files:
		var img := _load_raw(RAW_DIR.path_join(f))
		if img == null:
			quit(1)
			return
		var portrait := img.get_region(CROP)
		portrait.resize(OUT_W, OUT_H, Image.INTERPOLATE_LANCZOS)
		_tone_map(portrait)
		var out_path := OUT_DIR.path_join(f)
		var err := portrait.save_png(out_path)
		if err != OK:
			printerr("FAIL: could not write %s" % out_path)
			quit(1)
			return
		_write_keep_import(out_path)
		bytes_total += FileAccess.get_file_as_bytes(out_path).size()
		var thumb := portrait.duplicate()
		thumb.resize(OUT_W / 2, OUT_H / 2, Image.INTERPOLATE_LANCZOS)
		thumbs.append(thumb)

	_write_contact_sheet(thumbs)
	print("portraits: %d written (%.1f KB total), %d register people without art (falls back to the silhouette), largest single file %.1f KB"
		% [thumbs.size(), bytes_total / 1024.0, missing,
		   _largest_kb(OUT_DIR)])
	quit(0)


func _load_raw(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		printerr("FAIL: could not read %s" % path)
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		printerr("FAIL: %s is not a decodable PNG" % path)
		return null
	if img.get_size() != SOURCE_FRAME:
		printerr("FAIL: %s is %s, expected the workflow's %s frame" % [path, img.get_size(), SOURCE_FRAME])
		return null
	return img


## The tone map is applied after the resize, on the final pixels: posterizing
## after downscale keeps the bands the eye will actually see.
func _tone_map(img: Image) -> void:
	for y in OUT_H:
		for x in OUT_W:
			var c := img.get_pixel(x, y)
			var t := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			t = clampf((t - 0.5) * CONTRAST + 0.5 + LIFT, 0.0, 1.0)
			t = minf(floorf(t * LEVELS), LEVELS - 1) / float(LEVELS - 1)
			var out := _ramp(t)
			out.a = c.a
			img.set_pixel(x, y, out)


func _ramp(t: float) -> Color:
	if t <= MIDPOINT:
		return INK.lerp(SLATE, t / MIDPOINT)
	return SLATE.lerp(ACCENT, (t - MIDPOINT) / (1.0 - MIDPOINT))


func _write_keep_import(png_path: String) -> void:
	var import_path := png_path + ".import"
	var file := FileAccess.open(import_path, FileAccess.WRITE)
	file.store_string("[remap]\n\nimporter=\"keep\"\n\n[deps]\n\nsource_file=\"%s\"\n" % png_path)
	file.close()


func _write_contact_sheet(thumbs: Array[Image]) -> void:
	var cols := 10
	var rows := ceili(thumbs.size() / float(cols))
	var tw := OUT_W / 2
	var th := OUT_H / 2
	var sheet := Image.create_empty(cols * tw, rows * th, false, thumbs[0].get_format())
	sheet.fill(INK)
	for i in thumbs.size():
		var pos := Vector2i((i % cols) * tw, (i / cols) * th)
		sheet.blit_rect(thumbs[i], Rect2i(Vector2i.ZERO, Vector2i(tw, th)), pos)
	sheet.save_png(CONTACT_PATH)


func _largest_kb(dir_path: String) -> float:
	var largest := 0
	for f in DirAccess.get_files_at(dir_path):
		if f.ends_with(".png"):
			largest = maxi(largest, FileAccess.get_file_as_bytes(dir_path.path_join(f)).size())
	return largest / 1024.0
