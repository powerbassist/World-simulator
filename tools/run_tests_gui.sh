#!/bin/bash
# The suite cockpit (V3.6 tooling). Detached so the window survives the
# calling shell; it launches tools/suite_runner.py itself.
cd "$(dirname "$0")/.." || exit 1
python tools/suite_gui.py &
