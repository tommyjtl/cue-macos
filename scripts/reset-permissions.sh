#!/usr/bin/env bash
set -euo pipefail

BUNDLE_ID="com.cruxbetalabs.Cue"

echo "Resetting TCC permissions for ${BUNDLE_ID}..."
tccutil reset ScreenCapture "$BUNDLE_ID"
tccutil reset Accessibility "$BUNDLE_ID"
echo "Done. Quit Cue if it is running, then reopen and enable both permissions in System Settings."
