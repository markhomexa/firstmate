#!/usr/bin/env bash
# Live drive of bin/fm-teardown.sh --retire-unidentified-worktree against a
# disposable lab home, a real named Herdr lab session, and a real Treehouse pool.
set -u
WT=/home/homexa/.no-mistakes/worktrees/a20fe525da72/01M4X9GMSYX971HTTAYQT48WVE
S=$(cat /tmp/fm-retire-live.path)
SESSION=$(cat "$S/session")
HELPER="$WT/bin/fm-herdr-lab.sh"
REAL_HERDR=$(command -v herdr)
ORIG_PATH=$PATH
export HERDR_LAB_HELPER=$HELPER HERDR_LAB_SESSION=$SESSION REAL_HERDR HERDR_ORIGINAL_PATH=$ORIG_PATH

LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
echo "$LAB" > "$S/lab"
"$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/tmux" "$S/fakebin"
touch "$LAB/config/fleet-ledger"

# Same transport shim as tests/fm-herdr-session-cleanup-e2e.test.sh: every
# production herdr call goes through the guarded lab helper.
cat > "$S/fakebin/herdr" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${HERDR_CALL_LOG:-/dev/null}"
args=("$@")
last=$((${#args[@]} - 1))
flag=$((last - 1))
if [ "${#args[@]}" -ge 2 ] && [ "${args[$flag]}" = --session ] && [ "${args[$last]}" = "$HERDR_LAB_SESSION" ]; then
  unset "args[$last]" "args[$flag]"
fi
set -- "${args[@]}"
for arg in "$@"; do case "$arg" in --session|--session=*) exit 9 ;; esac; done
if [ "${1:-}" = --version ]; then
  exec env PATH="$HERDR_ORIGINAL_PATH" "$REAL_HERDR" "$@" --session "$HERDR_LAB_SESSION"
fi
exec env PATH="$HERDR_ORIGINAL_PATH" "$HERDR_LAB_HELPER" run "$HERDR_LAB_SESSION" "$@"
SH
chmod +x "$S/fakebin/herdr"
export HERDR_CALL_LOG="$S/herdr-calls.log"
lab() { env PATH="$ORIG_PATH" "$HELPER" run "$SESSION" "$@"; }

# Project with an origin, and a real Treehouse pool rooted inside the scratch dir.
export TREEHOUSE_ROOT="$S/pool"
git init -q --bare "$S/origin.git"
git init -q -b main "$LAB/projects/proj"
git -C "$LAB/projects/proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$LAB/projects/proj" remote add origin "$S/origin.git"
git -C "$LAB/projects/proj" push -q origin main
PROJ="$LAB/projects/proj"
lease() { (cd "$PROJ" && treehouse get --lease --no-fetch --lease-holder "$1" 2>/dev/null); }
claim() { printf 'task=%s\nhome=%s\n' "$2" "$3" > "$(dirname "$(cd "$1" && pwd -P)")/.fm-slot-owner"; }

# Backlog with every fixture task in flight.
printf '%s\n' '# Backlog' '' '## In flight' '' '## Queued' '' '## Done' > "$LAB/data/backlog.md"

# record <id> [kind]: a real Herdr pane plus a meta with NO worktree= line.
record() {
  local id=$1 kind=${2:-ship} created ws tab pane
  created=$(lab workspace create --cwd "$PROJ" --label "$id" --no-focus) || { echo "workspace create failed for $id"; exit 1; }
  ws=$(printf '%s' "$created" | jq -r '.result.workspace.workspace_id')
  tab=$(printf '%s' "$created" | jq -r '.result.tab.tab_id')
  pane=$(printf '%s' "$created" | jq -r '.result.root_pane.pane_id')
  printf '%s\n' "window=$SESSION:$pane" "endpoint_task_id=$id" "project=$PROJ" "harness=claude" \
    "kind=$kind" "backend=herdr" "herdr_session=$SESSION" "herdr_workspace_id=$ws" \
    "herdr_tab_id=$tab" "herdr_pane_id=$pane" "mode=no-mistakes" "spawn_gen=live-$id" > "$LAB/state/$id.meta"
  tasks-axi add "$id" "live fixture $id" --kind "$kind" --file "$LAB/data/backlog.md" >/dev/null
  tasks-axi start "$id" --file "$LAB/data/backlog.md" >/dev/null
  echo "$pane" > "$S/$id.pane"
}

teardown() {  # <id> [args...]
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
    -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
    FM_HOME="$LAB" HERDR_SESSION="$SESSION" PATH="$S/fakebin:$ORIG_PATH" "$WT/bin/fm-teardown.sh" "$@"
}
pane_alive() { lab pane get "$(cat "$S/$1.pane")" >/dev/null 2>&1 && echo alive || echo gone; }
live_count() { find "$LAB/state" -maxdepth 1 -name '*.meta' | wc -l | tr -d ' '; }

record tx-templates-owner          # the measured shape: clean slot claimed by it
record tx-dirty                    # its claimed slot holds uncommitted work
record tx-noclaim                  # no claim anywhere
record tx-foreign                  # a claim with its id but written by another home
record tx-scout scout              # scout with a gated report
printf 'decisions_reviewed=1\n' >> "$LAB/state/tx-scout.meta"
mkdir -p "$LAB/data/tx-scout"; printf 'Scout report.\n' > "$LAB/data/tx-scout/report.md"

SLOT_MINE=$(lease a); SLOT_OTHER=$(lease b); SLOT_DIRTY=$(lease c); SLOT_FOREIGN=$(lease d)
claim "$SLOT_MINE" tx-templates-owner "$LAB"
claim "$SLOT_OTHER" someone-else "$LAB"
claim "$SLOT_DIRTY" tx-dirty "$LAB"
printf 'unlanded work\n' > "$SLOT_DIRTY/WIP.txt"
claim "$SLOT_FOREIGN" tx-foreign "$S/another-home"
echo "slots: mine=$SLOT_MINE other=$SLOT_OTHER dirty=$SLOT_DIRTY foreign=$SLOT_FOREIGN"
echo "treehouse status before:"; (cd "$PROJ" && treehouse status --json) | jq -c '.[] | {path, name}' 2>/dev/null || (cd "$PROJ" && treehouse status)

step() { printf '\n===== %s =====\n' "$*"; }
step "live records before: $(live_count)"
ls "$LAB/state"/*.meta | xargs -n1 basename

step "A1 ordinary teardown of tx-templates-owner (no worktree=) must still refuse"
teardown tx-templates-owner; echo "exit=$?"; echo "record: $([ -e "$LAB/state/tx-templates-owner.meta" ] && echo present || echo gone); pane: $(pane_alive tx-templates-owner)"

step "A2 --force must still refuse and must not guess a worktree"
teardown tx-templates-owner --force; echo "exit=$?"; echo "record: $([ -e "$LAB/state/tx-templates-owner.meta" ] && echo present || echo gone); pane: $(pane_alive tx-templates-owner)"

step "A3 --retire-unidentified-worktree --force is an invalid request"
teardown tx-templates-owner --retire-unidentified-worktree --force; echo "exit=$?"; echo "record: $([ -e "$LAB/state/tx-templates-owner.meta" ] && echo present || echo gone)"

step "A4 --retire-unidentified-worktree on a record that names a worktree is refused"
cp "$LAB/state/tx-noclaim.meta" "$S/noclaim.meta.bak"
printf 'worktree=%s\n' "$SLOT_OTHER" >> "$LAB/state/tx-noclaim.meta"
teardown tx-noclaim --retire-unidentified-worktree; echo "exit=$?"; echo "record: $([ -e "$LAB/state/tx-noclaim.meta" ] && echo present || echo gone); pane: $(pane_alive tx-noclaim); slot sentinel intact: $(git -C "$SLOT_OTHER" status --porcelain | wc -l) changes"
cp "$S/noclaim.meta.bak" "$LAB/state/tx-noclaim.meta"

step "S1 retire tx-templates-owner (clean slot claimed by it, another task's claim beside it)"
before=$(live_count)
teardown tx-templates-owner --retire-unidentified-worktree; echo "exit=$?"
echo "live records $before -> $(live_count); record: $([ -e "$LAB/state/tx-templates-owner.meta" ] && echo present || echo gone); pane: $(pane_alive tx-templates-owner)"
echo "own claim: $(cat "$(dirname "$SLOT_MINE")/.fm-slot-owner" 2>/dev/null || echo '<released>')"
echo "other task's claim: $(tr '\n' ' ' < "$(dirname "$SLOT_OTHER")/.fm-slot-owner")"
echo "slot checkout still present: $([ -d "$SLOT_MINE/.git" ] || [ -f "$SLOT_MINE/.git" ] && echo yes || echo no)"
echo "--- data/tx-templates-owner/retired-unverified.txt"; cat "$LAB/data/tx-templates-owner/retired-unverified.txt"
echo "--- backlog row"; tasks-axi show tx-templates-owner --file "$LAB/data/backlog.md"
echo "--- ledger close"; grep -F '"task.cleaned_up"' "$LAB/state/fleet-ledger.jsonl" | grep -F tx-templates-owner

step "S2 retire tx-dirty (its claimed slot is dirty)"
teardown tx-dirty --retire-unidentified-worktree; echo "exit=$?"
echo "record: $([ -e "$LAB/state/tx-dirty.meta" ] && echo present || echo gone); pane: $(pane_alive tx-dirty)"
echo "dirty slot claim: $(tr '\n' ' ' < "$(dirname "$SLOT_DIRTY")/.fm-slot-owner")"
echo "dirty slot WIP: $(cat "$SLOT_DIRTY/WIP.txt")"
echo "--- retired-unverified.txt"; cat "$LAB/data/tx-dirty/retired-unverified.txt"

step "S3 retire tx-noclaim (no claim names it)"
teardown tx-noclaim --retire-unidentified-worktree; echo "exit=$?"
echo "record: $([ -e "$LAB/state/tx-noclaim.meta" ] && echo present || echo gone); pane: $(pane_alive tx-noclaim)"
echo "other task's claim still: $(tr '\n' ' ' < "$(dirname "$SLOT_OTHER")/.fm-slot-owner")"

step "S4 retire tx-foreign (claim with this id but another home)"
teardown tx-foreign --retire-unidentified-worktree; echo "exit=$?"
echo "record: $([ -e "$LAB/state/tx-foreign.meta" ] && echo present || echo gone); pane: $(pane_alive tx-foreign)"
echo "foreign-home claim: $(tr '\n' ' ' < "$(dirname "$SLOT_FOREIGN")/.fm-slot-owner")"

step "S5 retire tx-scout (scout keeps its report link plus the unverified note)"
teardown tx-scout --retire-unidentified-worktree; echo "exit=$?"
echo "record: $([ -e "$LAB/state/tx-scout.meta" ] && echo present || echo gone); pane: $(pane_alive tx-scout)"
echo "--- backlog row"; tasks-axi show tx-scout --file "$LAB/data/backlog.md"

step "end state: live records $(live_count)"
echo "--- fleet ledger task.cleaned_up events"; grep -F '"task.cleaned_up"' "$LAB/state/fleet-ledger.jsonl" | jq -c '{event: .event, task: (.task // .id), verified}'
echo "--- treehouse status after"; (cd "$PROJ" && treehouse status)
echo "--- backlog Done section"; sed -n '/## Done/,$p' "$LAB/data/backlog.md"
