"""V3.7 Phase B3: the reference-photo curation workbench (the author's call of
2026-09-13: scraped photos need curation AFTER generation -- never stop a
running batch for it).

--sheet        build sources/portraits/reference_sheet.png: every reference
               photo as a labelled thumbnail in a grid, for eyeball review.
--reject pid   [repeatable] un-curate a person: the reference photo and its
               sources entry are removed, the person's five raws/masks/WebPs
               are deleted, and the attribution doc regenerates without them.
               The NEXT batch pass re-renders that person through the
               seed-locked text path (skip-existing logic picks them up).

All real names stay in the uncommitted sources file; the attribution doc is
the single committed record (check_names exclusion documented)."""

import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import portraits_generate as pg  # noqa: E402

REPO = HERE.parent
MAPPING = HERE / "portraits_counterparts.json"
SOURCES = HERE / "portraits_photo_sources.json"
REF_DIR = REPO / "sources" / "portraits" / "reference"
ATTR = REPO / "docs" / "portrait-attribution.md"

C = json.loads(MAPPING.read_text(encoding="utf-8"))
SOURCES = json.loads(SOURCES.read_text(encoding="utf-8")) if SOURCES.exists() else {}
people = pg._load_people()
names = {pid: name for pid, name in people}


def regen_attribution():
    lines = [
        "# Portrait reference attribution (V3.7 Phase B3)",
        "",
        "The portrait wall's likeness comes from Wikimedia Commons photographs of the",
        "real politicians each fictional person plays on (the author's call of",
        "2026-09-13: names differ, images ground the likeness). The generated busts",
        "are derivatives of the works below; this file credits them as their",
        "licences require. No real person's name appears in any prompt or in `data/`",
        "— this file is the single committed record of the reference sources.",
        "",
    ]
    for pid in sorted(SOURCES):
        ref = REF_DIR / (pid + ".jpg")
        ref2 = REF_DIR / (pid + ".png")
        if not (ref.exists() or ref2.exists()):
            continue  # rejected: the reference is gone
        s = SOURCES[pid]
        lines.append("- `%s` (as %s): \"%s\" — %s, %s. %s"
                     % (pid, names.get(pid, "?"), s.get("title", "?"),
                        s.get("artist", "unknown author"), s.get("license", "?"),
                        s.get("description_url", "")))
    ATTR.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("attribution regenerated:", ATTR, "| entries:", len(SOURCES))


def reject(pids):
    for pid in pids:
        for ext in (".jpg", ".jpeg", ".png"):
            ref = REF_DIR / (pid + ext)
            if ref.exists():
                ref.unlink()
        SOURCES.pop(pid, None)
        removed = 0
        for emotion in pg.EMOTIONS:
            for sub in ("raw", "mask"):
                p = REPO / "sources" / "portraits" / sub / emotion / (pid + ".png")
                if p.exists():
                    p.unlink()
                    removed += 1
            for webp in (REPO / "assets" / "portraits" / emotion).glob(pid + ".webp"):
                webp.unlink()
                removed += 1
        print("rejected %s: reference removed, %d renders cleared -> text path next pass" % (pid, removed))
    (HERE / "portraits_photo_sources.json").write_text(
        json.dumps(SOURCES, indent=1, ensure_ascii=False), encoding="utf-8")
    regen_attribution()


def sheet():
    from PIL import Image, ImageDraw
    refs = sorted(p for p in REF_DIR.glob("*.png")) + sorted(p for p in REF_DIR.glob("*.jpg"))
    cols, cell_w, cell_h, label_h = 8, 180, 247, 18
    rows = (len(refs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell_w, rows * (cell_h + label_h)), (24, 28, 40))
    draw = ImageDraw.Draw(sheet)
    for i, p in enumerate(refs):
        img = Image.open(p).convert("RGB")
        img.thumbnail((cell_w - 4, cell_h - 4))
        x = (i % cols) * cell_w
        y = (i // cols) * (cell_h + label_h)
        sheet.paste(img, (x + 2, y + 2))
        draw.text((x + 4, y + cell_h + 2), p.stem, fill=(220, 220, 200))
    out = REF_DIR.parent / "reference_sheet.png"
    sheet.save(out)
    print("reference sheet:", out, "| photos:", len(refs))


def main():
    args = sys.argv[1:]
    if "--reject" in args:
        pids = [args[i + 1] for i, a in enumerate(args) if a == "--reject" and i + 1 < len(args)]
        reject(pids)
    elif "--sheet" in args or not args:
        sheet()


if __name__ == "__main__":
    main()
