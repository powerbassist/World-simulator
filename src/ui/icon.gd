extends RefCounted

## Loads an SVG glyph and rasterises it, tinted, at a given pixel size -- U5a, and since
## V5.1a the Material Symbols Rounded set under assets/icons/material.
##
## Deliberately **not** load("res://addons/.../x.svg"). That path returns the
## editor's imported CompressedTexture2D, which lives in .godot/ -- gitignored,
## and absent on a fresh clone until the editor has opened the project once.
## tools/run_tests.sh runs headless straight from the repo, so an icon loaded
## that way would be a hard failure in exactly the situation the .gitignore's
## import-cache exception exists to prevent. Reading the file as text and calling
## Image.load_svg_from_string() sidesteps the import system entirely.
##
## Rasterising at the size it will be drawn, rather than scaling a 16px texture
## up, is the other reason: these are 16x16 source files and the bottom bar
## wants them at 22.
##
## Recolouring is done in the SVG's own text before it is ever rasterised --
## cheaper and sharper than modulating a texture. Two families are understood: a
## file that names the old at-icons green is a string replace on that fill, and a
## file with no fill at all (Material Symbols draw in the default black) gets the
## tint as a fill on the root <svg>. The scale comes from the file's own width, so
## a 16-unit and a 24-unit source both land on the requested size.

const SOURCE_FILL := "#8eef97"

static var _width := RegEx.create_from_string("<svg[^>]*?\\swidth=\"(\\d+)\"")


static func load_icon(path: String, tint: Color, px: int) -> ImageTexture:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var svg := file.get_as_text()
	file.close()

	var hex := "#" + tint.to_html(false)
	if svg.contains(SOURCE_FILL):
		svg = svg.replace(SOURCE_FILL, hex)
	else:
		svg = svg.insert(svg.find("<svg ") + 5, "fill=\"%s\" " % hex)  # i18n: ok

	var native := 16.0
	var found := _width.search(svg)
	if found != null:
		native = float(found.get_string(1))

	var image := Image.new()
	# `native` is the file's own width attribute (its user units); scale is a multiplier, not a size.
	if image.load_svg_from_string(svg, float(px) / native) != OK:
		return null
	return ImageTexture.create_from_image(image)
