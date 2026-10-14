#!/usr/bin/env bash
# Live driver: real bin/fm-teardown.sh, real git, real bare remotes, inside a
# disposable marked lab home. Only treehouse/tmux/gh/gh-axi/no-mistakes are
# shimmed so nothing touches the real pool, default tmux server, or GitHub.
set -u
REPO=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); rmdir "$LAB"
"$REPO/bin/fm-lab-home.sh" create "$LAB" >/dev/null; mkdir -p "$LAB/tmux" "$LAB/shim"
for c in treehouse tmux gh gh-axi no-mistakes; do printf '#!/bin/sh\nexit 0\n' > "$LAB/shim/$c"; done
printf '#!/bin/sh\ncase "$1 $2" in "pr list") echo "count: 0 (showing first 0)"; echo "pull_requests[]: []";; "pr view") exit 1;; esac\nexit 0\n' > "$LAB/shim/gh-axi"
chmod +x "$LAB/shim/"*
export GIT_AUTHOR_NAME=lab GIT_AUTHOR_EMAIL=lab@lab GIT_COMMITTER_NAME=lab GIT_COMMITTER_EMAIL=lab@lab
setup() { # name -> builds $LAB/projects/$1/{origin.git,project,wt}
  local d="$LAB/projects/$1"; mkdir -p "$d"
  git init -q --bare -b main "$d/origin.git"
  git clone -q "$d/origin.git" "$d/seed" 2>/dev/null; git -C "$d/seed" commit -q --allow-empty -m base; git -C "$d/seed" push -q origin main; rm -rf "$d/seed"
  git clone -q "$d/origin.git" "$d/project"; git -C "$d/project" remote set-head origin main
  git -C "$d/project" worktree add -q -b fm/$1 "$d/wt" main
  printf 'window=firstmate:fm-%s\nendpoint_task_id=%s\nworktree=%s\nproject=%s\nkind=ship\nmode=no-mistakes\nspawn_gen=lab-%s\n' "$1" "$1" "$d/wt" "$d/project" "$1" > "$LAB/state/$1.meta"
  touch "$LAB/state/.last-watcher-beat"
}
commit() { printf '%s\n' "$3" > "$LAB/projects/$1/wt/$2"; git -C "$LAB/projects/$1/wt" add "$2"; git -C "$LAB/projects/$1/wt" commit -q -m "$4"; }
fork_push_by_url() { local d="$LAB/projects/$1"; [ -d "$d/fork.git" ] || { git init -q --bare "$d/fork.git"; git -C "$d/project" remote add fork "$d/fork.git"; }; git -C "$d/wt" push -q "$d/fork.git" "fm/$1"; }
td() { local id=$1; shift; echo "\$ FM_HOME=\$LAB bin/fm-teardown.sh $id $*"
  local t0=$(date +%s)
  ( set -o pipefail; cd "${TDREPO:-$REPO}" && env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u TMUX \
      FM_HOME="$LAB" TMUX_TMPDIR="$LAB/tmux" PATH="$LAB/shim:$PATH" ${EXTRA_ENV:-} bin/fm-teardown.sh "$id" "$@" 2>&1 | sed "s#$LAB#\$LAB#g" ); local rc=$?
  echo "[exit=$rc elapsed=$(( $(date +%s)-t0 ))s meta_present=$([ -f "$LAB/state/$id.meta" ] && echo yes || echo no)]"; }
track() { git -C "$LAB/projects/$1/wt" for-each-ref --format='%(refname:short) %(objectname:short)' refs/remotes/fork | sed 's/^/  tracking: /'; echo "  HEAD: $(git -C "$LAB/projects/$1/wt" rev-parse --short HEAD)"; }

echo "=== S0: BASELINE at base commit 0397cb2 (pre-fix code), same incident setup ==="
mkdir -p "$LAB/base"; git -C "$REPO" archive 0397cb2 | tar -x -C "$LAB/base"
setup s0; commit s0 a.txt 1 "feat a"; commit s0 b.txt 2 "feat b"; commit s0 c.txt 3 "feat c"; fork_push_by_url s0
echo "before:"; track s0; TDREPO="$LAB/base" td s0

echo "=== S1: incident repro - 3 commits pushed to fork by URL, fork/<branch> tracking ref ABSENT ==="
setup s1; commit s1 a.txt 1 "feat a"; commit s1 b.txt 2 "feat b"; commit s1 c.txt 3 "feat c"; fork_push_by_url s1
echo "before:"; track s1; td s1; echo "after:"; track s1

echo; echo "=== S2: tracking ref STALE (fetched after 1st commit, 2 more pushed by URL) ==="
setup s2; commit s2 a.txt 1 "first"; fork_push_by_url s2; git -C "$LAB/projects/s2/project" fetch -q fork
commit s2 b.txt 2 "second"; commit s2 c.txt 3 "third"; fork_push_by_url s2
echo "before:"; track s2; td s2; echo "after:"; track s2

echo; echo "=== S3 (adversarial): pushed commit + one commit only on this disk -> must still REFUSE ==="
setup s3; commit s3 a.txt 1 "pushed"; fork_push_by_url s3; commit s3 b.txt 2 "local only work"
td s3

echo; echo "=== S4 (adversarial): fork remote unreachable (repo moved away) -> must REFUSE with refresh note ==="
setup s4; commit s4 a.txt 1 "pushed"; fork_push_by_url s4; mv "$LAB/projects/s4/fork.git" "$LAB/projects/s4/fork.gone"
td s4

echo; echo "=== S5 (adversarial): hanging ssh remote, FM_TEARDOWN_FETCH_TIMEOUT=3 -> bounded, no prompt, REFUSE with note ==="
setup s5; commit s5 a.txt 1 "pushed"; git -C "$LAB/projects/s5/project" remote add fork ssh://hang.invalid/x.git
printf '#!/bin/sh\nsleep 120\n' > "$LAB/hang-ssh"; chmod +x "$LAB/hang-ssh"
EXTRA_ENV="FM_TEARDOWN_FETCH_TIMEOUT=3 GIT_SSH_COMMAND=$LAB/hang-ssh" td s5 </dev/null

echo; echo "=== S6: genuine local-only work + --force escape hatch still works ==="
td s3 --force

rm -rf "$LAB"; echo; echo "lab removed: $([ -e "$LAB" ] && echo no || echo yes)"
