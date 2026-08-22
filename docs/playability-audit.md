---
title: Playability audit
tags:
  - audit
---

# Playability audit

The first pass that tried to **play** the game rather than test it.

Twenty-plus sessions shipped simulation depth — MVP through V1.6d — behind a
green suite and a per-session screenshot pass. The suite tests systems in
isolation; `tools/screenshot.gd` tests one frame with one flag on it. Neither
answers *is this playable*, and nothing had ever booted the menu, started a
term, pressed every verb, run to the election and lost.

This is what came back. **Nine defects, five of which break a playthrough**, and
the five worst were all found by reading the source against the question "what
does the player do next" — before a frame was rendered.

## How this register is enforced

The register was first written as assertions of the **broken** behaviour: each
check pinned the defect and would turn red the moment somebody fixed it. That is
V1.3c's `SAVE_VERSION` device ("the version is still 10, so a later session
raising it had to come and say why") pointed at defects instead of at a number.

It worked. On the repair pass all eight checks went red in one run, each naming
its own fix by number, and `tests/test_playability.gd` is now rewritten as
ordinary regressions guarding the repairs.

**Nine of the ten are fixed. V5 is not, and it is deliberately not** — see its
row. The repair pass also turned up V10, which only became visible once V3's
stray Close button stopped covering for it.

## Severity

| | Meaning |
|---|---|
| **P1** | Breaks a playthrough: the player loses the game, the state, or a surface, with no way back |
| **P2** | A control that lies, or a check that does not run |
| **P3** | Hygiene |

---

## Register A — verified against source, five reproduced as tests

| # | Sev | Defect | Pinned by | Status |
|---|---|---|---|---|
| V1 | **P1** | Term limit removed the player silently, forever | `test_playability.gd` | **fixed** |
| V2 | **P1** | The defeat plate was permanent, and play continued behind it | `test_playability.gd` | **fixed** |
| V3 | **P1** | Three windows were destroyed by their own Close button | `test_playability.gd` | **fixed** |
| V4 | **P1** | A failed load from the main menu started a new game with no message | — | **fixed** |
| V5 | **P1** | A fresh clone declares three autoload scripts that are not in the repo | — | **open — needs your call** |
| V6 | P2 | Companies' and People's Close buttons did nothing at all | `test_playability.gd` | **fixed** |
| V7 | P2 | `tests/test_cabinet.gd` had never run in the suite | it now runs | **fixed** |
| V8 | P3 | `Bloc.cast_vote` was the only command with no effect delta | `test_playability.gd` | **fixed** |
| V9 | P3 | Uncommitted deletion in `project.godot` | — | **fixed** |
| V10 | **P1** | Diplomacy opened from the action bar rendered an empty window | — | **fixed** |

### V1 · Term limit removes the player silently, forever · P1

`src/sim/elections.gd:150-151`

```gdscript
if ns.term_limit > 0 and ns.terms_served >= ns.term_limit:
    ns.in_government = false
```

Nothing is appended to `results`. That Array is what `src/ui/main.gd:674` gates
the result screen on, so **the one event that ends a French presidency renders
nothing at all**: no screen, no pause, no message card. The branch's own comment
claims the run ends here "the same as any other lost office" — but every other
lost office appends a result and this one does not.

France is `term_limit: 2` on a five-year executive term first falling 2027-05.
A player who wins 2027 and wins 2032 is removed from office in **May 2037** with
an unchanged screen.

The second half is worse than the first. `Elections.tick_month:100-101` skips
any nation with `in_government == false`, so from that month on `months_in_term`
stops advancing and **no election can ever resolve again**. The game does not
end; it becomes an unbounded sandbox in which the player is not the government
and nothing says so. `src/ui/overview_panel.gd:179,232` then reads a negative
`months_to_election` forever and the lead line permanently reads "Election this
month."

*Right behaviour:* append a result the panel can show, as every other lost
office does.

**Fixed.** `elections.gd` now appends a notice on that branch, and the panel
renders it as **TERM LIMIT** with the reason and a control.

It appends a *notice*, not an election — and that distinction was forced by an
existing test rather than chosen. The first attempt called `resolve_executive()`
so the successor race could be shown, and `test_balance.gd` went red on a stated
invariant: *"expected exactly 2 executive elections before the term limit barred
a third, saw 3."* That invariant is right, and the branch's own comment says why
— a termed-out incumbent does not stand, so there is no verdict to compute. The
notice therefore carries `resolve_executive()`'s key set with the vote emptied
and its **own `kind`**, `"termed_out"`, so nothing that counts elections by kind
sees one. The invariant is untouched, which is the evidence the fix did not move
the model.

### V2 · The defeat plate is permanent, and play continues behind it · P1

`src/ui/election_panel.gd:130-138`

```gdscript
if defeated:
    var over := Label.new()
    over.text = "You have lost your office. This term is over."
    _footer.add_child(over)
else:
    var cont := Button.new()
    cont.text = "Continue"
    cont.pressed.connect(func(): hide(); dismissed.emit())
    _footer.add_child(cont)
```

The `Continue` button exists **only in the not-defeated branch**. `main.gd:675`
pauses the clock on any result and `:294` unpauses only on `dismissed`, which
only that button emits. The panel builds no close control, sits in no
`WindowFrame`, and is bound to no key, so it stays on screen for the rest of the
session.

It is not a lock, which would at least be honest. `_add_centered()`
(`main.gd:410-416`) defaults to `blocking := false`, so the holder is
`MOUSE_FILTER_IGNORE` and the whole HUD stays live. **Space unpauses and the
player governs indefinitely behind a permanent "DEFEATED" plate** — budgeting,
passing laws, acting diplomatically — and by V1's second half no further
election can ever resolve to contradict it.

Captured:

```bash
godot --path "<repo>" --script res://tools/screenshot.gd -- --defeated --out defeated.png
```

The frame shows the plate with **no button anywhere on it**, and behind it a
fully live action bar, map-layer toggles, clock cluster, SAVE and MENU. It also
shows a smaller thing worth its own line: the portrait card still reads
*"53% APPROVAL — Daniel Moucron, President of the Republic"*, so a president who
has just lost the office is still captioned as holding it.

*Right behaviour:* a defeated player gets a control that ends the run, or the
run ends itself. Not an unbounded game behind a plate that cannot be moved.

**Fixed.** The footer builds a button in **both** branches: `Continue` on a win,
`Leave office` on a defeat. main.gd's `dismissed` handler now branches too —
dismissing a won election resumes play, dismissing a lost one leaves office by
returning to the menu, because there is nothing behind that plate to go back to.

### V3 · Three windows are destroyed by their own Close button · P1

`src/ui/nation_panel.gd:91-92`, `src/ui/bloc_panel.gd:69-70`,
`src/ui/calendar_panel.gd:125-126` — each builds a **visible** Close button that
calls `hide()` on the panel's own content Control and emits `closed`.

Three facts combine into the bug:

1. `main.gd` connects exactly one `closed` signal in the whole file — the
   settings panel, `:305`. These three go nowhere.
2. `main.gd` calls `hide_close_button()` for only four panels (`:195, 204, 215,
   220`), and none of these three is among them.
3. `window_manager.open()` calls `frame.show()` — the **frame**, never the
   content.

So the content Control stays `visible = false` for good, and every later
`_process` bails on `not visible`. Reopening **Diplomacy**, **The Union** or the
**Diary** from the action bar yields an empty frame for the rest of the session.
Three of the eleven windows can be permanently destroyed by clicking a button
inside them, and the action a player takes to undo the mistake is the action
that proves it is permanent.

Captured:

```bash
godot --path "<repo>" --script res://tools/screenshot.gd -- --blank diplomacy --out blank_diplomacy.png
```

The frame shows the DIPLOMACY title bar with its PIN and X still intact above a
completely empty body — after one press of Close and one reopen.

*Right behaviour:* hide the button as the other four panels do, or connect
`closed` to the window manager.

**Fixed.** All three gained the `_close_button` field and `hide_close_button()`
method the other four already had, and main.gd now calls it for all five. The
regression check is stronger than the bug: it asserts that **no** docked panel
shows a Close button of its own, and that every window's content survives a
close-and-reopen through the frame's X.

### V4 · A failed load from the main menu starts a new game with no message · P1

`src/ui/main.gd:963-967` reports a load failure through
`_save_load_panel.report(...)` — but that panel is hidden at `:298` and nothing
shows it on this path. From the menu (`:332-333`) a new game has **already been
built** in `_ready()` before the load is attempted, so a corrupt, missing or
version-stale save silently drops the player into a brand-new France with
nothing on screen to say the load failed.

`Continue` (`menu.gd:136-138`) takes the newest slot by mtime and has the same
silent failure — so the button a returning player presses first is the one most
likely to discard their game without a word. The save format refuses a
superseded version outright by design (`save_manager.gd:96-102`, currently
version 22), which makes this reachable on the next bump for every save anybody
holds.

*Right behaviour:* the menu reports the failure and stays on the menu.

**Fixed.** `_on_load_requested` now **shows** the save/load panel on failure and
pauses the clock, instead of painting a message onto a hidden panel.

### V5 · A fresh clone declares three autoload scripts that are not in the repo · P1

`project.godot` `[autoload]` commits three entries pointing into
`res://addons/godot_mcp/services/`. `.gitignore:9` ignores `addons/*` and
whitelists only `addons/at-icons/`, so none of the three exists on a clone.

Proven by cloning the repo and running one test in it:

```
ERROR: Attempt to open script 'res://addons/godot_mcp/services/mcp_runtime_bridge.gd' resulted in error 'File not found'.
ERROR: Failed loading resource: res://addons/godot_mcp/services/mcp_runtime_bridge.gd.
ERROR: Failed to instantiate an autoload, can't load from path: res://addons/godot_mcp/services/mcp_runtime_bridge.gd.
```

— nine lines, three per bridge, on **every startup**, `tools/run_tests.sh`
included. The exit code is still 0, which is exactly why nobody noticed.

This breaks two rules CLAUDE.md states outright: *"no autoloads in the game
code"*, and *"`src/` may reference an addon file **only if that file is
committed**"*. It is dev tooling leaked into shipping config, and it is the one
finding here that a new contributor meets before they have played anything.

*Right behaviour:* the MCP bridges are a local dev concern and do not belong in
a committed `project.godot`.

**Deliberately NOT fixed — this one is yours to call.** Deleting the three
entries fixes every clone and breaks the MCP tooling on this machine, which is
the tooling the audit was asked to use. The options are: commit the three bridge
scripts (they are small, but `.gitignore` says addons are reinstalled per
machine); drop the autoloads and have `docs/tooling.md` tell each machine to add
them locally; or keep them and accept nine error lines per startup on every
clone. That is a decision about how this repo wants to carry dev tooling, not a
repair.

### V6 · Companies' and People's Close buttons do nothing at all · P2

`src/ui/companies_panel.gd:84` and `src/ui/people_panel.gd:72` connect Close to
`closed.emit()` with **no `hide()`**. `main.gd` connects neither signal and
calls neither panel's `hide_close_button()` (contrast `:195, 204, 215, 220`).
The button is visible, themed, and completely inert.

The pair with V3 is the interesting part: five panels build their own Close
button and **no two of them behave the same way** — three destroy the window,
two do nothing, and the four that got `hide_close_button()` never show one.

*Right behaviour:* hidden like the other four; the window frame already carries
an X.

**Fixed** by the same five `hide_close_button()` calls as V3.

### V7 · `tests/test_cabinet.gd` had never run in the suite · P2 · fixed

55 test files on disk against 54 in `tools/run_tests.sh`'s hand-maintained
array. The missing one covers `can_assign`, `assign`, `effectiveness` and
resignations — a player verb (Politics → **Reassign**) and one of the three
bookable diary verbs.

**Third instance of the class.** `run_tests.sh:36-40` already records
`test_companies.gd` missing for three sessions and `test_society.gd` found in
the same sweep; that sweep did not catch this one.

It **passes**, so nothing was hidden by it. What was hidden is that nobody would
have known if it stopped passing. Added to the runner, with the comment extended
to record the third instance beside the first two.

### V8 · `Bloc.cast_vote` is the only command with no effect delta · P3

`src/ui/bloc_panel.gd:293` calls it with no command signal. Every other player
command has one that `main.gd` turns into a U4 effect delta — budget
`committed`, law `proposed`, diplomacy and companies `acted`, government
`dissolved` and `reassigned`. `bloc_panel` carries only `closed`.

So casting a vote in the council — binding on the player whichever way it goes —
never appears in Overview's RECENT DECISIONS, the surface that exists to say
what you did.

The test states the comparison rather than asserting the absence alone: if the
other six lost their signals the absence would still hold and would mean
nothing.

**Fixed.** `bloc_panel` gained `signal voted(before, label)`, emitted from
`_on_vote` with a `Trends.snapshot_now()` baseline exactly as `nation_panel.acted`
does, and main.gd connects it to `_queue_effect`. The regression asserts both the
signal **and** that something is connected to it — a signal nothing listens to is
the same silence with more code in it.

### V9 · Uncommitted deletion in `project.godot` · P3 · fixed

The working tree had silently dropped the four-line `[display]` comment
explaining why the stretch mode is `expand` rather than `keep`. Nothing else in
the file had changed. Restored.

### V10 · Diplomacy opened from the action bar rendered an empty window · P1 · fixed

Found by the repair pass, and only visible **because** V3 was fixed: the stray
Close button had been the one thing drawn in that window, so a blank body read as
a panel with a control rather than as a panel with nothing in it.

`nation_panel._process()` early-returned on `_nation_id == ""`, so the panel drew
literally nothing until a nation had been clicked on the map. main.gd registers
the window with the comment that it is reachable from the World cluster *"so the
diplomatic verbs are not hidden behind knowing to click the map"* — and they were
exactly that. One of the eleven windows was dead on the path the UI advertises.

**Fixed.** The panel now renders an empty state — *"No nation selected / Click a
country on the map to open its file"* — instead of nothing. Deliberately not a
nation picker: the map **is** the picker, and a second list of the same ten would
be a surface to keep in step with it for no gain.

---

## Register B — read from source, not yet reproduced

Each carries a `file:line`. None is pinned by a test yet; a later session
confirming one should move it up and add its check.

### Elections

- **A GBR player who loses badly is told they were RE-ELECTED.**
  `dissolution.gd:100-115` moves `next_election_*` and by design leaves
  `next_executive_*` alone — but for a nation with no executive
  `elections.gd:54-56` had set the two clocks equal. Great Britain is
  `has_executive` false, `executive_discretion`, `party_not_largest`, and
  **playable**. One snap election desyncs the clocks permanently, and
  `election_panel.gd:86,103` then picks its title from a stale `ns.last_election`.
- **Two more paths lose the game with no panel at all**, on the same
  no-result-appended shape as V1: `elections.gd:150-151` (V1 itself) and
  `:158,164`.

### Pause menu and modals

- **Resume does not resume.** `main.gd:313-317` opens Save/Load from the pause
  menu without calling `_close_pause_menu()`, leaving `paused == true`. A later
  Escape re-enters `_open_pause_menu()` and captures `_paused_before_menu =
  true`, so Resume (`:434-438`) restores `paused = true`. Escapable only via
  Space or the clock cluster.
- **`S` during the pause menu opens the save panel underneath it.** The binding
  is in `_unhandled_input` and still fires; the save holder is added at `:296`,
  before the pause holder at `:309`, so it renders below and is unclickable.

### Staleness and cost

- **A second pinned panel shows pre-command figures.** None of the five command
  handlers (`main.gd:196, 205, 208, 221, 236, 279`) calls `_mark_all_dirty()`.
  The list itself is complete — U6b's `_people_panel` omission is fixed at
  `:1018` — so the gap is in who calls it, not in what it contains.
- **The budget panel simulates 48 months every month with its window shut.**
  `budget_panel.gd:345-349` gates `_process` on `visible`, not
  `is_visible_in_tree()`; `window_manager` hides only the frame and
  `hide_close_button()` makes the panel's own `hide()` unreachable, so `visible`
  is permanently true. Each refresh is 2× `Budget.preview()` and 2× a 24-month
  `Budget.project()`.
- **The budget panel offers to undo a law that just passed.** `_on_revert()`
  (`:303-315`) is the only path that re-syncs `_pending` from state, and
  `mark_dirty()` (`:354-356`) does not call it — so a tax law applied through
  `legislature.gd:262-277` leaves the levers showing the pre-law position.
  Already written up in [[tax-model]] §11 at V1.6d.

### Numbers that are wrong rather than absent

- `trends.gd:75-88` — `approval_delta()` checks `is_empty()` but not
  `has(APPROVAL_KEY)`, unlike its sibling `delta()` which returns `NAN`. A
  history entry missing approval yields a small **fake** approval movement, and
  that number feeds Overview's lead sentence, the election countdown and the
  Moving column.
- `elections.gd:258-259` `.get(..., 0)` renders at `election_panel.gd:172,176`
  as *"X is no longer the largest party: 0 of 577 seats"*.
- `polling_panel.gd:197` renders a missing bloc as **`0%`** approval — a
  plausible-looking catastrophe rather than an obvious absence.
- `bloc_panel.gd:159-161` prints *"Divides in 0 months"*.

### Diary

- **30 February is accepted.** The day SpinBox allows 1–31 for any month
  (`calendar_panel.gd:180-183`) and `calendar.gd:99-122` never checks month
  length, so the entry fires on 1 March via the `<=` at `:154-162`.
- **A booked law fires without re-checking `Legislature.available()`**
  (`main.gd:882-887`), unlike the booking-time gate at
  `calendar_panel.gd:452-455`. The diplomatic branch does re-gate.

### Crash surface

- Hard `[...]` reads on **save-borne** dictionaries: `election_panel.gd:75-242`,
  `law_panel.gd:140-234`, `overview_panel.gd:457-476` (`recent_effects` is
  serialised), `main.gd:746-798` (`foreign_acts`, `unrest_acts`).
- A save with a bad `player_nation_id` gives `player() == null`
  (`game_state.gd:807-808`, unvalidated at `save_manager.gd:107`) and crashes at
  `top_bar.gd:104-109` on the next day tick.

### Save format and UX

- `history` grows one entry per month, unbounded and fully serialised
  (`game_state.gd:848-852, 879`), each entry carrying a nested `sectors` dict.
  `recent_effects` and appointments are both trimmed; this is not.
- No delete, no overwrite confirmation, no autosave
  (`save_load_panel.gd:154-159`).

### Smaller

- Five windows have no keyboard shortcut at all: `diplomacy`, `bloc`,
  `calendar`, `people`, `companies`.
- `hud.gd:112-118` `is_over_furniture()` is documented as guarding map clicks;
  its only callers are in `tests/test_shell.gd`. Dead in the shipped path.

---

## What the audit changed

Found and registered first, then repaired in a second pass:

- `src/sim/elections.gd` — V1: the term limit appends a `termed_out` notice.
- `src/ui/election_panel.gd` — V1 and V2: a TERM LIMIT title and reason, and a
  dismiss control in **both** footer branches.
- `src/ui/main.gd` — V2, V3, V4, V6, V8: `dismissed` branches on whether the
  player still holds office; `hide_close_button()` for all five remaining panels;
  the load-failure panel is shown rather than painted while hidden;
  `bloc_panel.voted` is connected to `_queue_effect`.
- `src/ui/nation_panel.gd`, `bloc_panel.gd`, `calendar_panel.gd` — V3: the Close
  button moved into a field with a `hide_close_button()` method.
- `src/ui/nation_panel.gd` — V10: an empty state instead of an empty window.
- `src/ui/bloc_panel.gd` — V8: `signal voted(before, label)`.
- `tests/test_playability.gd` — new; the register, first as bug-pins, now as
  regressions.
- `tools/run_tests.sh` — `test_cabinet.gd` (V7) and `test_playability.gd` added;
  the missing-test comment extended to record the third instance.
- `tools/screenshot.gd` — `--defeated`, `--blank <window id>` and `--termlimit`,
  the first flags that photograph a defect rather than a feature.
- `project.godot` — V9 restored.

## What it did not

The live pass was specified against godot-mcp, and its **input family was
structurally broken for this project**: `base_commands.gd:_get_input_bridge` looks
up `/root/MCPInputBridge` in the *editor* process, where `mcp_input_bridge.gd` has
no `@tool` annotation and never runs, so every `simulate_key` /
`simulate_mouse_click` call was a silent no-op that reported `{"queued": true}`.
The file-based families (`_runtime_call`, `_request_screenshot`) were unaffected.

> [!note] Since resolved
> That whole stack has been replaced by `godot_mcp_toolkit` — see
> [[tooling#Godot MCP]]. `input_simulate` drives the running game for real, verified
> by effect rather than by a success flag, and `tools/send_input.py` is deleted. A
> re-run of the sittings below can use the live path after all; what is recorded
> here is what the pass had available at the time.

The visual evidence here therefore comes from `tools/screenshot.gd`, driving the
panels' real Buttons through `pressed.emit()` in the running windowed game.
Sittings A4 (run to the 2032 election) and A6 (save/load round-trip, stale
version, corrupt file) have not been run — Register B's save and staleness rows
are the ones they would confirm.
