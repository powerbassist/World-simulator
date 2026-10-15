# Contributing

Thank you for looking. Issues are welcome for bugs, balance problems and ideas.
Pull requests are welcome once they meet the points below.

## Before a pull request

- **Sign the [CLA](CLA.md) once.** On your first pull request, a bot asks you to
  comment *"I have read the CLA Document and I hereby sign the CLA"*. It is what
  lets the project stay noncommercial in public and still be offered commercially
  by its author.
- **Read [AGENTS.md](AGENTS.md).** It is the project's rulebook, for humans and AI
  assistants alike. The parts that most often fail a review:
  - content lives in `data/`, never in code: no `if nation_id == "FRA"`;
  - dependencies go `data → sim → ui`, and `src/sim/` never touches the UI;
  - tuning constants live in `src/sim/*_constants.gd`;
  - new simulation behaviour needs a headless test.
- **Run the suite.** `bash tools/run_tests.sh` must be green, and so must
  `bash tools/check_names.sh`. CI runs both on your pull request.
- **No real names.** Every person, party and company in the game is fictional.
  `tools/check_names.sh` enforces it.
- **Declare the licence of anything new that is not code.** `reuse lint` must
  pass: add a `REUSE.toml` annotation for new assets, data from a new source, or
  third-party files.
- **UI changes.** Attach a screenshot from `tools/screenshot.gd`, run windowed.
  `--headless` draws nothing.

## Godot version

4.7.1-stable, standard (non-Mono). Do not commit `project.godot`: the editor
rewrites it on every open (see AGENTS.md, "Gotchas").
