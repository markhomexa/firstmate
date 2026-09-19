. /tmp/fmlive/drive.sh
WATCH=/tmp/fmlive/base/bin/fm-watch.sh; DRAIN=/tmp/fmlive/base/bin/fm-wake-drain.sh
echo "BASELINE watcher: $WATCH (commit 2bcb88c3)"
WORK='state: working · source: run-step · ci running'
PANE='state: working · source: pane · busy footer'
PAST=$(date -u -d '-2 hours' +%Y-%m-%dT%H:%MZ)
show() { echo "--- $1"; { cat "$2/../all.log" 2>/dev/null; payloads "$2" "test:fm-$3"; } | sed 's/^/    ALARM: /'; }
s=$(lane b3 "paused: waiting on the build queue until $PAST" 2000)
round "$s" "$WORK" 240 exit; ack "$s"; for i in 1 2 3; do round "$s" "$WORK" 240 exit; ack "$s"; done
show "BASE S3: expired until + attributed active run (healthy pipeline)" "$s" b3
tmux kill-server
