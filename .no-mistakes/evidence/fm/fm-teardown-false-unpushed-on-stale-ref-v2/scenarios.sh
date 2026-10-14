#!/usr/bin/env bash
# Usage: scenarios.sh <repo-worktree>
. "$(dirname "$0")/drive-teardown.sh" "$1"
show() { echo "--- $1: exit=$2"; sed 's/^/    /' "$3"; }
trk() { git -C "$PROJ" rev-parse --verify -q "refs/remotes/fork/fm/$1" >/dev/null && echo present || echo absent; }

echo "=== S1 incident: three lanes pushed to fork by URL (no fetch), torn down concurrently"
for id in lane-a lane-b lane-c; do
  wt=$(lane $id); commit "$wt" $id.txt "work $id"
  git -C "$wt" push -q "$R/fork.git" "fm/$id"
  echo "  $id: local HEAD=$(git -C "$wt" rev-parse --short HEAD) fork head=$(git -C "$R/fork.git" rev-parse --short fm/$id) tracking ref=$(trk $id)"
  echo "  $id: pre-refresh 'git log HEAD --not --remotes' => $(git -C "$wt" log --oneline HEAD --not --remotes | tr '\n' ' ')"
done
for id in lane-a lane-b lane-c; do ( teardown > "$LAB/$id.out" 2> "$LAB/$id.err"; echo $? > "$LAB/$id.rc" ) & done; wait
for id in lane-a lane-b lane-c; do show "$id" "$(cat $LAB/$id.rc)" "$LAB/$id.err"; echo "    stdout: $(tr '\n' ' ' < $LAB/$id.out | cut -c1-300)"; echo "    meta removed: $([ -e $LAB/state/$id.meta ] && echo no || echo yes)"; done

echo "=== S2 stale tracking ref (older push fetched, newer commits pushed by URL)"
id=lane-d; wt=$(lane $id); commit "$wt" a.txt one; git -C "$wt" push -q fork fm/$id
commit "$wt" b.txt two; git -C "$wt" push -q "$R/fork.git" fm/$id
echo "  tracking=$(git -C "$PROJ" rev-parse --short refs/remotes/fork/fm/$id) local=$(git -C "$wt" rev-parse --short HEAD) fork=$(git -C "$R/fork.git" rev-parse --short fm/$id)"
teardown > $LAB/d.out 2> $LAB/d.err; show $id $? $LAB/d.err

echo "=== S3 adversarial: commit only on this disk (pushed one, then another local-only)"
id=lane-e; wt=$(lane $id); commit "$wt" a.txt pushed-e; git -C "$wt" push -q "$R/fork.git" fm/$id
commit "$wt" b.txt "local-only-e"
teardown > $LAB/e.out 2> $LAB/e.err; show $id $? $LAB/e.err
echo "    worktree still exists: $([ -d $wt ] && echo yes || echo no); meta kept: $([ -e $LAB/state/$id.meta ] && echo yes || echo no)"

echo "=== S4 adversarial: pushed work but uncommitted edit"
id=lane-f; wt=$(lane $id); commit "$wt" a.txt pushed-f; git -C "$wt" push -q "$R/fork.git" fm/$id
echo dirty >> "$wt/a.txt"
teardown > $LAB/f.out 2> $LAB/f.err; show $id $? $LAB/f.err

echo "=== S5 adversarial: fork remote unreachable (cannot tell) -> must refuse, with note"
id=lane-g; wt=$(lane $id); commit "$wt" a.txt pushed-g; git -C "$wt" push -q "$R/fork.git" fm/$id
mv "$R/fork.git" "$R/fork.gone"
teardown > $LAB/g.out 2> $LAB/g.err; show $id $? $LAB/g.err
mv "$R/fork.gone" "$R/fork.git"

echo "=== S6 adversarial: hanging remote bounded by FM_TEARDOWN_FETCH_TIMEOUT=3"
id=lane-h; wt=$(lane $id); commit "$wt" a.txt pushed-h; git -C "$wt" push -q "$R/fork.git" fm/$id
mkfifo "$LAB/hang.fifo"
git -C "$PROJ" remote add slow "ext::sh -c cat\ $LAB/hang.fifo"
git -C "$PROJ" config protocol.ext.allow always
# break fork so only a hanging remote could have helped -> must refuse after timeout
mv "$R/fork.git" "$R/fork.gone"
start=$(date +%s); teardown FM_TEARDOWN_FETCH_TIMEOUT=3 > $LAB/h.out 2> $LAB/h.err; rc=$?; end=$(date +%s)
show $id $rc $LAB/h.err; echo "    elapsed: $((end-start))s"
mv "$R/fork.gone" "$R/fork.git"; git -C "$PROJ" remote remove slow

echo "=== S7 failed fetch that still wrote the task ref (lock on unrelated ref, origin broken)"
id=lane-i; wt=$(lane $id); commit "$wt" a.txt pushed-i; git -C "$wt" push -q "$R/fork.git" fm/$id fm/$id:zz-other
GD=$(git -C "$PROJ" rev-parse --absolute-git-dir); mkdir -p "$GD/refs/remotes/fork"; : > "$GD/refs/remotes/fork/zz-other.lock"
mv "$R/origin.git" "$R/origin.gone"
teardown > $LAB/i.out 2> $LAB/i.err; show $id $? $LAB/i.err
echo "    fork tracking ref now: $(trk $id)"
rm -f "$GD/refs/remotes/fork/zz-other.lock"; mv "$R/origin.gone" "$R/origin.git"

echo "=== cleanup"
rm -rf "$LAB"; echo "lab removed: $([ -e "$LAB" ] && echo no || echo yes)"
