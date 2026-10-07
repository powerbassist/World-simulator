# V4.4 event art — generation plan (Task 11)

40–60 themed illustrations REUSED BY CATEGORY (CK3's `theme` shape), on the V3.7
recipe. One image per (category × severity band), not per event: 9 categories ×
(1 minor + 1 major + 1 critical where the category warrants it) ≈ 20–24 base
plates, × 2 seeded variants each ≈ 40–48 images. That is the whole library.

## Licence / attribution

GENERATED, the V2.3/V3.7 recipe (local ComfyUI, Juggernaut X). The likeness
policy applies as always — prompts describe scenes and moods, never a real
person's or party's name or likeness. **No ATTRIBUTION.md row, no licence
surface, no committed binaries question** — same status as the portrait wall.
Fictionalization rules apply to prompt text (no real logos, no real newspaper
mastheads, no identifiable landmarks-as-branding).

## Machine dependency, stated honestly

ComfyUI at `F:/ComfyUI_windows_portable` (0.34.0, torch 2.13+cu126, RTX 3070 Ti
8 GB), listening on 127.0.0.1:8188 via `tools/comfy_client.py`, with the
Juggernaut X (non-Hyper for quality at this volume, the backgrounds' precedent).
GPU pass: ~45 images × ~35 s ≈ 30–40 min. FIRED DETACHED
(`(cmd > log 2>&1 &)` — never a tracked background task; a user message kills
those mid-render). If the machine is down when this task runs, the script and
staging land COMMITTED and the render is recorded as staged-but-unrun (the V3.7
Phase-B precedent, stated as such at close-out).

## The plates

| category | minor | major | critical |
|---|---|---|---|
| scandal | a leaked file on a desk | a press scrum | a resignation podium |
| fiscal | ledger and calculator | a bond ticker | an emergency cabinet |
| unrest | a small march | a picket line, winter | a riot's morning after |
| personal | two chairs, one empty | a letter unopened | a party table split |
| european | flags in a corridor | a summit hall at night | a lone seat at the table |
| foreign | a port at dusk | an embassy gate | a phone call at 3 a.m. |
| industrial | a quiet factory floor | a plant gate, padlocked | a cooling tower, sirens |
| commodity | a market stall | a container yard | empty shelves, one light |
| disaster | a swollen river | a burnt hillside | a flooded street at night |

Mood grammar shared by every prompt (the V3.7 constraint set, adapted): "no
people, no readable text, painterly editorial illustration, muted palette, soft
light from camera-left" — people-free keeps it category art rather than portraiture
(the portraits own faces), and no-readable-text keeps generated signage from
inventing words the interface then contradicts.

## Post-pass and wiring

`tools/event_art.gd` (the portraits.gd pattern): crop to 16:9, WebP q90, into
`assets/event_art/<category>_<band>_<n>.webp` with committed
`importer="keep"` `.import` files beside each. `src/ui/events_panel.gd` and the
card path pick the plate at display time, stably, from (category, severity,
event id hash) — the backdrop library's assignment rule. Assets load as BYTES
(the fresh-clone rule), never `load()`.

## The gate

The contact sheet is the author's eye (V3.7's honest gap standing: no vision
path judges generated art better than the author's look). The suite gates what
code can see: every registered plate exists on disk, bytes-loadable, and the
panel never references a plate the library does not hold.
