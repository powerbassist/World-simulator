#!/bin/bash
# Launch the test suite inside its progress window (V3.3, author request).
# Detached via `start` so the window survives the calling shell; the suite's
# output is teed to reports/suite_gui.log either way.
cd "$(dirname "$0")/.." || exit 1
mkdir -p reports
python tools/test_progress_gui.py --log reports/suite_gui.log &
echo "progress window running; output teed to reports/suite_gui.log"
