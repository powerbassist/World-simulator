extends RefCounted

## The president's registers (V5.2a): the knowledge bands and the closed
## vocabularies src/sim/president.gd writes against. The model is
## docs/people-model.md section 14.9; the design, docs/design/v5.2-spec.md.

## Band B4's edges (docs/design/bands-v5.2.md), declared before the build:
## stranger [0, 0.33), acquaintance [0.33, 0.67), known [0.67, 1]. The lever
## odds' printed range narrows across them, so the edges are the fog's, not a
## label's -- move one and B4's widths move with it.
const KNOWLEDGE_ACQUAINTANCE := 0.33
const KNOWLEDGE_KNOWN := 0.67

## The explicit bonds, the only values person_bond stores. The spec's
## relationship ladder also names stranger and acquaintance; those are READ off
## knowledge rather than stored, so the bond and the knowledge cannot disagree.
const BONDS := ["friend", "close", "rival", "enemy", "affair"]

## What the president can owe: a dated promise (broken, it is a lie revealed at
## its date) or an IOU, the council's vote trade extended to people.
const COMMITMENT_KINDS := ["promise", "iou"]

## What an act leaves behind: the author's four corruption currencies, ordered
## by how much evidence each leaves, and the affair (spec, the currencies table).
const EVIDENCE_KINDS := ["favour", "party_money", "personal_wealth", "diverted_budget", "affair"]
