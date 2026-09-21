#!/usr/bin/env bash
# Live lab: flat task pane cwd + restart restore, and post-delivery abort retention.
# Usage: live-lab-scenarios.sh <firstmate-root> <label>
set -u
ROOT=$1; LABEL=$2
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane
H="$ROOT/bin/fm-herdr-lab.sh"
S=$("$H" name "$LABEL") || exit 1
export HERDR_SESSION="$S"
TMP=$(mktemp -d "$(cd /tmp && pwd -P)/fm-live-cwd.XXXXXX")
WTS=()
cleanup() {
  for wt in ${WTS[@]+"${WTS[@]}"}; do treehouse return --force "$wt" >/dev/null 2>&1; done
  "$H" teardown "$S"; echo "teardown rc=$?"; rm -rf "$TMP"
}
trap cleanup EXIT
"$H" provision "$S" || { echo "provision failed"; exit 1; }
lab() { "$H" run "$S" "$@"; }
echo "lab session: $S   root: $ROOT ($(git -C "$ROOT" rev-parse --short HEAD))"
PROJ="$TMP/proj"; mkdir -p "$PROJ"; git -C "$PROJ" init -q; echo x > "$PROJ/README.md"
git -C "$PROJ" add . ; git -C "$PROJ" -c user.name=t -c user.email=t@e.invalid commit -qm init
git clone -q --bare "$PROJ" "$PROJ.origin.git"; git -C "$PROJ" remote add origin "file://$PROJ.origin.git"
mkhome() { mkdir -p "$1/state" "$1/config" "$1/data/$2"; echo off > "$1/config/herdr-presentation-spaces"
  printf '# Task\n## Captain'"'"'s intent\nLive cwd check.\n\n## Firstmate spec\nNothing.\n' > "$1/data/$2/brief.md"; }
spawn() { # home id
  env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_SOCKET_PATH HERDR_SESSION="$S" FM_SPAWN_NO_GUARD=1 \
    FM_HOME="$1" FM_ROOT_OVERRIDE="$ROOT" ${EXTRA_PATH:+PATH="$EXTRA_PATH:$PATH"} \
    "$ROOT/bin/fm-spawn.sh" "$2" "$PROJ" "sh -c 'echo live-ok; exec sleep 600'" --backend herdr --mode no-mistakes --yolo off; }
field() { grep "^$2=" "$1" 2>/dev/null | tail -1 | cut -d= -f2-; }

if [ "${SKIP_A:-0}" != 1 ]; then
echo; echo "=== Scenario A: flat spawn, pane cwd, then server restart ==="
HA="$TMP/homeA"; mkhome "$HA" liveA
spawn "$HA" liveA > "$TMP/a.out" 2>&1; echo "spawn rc=$?"; tail -3 "$TMP/a.out"
WT=$(field "$HA/state/liveA.meta" worktree); WTS+=("$WT"); PANE=$(field "$HA/state/liveA.meta" herdr_pane_id)
echo "primary checkout : $PROJ"; echo "recorded worktree: $WT"; echo "task pane        : $PANE"
lab pane get "$PANE" | jq -c '.result.pane | {pane_id, cwd, foreground_cwd}'
"$H" stop "$S" >/dev/null && echo "lab server stopped (simulated reboot)"
"$H" provision "$S" >/dev/null && echo "lab server restarted"
for _ in $(seq 1 30); do R=$(lab pane get "$PANE" 2>/dev/null | jq -r '.result.pane.foreground_cwd // empty'); [ -n "$R" ] && break; sleep 0.3; done
echo "restored pane after restart:"; lab pane get "$PANE" | jq -c '.result.pane | {pane_id, cwd, foreground_cwd}'
if [ -n "$R" ] && [ "$(cd "$R" && pwd -P)" = "$(cd "$WT" && pwd -P)" ]; then echo "RESULT A: PASS restored pane resumed in its worktree"
else echo "RESULT A: FAIL restored pane resumed in '${R:-none}' (primary=$PROJ)"; fi

fi
[ "${SKIP_B:-0}" = 1 ] && exit 0
echo; echo "=== Scenario B: flat spawn aborts after launch delivery (In-flight commit fails) ==="
HB="$TMP/homeB"; mkhome "$HB" liveB
printf '%s\n' '# Backlog' '' '## In flight' '' '## Queued' '' '## Done' > "$HB/data/backlog.md"
printf 'backend = "markdown"\n\n[markdown]\npath = "data/backlog.md"\n' > "$HB/.tasks.toml"
FB="$TMP/failbin"; mkdir -p "$FB"
cat > "$FB/tasks-axi" <<'SH'
#!/usr/bin/env bash
# fault injection: the backlog In-flight commit fails
case "${1:-}" in
  --version) echo 0.2.5 ;;
  update) [ "${2:-}" = --help ] && { echo --archive-body; exit 0; }; echo 'error: row could not be moved' >&2; exit 1 ;;
  mv) [ "${2:-}" = --help ] && { echo 'usage: tasks-axi mv [<id>...]'; exit 0; }; echo 'error: row could not be moved' >&2; exit 1 ;;
  show) printf 'task:\n  state: queued\n  held: no\n  blocked: no\n' ;;
  start) echo 'error: row could not be moved' >&2; exit 1 ;;
esac
exit 0
SH
chmod +x "$FB/tasks-axi"
EXTRA_PATH="$FB" spawn "$HB" liveB > "$TMP/b.out" 2>&1; echo "spawn rc=$? (expected non-zero)"; tail -6 "$TMP/b.out"
echo "task record present? $([ -e "$HB/state/liveB.meta" ] && echo yes || echo no)"
M=$(ls "$HB"/state/.treehouse-lease-retained/*.retained 2>/dev/null | head -1)
echo "retained-lease record: ${M:-NONE}"; [ -n "$M" ] && cat "$M"
BWT=$(field "$M" worktree); [ -n "$BWT" ] && WTS+=("$BWT")
BP=$(lab pane list 2>/dev/null | jq -r '.result.panes[]? | select((.label // "")=="fm-liveB") | .pane_id' | head -1)
[ -z "$BP" ] && BP=$(printf '%s' "$(field "$M" reason)" | grep -oE 'w[0-9]+:p[0-9]+$' | head -1)
echo "live pane for liveB:"; lab pane get "$BP" 2>/dev/null | jq -c '.result.pane | {pane_id, cwd, foreground_cwd}' || echo "(pane lookup failed for '$BP')"
echo "treehouse status of slot:"; (cd "$BWT" 2>/dev/null && treehouse status --json 2>/dev/null | jq -c --arg p "$BWT" '[.. | objects | select((.path? // "")==$p)] | .[0] | {path, status, lease_holder}')
echo; echo "--- fm-bootstrap.sh session-start output (TREEHOUSE_LEASE lines) ---"
FM_HOME="$HB" FM_ROOT_OVERRIDE="$HB" timeout 300 "$ROOT/bin/fm-bootstrap.sh" 2>&1 | grep 'TREEHOUSE_LEASE' || echo "(no TREEHOUSE_LEASE line)"
