#!/usr/bin/env bash
# Build an isolated Firstmate home + a PRIVATE tmux server (TMUX_TMPDIR) holding one
# ship task whose fake `claude` agent was resumed in the PRIMARY checkout (reboot shape).
# Nothing here touches the host's tmux/herdr servers or real claude processes.
set -eu
REPO=$1; SB=$2
rm -rf "$SB"; mkdir -p "$SB/tmux" "$SB/fakebin" "$SB/home/state" "$SB/home/data/t1"
chmod 700 "$SB/tmux"
export TMUX_TMPDIR="$SB/tmux"; unset TMUX
cat > "$SB/fakebin/claude" <<'SH'
#!/bin/bash
# fake claude: logs its cwd+args, draws a composer, exits on /exit.
LOG=${FAKE_CLAUDE_LOG:?}
case "${1:-}" in --version|-v) echo "2.1.999 (Claude Code)"; exit 0;; esac
printf '%s start pid=%s cwd=%s args=%s\n' "$(date +%T)" "$$" "$(pwd -P)" "$*" >> "$LOG"
draw(){ stty -echo 2>/dev/null; printf '\033[2J\033[H╭────╮\n│    │\n╰────╯\033[2;3H'; }
draw
while IFS= read -r line; do
  printf '%s input pid=%s: %s\n' "$(date +%T)" "$$" "$line" >> "$LOG"
  case "$line" in /exit|/quit) printf '%s exit pid=%s\n' "$(date +%T)" "$$" >> "$LOG"; exit 0;; esac
  draw
done
SH
chmod +x "$SB/fakebin/claude"
git init -q -b main "$SB/proj"
git -C "$SB/proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$SB/proj" worktree add -q -b task-t1 "$SB/wt"
printf '%s\n' '# Task' "## Captain's intent" 'Keep working.' '' '## Firstmate spec' 'Stay in the worktree.' > "$SB/home/data/t1/brief.md"
cat > "$SB/home/state/t1.meta" <<M
window=fmses:fm-t1
endpoint_task_id=t1
worktree=$SB/wt
project=$SB/proj
harness=claude
kind=ship
mode=no-mistakes
yolo=off
tasktmp=$SB/tasktmp
model=default
effort=default
M
# Pane created in the primary checkout (as Herdr/spawn records it), agent resumed there.
env PATH="$SB/fakebin:$PATH" FAKE_CLAUDE_LOG="$SB/claude.log" \
  tmux new-session -d -s fmses -n fm-t1 -c "$SB/proj" 'bash --norc --noprofile -i'
tmux set-option -t fmses default-command 'bash --norc --noprofile -i' >/dev/null
tmux set-window-option -t fmses:fm-t1 automatic-rename off >/dev/null
sleep 0.5
tmux send-keys -t fmses:fm-t1 'claude --resume 11111111-2222-3333-4444-555555555555' Enter
sleep 1
echo "sandbox ready: $SB"
