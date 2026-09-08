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
these 213 regions), edge identity (can a line be attributed to one of the graph
edges the convoys ride -- 463 of them today, and the count is read from the
graph, not typed), and -- asked only because the second failed -- what a
decorative layer under the spines would cost in vertices and bytes.

Every number docs/data-sources.md quotes about Natural Earth roads is printed
here, so the record is re-derivable by one command rather than by trusting it.
That includes the denominators: the edge count comes from region_graph.json and
the committed-geometry point count from the three map files, because a ratio
whose denominator is typed in stops being true the first time the map grows.

What this probe does NOT measure, and the doc must not claim: whether the
linework could be attributed to an edge GEOMETRICALLY -- by building a graph out
of it and routing between two regions' principal cities. That needs no
identifier and was never attempted or priced here. The refusal below is about
the attribute join only.

Run:  python tools/roads_probe.py    (~4 minutes over the 50 MB source)
"""

import json
import os
from collections import Counter

REGIONS = "data/geo/regions.geojson"
GRAPH = "data/geo/region_graph.json"
ROADS = "sources/ne_10m_roads.geojson"

# Every polygon file the map actually draws. The decorative layer is priced as a
# RATIO against this, so the denominator is counted from the committed files
# rather than quoted from a past run -- a doc figure that stops moving when the
# geometry moves is the one nobody notices going stale.
MAP_GEOMETRY = (
    "data/geo/europe.geojson",
    "data/geo/regions.geojson",
    "data/geo/world.geojson",
)


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
            "v5.1.2 tag first (the curl line is in docs/data-sources.md, "
            "'How to fetch the raw datasets')"
        )

    # encoding="utf-8" is not optional: on Windows the default is cp1252 and
    # both files carry accented place names, which fails at byte 271796 of
    # regions.geojson with a charmap decode error rather than anything readable.
    regions = json.load(open(REGIONS, encoding="utf-8"))["features"]
    roads = json.load(open(ROADS, encoding="utf-8"))["features"]
    edges = json.load(open(GRAPH, encoding="utf-8"))["edges"]

    committed_points = {}
    for path in MAP_GEOMETRY:
        features = json.load(open(path, encoding="utf-8"))["features"]
        committed_points[path] = sum(
            len(ring) for f in features for ring in rings(f["geometry"]))
    committed_total = sum(committed_points.values())

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
    # The bounding box is a rectangle and the roster is not: the box reaches into
    # North Africa, Anatolia and the Atlantic, so a box figure prices linework the
    # game never draws over. The containment test the coverage question already
    # runs on every vertex gives the roster figure for free, so both are kept and
    # the doc says which is which rather than quoting the flattering one.
    roster_features = Counter()
    roster_vertices = Counter()
    roster_bytes = Counter()
    # Coordinate text is what the map PARSES; a written file is what the repo
    # SHIPS, and the second is the one a reader weighs when asked "should we
    # commit this". The wrapper and the properties are measured rather than
    # guessed at, by dumping the feature a clip would emit.
    box_file_bytes = Counter()
    populated = Counter()
    # Which continent the in-box features claim. This is the box's overreach
    # stated as a number rather than as an adjective: features Natural Earth
    # itself files under Asia or Africa are inside the rectangle and outside the
    # roster, and they are the gap between the two prices below.
    box_continents = Counter()
    for feature in roads:
        pts = line_points(feature["geometry"])
        if not pts:
            continue
        props = feature["properties"]
        kind = props.get("type", "?")
        kinds[kind] += 1
        in_box = 0
        in_roster = 0
        kept = []
        for p in pts:
            x, y = p[0], p[1]
            if rx0 <= x <= rx1 and ry0 <= y <= ry1:
                in_box += 1
                kept.append([round(x, 4), round(y, 4)])
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
                    in_roster += 1
                    roster_bytes[kind] += len("[%.4f,%.4f]," % (x, y))
                    break
        if in_box:
            box_features[kind] += 1
            box_vertices[kind] += in_box
            box_continents[props.get("continent") or "?"] += 1
            box_file_bytes[kind] += len(json.dumps({
                "type": "Feature",
                "properties": props,
                "geometry": {"type": "LineString", "coordinates": kept},
            }, separators=(",", ":"))) + 1
            # Which property fields carry a value at all, counted over the
            # features a clip would actually keep. A key that exists on every
            # feature and is empty on every one of them is not a field this data
            # has -- and the edge-identity refusal below is stronger for it.
            # null, "", 0 and -99 all count as ABSENT because those are Natural
            # Earth's own no-data fills: `add`, `toll`, `ignore` and `uident`
            # came back 0 on every in-box feature, and counting a zero as a value
            # would make this line say every key is populated, which is the one
            # thing it exists to disprove.
            for key, value in props.items():
                if value not in (None, "", 0, -99):
                    populated[key] += 1
        if in_roster:
            roster_features[kind] += 1
            roster_vertices[kind] += in_roster

    codes = sorted({b[0] for b in boxes})
    covered = [c for c in codes if hits[c] > 0]
    empty = [c for c in codes if hits[c] == 0]

    # The loop above files each vertex under the FIRST region box that contains
    # it and then breaks, and rings() reads hole rings -- so a vertex inside an
    # enclave also lands inside its host's hole ring, and whichever comes first
    # in feature order takes it. That is the same ENCLAVE CLASS the V2.7 network
    # probe tripped over (docs/network-model.md section 1: AT13 Wien, BE1
    # Bruxelles, DE3 Berlin), by the opposite mechanism -- V2.7 ignored hole
    # rings, this reads them and lets the first match win -- and it bites a
    # different subset: AT12 precedes AT13 and RO31 precedes RO32 so Wien and
    # Bucuresti lost their vertices, while BE1 and DE3 precede their hosts and
    # were counted correctly. RO32 is not in that section's list at all.
    # So the empty codes are re-tested against their OWN rings alone, ignoring
    # order: a code still at zero here is genuinely empty of road linework.
    # The re-test runs only on codes that came back empty, so it corrects false
    # negatives only. The same first-match path can in principle produce a false
    # POSITIVE -- a host with no linework of its own but a road-bearing enclave
    # inside its hole ring would be credited and never re-tested -- so "true
    # coverage" is exact only because no host on this roster is in that state.
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
    # here if it can be attributed to an edge. What is tested is the ATTRIBUTE
    # JOIN -- can an edge's line be LOOKED UP. Attributing geometrically instead
    # (build a graph from the linework, route city to city) needs no key at all
    # and is not measured here, so nothing printed below rules it out.
    # The substring test is a tripwire, not the check. It cannot know what a
    # future schema calls a region id, so the full key list is printed above it
    # and READING THAT LIST is the actual check -- the tripwire only exists so a
    # schema change cannot slip past a session that skims. `sov_a3` is
    # deliberately outside the set: it names a sovereign state, ten values over
    # the whole roster, which is a nation and not one of the 213 regions.
    keys = sorted(roads[0]["properties"].keys()) if roads else []
    wanted_keys = ("nuts", "region", "adm", "iso", "code", "prov", "state",
                   "county", "district", "muni", "gid", "fips", "hasc",
                   "nation", "country", "postal")
    print()
    print("road feature property keys: %s" % ", ".join(keys))
    matchable = [k for k in keys if any(w in k.lower() for w in wanted_keys)]
    print("keys naming a region or an edge: %s" % (matchable or "NONE"))
    print("keys populated on in-box features: %s" % ", ".join(
        "%s %d" % (k, populated[k]) for k in keys if populated[k]))
    print()
    print("THE TWO TESTS:")
    print("  coverage       -- %d/%d regions carry a line" % (len(covered), len(codes)))
    # Both numbers on this line are derived: the edge count from region_graph.json,
    # because the graph grows and a literal 463 would keep reading true after it
    # did; and the zero from the key scan above rather than from the conclusion
    # this run reached. A file that DID carry a candidate key cannot be scored
    # from key names alone, so the line says that instead of a measured-looking 0.
    if matchable:
        print("  edge identity  -- UNRESOLVED: %d candidate key(s) (%s) against %d"
              " graph edges; measure the join before claiming a number" % (
                  len(matchable), ", ".join(matchable), len(edges)))
    else:
        print("  edge identity  -- %d of %d graph edges are nameable from this data"
              % (0, len(edges)))
    print()
    print("Generated spines score %d of %d on the second test by construction,"
          % (len(edges), len(edges)))
    print("because they are DERIVED from the graph rather than matched to it.")

    # The third question, asked only because the second one failed: if this data
    # cannot BE the road layer, what would it cost to put it UNDER one for looks?
    # Every figure docs/data-sources.md quotes for that option comes from here,
    # so the priced-and-declined option is re-derivable by one command.
    print()
    print("--- decorative-layer price, two ways ---")
    print("box from regions.geojson: lon %.4f..%.4f  lat %.4f..%.4f" % (
        rx0, rx1, ry0, ry1))
    print("BOX: a feature counts if ANY vertex is in that rectangle; vertices are")
    print("     the in-box ones. The rectangle reaches past the roster.")
    print("ROSTER: same test against the region RINGS -- the linework the map")
    print("     would actually draw over. Both are printed; the box is the ceiling.")
    print("in-box features by continent: %s" % dict(box_continents.most_common()))
    print("%-20s %9s %9s %9s %9s" % (
        "type", "box feat", "box vert", "ros feat", "ros vert"))
    for kind, _count in kinds.most_common():
        print("%-20s %9d %9d %9d %9d" % (
            kind, box_features[kind], box_vertices[kind],
            roster_features[kind], roster_vertices[kind]))
    print("%-20s %9d %9d %9d %9d" % (
        "TOTAL", sum(box_features.values()), sum(box_vertices.values()),
        sum(roster_features.values()), sum(roster_vertices.values())))
    print()
    print("committed map geometry (the denominator every ratio below is against):")
    for path in MAP_GEOMETRY:
        print("  %-26s %7d points" % (path, committed_points[path]))
    print("  %-26s %7d points" % ("TOTAL", committed_total))
    print()
    for label, wanted in (
        ("Major Highway", ("Major Highway",)),
        ("Major Highway + Secondary Highway",
         ("Major Highway", "Secondary Highway")),
    ):
        for scope, feat_c, vert_c, byte_c in (
            ("box   ", box_features, box_vertices, box_bytes),
            ("roster", roster_features, roster_vertices, roster_bytes),
        ):
            feats = sum(feat_c[k] for k in wanted)
            verts = sum(vert_c[k] for k in wanted)
            raw = sum(byte_c[k] for k in wanted)
            print("%-34s %s %d features, %d vertices, %d coordinate bytes"
                  " = %.2f MB (%.2f MiB) at 4 decimals; +%.0f%% on the committed"
                  " geometry (x%.2f)" % (
                      label, scope, feats, verts, raw, raw / 1e6,
                      raw / 1048576.0,
                      100.0 * verts / committed_total,
                      (committed_total + verts) / float(committed_total)))
        written = sum(box_file_bytes[k] for k in wanted)
        print("%-34s box    as a WRITTEN GeoJSON file, properties and wrappers"
              " included: %d bytes = %.2f MB" % (
                  label, written, written / 1e6))
    print()
    print("No file is written. To reproduce the size as one: keep every feature of")
    print("sources/ne_10m_roads.geojson whose type is in that set and that has at")
    print("least one vertex inside the box above, drop the vertices outside it, and")
    print("round what is left to 4 decimals. The byte figure is those coordinates")
    print("as '[lon,lat],' text -- geometry only, no property or envelope overhead;")
    print("the FILE such a clip produces is larger, because every feature carries a")
    print("GeoJSON wrapper and its properties on top of these bytes.")


if __name__ == "__main__":
    main()
