"""V5.2a: screen the shipped faces and backdrops for the defects the author found
by eye on the V4.3 wall -- so the wall's first pages are the suspects, not a
needle in 1 595 faces. It nominates; the author decides (the reject marks are
the author's, and a nomination is not a verdict).

  python tools/portraits_screen.py            # writes sources/portraits/screen.json
  python tools/portraits_screen.py --top 30   # print the worst per check

Checks, all on the committed WebP (what the game draws), numpy + PIL only:
  coverage   alpha share of the frame: a matte that failed (opaque frame, or
             almost nothing left) is a wide shot or a corrupt cut-out
  parts      more than one big connected piece of alpha: a group shot
  sketch     near-white, low-saturation frames: line art, not a photograph
  dup        near-identical faces (16x16 difference hash, tiny Hamming distance)
  streak     backdrops only: horizontal banding -- the row-to-row jitter of the
             row means against the column-to-column jitter of the column means

Thresholds are starting points read off the shipped wall, not laws: a person
the screen misses is a person the author's eye catches on the wall."""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

REPO = Path(__file__).resolve().parent.parent
PORTRAITS = REPO / "assets" / "portraits" / "neutral"
SCENES = REPO / "assets" / "portrait_scenes"
OUT = REPO / "sources" / "portraits" / "screen.json"

DUP_BITS = 8          # Hamming distance at or under this out of 256 = same face
MIN_PART_SHARE = 0.04 # a connected piece of alpha below 4% of the frame is noise


def _dhash(gray: np.ndarray) -> np.ndarray:
    small = np.asarray(Image.fromarray(gray).resize((17, 16), Image.LANCZOS), dtype=np.int16)
    return (small[:, 1:] > small[:, :-1]).ravel()


def face_features(path: Path) -> dict:
    rgba = Image.open(path).convert("RGBA")
    arr = np.asarray(rgba)
    alpha = arr[..., 3]
    solid = alpha > 128
    coverage = float(solid.mean())
    labels, count = ndimage.label(solid)
    sizes = ndimage.sum(solid, labels, range(1, count + 1)) if count else []
    parts = int(sum(1 for s in sizes if s / solid.size >= MIN_PART_SHARE))
    px = arr[..., :3][solid] if solid.any() else arr[..., :3].reshape(-1, 3)
    mx, mn = px.max(axis=1).astype(float), px.min(axis=1).astype(float)
    sat = float(np.mean((mx - mn) / np.maximum(mx, 1)))
    white = float(np.mean(mn > 225))
    gray = np.asarray(rgba.convert("L"))
    return {"coverage": round(coverage, 3), "parts": parts, "sat": round(sat, 3),
            "white": round(white, 3), "hash": _dhash(gray)}


def streak_score(path: Path) -> float:
    lum = np.asarray(Image.open(path).convert("L"), dtype=float)
    rows, cols = lum.mean(axis=1), lum.mean(axis=0)
    jr = np.median(np.abs(np.diff(rows, 2)))
    jc = np.median(np.abs(np.diff(cols, 2)))
    # A natural scene's row means and column means jitter alike; banding makes
    # the rows jitter more. The log ratio is symmetric and unit-free.
    return float(np.log((jr + 0.05) / (jc + 0.05)))


def screen() -> dict:
    faces = {}
    for p in sorted(PORTRAITS.glob("*.webp")):
        faces[p.stem] = face_features(p)
    flags = {pid: [] for pid in faces}
    cov = np.array([f["coverage"] for f in faces.values()])
    lo, hi = np.percentile(cov, 1), np.percentile(cov, 99)
    for pid, f in faces.items():
        if f["coverage"] < min(lo, 0.35) or f["coverage"] > max(hi, 0.97):
            flags[pid].append("coverage %.2f" % f["coverage"])
        if f["parts"] > 1:
            flags[pid].append("parts %d" % f["parts"])
        if f["white"] > 0.25 and f["sat"] < 0.12:
            flags[pid].append("sketch white %.2f sat %.2f" % (f["white"], f["sat"]))
    ids = list(faces)
    bits = np.stack([faces[i]["hash"] for i in ids])
    for i in range(len(ids)):
        d = (bits[i + 1:] != bits[i]).sum(axis=1)
        for j in np.nonzero(d <= DUP_BITS)[0]:
            other = ids[i + 1 + int(j)]
            flags[ids[i]].append("dup of " + other)
            flags[other].append("dup of " + ids[i])
    scenes = {}
    for p in sorted(SCENES.glob("*.webp")):
        scenes[p.stem] = round(streak_score(p), 3)
    s = np.array(list(scenes.values()))
    cut = float(np.median(s) + 3 * 1.4826 * np.median(np.abs(s - np.median(s))))
    streaked = {k: v for k, v in scenes.items() if v > cut}
    return {"faces": {k: {kk: vv for kk, vv in v.items() if kk != "hash"} for k, v in faces.items()},
            "face_flags": {k: v for k, v in flags.items() if v},
            "scene_streak": scenes, "streak_cut": round(cut, 3), "streaked": streaked}


def main() -> int:
    report = screen()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(report, indent=1), encoding="utf-8")
    print("faces %d, flagged %d; scenes %d, streaked %d (cut %.2f) -> %s"
          % (len(report["faces"]), len(report["face_flags"]), len(report["scene_streak"]),
             len(report["streaked"]), report["streak_cut"], OUT))
    if "--top" in sys.argv:
        n = int(sys.argv[sys.argv.index("--top") + 1])
        for pid, why in list(report["face_flags"].items())[:n]:
            print("  %s: %s" % (pid, "; ".join(why)))
        worst = sorted(report["scene_streak"].items(), key=lambda kv: -kv[1])[:n]
        print("  worst streak:", ", ".join("%s %.2f" % kv for kv in worst))
    return 0


if __name__ == "__main__":
    sys.exit(main())
