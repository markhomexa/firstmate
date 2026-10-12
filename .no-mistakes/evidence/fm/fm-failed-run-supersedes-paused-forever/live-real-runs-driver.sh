#!/usr/bin/env bash
# Live driver: real no-mistakes CLI (v1.72.0) + real run records (copied state DB,
# repo working_path repointed at a throwaway clone) + real gh forge reads.
# Runs base (a1ecefb) and target (HEAD) bin/fm-crew-state.sh against a lab FM_HOME.
set -u
ROOT=$1; LABW=$2
NMH=$LABW/nm; CLONE=$LABW/Yapii
rm -rf "$LABW/base"; mkdir -p "$LABW/base"; git -C "$ROOT" archive a1ecefb bin | tar -x -C "$LABW/base"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); "$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null; mkdir -p "$LAB/tmux"
S=$LAB/state
run(){ env -u TMUX -u NO_MISTAKES_GATE -u FM_STATE_OVERRIDE -u FM_ROOT_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
  NM_HOME="$NMH" TMUX_TMPDIR="$LAB/tmux" FM_HOME="$LAB" "$1/bin/fm-crew-state.sh" labcrew 2>&1 | grep -v 'new version\|no-mistakes update'; }
crew(){ # <branch> <sha> [pr]
  git -C "$CLONE" checkout -q -B "$1" "$2"
  printf 'window=fm:fm-labcrew\nworktree=%s\nkind=ship\n' "$CLONE" > "$S/labcrew.meta"
  [ -z "${3:-}" ] || printf 'pr=%s\n' "$3" >> "$S/labcrew.meta"
  echo; echo "=== crew on $1 @ ${2:0:8}${3:+ (meta pr=$3)}"
  (cd "$CLONE" && NM_HOME=$NMH no-mistakes axi status 2>/dev/null | grep -E '^  (id|status|pr):|^outcome|^error' | sed 's/^/  real axi status> /')
}
case_(){ echo "## $1"; rm -f "$S/labcrew.status"; [ -z "$2" ] || printf '%b' "$2" > "$S/labcrew.status"; [ -f "$S/labcrew.status" ] && sed 's/^/  status> /' "$S/labcrew.status"
  echo "  base   (a1ecefb): $(run "$LABW/base")"; echo "  target (HEAD)   : $(run "$ROOT")"; }
NOW=$(date +%s)
echo "gh: PR 3225 = $(gh pr view 3225 -R austinhellickson/Yapii --json state -q .state); PR 3110 = $(gh pr view 3110 -R austinhellickson/Yapii --json state -q .state)"

crew fm/tx-preview-half-width-full-suite ee9735b4e54321bb47aa71ef749e3a3ce03aca39
echo "  run updated_at=1791529813 (via fm_nm_run_updated_at: $(NM_HOME=$NMH bash -c ". '$ROOT/bin/fm-nm-run-lib.sh'; fm_nm_run_updated_at '$CLONE' 10 01M4F21BDX9S2CHQKC8TSNTQ9J"))"
case_ "S1 INCIDENT: run died (daemon shutting down), its PR merged, no later line" ''
case_ "S1b INCIDENT: same, with stale working line from before the run ended" 'working [at=1791500000]: validating\n'
case_ "S1c INCIDENT: same, finished worker later declares paused" "paused [at=$NOW]: waiting on captain\n"

crew fm/tx-zone-read-failure-falls-back-to-utc-silently 831c7e749ec1cd2f783b2d2b5f4b9e519e37e847
echo "  run updated_at=$(NM_HOME=$NMH bash -c ". '$ROOT/bin/fm-nm-run-lib.sh'; fm_nm_run_updated_at '$CLONE' 10 01M4C4X29V5B9JKSHRX61SWYCC")"
case_ "S2 INCIDENT: failed run (open PR), worker declares paused afterwards" "paused [at=$NOW]: waiting on the follow-up review\n"
case_ "S3 GUARD: paused stamped BEFORE the run ended" 'paused [at=1791400000]: waiting on my validation round\n'
case_ "S4 GUARD: failed run, open PR, no status log" ''
case_ "S5 GUARD: earlier pause then later working line" "paused [at=1791400000]: waiting\nworking [at=$NOW]: resumed\n"
case_ "S6 GUARD: later done line alone, PR still open" "done [at=$NOW]: shipped\n"
