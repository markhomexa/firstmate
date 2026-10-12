#!/usr/bin/env bash
# Same lab as live-real-runs-driver.sh, for a real cancelled run (aborted by user).
set -u
ROOT=$1; LABW=$2; NMH=$LABW/nm; CLONE=$LABW/Yapii
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); "$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null; mkdir -p "$LAB/tmux"; S=$LAB/state
run(){ env -u TMUX -u NO_MISTAKES_GATE -u FM_STATE_OVERRIDE -u FM_ROOT_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
  NM_HOME="$NMH" TMUX_TMPDIR="$LAB/tmux" FM_HOME="$LAB" "$1/bin/fm-crew-state.sh" labcrew 2>&1 | grep -v 'new version\|no-mistakes update'; }
git -C "$CLONE" checkout -q -B fm/tx-row25-task-order-by-due-date-v4 6a7015726cf3578896efa495ae4ae1e988521c62
printf 'window=fm:fm-labcrew\nworktree=%s\nkind=ship\n' "$CLONE" > "$S/labcrew.meta"
(cd "$CLONE" && NM_HOME=$NMH no-mistakes axi status 2>/dev/null | grep -E '^  (id|status):|^outcome|^error' | sed 's/^/  real axi status> /')
printf 'paused [at=%s]: waiting on the follow-up review\n' "$(date +%s)" > "$S/labcrew.status"; sed 's/^/  status> /' "$S/labcrew.status"
echo "## S7 GUARD: cancelled run + later paused line"
echo "  base   (a1ecefb): $(run "$LABW/base")"; echo "  target (HEAD)   : $(run "$ROOT")"
rm -rf "$LAB"
