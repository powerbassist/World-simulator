extends SceneTree

## V3.7 portrait recipe, Godot half. Run headless from the repo root:
##
##   godot --headless --script res://tools/portraits.gd
##
## Reads the raw photoreal generations (produced by tools/portraits_generate.py
## and tools/backgrounds_generate.py against a running ComfyUI), imposes the
## ONE frame every portrait shares, and writes the committed assets:
##
##   assets/portraits/<emotion>/<person_id>.webp   432x592, alpha from matting
##   assets/portrait_scenes/<scene>_<n>.webp       432x632 backdrops
##
## each with a committed .import carrying importer="keep" -- the Blue Marble's
## rule, so the editor never spends an import pass on files nothing load()s.
## The extension changed at V3.7 (duotone PNG -> WebP q90 with alpha) and the
## rule did not.
##
## The look changed at V3.7 and the reason is worth keeping: the V2.3 duotone
## ramp existed to stop a wall of generated photographs reading as stock
## pasted into a HUD. The author retired it -- realism is the look -- and the
## unifying work moves to what this pass still does: one crop rectangle, one
## eyeline, one output size for every person, and matting masks turned into
## real alpha, so the game can composite a room BEHIND a head instead of
## painting a nation-hue band around it (the band is gone; a photographic
## scene library took its place).
##
## Determinism: crop, resize, mask compose and WebP encode are pure functions
## of the input bytes, so re-running over the same raws reproduces the same
## assets. The alpha compose writes the mask's bytes straight into the RGBA
## packed array rather than per-pixel -- 1065 busts is too many for a
## per-pixel walk in GDScript, and the byte path is exact either way.
##
## Coverage, printed rather than enforced: a person with no raw portrait is
## BY DESIGN not an error -- the game falls back to the silhouette
## (src/ui/portrait.gd), which is what lets a session author a person before
## the art run catches up. The V2.3 flat layout (sources/portraits/raw/*.png)
## is ignored by design -- superseded by the per-emotion layout. A raw under
## an emotion dir that nobody references IS worth refusing: that is stale
## art, the orphan precedent pointed at assets.

const DataLoader = preload("res://src/core/data_loader.gd")

const RAW_ROOT := "res://sources/portraits/raw"
const MASK_ROOT := "res://sources/portraits/mask"
const SCENE_RAW_DIR := "res://sources/backgrounds/raw"
const OUT_DIR := "res://assets/portraits"
const SCENE_OUT_DIR := "res://assets/portrait_scenes"

## Source frames are 832x1216 (the workflow's EmptyLatentImage). The crop takes
## the full width and the upper 1140px -- 432:592's aspect -- starting below a
## small top margin, which lands the eyeline at a consistent height for the
## workflow's fixed head-and-shoulders prompt. Tuned against the V2.3 contact
## sheet, not from taste -- the frame is not re-opened by the look change.
const SOURCE_FRAME := Vector2i(832, 1216)
const CROP := Rect2i(0, 48, 832, 1140)
const OUT_W := 432
const OUT_H := 592
## Backdrops resize the FULL frame, never the portrait crop -- the portrait's
## crop would stretch them 6.8 % vertically (832x1140 into a 432:632 box).
## 432x632 keeps the source's own aspect (832:1216); the display's COVER crop
## takes the half-dozen pixels of difference.
const SCENE_OUT_W := 432
const SCENE_OUT_H := 632

const EMOTIONS := ["neutral", "pleased", "stern", "worried", "weary"]

## The sheets are how the author judged the first wall (and rejected it); they
## stay the Phase B gate, now in colour: one per emotion, plus a five-across
## strip for ten people so the expression RANGE is reviewable at a glance.
const CONTACT_DIR := "res://sources/portraits"


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		for e in loader.errors:
			printerr("load error: %s" % e)
		quit(1)
		return

	var written := 0
	var bytes_total := 0
	var per_emotion := {}  # emotion -> Array[Image] thumbs, for the sheets
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for emotion in EMOTIONS:
		DirAccess.make_dir_recursive_absolute(OUT_DIR.path_join(emotion))
		if not DirAccess.dir_exists_absolute(RAW_ROOT.path_join(emotion)):
			per_emotion[emotion] = []
			continue  # the whole of Phase A: no art exists yet, keep the tool runnable
		var raws := _emotion_raws(emotion)
		var thumbs: Array[Image] = []
		for pid in raws:
			if not loader.person_by_id.has(pid):
				printerr("FAIL: raw portrait '%s/%s' belongs to no person in the register" % [emotion, pid])
				quit(1)
				return
			var img := _load_frame(RAW_ROOT.path_join(emotion).path_join(pid + ".png"))
			if img == null:
				quit(1)
				return
			var mask := _load_frame(MASK_ROOT.path_join(emotion).path_join(pid + ".png"))
			if mask == null:
				quit(1)
				return
			var bust := _crop_and_resize(img)
			bust = _compose_alpha(bust, _crop_and_resize(mask))
			var out_path := OUT_DIR.path_join(emotion).path_join(pid + ".webp")
			# lossy=TRUE is the lossy encoder; false encodes lossless and
			# ignores quality -- pinned by size comparison, after a first
			# reading of the signature had it inverted (the review's P0).
			var err := bust.save_webp(out_path, true, 0.90)
			if err != OK:
				printerr("FAIL: could not write %s (%d)" % [out_path, err])
				quit(1)
				return
			_write_keep_import(out_path)
			written += 1
			bytes_total += FileAccess.get_file_as_bytes(out_path).size()
			thumbs.append(bust)
		per_emotion[emotion] = thumbs

	DirAccess.make_dir_recursive_absolute(SCENE_OUT_DIR)
	var scenes := 0
	if DirAccess.dir_exists_absolute(SCENE_RAW_DIR):
		for f in DirAccess.get_files_at(SCENE_RAW_DIR):
			if not f.ends_with(".png"):
				continue
			var img := _load_frame(SCENE_RAW_DIR.path_join(f))
			if img == null:
				quit(1)
				return
			var backdrop: Image = img.duplicate()
			backdrop.resize(SCENE_OUT_W, SCENE_OUT_H, Image.INTERPOLATE_LANCZOS)
			var out_path := SCENE_OUT_DIR.path_join(f.get_basename() + ".webp")
			if backdrop.save_webp(out_path, true, 0.90) != OK:
				printerr("FAIL: could not write %s" % out_path)
				quit(1)
				return
			_write_keep_import(out_path)
			scenes += 1
			bytes_total += FileAccess.get_file_as_bytes(out_path).size()

	if written > 0:
		_write_sheets(per_emotion, loader)

	var missing := 0
	for pid in loader.person_by_id:
		if not FileAccess.file_exists(OUT_DIR.path_join("neutral").path_join(pid + ".webp")):
			missing += 1
	print("portraits: %d busts (%d without neutral art, falls back to the silhouette), %d backdrops, %.1f MB total, largest single file %.1f KB"
		% [written, missing, scenes, bytes_total / 1048576.0, _largest_kb(OUT_DIR)])
	quit(0)


## emotion -> {person_id: true}, only ids with BOTH a raw and a mask present.
func _emotion_raws(emotion: String) -> Dictionary:
	var found := {}
	var raw_dir := RAW_ROOT.path_join(emotion)
	var mask_dir := MASK_ROOT.path_join(emotion)
	for f in DirAccess.get_files_at(raw_dir):
		if f.ends_with(".png") and FileAccess.file_exists(mask_dir.path_join(f)):
			found[f.get_basename()] = true
		elif f.ends_with(".png"):
			printerr("FAIL: raw '%s/%s' has no matching mask -- the generation pass writes them as a pair" % [emotion, f])
			quit(1)
	return found


func _load_frame(path: String) -> Image:
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


func _crop_and_resize(img: Image) -> Image:
	var out := img.get_region(CROP)
	out.resize(OUT_W, OUT_H, Image.INTERPOLATE_LANCZOS)
	return out


## The mask (white = person) becomes the bust's alpha: its L8 bytes written
## straight into the RGBA packed array, one byte in four -- the fast path the
## header comment owes to 1065 busts. Returns the composed image.
func _compose_alpha(bust: Image, mask: Image) -> Image:
	var m: Image = mask.duplicate()
	m.convert(Image.FORMAT_L8)
	var rgba: Image = bust.duplicate()
	rgba.convert(Image.FORMAT_RGBA8)
	var px := rgba.get_data()
	var ma := m.get_data()
	var count := OUT_W * OUT_H
	for i in count:
		px[i * 4 + 3] = ma[i]
	return Image.create_from_data(OUT_W, OUT_H, false, Image.FORMAT_RGBA8, px)


func _write_sheets(per_emotion: Dictionary, loader) -> void:
	var tw := OUT_W / 2
	var th := OUT_H / 2
	var ground := Color(0.055, 0.075, 0.13)
	for emotion in EMOTIONS:
		var thumbs: Array = per_emotion[emotion]
		if thumbs.is_empty():
			continue
		var cols := 10
		var rows := ceili(thumbs.size() / float(cols))
		var sheet := Image.create_empty(cols * tw, rows * th, false, Image.FORMAT_RGBA8)
		sheet.fill(ground)
		for i in thumbs.size():
			var thumb: Image = thumbs[i]
			thumb.resize(tw, th, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(thumb, Rect2i(Vector2i.ZERO, Vector2i(tw, th)),
				Vector2i((i % cols) * tw, (i / cols) * th))
		sheet.save_png(CONTACT_DIR.path_join("contact_%s.png" % emotion))

	# The expression strip: the first ten register ids in sorted order, one row
	# each, five emotions across.
	var ids: Array[String] = []
	for pid in loader.person_by_id:
		ids.append(pid)
	ids.sort()
	ids = ids.slice(0, mini(10, ids.size()))
	var strip := Image.create_empty(EMOTIONS.size() * tw, ids.size() * th, false, Image.FORMAT_RGBA8)
	strip.fill(ground)
	for r in ids.size():
		for c in EMOTIONS.size():
			var path := OUT_DIR.path_join(EMOTIONS[c]).path_join(ids[r] + ".webp")
			if not FileAccess.file_exists(path):
				continue
			var img := Image.new()
			if img.load_webp_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
				continue
			img.resize(tw, th, Image.INTERPOLATE_LANCZOS)
			strip.blit_rect(img, Rect2i(Vector2i.ZERO, Vector2i(tw, th)), Vector2i(c * tw, r * th))
	strip.save_png(CONTACT_DIR.path_join("expressions_strip.png"))


func _write_keep_import(asset_path: String) -> void:
	var import_path := asset_path + ".import"
	var file := FileAccess.open(import_path, FileAccess.WRITE)
	file.store_string("[remap]\n\nimporter=\"keep\"\n\n[deps]\n\nsource_file=\"%s\"\n" % asset_path)
	file.close()


func _largest_kb(dir_path: String) -> float:
	var largest := 0
	for emotion in EMOTIONS:
		var sub := dir_path.path_join(emotion)
		if not DirAccess.dir_exists_absolute(sub):
			continue
		for f in DirAccess.get_files_at(sub):
			if f.ends_with(".webp"):
				largest = maxi(largest, FileAccess.get_file_as_bytes(sub.path_join(f)).size())
	return largest / 1024.0
