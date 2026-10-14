#!/usr/bin/env bash
# Live lab drive of --retire-unidentified-worktree against a disposable FM_HOME,
# a private real tmux server, a real git project + origin, and a real treehouse pool.
set -u
WT_ROOT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$WT_ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/tmux"; chmod 700 "$LAB/tmux"
export TMUX_TMPDIR="$LAB/tmux"; unset TMUX
trap 'tmux kill-server 2>/dev/null; rm -rf "$LAB"' EXIT
TD() { env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" "$WT_ROOT/bin/fm-teardown.sh" "$@"; }
step() { printf '\n===== %s =====\n' "$*"; }
lanes() { find "$LAB/state" -maxdepth 1 -name '*.meta' | wc -l; }

# Real project with an origin and an in-project treehouse pool.
P="$LAB/projects/demo"; git init -q --bare "$LAB/origin.git"; git init -q -b main "$P"
( cd "$P"; git -c user.email=l@l -c user.name=l commit -q --allow-empty -m init
  git remote add origin "$LAB/origin.git"; printf 'max_trees = 2\nroot = "."\n' > treehouse.toml
  echo '.treehouse/' > .gitignore; git add -A; git -c user.email=l@l -c user.name=l commit -qm cfg
  git push -q origin HEAD:refs/heads/main; git fetch -q origin )
SLOT=$(cd "$P" && treehouse get --lease --no-fetch 2>/dev/null)
printf 'task=tx-templates-owner\nhome=%s\n' "$LAB" > "$(dirname "$SLOT")/.fm-slot-owner"
echo "pool slot leased by real treehouse: $SLOT (claim: task=tx-templates-owner)"

# Real tmux endpoints: the stale record's window and a bystander lane.
tmux new-session -d -s firstmate -n fm-tx-templates-owner 'sleep 3600'
tmux new-window -d -t firstmate -n fm-task-ok 'sleep 3600'
mkdir -p "$LAB/wt-ok"
# The measured shape: window, endpoint, project, harness, kind, backend - and NO worktree= line.
printf '%s\n' "window=firstmate:fm-tx-templates-owner" "endpoint_task_id=tx-templates-owner" \
  "project=$P" "harness=claude" "kind=ship" "backend=tmux" "mode=no-mistakes" \
  "spawn_gen=lab-gen-1" > "$LAB/state/tx-templates-owner.meta"
printf '%s\n' "window=firstmate:fm-task-ok" "endpoint_task_id=task-ok" "worktree=$LAB/wt-ok" \
  "project=$P" "harness=claude" "kind=ship" "backend=tmux" "mode=no-mistakes" \
  "spawn_gen=lab-gen-2" > "$LAB/state/task-ok.meta"
printf '%s\n' '# Backlog' '' '## In flight' '' '## Queued' '' '## Done' > "$LAB/data/backlog.md"
tasks-axi add tx-templates-owner "templates owner" --kind ship --file "$LAB/data/backlog.md" >/dev/null
tasks-axi start tx-templates-owner --file "$LAB/data/backlog.md" >/dev/null
: > "$LAB/config/fleet-ledger"

step "BEFORE: live records (lanes) = $(lanes); tmux windows:"; tmux list-windows -t firstmate -F '#W'
step "S1 ordinary teardown (no flag)"; TD tx-templates-owner; echo "exit=$?"
step "S1 ordinary teardown --force"; TD tx-templates-owner --force; echo "exit=$?"
echo "lanes=$(lanes)  record present: $([ -e "$LAB/state/tx-templates-owner.meta" ] && echo yes || echo no)"
step "S2 --retire-unidentified-worktree --force"; TD tx-templates-owner --retire-unidentified-worktree --force; echo "exit=$?"
step "S5 retirement of a record that NAMES a worktree (task-ok)"; TD task-ok --retire-unidentified-worktree; echo "exit=$?"
echo "task-ok record present: $([ -e "$LAB/state/task-ok.meta" ] && echo yes || echo no)"

step "S3 claimed pool slot holds UNCOMMITTED work -> retire"
echo wip > "$SLOT/wip.txt"
TD tx-templates-owner --retire-unidentified-worktree; echo "exit=$?"
echo "lanes=$(lanes)  record present: $([ -e "$LAB/state/tx-templates-owner.meta" ] && echo yes || echo no)  wip kept: $(cat "$SLOT/wip.txt")"
tmux list-windows -t firstmate -F '#W'
step "S3b claimed slot has a COMMIT on no remote -> retire"
( cd "$SLOT"; git add wip.txt; git -c user.email=l@l -c user.name=l commit -qm wip )
TD tx-templates-owner --retire-unidentified-worktree; echo "exit=$?"
step "S6 project path missing -> retire"
mv "$P" "$P.moved"; TD tx-templates-owner --retire-unidentified-worktree; echo "exit=$?"; mv "$P.moved" "$P"

step "S4 slot work landed (pushed) -> retire"
( cd "$SLOT"; git push -q origin HEAD:refs/heads/wip; git fetch -q origin )
TD tx-templates-owner --retire-unidentified-worktree; echo "exit=$?"
step "AFTER: lanes = $(lanes); tmux windows:"; tmux list-windows -t firstmate -F '#W'
echo "record present: $([ -e "$LAB/state/tx-templates-owner.meta" ] && echo yes || echo no); task-ok present: $([ -e "$LAB/state/task-ok.meta" ] && echo yes || echo no)"
step "data/tx-templates-owner/retired-unverified.txt"; cat "$LAB/data/tx-templates-owner/retired-unverified.txt"
step "backlog item"; tasks-axi show tx-templates-owner --full --file "$LAB/data/backlog.md"
step "fleet ledger close"; grep -F task.cleaned_up "$LAB/state/fleet-ledger.jsonl"
step "slot claim + checkout untouched"; cat "$(dirname "$SLOT")/.fm-slot-owner"; git -C "$SLOT" log --oneline -1; ls "$SLOT"
(cd "$P" && treehouse status --json 2>/dev/null)
