#!/usr/bin/env bash
# Live drive of bin/fm-control.sh relaunch against a REAL tmux server (isolated
# via TMUX_TMPDIR) whose pane runs a stand-in `claude` process.
# usage: live-relaunch-drive.sh <repo-root> <case: held|close|ok>
set -u
ROOT=$1 CASE=$2
. "$ROOT/tests/lib.sh" >/dev/null 2>&1 || true
W=$(mktemp -d /tmp/fm-live-XXXX); export TMUX_TMPDIR=$W/tmux; mkdir -p "$TMUX_TMPDIR"
ID=live${CASE}
HOME_FM=$W/home; mkdir -p $HOME_FM/state $HOME_FM/data/$ID $W/bin $W/user-home
git init -q -b main $W/proj && git -C $W/proj -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git init -q --bare $W/proj.origin.git && git -C $W/proj remote add origin $W/proj.origin.git && git -C $W/proj push -q origin main
git -C $W/proj worktree add -q -b task-$ID $W/wt
printf '# Task\n## Captain%ss intent\nLive relaunch %s.\n\n## Firstmate spec\nKeep the worker.\n' "'" "$ID" > $HOME_FM/data/$ID/brief.md
cat > $HOME_FM/state/$ID.meta <<M
window=fmses:fm-$ID
endpoint_task_id=$ID
worktree=$W/wt
project=$W/proj
harness=claude
kind=ship
mode=no-mistakes
yolo=off
tasktmp=/tmp/fm-$ID
model=default
effort=default
M
# stand-in agent: an idle composer that exits on /exit
cat > $W/bin/claude <<'A'
#!/usr/bin/env python3
# Stand-in agent: names its process "claude" (what tmux reports as
# pane_current_command), draws an idle composer with the cursor inside it,
# and exits on /exit.
import ctypes, os, sys
ctypes.CDLL(None).prctl(15, b"claude", 0, 0, 0)
log = open(os.environ["FM_LIVE_LOG"], "a", buffering=1)
log.write(f"stand-in claude pid {os.getpid()} started, argv={sys.argv[1:][:2]}\n")
while True:
    sys.stdout.write("\033[2J\033[H╭────╮\n│    │\n╰────╯\033[2;3H"); sys.stdout.flush()
    line = sys.stdin.readline()
    if not line: sys.exit(0)
    log.write(f"agent received: {line.strip()[:80]}\n")
    if line.strip() in ("/exit", "/quit"):
        log.write(f"stand-in claude pid {os.getpid()} exited\n"); sys.exit(0)
A
chmod +x $W/bin/claude
export FM_LIVE_LOG=$W/agent.log; : > $FM_LIVE_LOG
tmux new-session -d -s fmses -n fm-$ID -c $W/wt -e PATH="$W/bin:$PATH" -e FM_LIVE_LOG=$FM_LIVE_LOG
tmux send-keys -t fmses:fm-$ID "export PATH=$W/bin:\$PATH FM_LIVE_LOG=$FM_LIVE_LOG; hash -r; claude" Enter; sleep 1
if command -v tasks-axi >/dev/null; then
  printf '%s\n' '# Backlog' '' '## In flight' '' '## Queued' '' '## Done' > $HOME_FM/data/backlog.md
  tasks-axi add $ID "live relaunch fixture" --kind ship --file $HOME_FM/data/backlog.md >/dev/null
  tasks-axi start $ID --file $HOME_FM/data/backlog.md >/dev/null
fi
case $CASE in
  held)  tasks-axi hold $ID --reason "captain scope question pending" --kind captain --file $HOME_FM/data/backlog.md >/dev/null ;;
  close) printf 'id=%s\n' $ID > $HOME_FM/state/$ID.backlog-close ;;
esac
echo "== before: pane_current_command=$(tmux display-message -p -t fmses:fm-$ID '#{pane_current_command}')"
brief_before=$(sha256sum < $HOME_FM/data/$ID/brief.md); meta_before=$(sha256sum < $HOME_FM/state/$ID.meta)
echo "== \$ fm-control.sh $ID relaunch --note 'resume after reboot'"
env PATH="$W/bin:$PATH" FM_HOME=$HOME_FM HOME=$W/user-home CLAUDE_CONFIG_DIR= FM_SPAWN_NO_GUARD=1 \
  "$ROOT/bin/fm-control.sh" $ID relaunch --note "resume after reboot" 2>&1; rc=$?
sleep 1
echo "== exit code: $rc"
echo "== after: pane_current_command=$(tmux display-message -p -t fmses:fm-$ID '#{pane_current_command}')"
echo "== brief.md unchanged: $([ "$(sha256sum < $HOME_FM/data/$ID/brief.md)" = "$brief_before" ] && echo yes || echo NO)"
echo "== meta unchanged: $([ "$(sha256sum < $HOME_FM/state/$ID.meta)" = "$meta_before" ] && echo yes || echo NO)"
echo "== journal phase: $(grep '^phase=' $HOME_FM/state/$ID.control-relaunch 2>/dev/null | tail -1)"
[ -f $HOME_FM/data/backlog.md ] && echo "== backlog state: $(tasks-axi show $ID --file $HOME_FM/data/backlog.md | sed -n 's/^  state: *//p' | head -1)"
echo "== stand-in agent log:"; cat $FM_LIVE_LOG
tmux kill-server 2>/dev/null; rm -rf "$W" /tmp/fm-$ID
