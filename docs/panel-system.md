---
title: The panel system
tags:
  - model
  - ui
---

# The panel system — V2.1a

The primitives every panel builds its body out of, the sweep that keeps them
fresh, and the contract that says a panel's verb has to be on screen.

Related: [[ROADMAP]] · [[v2]] · [[engine-decision]]

## 1. Why a system rather than another round of fixes

`src/ui/` is **41 `.gd` files and 11 701 lines**, of which **19 are `*_panel.gd`**
and **14 are registered windows**. Nine of those panels carried **twenty-six**
private row helpers between them — `_header`, `_heading`, `_line`, `_add_line`,
`_row`, `_figure`, `_caption`, `_trend`, `_right`, `_build_column` — most of them
byte-identical and none of them agreeing on the edges.

Three shipped bugs came out of that, and **all three are edges rather than
typos**, which is the argument for a primitive instead of a fourth round of
per-panel corrections:

| Session | Bug | Killed by |
|---|---|---|
| V1.6b | `%+.1f` copied from the neighbouring row onto a quantity whose whole reachable range is 0.145 points, printing `+0.0` against a live figure | `PanelKit.delta()` |
| V1.6d | `Budget.snapshot()` never carried `gini_effective`, the panel read it with `.get(key, 0.0)`, and the row printed a confident **0.00** against a live 31.80 | `PanelKit.figure_text()` |
| V1.6f | two value columns each sizing to their own widest row until one extra clause pushed the pair past the window edge | `PanelKit.ledger()` |

A test that only checked that `row()` makes a row would have passed with all
three of them still in, which is why every assertion in
`tests/test_panel_kit.gd` is about an edge.

## 2. The kit is static and it is not a base class

`src/ui/panel_kit.gd` is `extends RefCounted` with every function static —
`trends.gd` and `ui_theme.gd`'s shape. All nineteen panels already
`extends PanelContainer`, so a hierarchy would buy nothing: the dirty sweep is
duck-typed on `has_method("mark_dirty")` and finds them without one, and
[[ROADMAP|CLAUDE.md]] lists abstract base classes among the things this project
does without. Migration is therefore a call-site substitution rather than a
re-parenting, which is what makes V2.1b mechanical.

Six primitives, where the row named five. `line()` is the sixth and five panels
had already written it.

- `section(parent, heading)` — the tracked heading and the box the rows go in,
  returning the **body** because no caller wants the heading back
- `heading(parent, text)` — a section label with no body, for a panel that runs
  one column
- `line(parent, text, tone)` — a wrapping sentence
- `row(parent, left, right, tone)` — caption left, value right; the commonest
  shape in the interface, built by hand in eleven panels
- `figure(parent, value, caption, tone)` — a large number over its caption
- `ledger(parent, rows)` — an aligned table

`Tone` is `PLAIN / GOOD / BAD / DIM`, and the kit never infers it from the sign.
A falling deficit and a falling approval are both negative and only one of them
is good news; `trends.gd` has carried `worse_when_rising` per figure since U3 and
`tone_for(value, worse_when_rising)` reads it rather than guessing.

### The one behavioural rule

**A missing key is an em dash and an error, never a zero.** `figure_text()`
separates three cases the old `.get(key, 0.0)` collapsed into one:

| Case | Prints | Errors |
|---|---|---|
| key absent from the snapshot | `—` | yes |
| key present and `null` | `—` | no — a snapshot saying "not applicable" |
| key present and `0.0` | `0.00` | no — a genuine zero |

A default that hides a missing key is worse than a crash, because a crash gets
fixed and a plausible number gets quoted.

And `delta()` **widens its own precision until the printed number is not a lie**,
up to `DELTA_MAX_PLACES = 4`. V1.6b's row was not wrong about the number; it was
wrong about how many places that number lives in, and the caller should not have
to get that right per quantity.

### `AUTOWRAP_WORD`, measured rather than chosen on taste

The panels disagreed — twenty-eight `AUTOWRAP_WORD` against eleven
`AUTOWRAP_WORD_SMART` — and the probe says why it matters beyond appearance. The
economy panel's own reported minimum height is **928px under WORD and 2602px
under WORD_SMART**, on identical content at an identical width, because
WORD_SMART takes far more break opportunities when asked to measure against a
width it has not been given. A panel that claims to need 2602px for 928px of
prose is a panel §4's contract would read a fold into that is not there. The
quieter mode is also the honest one.

## 3. The derived registry, and the five lists it deleted

`WindowManager.register()` has known every panel since U5a. Five separate places
kept their own copy of that knowledge, and each was written by copying the last:

| Where | Held | Drifted |
|---|---|---|
| `main.gd::_mark_all_dirty()` | 14 | `_people_panel` missing from U6b until V1.4a |
| `tools/screenshot.gd::_mark_panels_dirty()` | 14 | `_projects_panel` and `_campaign_panel` missing from V1.6f and V1.7a until V1.8 |
| `tests/test_shell.gd::EXPECTED_PANELS` | **7** | never updated at all since U5a |
| `tools/screenshot.gd::PANEL_BY_WINDOW_ID` | 5 | id → member map, for `--blank` |
| — | | |

All five are gone. `window_manager.gd` gained `panel_ids()`, `panels()` and
`mark_all_dirty()`; the three sweeps call it, `test_shell.gd` iterates the
registry, and `--blank` reads `frame(id)._content`.

**The interesting one is `EXPECTED_PANELS`**, because it was not a refresh bug
and nobody was looking for it. It held **seven of fourteen**, so bloc, calendar,
people, companies, projects, campaign and dispatches — every surface added since
U5a — were never checked for registration, reachability, exclusivity or cluster
routing. That is `check_names.sh`'s U6b failure and `run_tests.sh`'s
`test_companies.gd` failure in a third place: **a check that silently covers less
than it appears to.** All seven pass now they are checked, which is luck rather
than design.

`tests/test_panel_kit.gd` forbids the sixth: **no file under `src/ui/` or
`tools/` may name three or more panel variables inside one literal**, arrays and
dictionaries both. Two is a legitimate pair; three is a list, and a list drifts.
The dictionary half is not decoration — `PANEL_BY_WINDOW_ID` was a dictionary,
and a scanner that only read arrays would have called that file clean while it
held the longest list of the five.

## 4. The fold contract

Since U5a every panel has sat inside a `ScrollContainer`, so **nothing has been
unreachable** — the V1.3e, V1.3g and V1.6e failures are all about
**discoverability**. The player could always scroll. They had no reason to think
there was anything to scroll to.

### The mark is split in two, because one rule was doing two jobs

- **"There is more below" is the scrollbar's job**, and `ui_theme.gd` themes
  `VScrollBar` and `HScrollBar` as of this session. It had been on the engine
  default — a light grey slab on `#0A1020` navy — since U5a.
- **The brass hairline along the plate's bottom edge fires only when the panel's
  primary action is below the fold.** That is a thing a scrollbar structurally
  cannot say, and it is exactly the failure that has cost five screenshot passes.

Brass therefore keeps one meaning: *the state's own material marks what matters*.
It does not become a second word for the scrollbar, and [[v2|§2 of the tier]] has
already reserved the next spend of it for cities on the map.

> [!note] The bottom edge was already spoken for once
> `ui_theme._cluster_box()` has drawn a brass bar along the **bottom** edge since
> U5a — the action bar's "you are here" marker, whose own comment says the marker
> sits on the edge the control is anchored to. A Button in the bottom bar and a
> window plate are far enough apart that this is a decision rather than a
> collision, but it is recorded as a decision.

`PLATE_FOLDED` is a separate type variation rather than a mutation of `PLATE`, so
`tests/test_ui_theme.gd`'s standing assertion — the plate draws on its top edge
and nowhere else — is untouched and still means what it meant.

### A panel declares its own verb

`primary_action() -> Control`, duck-typed through `has_method()` — `mark_dirty()`'s
idiom exactly. A panel with nothing to press implements nothing and never draws
the mark. There is no base class and no registry of which panels have verbs.

The rule is **the first enabled verb**, not the most important one: a panel whose
first verb has scrolled off is already a panel whose verbs are hidden, and
deciding between two is a judgement this contract does not need to make.

Four panels declare one — `nation_panel` and `government_panel` because they are
the two the record names, `projects_panel` because it was migrated, and
`companies_panel` because V1.6e photographed it at the top of a body whose rows
were out of sight.

## 5. THE STEP-0 FINDING: a fold IS measurable headless

`tests/test_nation_panel.gd` has recorded since V1.3e that it is not:

> "…inside a single-frame headless harness the layout never runs, so an
> autowrapped label reports the height it would need at ONE WORD PER LINE: 1312px
> against a true ~700 … So a fold is a thing this suite structurally cannot see."

**The observation was right and the diagnosis was wrong**, and `tools/fold_probe.gd`
is the measurement. Its three tables:

**(a)** Every panel's `size` equals its own combined minimum, so a layout pass
*did* run, and the minimum does not move between frame 2 and frame 12. Four of
fourteen report taller than U5a's 886px band.

**(b)** Width set and read inside one call — what a single-frame harness does:

| state | reported min.y | lines |
|---|---|---|
| no width imposed at all | 81 | 187 |
| width 1840, read immediately | 3924 | 1 |
| width 900, read immediately | 18 | 2 |
| width 600, read immediately | 39 | 2 |
| width 420, read immediately | 39 | 3 |
| width 300, read immediately | 60 | 4 |

Each height is the answer for the **previous** row's width. The minimum-size
cache lags one invalidation; `get_line_count()` is current and
`get_combined_minimum_size()` is not.

**(c)** Width set on one frame and read on the next:

| width | min height | lines | per line |
|---|---|---|---|
| 1840 | 18 | 1 | 18 |
| 900 | 39 | 2 | 20 |
| 600 | 39 | 2 | 20 |
| 420 | 60 | 3 | 20 |
| 300 | 81 | 4 | 20 |

Monotone in the width, every height an exact multiple of its own line height.

**So the rule is one sentence: impose a width, let a frame pass, then read.**
Which is what a multi-frame harness does anyway — `test_nation_panel.gd` runs two
frames and imposes no width, and that is the whole of why it could not see one.
`tests/test_panel_kit.gd` and `tests/test_window_frame.gd` are both staged around
it. What that file recorded stands as a description of *itself*; it is not a
property of the engine.

### The contract is measured before it is enforced

`test_panel_kit.gd` prints the table and fails only on the **machinery** — a
panel that declares a verb must get a truthful answer out of the frame, and the
frame's variation must agree with it. Whether every panel currently satisfies the
contract is a different question, and re-composing the ones that do not is
V2.1b's job by name: **V1.3g proved height alone does not fix a fold**, so a
session that turned this red here would be forced into a redesign it is not
scoped for.

Measured at the shipped band, the sharpest row is **Politics: its Dissolve button
clears the fold by twenty-one pixels.** One added row in the header block hides
the panel's own verb, which is the state `nation_panel.gd` was in twice.

## 6. What the screenshot pass found, and two of the three were live bugs

The twenty-first consecutive pass to earn its keep.

**`fit_within()` spent the whole band on the SCROLL**, then the title bar, the
container separation and the plate's two content margins were added on top — so
**every window that filled its band overflowed it by about fifty pixels**. The
Politics window ran 945px into an 886px band at the shipped size, and because
`clamp_into_parent()` only constrains **position**, its last row sat under the
bottom furniture with nothing saying so. A second pass takes the excess off the
scroll; reading the difference back is one subtraction where adding up the chrome
is four lookups that go stale the day the theme changes.

**Theming the scrollbar made it disappear.** A `StyleBoxFlat` with no content
margins has a minimum size of zero, so the first version gave `VScrollBar` a
colour and a width of **0px** and it vanished from every panel at once — worse
than the engine default it replaced. The content margins *are* the bar's width;
`BAR_WIDTH_PX` is 10.

**A window is sized from its content as it was before the refresh that filled
it.** `window_manager.open()` marks the panel dirty and places the window in the
same call, and the panel does not rebuild until its own `_process` runs on the
next frame. `window_frame._process()` now re-fits when the content minimum has
moved since the fit.

**The tool's own bug** was a `--fold` flag that resized the window to 1280×720 to
force the mark. It did nothing: `project.godot` sets a 1920×1080 viewport with
`stretch/mode="canvas_items"`, so the layout is always at 1080 whatever the window
is. The flag was **deleted** rather than fixed — once `fit_within` was correct the
mark fires on `--open politics` at the shipped size, and a flag that does nothing
the panel does not already do is noise. U6a's deleted day budget, one tier on.

## 7. What is NOT fixed, and is handed on

**`get_combined_minimum_size()` is not the truth in either direction**, and both
directions are now measured. `economy_panel` reports **928px for roughly 500px**
of rendered prose, because its wrapping labels are measured at their own minimum
width and never at the window's — so its window opens with a third of its band
empty. `people_panel` reports **520px** and renders about **550**, so its last
four rows are clipped.

A grow-to-the-band heuristic was written for the second and **deleted**: every
rect the engine reports agrees that the panel fits, so the correction had nothing
to key off and would have been a number tuned against a symptom. This is V2.1b's
work by its own charter — *every fold fixed by the contract rather than by
height* — and it is recorded here so that session does not have to rediscover
which panels are wrong or in which direction.

## 8. The row, counted cold

V2.1a's ROADMAP row was written by the previous session rather than authored at
plan time — a first on this project, done because the missing-row failure is
recorded four times in almost identical words. Read cold:

| Row claim | Counted |
|---|---|
| "25 files and ~11 700 lines" | **41 files**, 11 701 lines, 19 `*_panel.gd` |
| "register() already knows all **fifteen**" | **fourteen** |
| "~14 surfaces, 2 new files, ~12 edits" | ~18 surfaces, 3 new files, ~15 edits |
| "one machine" | holds — one kit and two small structural fixes; **no split** |
| "`_mark_all_dirty()` has been wrong twice" | true historically; both lists were **correct on the day**, so the fix is prophylactic |

Four things it did not name, all found by counting: `screenshot.gd`'s second
list, `test_shell.gd`'s third and stale one, that the fold lives in
`window_frame.gd` rather than in `ui_theme.gd`, and that the affordance it wanted
to invent already existed and had simply never been themed.
