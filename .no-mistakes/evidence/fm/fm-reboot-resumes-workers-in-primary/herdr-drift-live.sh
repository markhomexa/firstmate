#!/usr/bin/env bash
# Live drive of bin/fm-worktree-drift.sh against a REAL Herdr server on a private
# fm-lab-* session (never the default session). Reproduces the 2026-09-19 reboot
# shape: the task pane's recorded cwd is the PRIMARY checkout, and a resumed
# `claude --resume <id>` agent is running there instead of in its worktree.
# Usage: herdr-drift-live.sh <repo-root> <scratch-dir>
set -u
ROOT=$1; SB=$2
. "$ROOT/tests/herdr-test-safety.sh"      # exports FM_GATE_REFUSE_BYPASS=1 (sandbox only)
herdr_forget_inherited_pane
unset NO_MISTAKES_GATE
SESSION="fm-lab-drift-$$"
export HERDR_SESSION="$SESSION"
cleanup() { herdr_safe_stop_and_delete "$SESSION"; }
trap cleanup EXIT
fm_herdr_lab_prepare "$SESSION" || { echo "lab prepare failed"; exit 1; }
rm -rf "$SB"; mkdir -p "$SB/fakebin" "$SB/home/state" "$SB/home/data/t1"
SB=$(cd "$SB" && pwd -P)
cat > "$SB/fakebin/claude" <<'SH'
#!/bin/bash
LOG=${FAKE_CLAUDE_LOG:?}
case "${1:-}" in --version|-v) echo "2.1.999 (Claude Code)"; exit 0;; esac
printf '%s start pid=%s cwd=%s args=%.80s\n' "$(date +%T)" "$$" "$(pwd -P)" "$*" >> "$LOG"
herdr pane report-agent "$HERDR_PANE_ID" --source fake-claude --agent claude --state idle --session "$HERDR_SESSION" >/dev/null 2>&1 \
  || printf 'report-agent failed\n' >> "$LOG"
draw(){ stty -echo 2>/dev/null; printf '\033[2J\033[H╭────╮\n│    │\n╰────╯\033[2;3H'; }
draw
while IFS= read -r line; do
  printf '%s input pid=%s: %.60s\n' "$(date +%T)" "$$" "$line" >> "$LOG"
  case "$line" in /exit|/quit) printf '%s exit pid=%s\n' "$(date +%T)" "$$" >> "$LOG"; exit 0;; esac
  draw
done
SH
chmod +x "$SB/fakebin/claude"
PROJ="$SB/proj"; WT="$SB/wt"
git init -q -b main "$PROJ"; printf '# proj\n' > "$PROJ/README.md"; git -C "$PROJ" add README.md
git -C "$PROJ" -c user.email=t@t -c user.name=t commit -qm init
git -C "$PROJ" worktree add -q -b task-t1 "$WT"
printf '%s\n' '# Task' "## Captain's intent" 'Keep working.' '' '## Firstmate spec' 'Stay in the worktree.' > "$SB/home/data/t1/brief.md"
. "$ROOT/bin/fm-backend.sh"; fm_backend_source herdr || exit 1
CONTAINER_RAW=$(fm_backend_herdr_container_ensure "$PROJ") || { echo container_ensure failed; exit 1; }
CONTAINER=${CONTAINER_RAW%%$'\t'*}; SEEDED=${CONTAINER_RAW#*$'\t'}; WSID=${CONTAINER#*:}
# The task pane is created with the PRIMARY checkout as its cwd - what Herdr records and restores.
read -r TAB PANE <<<"$(fm_backend_herdr_create_task "$CONTAINER" fm-t1 "$PROJ" "$SEEDED")"
T="$SESSION:$PANE"
cat > "$SB/home/state/t1.meta" <<M
window=$T
endpoint_task_id=t1
worktree=$WT
project=$PROJ
harness=claude
kind=ship
mode=no-mistakes
yolo=off
tasktmp=$SB/tasktmp
model=default
effort=default
backend=herdr
herdr_session=$SESSION
herdr_workspace_id=$WSID
herdr_tab_id=$TAB
herdr_pane_id=$PANE
M
cp "$SB/home/state/t1.meta" "$SB/meta-before"
fm_backend_herdr_send_text_line "$T" "export PATH=$SB/fakebin:\$PATH FAKE_CLAUDE_LOG=$SB/claude.log HERDR_PANE_ID=$PANE HERDR_SESSION=$SESSION"
fm_backend_herdr_send_text_line "$T" "claude --resume 11111111-2222-3333-4444-555555555555"
for _ in $(seq 1 50); do [ "$(fm_backend_agent_state herdr "$T")" = alive ] && break; sleep 0.2; done
echo "== BEFORE (restored-after-reboot shape) =="
echo "agent state:            $(fm_backend_agent_state herdr "$T")"
echo "herdr foreground_cwd:   $(fm_backend_herdr_current_path "$T")"
echo "recorded worktree:      $WT"
git -C "$PROJ" status --porcelain=v1 --ignored > "$SB/proj-status-before"; ls -lA "$PROJ" | sed 1d > "$SB/proj-ls-before"
echo; echo "== \$ fm-worktree-drift.sh scan =="
FM_HOME="$SB/home" "$ROOT/bin/fm-worktree-drift.sh" scan
if [ "${MODE:-repair}" = prpoll ]; then
  # Intent's related bug: a relaunch rewrote the task record and silently disarmed its PR merge poll.
  printf '#!/bin/sh\nexit 1\n' > "$SB/fakebin/gh"; chmod +x "$SB/fakebin/gh"
  echo; echo "== product under test: $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || cat "$ROOT/.product-rev") =="
  echo "== \$ fm-pr-check.sh t1 https://github.com/example/repo/pull/40 =="
  FM_HOME="$SB/home" PATH="$SB/fakebin:$PATH" "$ROOT/bin/fm-pr-check.sh" t1 https://github.com/example/repo/pull/40 2>&1 | tail -2
  ( . "$ROOT/bin/fm-pr-lib.sh"; fm_pr_poll_artifacts_valid "$SB/home/state" t1 "$ROOT/bin/fm-pr-poll.sh" && echo "poll authenticates BEFORE relaunch: yes" || echo "poll authenticates BEFORE relaunch: NO" )
  echo; echo "== \$ fm-control.sh t1 relaunch --note ... (the lifecycle call drift repair makes) =="
  FM_HOME="$SB/home" PATH="$SB/fakebin:$PATH" FM_CONTROL_LAUNCH_WAIT=40 timeout 300 "$ROOT/bin/fm-control.sh" t1 relaunch --note "resumed outside its worktree after a reboot" 2>&1 | tail -1
  ( . "$ROOT/bin/fm-pr-lib.sh"; fm_pr_poll_artifacts_valid "$SB/home/state" t1 "$ROOT/bin/fm-pr-poll.sh" && echo "poll authenticates AFTER relaunch: yes" || echo "poll authenticates AFTER relaunch: NO" )
  echo "task record tail (pr lines must stay last):"; tail -4 "$SB/home/state/t1.meta"
  echo; echo "== live watcher check sweep (FM_CHECK_INTERVAL=1, 45s bound) =="
  FM_HOME="$SB/home" PATH="$SB/fakebin:$PATH" FM_CHECK_INTERVAL=1 FM_WORKTREE_DRIFT_INTERVAL=3600 \
    timeout 45 "$ROOT/bin/fm-watch.sh" > "$SB/watch.out" 2>&1; echo "watcher rc=$? (124 = no wake within 45s)"
  echo "-- watcher output:"; cat "$SB/watch.out"
  grep -q "rejected unauthenticated state checks" "$SB/watch.out" && echo "RESULT: watcher REJECTED the PR poll" || echo "RESULT: watcher did not reject the PR poll"
elif [ "${MODE:-repair}" = session ]; then
  # Throwaway firstmate root + fake network/bootstrap tools; the backend (real Herdr lab) is real.
  FROOT="$SB/fmroot"; mkdir -p "$FROOT"; git -C "$ROOT" archive HEAD | tar -x -C "$FROOT"
  git init -q -b main "$FROOT"; git -C "$FROOT" add -A; git -C "$FROOT" -c user.email=t@t -c user.name=t commit -q -m "product at target commit"
  TB="$SB/toolbin"; mkdir -p "$TB"
  for t in node chrome-devtools-axi; do printf '#!/bin/sh\nexit 0\n' > "$TB/$t"; done
  printf '#!/bin/sh\n[ "$1" = --version ] && echo 0.1.46; exit 0\n' > "$TB/lavish-axi"
  printf '#!/bin/sh\n[ "$1" = --version ] && echo 0.1.29; exit 0\n' > "$TB/gh-axi"
  printf '#!/bin/sh\nexit 0\n' > "$TB/gh"
  printf '#!/bin/sh\n[ "$1" = get ] && [ "$2" = --help ] && echo "Usage: treehouse get [--lease]"; exit 0\n' > "$TB/treehouse"
  chmod +x "$TB"/*
  ss() { env -u CLAUDECODE -u PI_CODING_AGENT -u FM_PI_HARNESS -u GROK_AGENT FM_HOME="$SB/home" FM_ROOT_OVERRIDE="$FROOT" \
      PATH="$TB:$SB/fakebin:$PATH" FM_CONTROL_LAUNCH_WAIT=40 timeout 200 "$ROOT/bin/fm-session-start.sh" "$@" 2>&1; }
  echo; echo "== (1) READ-ONLY session start (fleet lock held by another live process) =="
  mkdir -p "$SB/holderbin"; printf '#!/bin/bash\nwhile :; do sleep 1; done\n' > "$SB/holderbin/claude"; chmod +x "$SB/holderbin/claude"
  "$SB/holderbin/claude" 600 & HOLDER=$!; printf '%s\n' "$HOLDER" > "$SB/home/state/.lock"
  echo "lock status: $(FM_HOME="$SB/home" "$ROOT/bin/fm-lock.sh" status)"
  ss > "$SB/ss-readonly.out"; kill "$HOLDER"; wait "$HOLDER" 2>/dev/null; rm -f "$SB/home/state/.lock"
  grep -E "READ-ONLY SESSION -|WORKTREE_DRIFT" "$SB/ss-readonly.out"
  sleep 3; echo "relaunch journal present? $([ -e "$SB/home/state/t1.control-relaunch" ] && echo yes || echo no)"
  echo "herdr foreground_cwd now: $(fm_backend_herdr_current_path "$T")"
  echo; echo "== (2) LOCKED --reemit session start =="
  ss --reemit > "$SB/ss-reemit.out"
  grep -E "SESSION START \(CONTEXT RE-EMIT\)|READ-ONLY SESSION -|WORKTREE_DRIFT" "$SB/ss-reemit.out"
  sleep 5; echo "relaunch journal present? $([ -e "$SB/home/state/t1.control-relaunch" ] && echo yes || echo no)"
  echo "herdr foreground_cwd now: $(fm_backend_herdr_current_path "$T")"
  echo "fake claude starts so far: $(grep -c ' start ' "$SB/claude.log")"
  echo; echo "== (3) LOCKED full session start =="
  ss > "$SB/ss-full.out"
  grep -E "^=+ SESSION START|READ-ONLY SESSION -|WORKTREE_DRIFT" "$SB/ss-full.out"
  for _ in $(seq 1 120); do grep -q $'\tworktree-drift-t1\t' "$SB/home/state/.wake-queue" 2>/dev/null && break; sleep 1; done
  for f in "$SB"/ss-*.out; do cp "$f" "$(dirname "$0")/session-start-$(basename "$f" .out).txt"; done
elif [ "${MODE:-repair}" = watch ]; then
  echo; echo "== \$ fm-watch.sh (live watcher, FM_WORKTREE_DRIFT_INTERVAL=5) =="
  FM_HOME="$SB/home" PATH="$SB/fakebin:$PATH" FM_WORKTREE_DRIFT_INTERVAL=5 FM_CONTROL_LAUNCH_WAIT=40 \
    timeout 300 "$ROOT/bin/fm-watch.sh" > "$SB/watch.out" 2> "$SB/watch.err"; echo "watcher exit rc=$?"
  echo "-- watcher stdout:"; cat "$SB/watch.out"
  echo "-- watcher stderr (tail):"; tail -5 "$SB/watch.err"
else
echo; echo "== \$ fm-worktree-drift.sh repair --wake =="
FM_HOME="$SB/home" PATH="$SB/fakebin:$PATH" FM_CONTROL_LAUNCH_WAIT=40 timeout 400 "$ROOT/bin/fm-worktree-drift.sh" repair --wake; echo "rc=$?"
fi
sleep 1
echo; echo "== AFTER =="
echo "agent state:            $(fm_backend_agent_state herdr "$T")"
echo "herdr foreground_cwd:   $(fm_backend_herdr_current_path "$T")"
echo; echo "== fake claude log (every agent start/stop with its physical cwd) =="; cat "$SB/claude.log"
echo; echo "== durable wake queue rows =="; ls "$SB/home/state" | grep -i wake; find "$SB/home/state" -path '*wake*' -type f -exec sh -c 'echo "--- $1"; cat "$1"' _ {} \; 2>/dev/null | head -20
echo; echo "== primary checkout untouched? =="
git -C "$PROJ" status --porcelain=v1 --ignored > "$SB/proj-status-after"; ls -lA "$PROJ" | sed 1d > "$SB/proj-ls-after"
if diff "$SB/proj-status-before" "$SB/proj-status-after" && diff "$SB/proj-ls-before" "$SB/proj-ls-after"; then echo "primary checkout: unchanged (git status + listing identical)"; else echo "primary checkout CHANGED"; fi
echo; echo "== second scan after repair =="
FM_HOME="$SB/home" "$ROOT/bin/fm-worktree-drift.sh" scan; echo "(empty = no drift)"
echo; echo "== task record diff (before -> after relaunch) =="; diff "$SB/meta-before" "$SB/home/state/t1.meta"
echo; echo "== fm-control.sh t1 exit (cleanup of the lab agent) =="
FM_HOME="$SB/home" FM_CONTROL_EXIT_WAIT=5 "$ROOT/bin/fm-control.sh" t1 exit 2>&1 | tail -2
