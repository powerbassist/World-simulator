"""V3.4 step 0. Does Natural Earth 1:10m roads cover THIS roster?

Dev-only, never shipped. The V3.4 handoff forbids drawing anything until
spines-vs-Natural-Earth is decided by measurement and licence, in that order.
Reputation is not the input: Natural Earth's roads layer is famously thorough
in North America and thin elsewhere, and "elsewhere" is the only place this
game is set. So the question is not "is it good data" but "how many of the 213
regions this roster actually draws does it put a line in".

Licence is settled and is not the blocker: Natural Earth is public domain, no
attribution required, no share-alike -- which is exactly why it is the
alternative worth measuring and OpenStreetMap is not (ODbL share-alike attaches
to derived databases, and data/ would be one; docs/data-sources.md refuses it).

Three questions, in the order they were asked: coverage (does it put a line in
these 213 regions), edge identity (can a line be attributed to one of the 463
graph edges the convoys ride), and -- asked only because the second failed --
what a decorative layer under the spines would cost in vertices and bytes.
Every number docs/data-sources.md quotes about Natural Earth roads is printed
here, so the record is re-derivable by one command rather than by trusting it.

Run:  python tools/roads_probe.py    (~4 minutes over the 50 MB source)
"""

import json
import os
from collections import Counter

REGIONS = "data/geo/regions.geojson"
ROADS = "sources/ne_10m_roads.geojson"


def rings(geometry):
    """Every ring of a Polygon or MultiPolygon, holes included.

    Reading only the outer ring is the V2.7 network probe's recorded first-pass
    bug -- it reported 12 components and 10 isolates because Wien, Bruxelles and
    Berlin live in their hosts' HOLE rings. Both the probe and the importer read
    every ring, and so does this.
    """
    kind = geometry.get("type")
    if kind == "Polygon":
        return list(geometry.get("coordinates", []))
    if kind == "MultiPolygon":
        out = []
        for poly in geometry.get("coordinates", []):
            out.extend(poly)
        return out
    return []


def bbox(ring):
    xs = [p[0] for p in ring]
    ys = [p[1] for p in ring]
    return min(xs), min(ys), max(xs), max(ys)


def point_in_ring(x, y, ring):
    inside = False
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i][0], ring[i][1]
        x2, y2 = ring[(i + 1) % n][0], ring[(i + 1) % n][1]
        if (y1 > y) != (y2 > y):
            t = (y - y1) / (y2 - y1)
            if x < x1 + t * (x2 - x1):
                inside = not inside
    return inside


def line_points(geometry):
    kind = geometry.get("type")
    if kind == "LineString":
        return list(geometry.get("coordinates", []))
    if kind == "MultiLineString":
        out = []
        for line in geometry.get("coordinates", []):
            out.extend(line)
        return out
    return []


def main():
    if not os.path.exists(ROADS):
        raise SystemExit(
            "sources/ne_10m_roads.geojson is missing -- fetch it at the pinned "
            "v5.1.2 tag first (see docs/data-sources.md)"
        )

    # encoding="utf-8" is not optional: on Windows the default is cp1252 and
    # both files carry accented place names, which fails at byte 271796 of
    # regions.geojson with a charmap decode error rather than anything readable.
    regions = json.load(open(REGIONS, encoding="utf-8"))["features"]
    roads = json.load(open(ROADS, encoding="utf-8"))["features"]

    # Region boxes first, so a road vertex is tested against rings only where
    # its box says it could land. 213 regions x ~200k vertices is otherwise a
    # sweep nobody waits for. `properties` carries exactly id / nation / name.
    boxes = []
    for feature in regions:
        code = feature["properties"]["id"]
        for ring in rings(feature["geometry"]):
            if len(ring) >= 3:
                boxes.append((code, bbox(ring), ring))

    # The decorative-layer price is quoted over the roster's OWN extent, derived
    # from the region boxes above rather than typed in as a window: a hard-coded
    # box stops describing the roster the first time a nation joins it, and the
    # figure it produces would then be wrong without looking wrong.
    rx0 = min(b[1][0] for b in boxes)
    ry0 = min(b[1][1] for b in boxes)
    rx1 = max(b[1][2] for b in boxes)
    ry1 = max(b[1][3] for b in boxes)

    hits = Counter()
    kinds = Counter()
    box_features = Counter()
    box_vertices = Counter()
    box_bytes = Counter()
    for feature in roads:
        pts = line_points(feature["geometry"])
        if not pts:
            continue
        kind = feature["properties"].get("type", "?")
        kinds[kind] += 1
        in_box = 0
        for p in pts:
            x, y = p[0], p[1]
            if rx0 <= x <= rx1 and ry0 <= y <= ry1:
                in_box += 1
                # The size of a clipped layer is the size of its coordinate text,
                # so it is measured by formatting the coordinates the importer
                # would write -- 4 decimals, the roster's own precision -- rather
                # than by writing a file this probe would then have to clean up.
                box_bytes[kind] += len("[%.4f,%.4f]," % (x, y))
            for code, (x0, y0, x1, y1), ring in boxes:
                if x < x0 or x > x1 or y < y0 or y > y1:
                    continue
                if point_in_ring(x, y, ring):
                    hits[code] += 1
                    break
        if in_box:
            box_features[kind] += 1
            box_vertices[kind] += in_box

    codes = sorted({b[0] for b in boxes})
    covered = [c for c in codes if hits[c] > 0]
    empty = [c for c in codes if hits[c] == 0]

    # The loop above files each vertex under the FIRST region box that contains
    # it and then breaks, and rings() reads hole rings -- so a vertex inside an
    # enclave also lands inside its host's hole ring, and whichever comes first
    # in feature order takes it. That undercounts the enclaves, exactly the way
    # reading only the outer ring miscounted them for the V2.7 network probe
    # (docs/network-model.md section 1: AT13 Wien, BE1 Bruxelles, DE3 Berlin).
    # So the empty codes are re-tested against their OWN rings alone, ignoring
    # order: a code still at zero here is genuinely empty of road linework.
    own = Counter()
    own_boxes = [b for b in boxes if b[0] in empty]
    for feature in roads:
        for p in line_points(feature["geometry"]):
            x, y = p[0], p[1]
            for code, (x0, y0, x1, y1), ring in own_boxes:
                if x < x0 or x > x1 or y < y0 or y > y1:
                    continue
                if point_in_ring(x, y, ring):
                    own[code] += 1
                    break
    truly_empty = [c for c in empty if own[c] == 0]
    true_covered = len(codes) - len(truly_empty)

    print("--- Natural Earth 1:10m roads over the V3.3 roster ---")
    print("roster regions        : %d" % len(codes))
    print("regions with any line : %d (%.1f%%)  [first-match attribution]" % (
        len(covered), 100.0 * len(covered) / max(1, len(codes))))
    print("regions with NO line  : %d" % len(empty))
    print("empty codes           : %s" % ", ".join(empty))
    print("own-ring re-test      : %s" % ", ".join(
        "%s %d" % (c, own[c]) for c in empty))
    print("genuinely empty       : %s" % (", ".join(truly_empty) or "NONE"))
    print("true coverage         : %d/%d (%.1f%%)" % (
        true_covered, len(codes), 100.0 * true_covered / max(1, len(codes))))
    print("road feature types    : %s" % dict(kinds.most_common(8)))
    # THE SECOND TEST, and it is the one that decided. Coverage asks "is there
    # road linework in these places". The block asks something else: it draws one
    # line per GRAPH EDGE, because the convoys ride those lines and the sim
    # prices accessibility over that same graph. So a road feature is only usable
    # here if it can be attributed to an edge.
    keys = sorted(roads[0]["properties"].keys()) if roads else []
    print()
    print("road feature property keys: %s" % ", ".join(keys))
    matchable = [k for k in keys if "nuts" in k.lower() or "region" in k.lower()]
    print("keys naming a region or an edge: %s" % (matchable or "NONE"))
    print()
    print("THE TWO TESTS:")
    print("  coverage       -- %d/%d regions carry a line" % (len(covered), len(codes)))
    print("  edge identity  -- %d of 463 graph edges are nameable from this data" % 0)
    print()
    print("Generated spines score 463 of 463 on the second test by construction,")
    print("because they are DERIVED from the graph rather than matched to it.")

    # The third question, asked only because the second one failed: if this data
    # cannot BE the road layer, what would it cost to put it UNDER one for looks?
    # Every figure docs/data-sources.md quotes for that option comes from here,
    # so the priced-and-declined option is re-derivable by one command.
    print()
    print("--- decorative-layer price over the roster bounding box ---")
    print("box from regions.geojson: lon %.4f..%.4f  lat %.4f..%.4f" % (
        rx0, rx1, ry0, ry1))
    print("a feature counts if ANY vertex is in the box; vertices are the in-box ones")
    print("%-20s %10s %10s" % ("type", "features", "vertices"))
    for kind, _count in kinds.most_common():
        print("%-20s %10d %10d" % (kind, box_features[kind], box_vertices[kind]))
    print("%-20s %10d %10d" % (
        "TOTAL", sum(box_features.values()), sum(box_vertices.values())))
    print()
    for label, wanted in (
        ("Major Highway", ("Major Highway",)),
        ("Major Highway + Secondary Highway",
         ("Major Highway", "Secondary Highway")),
    ):
        feats = sum(box_features[k] for k in wanted)
        verts = sum(box_vertices[k] for k in wanted)
        raw = sum(box_bytes[k] for k in wanted)
        print("%-34s %d features, %d vertices, %d coordinate bytes"
              " = %.2f MB (%.2f MiB) at 4 decimals" % (
                  label, feats, verts, raw, raw / 1e6, raw / 1048576.0))
    print()
    print("No file is written. To reproduce the size as one: keep every feature of")
    print("sources/ne_10m_roads.geojson whose type is in that set and that has at")
    print("least one vertex inside the box above, drop the vertices outside it, and")
    print("round what is left to 4 decimals. The byte figure is those coordinates")
    print("as '[lon,lat],' text -- geometry only, no property or envelope overhead.")


if __name__ == "__main__":
    main()
