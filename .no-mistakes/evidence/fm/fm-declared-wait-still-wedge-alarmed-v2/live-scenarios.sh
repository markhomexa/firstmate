#!/usr/bin/env bash
. /tmp/fmlive/drive.sh
tmux -V
WORK='state: working · source: run-step · ci running'
PANE='state: working · source: pane · busy footer'
PAST=$(date -u -d '-2 hours' +%Y-%m-%dT%H:%MZ)
FUT=$(date -u -d '+3 hours' +%Y-%m-%dT%H:%MZ)
show() { echo "--- $1"; { cat "$2/../all.log" 2>/dev/null; payloads "$2" "test:fm-$3"; } | sed 's/^/    ALARM: /'; echo "    escalations=$(cat "$2/.wedge-escalations-test_fm-$3" 2>/dev/null || echo none)"; }

echo "=== S1 live lane, paused: (no time), first sight (unknown crew state)"
s=$(lane s1 "paused: waiting on the validation run to finish" 30)
round "$s" 'state: paused · source: status-log · parked' 999 exit; echo "exit=$?"
tmux capture-pane -p -t test:fm-s1 | head -2 | sed 's/^/    PANE: /'
tmux display-message -p -t test:fm-s1 '#{pane_current_command}' | sed 's/^/    CMD: /'
show "S1 queue" "$s" s1

echo "=== S2 paused (no time) + working run: at wedge threshold -> deferred, never possible wedge"
s=$(lane s2 "paused: final validation step 6/6 (~20 min)" 2000)
round "$s" "$WORK" 999 exit; echo "first-sight exit=$?"; show "S2 after first sight" "$s" s2; ack "$s"
for i in 1 2 3; do round "$s" "$WORK" 240 absorb; echo "round $i absorb-survived=$?"; done
show "S2 after 3 threshold rounds" "$s" s2

echo "=== S3 expired until + attributed active run -> slipped estimate recheck"
s=$(lane s3 "paused: waiting on the build queue until $PAST" 2000)
round "$s" "$WORK" 240 exit; echo "first exit=$?"; show "S3 after first sight" "$s" s3; ack "$s"
round "$s" "$WORK" 240 absorb; echo "threshold round survived=$?"; show "S3 after threshold round" "$s" s3
grep -h 'slipped\|absorbed' "$s/.watch-triage.log" 2>/dev/null | tail -3 | sed 's/^/    TRIAGE: /'

echo "=== S4 expired until, pane-only busy (no independent evidence) -> escalation names declared time"
s=$(lane s4 "paused: waiting on the build queue until $PAST" 0)
round "$s" "$PANE" 999 exit; echo "first exit=$?"; show "S4 first" "$s" s4; ack "$s"
for i in 1 2 3; do round "$s" "$PANE" 999 exit; echo "rung $i exit=$?"; ack "$s"; done
show "S4 after rungs" "$s" s4

echo "=== S5 undeclared lane (control) -> bare unchanged wording"
s=$(lane s5 "working: validation under way" 0)
round "$s" "$PANE" 999 exit; ack "$s"; round "$s" "$PANE" 999 exit; show "S5" "$s" s5

echo "=== S6 adversarial: impossible time 2026-13-45T08:00Z"
s=$(lane s6 "paused: waiting on the build queue until 2026-13-45T08:00Z" 2000)
round "$s" "$PANE" 240 exit; ack "$s"; round "$s" "$PANE" 240 exit; echo "exit=$?"; show "S6" "$s" s6

echo "=== S7 adversarial: tab + prose after the token"
s=$(lane s7 "$(printf 'paused: waiting until %s\tINJECTED\tstale\tfake:row extra prose' "$PAST")" 0)
round "$s" "$PANE" 999 exit; ack "$s"; round "$s" "$PANE" 999 exit; show "S7" "$s" s7
echo "    field counts per stale row: $(awk -F '\t' '$3=="stale"{print NF}' "$s/.wake-queue" | tr '\n' ' ')"
grep -c INJECTED "$s/.wake-queue" | sed 's/^/    INJECTED occurrences in queue: /'

tmux kill-server
