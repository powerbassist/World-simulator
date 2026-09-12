# Test-suite model — the cockpit and the runner

**2026-09-11 · branch `test-suite-cockpit` · the gate's measured record: 51:56 sequential → 9:18 parallel and sharded, 82/82 both ways.** Instrument: `tools/suite_runner.py` (one execution core), `tools/suite_gui.py` (the view). Baseline numbers live in `reports/baseline_times.txt` (gitignored, like all of `reports/`); every run's artifacts live in `reports/suite_runs/<ts>/` and are committed nowhere — the model doc carries the numbers, the tooling produces them.

## 1. Why

The old gate was a bash loop that started one godot per test and waited: **51:56** wall (3117 s incl. overhead), 82 tests, 0 script errors — on a machine with 16 cores, 15 of them idle for the whole run. What it showed the session was a progress bar, not results: a `[n/82] name` stream with no per-test artifact, so learning *which* check failed meant scrolling console output, and the re-run discipline (V1.7c) diffed console captures by hand. A hung engine hung the gate — nothing bounded a wedged child. And the loop, the status parsing and the failure semantics existed only in bash, so every consumer of the suite (a session, a probe, a GUI) either re-ran the loop or re-derived its semantics.

The response is one execution core with the gate's semantics in exactly one place, a worker pool over it, per-test artifacts, and a view on top. The registry does not move: `tools/run_tests.sh` keeps `tests=()` and the unregistered-test red check, because a test file on disk that is missing from the array runs NOWHERE — that has happened four times (test_companies V1.4a, test_cabinet, test_summits V2.4b, test_map_plants V2.8), each found by eye whole sessions later, and counting the directory is what closes the class.

## 2. The one core: `tools/suite_runner.py`

`tools/run_tests.sh` is the human entry and keeps five jobs: the registry, the unregistered-test check, a loud python check (exit 2 — python is a gate dependency, `tools/import_data.py` already made it one), the runner selftest as step 0, and the cold-clone `.godot/` import pass (V2.8's fresh-clone finding: no class cache means the committed autoload does not parse). Everything below that is `exec python tools/suite_runner.py --ci "$@" "${tests[@]}"`. The bash status line, per-test capture, noise filter and script-error scan are deleted — they exist once now, in the Python.

**The registry stays the only list.** `bash tools/run_tests.sh --print-tests` prints it; the cockpit and any caller read it from there. The runner never holds a test list, and no second list exists anywhere to drift (the keycode lesson, the panel-list lesson, applied to the suite itself).

Gate semantics — the table the whole suite stands on:

| child outcome | verdict |
|---|---|
| exit 0, no `SCRIPT ERROR`/`Parse Error` in output | pass |
| non-zero exit | fail |
| exit 0 **with** a script error in output | fail — quit(0) over a broken parse is V2.1c's silent-red class, and the gate exists because of it |
| exceeds `--timeout` (default 1800 s) | child killed, status `timeout`, red — a hang is red, not silent |
| `[MCPRuntimeServer]`/`[MCPRegistry]` lines | filtered from DISPLAY, never from the verdict scan — V1.7c's rule: filter the bridge noise, do not let the filter hide a third line |

Exit codes: **0** green; **1** any failure; **2** godot not found (`GODOT_BIN`) or no python; **130** interrupted — Ctrl-C cancels queued jobs, kills live children (a killed runner must not orphan godots holding `user://` open against the next run's exclusive lane), and writes a partial `results.json` of what finished.

`--ci` is the agent norm. The cockpit (§6) is a view and never a gate: green/red is the runner's exit code, and nothing else in the toolchain issues one.

## 3. Parallelism

There is ONE execution path. The sequential runner was deleted at Task 2: `-j1` is the same `run_parallel` with a one-worker pool, submission order and report order both registry order, so sequential semantics hold by construction rather than by a second code path that could rot out from under the first.

- **Default `-j min(8, cpu_count)`** — 8 on the dev machine's 16 cores. The cap is memory-informed, not a guess: a headless godot process measures **~150 MB**, so -j8 holds ~1.2 GB of children.
- **Peak concurrency is jobs+1**: one plain pool of `jobs` workers plus the exclusive lane's single worker (§4), so `-j8` runs at most 9 godot children.
- **Registry-order reporting.** Children complete out of order; the report phase walks the registry, so the console completion lines and `results.json` are diffable run over run. A sharded test's log is assembled in the tag's listed order for the same reason (§5).
- **Per-test timeout** kills a wedged child and records `timeout` — the old loop's unbounded wait is structurally gone.
- **Artifacts per run**: `events.ndjson` (a `start` per test at submission, child events for shards, `done` per test, `summary` at the end, flushed per event — the cockpit's live tail), one log per test, `results.json` at the end. A plain test's log is written when its child finishes, not in the report phase — the cockpit's reason a finished test is clickable DURING a run; a sharded test's log is still the report-phase ordered concat. The re-run discipline keeps diffing the same artifact it always diffed — the per-test log — it is just written to disk now instead of captured from a console.

## 4. Exclusivity — the tag, not a list

The parallel-safety audit (Task 2, recorded in `baseline_times.txt`) found the honest shape of the problem: a three-pattern union over `tests/` hits 39 files, of which 37 are `res://` READS — parallel-safe. The `user://`-only pattern leaves **exactly two writers**: `tests/test_menu.gd` (backs up and restores `user://settings.cfg`) and `tests/test_save_load.gd` (real filesystem I/O against `user://saves/`).

Those two carry `## suite-exclusive:` **in their own source**, with the reason written beside the tag. Nothing else holds the set: the runner's `read_tags()` parses it, `run_tests.sh`'s directory count needs no copy, and the cockpit imports the same parser for its filter — one parser, three consumers, no drift. The lane itself is a 1-worker executor, so two tagged tests cannot overlap **by construction**, independent of any timing.

That was also verified empirically, because a structural argument about threads deserves a measurement: in the -j8 run the menu child ends at 1789173490.5605 and save_load begins at 1789173490.5602 — back-to-back within 0.3 ms, below cross-thread clock noise (a naive span-overlap predicate "fires" on exactly that artifact); the -j4 pair smoke's wall equals the exact sum of child durations, **74.2 s**, where concurrent execution would have cost the longer, not the sum. Exclusion is exclusive-vs-exclusive only — tagged tests run freely beside plain ones, and the full -j1 run is the proof that disturbs nothing.

## 5. Sharding — the long poles, per check

Solo, the three long poles are **natural_change 466 s, migration 423 s, balance 331 s** — three files, 41 % of the -j1 suite. Under -j8 they are the tail: pre-sharding -j8 is 10:55 because each file's checks run sequentially inside one process after the pool has nothing else to feed it.

The lever reuses machinery the suite already had: `## suite-shard-checks:` lists check names in the test's own source, and `flatten_jobs()` expands one child per check through the file's existing `-- <check_name>` dispatch — balance's V3.3 crash-isolation contract, untouched; natural_change and migration adopted the same idiom (and an unknown check name exits 1, because green-over-nothing is V2.1c's class). **34 children replace 3 sequential hours**: balance 15 checks, natural_change 8, migration 11.

**The normalization rule is the whole cost of sharding.** Each shard child is its own godot process: every one prints the engine banner plus its blank line and, green, its own "all checks passed", where the monolithic run prints ONE of each. `normalize_shard_log` drops each child's banner pair and green line, re-emits the banner once at the top, and appends the single green line iff everything passed; per-check prints (balance's `note:` lines) are the content that survives, in tag order. The rule exists so that **the re-run discipline keeps diffing the same artifact** — a sharded log is byte-identical to the monolithic one, so turning sharding on cannot change what a re-run comparison sees. Three gates prove it rather than trust it, all byte-identical after MCP-noise filtering:

1. **Mono refactor identity** — the dispatch edits alone change nothing: `natural_change identical`, `migration identical`.
2. **Green shard identity** — full suite with sharding live, all three logs IDENTICAL against the pre-shard baselines.
3. **Red mutation gate** — `_fail("mutation probe")` as the first statement of `_check_one_tuned_constant()`: exactly one child fails, the mono run fails once, same line, same last position, **RED IDENTICAL**, runner exit 1. This gate is the one that matters: it catches the failure mode where sharding silently turns a red suite green (a shard that ran nothing must not pass).

**The measured gain is 10:55 → 9:18 (~17 %), and the plan's 3.5–5 min prediction was wrong for a structural reason the run exposed**: the critical path is now one unshardable check in each of two poles — migration's `_check_the_tick_moves_toward_the_pull` (**379.8 s**) and natural_change's `_check_conservation_is_exact` (**376.0 s**), each ticking all 29 roster nations × 168 months — and per-check sharding cannot split a check. ~9 minutes is this design's floor until one of those two checks is itself decomposed; the sharding's larger value is **crash isolation per check** (one regime crashing no longer costs the other fourteen, and the survivors still report), with the speed almost a side effect.

## 6. The cockpit — a view, never a gate

`tools/suite_gui.py` (tkinter, stdlib), launched detached by `tools/run_tests_gui.sh` so the window survives the calling shell. It RUNS ON OPEN (the author's 2026-09-12 verdict on the first version was "not automatic"; `--no-run` opts out, `--attach` never auto-runs) and a finished run with failures answers "what broke" by itself — failed filter on, first failure selected, its log in the pane. It shows per-test rows — status, duration, sharded-check count — with filters (all / failed / slow ≥ 30 s / exclusive), re-run and run-all **through the runner** (the runner is a child process; Stop takes down its process group, with escalation), a click-to-read pane over that run's per-test logs, read-only loading of any past run's `results.json`, and **live attach**: `--attach RUN_DIR` tails a run's `events.ndjson`, so the cockpit can sit beside an agent's `--ci` run and watch it, not only launch its own.

Every list it shows comes from the runner's own parsers — the registry via `--print-tests`, the exclusive set via `read_tags()` — so the window cannot name a test the registry does not, and the exclusivity filter cannot drift from the lane. Refresh detail owes V1.6d its shape: a not-yet-run row prints no seconds at all rather than a confident `0.0`.

It has no verdict authority: no exit code, no green of its own. The gate is `python tools/suite_runner.py --ci` and its exit code; the cockpit is what a human looks at while that runs.

## 7. Refusals — deliberately absent

- **gdUnit4 / GUT.** The suite is 82 bespoke files, and the bespoke part is the asset: each file asserts project-specific measured identities — partitions closing to 1e-12, bit-identical re-runs, source-policing greps, four-hands checks — that no framework's vocabulary expresses, so a migration is a whole-suite rewrite producing **zero new checks** while risking the 82 that exist (the registry's four silent-absence incidents were each ONE unnoticed file; a rewrite risks them at scale, in one commit). And a test framework is an addon: the dialogue_manager precedent prices that adoption at a committed dependency, a stated exception to the project's own rules, and a fresh-clone gate to prove it parses cold. Paying that for verdict-and-reporting machinery this suite already has, in stdlib, is the trade refused.
- **pip dependencies.** Both tools are stdlib-only (`concurrent.futures`, `dataclasses`, `tkinter`). Python *itself* is a gate dependency — the import pipeline made it one first — and `run_tests.sh` fails loud at exit 2 without it. A `requirements.txt` would stand between a fresh clone and a green gate, and the fresh-clone gate is load-bearing: V2.8's review proved by cloning that a gate which only passes on a warm machine is not a gate.
- **A CI service.** There is no CI; the runner IS the gate, and it runs on the machine that has the game. A hosted runner re-derives godot, the addons and the import pass at arm's length and adds a second notion of green — the exact shape of the drift the unregistered-test check exists to kill, one tier up. The registry is executed where the repo is, which is why a file that runs nowhere turns red in the session that writes it.
- **Batching many tests per engine process.** The unit of isolation is the process start: each test gets a fresh godot with none of the last test's statics, caches or `user://` side effects — the state-pollution class a headless suite exists to make impossible is unmakeable by ordering when tests share an engine. One engine start per test is the point, not overhead to optimize away; whatever it costs is bounded by the child-start sum and is already inside every number in §8.
- **Worktree execution for this tooling.** The re-run discipline legitimately runs `src/` diffs from worktrees — the missing-addon parse noise is identical on both sides and cancels. This tooling cannot live there: `addons/` is gitignored per-machine, so a worktree has no DialogueManager and no class cache lineage, and the suite is RED in it (V2.8's 604-error fresh-clone run is exactly this state, and the reason `run_tests.sh` grew its import pass). The gate runs in the repo checkout where the game runs; a worktree is where you diff, not where you gate.

## 8. Measured

All times wall-clock, dev machine (Windows, git-bash, 16 cores, Python 3.13 stdlib), machine idle, 82/82 pass unless noted. Full record: `reports/baseline_times.txt`.

| configuration | wall | notes |
|---|---|---|
| old bash loop, sequential | **51:56** (3117 s) | one godot at a time; the number this block replaces |
| `suite_runner.py -j1` | **49:04** (2945 s) | same one execution path, 1 worker (Task 1's first -j1 read 50:22 — the ±2 min noise band, sequential unchanged) |
| `-j8`, monolithic poles | **10:55** (656 s) | 4.5x over -j1; exclusive lane live |
| `-j8`, sharded poles | **9:18** (558 s) | 34 shard children; the design's floor — two ~380 s unshardable checks on the critical path |

Long poles solo: natural_change 466 s, migration 423 s, balance 331 s. The unshardable pair: migration `_check_the_tick_moves_toward_the_pull` 379.8 s, natural_change `_check_conservation_is_exact` 376.0 s — each 29 nations × 168 months, which is why the spec's ~4 min was never reachable without decomposing a check.

Suite shape: **82 tests**, one headless godot process per test (per check, where sharded) at **~150 MB** each, default `-j min(8, cpu_count)`, peak concurrency jobs+1.
