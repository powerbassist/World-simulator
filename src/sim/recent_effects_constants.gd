extends RefCounted

## The bound on GameState.recent_effects, read by src/sim/recent_effects.gd, its
## one writer. Here rather than beside the write because AGENTS.md keeps tuning
## constants in src/sim/*_constants.gd.

## How many decisions the Overview's list keeps -- U4. The array's own size is
## unbounded; trimmed so a long session's save does not grow one entry per commit
## forever.
const KEPT := 5
