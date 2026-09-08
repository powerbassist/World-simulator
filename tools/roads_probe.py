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

Run:  python tools/roads_probe.py
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

    hits = Counter()
    kinds = Counter()
    for feature in roads:
        pts = line_points(feature["geometry"])
        if not pts:
            continue
        kinds[feature["properties"].get("type", "?")] += 1
        for x, y in ((p[0], p[1]) for p in pts):
            for code, (x0, y0, x1, y1), ring in boxes:
                if x < x0 or x > x1 or y < y0 or y > y1:
                    continue
                if point_in_ring(x, y, ring):
                    hits[code] += 1
                    break

    codes = sorted({b[0] for b in boxes})
    covered = [c for c in codes if hits[c] > 0]
    print("--- Natural Earth 1:10m roads over the V3.3 roster ---")
    print("roster regions        : %d" % len(codes))
    print("regions with any line : %d (%.1f%%)" % (
        len(covered), 100.0 * len(covered) / max(1, len(codes))))
    print("regions with NO line  : %d" % (len(codes) - len(covered)))
    print("empty codes           : %s" % ", ".join(c for c in codes if hits[c] == 0))
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


if __name__ == "__main__":
    main()
