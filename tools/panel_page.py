"""A panel_dump.gd capture as a static HTML page where a comment leads to the code.

    python tools/panel_page.py DIR/books.json --out PAGE_DIR --state "Books, France, January" --commit <sha>
    python tools/panel_page.py --selftest

Every Control is one absolutely positioned element, in draw order, whose opening tag carries
`id`, `data-comment-target`, `data-script` and `data-node`: a comment on a published copy
quotes that tag, read from the page SOURCE, so nothing here is built by a script.

Text and flat boxes are redrawn from the dump's theme values over the bare frame (the capture
without them). What Godot draws itself (custom draw, shader, image, slider, rich text) is game
pixels: a window cut out of the full frame where nothing redrawn lies on top of it, and the
bare frame underneath otherwise. The "Game frame" box swaps the rebuild for the real capture.

Dev-only, never shipped. Publish PAGE_DIR/index.html with the other files of PAGE_DIR.
"""
import argparse
import html
import json
import shutil
import sys
from pathlib import Path

FONT = Path(__file__).resolve().parent.parent / "assets" / "fonts" / "Archivo-Variable.ttf"
ALIGN = ["left", "center", "right", "justify"]
VALIGN = ["flex-start", "center", "flex-end", "flex-start"]
# The share of a game-drawn node that redrawn nodes may cover and it still be cut from the frame:
# a sidebar row's badge is 8 %, the top strip's figures about 30 %.
COVER_LIMIT = 0.1

CSS = """@font-face{font-family:Archivo;src:url(Archivo-Variable.ttf);font-weight:100 900;font-stretch:62%% 125%%}
body{margin:0;background:#111;color:#ddd;font:14px Archivo,sans-serif}
header,table{margin:8px}label{margin-right:12px}.scroll{overflow-x:auto}
#stage{position:relative;overflow:hidden;width:%(w)dpx;height:%(h)dpx;background:url(%(bare)s) no-repeat;text-align:left}
.n{position:absolute;box-sizing:border-box;margin:0;border:0 solid transparent;font-kerning:normal}
.n:hover{outline:2px solid #f0f;outline-offset:-1px}.pass{pointer-events:none}
.t{position:absolute;display:flex;flex-direction:column}
#z50:checked~.scroll #stage{zoom:.5}#z75:checked~.scroll #stage{zoom:.75}
#game:checked~.scroll #stage{background-image:url(%(frame)s)}
#game:checked~.scroll .n,#game:checked~.scroll .n *{background:none!important;border-color:transparent!important;
box-shadow:none!important;color:transparent!important}
table{border-collapse:collapse;font-size:12px}td{border-top:1px solid #333;padding:2px 8px;vertical-align:top}"""


def px(value):
    return "%gpx" % round(value, 2)


def sides(values):
    return " ".join(px(v) for v in values)


def visible(colour):
    return bool(colour) and not colour.endswith(",0.000)")


def paints_box(box):
    return bool(box) and (visible(box["bg"]) or (any(box["widths"]) and visible(box["border"]))
                          or (box.get("shadow", {}).get("size", 0) > 0 and visible(box["shadow"]["color"])))


def redrawn(node):
    """True when the page itself puts pixels on the stage for this node, as text or a box."""
    return node["rebuilt"] and (bool(node["text"]) or paints_box(node.get("box")))


def game_drawn(node):
    """True when Godot draws something here that the page does not redraw."""
    plain = node["class"] == "Control" or node["class"].endswith("Container")
    return not node["rebuilt"] and (node["custom_draw"] or node["material"] or node["image"] or not plain)


def overlap(a, b):
    return (max(0, min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]))
            * max(0, min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])))


def crops(ordered):
    """Indices (in draw order) that can be cut out of the full frame: a game-drawn node that
    redrawn nodes painted later barely cover, since the cut carries their pixels too and they
    land a second time. A badge on a sidebar row is fine; a panel of text over the map is not,
    so that node stays in the bare frame, under whatever the page redraws above it."""
    return {i for i, node in enumerate(ordered)
            if game_drawn(node) and not node["behind"]
            and sum(overlap(node["clip"], later["clip"]) for later in ordered[i + 1:] if redrawn(later))
            <= COVER_LIMIT * node["clip"][2] * node["clip"][3]}


def element(ident, node, crop, frame):
    x, y, w, h = node["rect"]
    style = ["left:" + px(x), "top:" + px(y), "width:" + px(w), "height:" + px(h)]
    cx, cy, cw, ch = node["clip"]
    cut = [cy - y, x + w - cx - cw, y + h - cy - ch, cx - x]
    if any(v > 0.5 for v in cut):
        style.append("clip-path:inset(%s)" % sides(max(v, 0) for v in cut))
    box = node.get("box") if node["rebuilt"] else None
    widths = box["widths"] if box else [0, 0, 0, 0]
    inner = ""
    if crop:
        style.append("background:url(%s) %s %s no-repeat" % (frame, px(-x), px(-y)))
    else:
        if node["alpha"] < 0.999:
            style.append("opacity:%g" % round(node["alpha"], 3))
        if box:
            if visible(box["bg"]):
                style.append("background:" + box["bg"])
            if any(widths):
                style += ["border-width:" + sides(widths), "border-color:" + box["border"]]
            if any(box["radii"]):
                style.append("border-radius:" + sides(box["radii"]))
            shadow = box.get("shadow", {})
            if shadow.get("size", 0) > 0 and visible(shadow["color"]):
                style.append("box-shadow:%s %s %s %s" % (px(shadow["x"]), px(shadow["y"]), px(shadow["size"]), shadow["color"]))
        if node["rebuilt"] and node["text"]:
            inner = text_span(node, box["pad"] if box else [0, 0, 0, 0], widths)
    hit = crop or redrawn(node) or (game_drawn(node) or node["custom_draw"]) and not node["behind"]
    title = " · ".join(p for p in (ident, node["script"].rsplit("/", 1)[-1] or node["class"], node["text"][:80]) if p)
    # The four attributes come first: a comment thread quotes the opening tag, and paths run long.
    return '<div id="%s" data-comment-target data-script="%s" data-node="%s" class="n%s" title="%s" style="%s">%s</div>' % (
        ident, html.escape(node["script"]), html.escape(node["path"]), "" if hit else " pass",
        html.escape(" ".join(title.split())), html.escape(";".join(style)), inner)


def text_span(node, pad, widths):
    outer = ["%s:%s" % (side, px(pad[i] - widths[i])) for i, side in enumerate(("top", "right", "bottom", "left"))]
    button = "valign" not in node
    outer.append("justify-content:" + VALIGN[1 if button else node["valign"]])
    style = ["color:" + node["color"], "font-size:" + px(node["font_px"]), "line-height:" + px(node["line_px"]),
             "text-align:" + ALIGN[node.get("align", 0)], "white-space:" + ("pre-wrap" if node.get("wrap") else "pre")]
    if "weight" in node:
        style.append("font-variation-settings:'wght' %g,'wdth' %g" % (node["weight"], node["width_axis"]))
    if node.get("spacing_px"):
        style.append("letter-spacing:" + px(node["spacing_px"]))
    if node.get("tabular"):
        style.append("font-variant-numeric:tabular-nums")
    if node.get("trim"):
        style.append("overflow:hidden;text-overflow:ellipsis")
    return '<span class="t" style="%s"><span style="%s">%s</span></span>' % (
        ";".join(outer), html.escape(";".join(style)), html.escape(node["text"]))


def page(dump, prefix, state, commit):
    numbered = [("%s%d" % (prefix, i + 1), node) for i, node in enumerate(dump["nodes"])]
    # Godot draws by canvas layer, then z, then tree order; sorted() keeps the tree order.
    numbered = sorted(numbered, key=lambda pair: (pair[1]["layer"], pair[1]["z"]))
    cut = crops([node for _, node in numbered])
    frame, bare = html.escape(dump["frame"]), html.escape(dump["bare"])
    out = ['<!doctype html><meta charset="utf-8"><title>Panel critique: %s</title>' % html.escape(state),
           "<style>%s</style>" % (CSS % {"w": dump["width"], "h": dump["height"], "frame": frame, "bare": bare}),
           '<input type="checkbox" id="game"><label for="game">Game frame</label>',
           "".join('<input type="radio" name="zoom" id="z%s"%s><label for="z%s">%s%%</label>'
                   % (z, " checked" if z == 75 else "", z, z) for z in (50, 75, 100)),
           "<header>%s · commit %s · hover shows the id, a comment quotes the node and its script</header>"
           % (html.escape(state), html.escape(commit)),
           '<div class="scroll"><div id="stage">']
    out += [element(ident, node, i in cut, frame) for i, (ident, node) in enumerate(numbered)]
    out.append("</div></div><table>")
    for ident, node in sorted(numbered, key=lambda pair: int(pair[0][len(prefix):])):
        out.append("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>" % (ident, *(
            html.escape(v) for v in (node["class"], node["script"], node["text"], node["path"]))))
    out.append("</table>")
    return "\n".join(out)


def selftest():
    def node(path, cls, rect, **more):
        base = {"path": path, "class": cls, "script": "res://a.gd", "rect": rect, "clip": rect, "alpha": 1, "layer": 0,
                "z": 0, "text": "", "custom_draw": False, "material": False, "image": False, "behind": False, "rebuilt": True}
        return {**base, **more}

    label = {"color": "rgba(1,2,3,1.000)", "font_px": 15, "line_px": 18, "align": 1}
    nodes = [
        node("/root/Map", "Control", [0, 0, 100, 100], custom_draw=True, rebuilt=False),
        node('/root/Say "x"', "Button", [10, 10, 30, 20], text="<", **label),
        node("/root/Next", "Button", [40, 10, 30, 20], text=">", **label),
        node("/root/Slider", "HSlider", [10, 50, 30, 10], custom_draw=True, rebuilt=False),
        node("/root/Box", "HBoxContainer", [0, 0, 100, 100], rebuilt=False),
        node("/root/Badge", "Label", [10, 50, 5, 4], text="1", **label),
    ]
    out = page({"width": 100, "height": 100, "frame": "f.png", "bare": "b.png", "nodes": nodes}, "B", "s", "c")
    tags = {line.split('"')[1]: line for line in out.splitlines() if line.startswith("<div id=")}
    assert list(tags) == ["B1", "B2", "B3", "B4", "B5", "B6"]
    assert tags["B2"].startswith('<div id="B2" data-comment-target data-script="res://a.gd" data-node="/root/Say &quot;x&quot;"')
    assert "&lt;</span>" in tags["B2"] and "&gt;</span>" in tags["B3"]
    assert "url(f.png) -10px -50px" in tags["B4"], "a barely covered slider is cut from the frame"
    assert "url(f.png)" not in tags["B1"] and 'class="n"' in tags["B1"], "a covered map stays in the base, clickable"
    assert 'class="n pass"' in tags["B5"], "a container that draws nothing lets the click through"
    print("panel_page selftest ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("dump", nargs="?", type=Path, help="the .json panel_dump.gd wrote")
    parser.add_argument("--out", type=Path, help="page folder, created")
    parser.add_argument("--state", default="", help="what is on screen, shown in the header")
    parser.add_argument("--commit", default="unknown", help="the commit the capture was taken from")
    parser.add_argument("--prefix", help="id prefix, default the dump name's first letter")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    if args.selftest:
        selftest()
        return
    if not args.dump or not args.out:
        parser.error("a dump and --out are needed")
    dump = json.loads(args.dump.read_text(encoding="utf-8"))
    if "bare" not in dump:
        sys.exit("%s has no bare frame: capture it again with this checkout's panel_dump.gd" % args.dump)
    args.out.mkdir(parents=True, exist_ok=True)
    for name in (dump["frame"], dump["bare"]):
        shutil.copyfile(args.dump.parent / name, args.out / name)
    shutil.copyfile(FONT, args.out / FONT.name)
    text = page(dump, args.prefix or args.dump.stem[0].upper(), args.state or args.dump.stem, args.commit)
    (args.out / "index.html").write_text(text, encoding="utf-8", newline="\n")
    print("wrote %s: %d nodes" % (args.out / "index.html", len(dump["nodes"])))


if __name__ == "__main__":
    main()
