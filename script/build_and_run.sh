#!/usr/bin/env bash
set -euo pipefail

mode="${1:-run}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/dist/SmileTool.app"

case "$mode" in
    run|--verify|--debug|--logs|--telemetry) ;;
    *) echo "Usage: $0 [run|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac

pkill -x SmileTool >/dev/null 2>&1 || true
"$root/scripts/build-app.sh"
/usr/bin/open -n "$app"

if [[ "$mode" == --verify || "$mode" == --debug ]]; then
    pid=""
    for _ in {1..20}; do
        pid="$(pgrep -x SmileTool | head -1 || true)"
        [[ -n "$pid" ]] && break
        sleep 0.25
    done
    [[ -n "$pid" ]] || { echo "SmileTool did not start" >&2; exit 1; }
    command_line="$(ps -p "$pid" -o command=)"
    [[ "$command_line" == "$app/Contents/MacOS/SmileTool"* ]] || {
        echo "A different SmileTool process started: $command_line" >&2
        exit 1
    }
    sleep 0.5
    kill -0 "$pid" 2>/dev/null || { echo "SmileTool exited immediately" >&2; exit 1; }
    echo "SmileTool started (PID $pid)"
    if [[ "$mode" == --debug ]]; then exec lldb -p "$pid"; fi
elif [[ "$mode" == --logs ]]; then
    exec /usr/bin/log stream --info --style compact --predicate 'process == "SmileTool"'
elif [[ "$mode" == --telemetry ]]; then
    exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.gumu.smiletool"'
fi
