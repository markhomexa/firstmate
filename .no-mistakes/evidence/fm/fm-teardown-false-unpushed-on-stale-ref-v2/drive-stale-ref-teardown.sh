#!/usr/bin/env bash
# Live driver: real fm-teardown.sh against a disposable lab FM_HOME with real
# bare-repo origin and fork remotes. Only treehouse/tmux (post-check worktree
# return + window kill) and gh/no-mistakes lookups are stubbed so nothing
# outside the lab is touched.
# Usage: drive-stale-ref-teardown.sh <repo-root-to-test> <label>
set -u
ROOTDIR=$1; LABEL=$2
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$ROOTDIR/bin/fm-lab-home.sh" create "$LAB" >/dev/null || { echo "lab create failed"; exit 1; }
FB=$LAB/fakebin; mkdir -p "$FB"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FB/treehouse"; cp "$FB/treehouse" "$FB/tmux"
printf '#!/usr/bin/env bash\ncase "$1 $2" in "pr list") printf "count: 0 (showing first 0)\\npull_requests[]: []\\n";; "pr view") exit 1;; esac\nexit 0\n' > "$FB/gh-axi"
printf '#!/usr/bin/env bash\n[ "$1 $2" = "pr view" ] && exit 1\nexit 0\n' > "$FB/gh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FB/no-mistakes"
chmod +x "$FB"/*
touch "$LAB/state/.last-watcher-beat"
G() { git -c user.email=t@t -c user.name=t "$@"; }

new_lane() {  # id -> creates $LAB/lanes/<id>/{origin.git,fork.git,project,wt}, meta
  local id=$1 d=$LAB/lanes/$1
  mkdir -p "$d"
  git init -q --bare "$d/origin.git"; git -C "$d/origin.git" symbolic-ref HEAD refs/heads/main
  git clone -q "$d/origin.git" "$d/seed" 2>/dev/null; G -C "$d/seed" commit -q --allow-empty -m baseline
  git -C "$d/seed" push -q origin main; rm -rf "$d/seed"
  git clone -q "$d/origin.git" "$d/project"; git -C "$d/project" remote set-head origin main
  git -C "$d/project" worktree add -q -b "fm/$id" "$d/wt" main
  git init -q --bare "$d/fork.git"; git -C "$d/project" remote add fork "$d/fork.git"
  printf '%s\n' "window=firstmate:fm-$id" "endpoint_task_id=$id" "worktree=$d/wt" \
    "project=$d/project" kind=ship mode=no-mistakes "spawn_gen=lab-$id" > "$LAB/state/$id.meta"
}
commit() { printf '%s\n' "$3" > "$LAB/lanes/$1/wt/$2"; git -C "$LAB/lanes/$1/wt" add "$2"; G -C "$LAB/lanes/$1/wt" commit -q -m "$4"; }
push_by_url() { git -C "$LAB/lanes/$1/wt" push -q "$LAB/lanes/$1/fork.git" "fm/$1"; }  # no tracking ref update
teardown() {
  local id=$1; shift
  echo "\$ fm-teardown.sh $id   [$LABEL]"
  local s=$SECONDS
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
      -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
      "$@" FM_HOME="$LAB" PATH="$FB:$PATH" "$ROOTDIR/bin/fm-teardown.sh" "$id" 2>&1 | sed 's/^/    /'
  echo "    -> exit ${PIPESTATUS[0]} after $((SECONDS-s))s; meta present: $([ -f "$LAB/state/$id.meta" ] && echo yes || echo no)"
}
hdr() { echo; echo "=== $* ==="; }

hdr "S1 incident: three lanes, PR head pushed to fork, tracking ref ABSENT"
for id in lane-a lane-b lane-c; do
  new_lane $id; commit $id f.txt "$id" "feat($id): real work"; push_by_url $id
  echo "  $id: local HEAD $(git -C $LAB/lanes/$id/wt rev-parse --short HEAD), fork head $(git -C $LAB/lanes/$id/fork.git rev-parse --short fm/$id), tracking ref: $(git -C $LAB/lanes/$id/wt rev-parse -q --verify refs/remotes/fork/fm/$id >/dev/null && echo present || echo absent)"
done
for id in lane-a lane-b lane-c; do teardown $id; done

hdr "S2 tracking ref STALE (fetched once, two more commits pushed by URL)"
new_lane lane-d; commit lane-d a.txt 1 first; git -C $LAB/lanes/lane-d/wt push -q fork fm/lane-d
commit lane-d b.txt 2 second; commit lane-d c.txt 3 third; push_by_url lane-d
echo "  tracking ref $(git -C $LAB/lanes/lane-d/wt rev-parse --short refs/remotes/fork/fm/lane-d) vs HEAD $(git -C $LAB/lanes/lane-d/wt rev-parse --short HEAD)"
teardown lane-d

hdr "S3 adversarial: one commit genuinely only on this disk (rest pushed)"
new_lane lane-e; commit lane-e a.txt 1 "pushed commit"; push_by_url lane-e; commit lane-e b.txt 2 "LOCAL-ONLY commit"
teardown lane-e

hdr "S4 adversarial: fork remote unreachable (path gone)"
new_lane lane-f; commit lane-f a.txt 1 "pushed commit"; push_by_url lane-f; mv $LAB/lanes/lane-f/fork.git $LAB/lanes/lane-f/fork.gone
teardown lane-f

hdr "S5 adversarial: fork remote HANGS (ssh never answers), FM_TEARDOWN_FETCH_TIMEOUT=3"
new_lane lane-g; commit lane-g a.txt 1 "pushed commit"; push_by_url lane-g
git -C $LAB/lanes/lane-g/project remote set-url fork ssh://lab.invalid/fork.git
git -C $LAB/lanes/lane-g/project config core.sshCommand "sleep 600 #"
teardown lane-g FM_TEARDOWN_FETCH_TIMEOUT=3

hdr "S6 adversarial: pushed work but uncommitted edit in worktree"
new_lane lane-h; commit lane-h a.txt 1 "pushed commit"; push_by_url lane-h; echo edit >> $LAB/lanes/lane-h/wt/a.txt
teardown lane-h

pkill -f "sleep 600 #" 2>/dev/null; pkill -f "^sleep 600" 2>/dev/null
rm -rf "$LAB"; echo; echo "lab removed: $([ -e "$LAB" ] && echo no || echo yes)"
