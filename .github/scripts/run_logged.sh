#!/usr/bin/env bash
# Runs a command; if it fails, publishes the important log lines as
# GitHub annotations (visible on the run page without signing in).
set -o pipefail
"$@" 2>&1 | tee build.log
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
  { grep -nE "error|Error|ERROR|What went wrong|FAILURE|Exception|Could not|Failed" build.log | head -40; echo "----- last lines -----"; tail -50 build.log; } > err.txt
  split -l 22 err.txt errpart_
  for f in errpart_*; do
    msg=$(sed -e 's/%/%25/g' -e 's/\r//g' "$f" | cut -c1-300 | awk '{printf "%s%%0A", $0}')
    echo "::error title=$(basename "$f")::$msg"
  done
fi
exit "$status"
