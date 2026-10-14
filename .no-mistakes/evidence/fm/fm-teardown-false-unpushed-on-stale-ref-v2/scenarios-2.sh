#!/usr/bin/env bash
# Usage: scenarios-2.sh <repo-tree> <label>
. "$(dirname "$0")/drive-teardown.sh" "$1"
echo "##### tree: $2"
show() { echo "--- $1: exit=$2"; sed 's/^/    /' "$3"; }
echo "=== S1 incident repro: lane pushed to fork by URL, no tracking ref"
id=lane-a; wt=$(lane $id); printf x > "$wt/a"; git -C "$wt" add a; git -C "$wt" -c user.email=t@t -c user.name=t commit -qm "work lane-a"
git -C "$wt" push -q "$R/fork.git" fm/$id
teardown > $LAB/a.out 2> $LAB/a.err; show $id $? $LAB/a.err
echo "=== S6 hanging remote (ext::sleep 120), FM_TEARDOWN_FETCH_TIMEOUT=3, fork also unreachable"
id=lane-h; wt=$(lane $id); printf x > "$wt/h"; git -C "$wt" add h; git -C "$wt" -c user.email=t@t -c user.name=t commit -qm "work lane-h"
git -C "$wt" push -q "$R/fork.git" fm/$id
git -C "$PROJ" remote add slow "ext::sleep 120"; git -C "$PROJ" config protocol.ext.allow always
mv "$R/fork.git" "$R/fork.gone"
start=$(date +%s); teardown FM_TEARDOWN_FETCH_TIMEOUT=3 > $LAB/h.out 2> $LAB/h.err; rc=$?; end=$(date +%s)
show $id $rc $LAB/h.err; echo "    elapsed: $((end-start))s"
echo "=== S6b hanging remote present but fork reachable -> closes after timeout"
mv "$R/fork.gone" "$R/fork.git"
start=$(date +%s); teardown FM_TEARDOWN_FETCH_TIMEOUT=3 > $LAB/h2.out 2> $LAB/h2.err; rc=$?; end=$(date +%s)
show $id $rc $LAB/h2.err; echo "    elapsed: $((end-start))s"
rm -rf "$LAB"; echo "lab removed"
