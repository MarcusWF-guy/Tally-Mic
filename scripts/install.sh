#!/bin/bash
# Builds Tally Mic, quits the running copy, replaces "/Applications/Tally Mic.app" and relaunches it.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh

if pgrep -x TallyMic >/dev/null; then
    pkill -x TallyMic || true
    for _ in $(seq 50); do
        pgrep -x TallyMic >/dev/null || break
        sleep 0.1
    done
fi

rm -rf "/Applications/Tally Mic.app"
cp -R "build/Tally Mic.app" "/Applications/Tally Mic.app"

# Right after the old copy quits, macOS can refuse to open the new one (error -600) for a moment.
for _ in $(seq 5); do
    open "/Applications/Tally Mic.app" 2>/dev/null && break
    sleep 1
done
sleep 1
if pgrep -x TallyMic >/dev/null; then
    echo "Tally Mic is installed and running."
else
    echo "Tally Mic is installed but didn't start. Open it from the Applications folder." >&2
    exit 1
fi
