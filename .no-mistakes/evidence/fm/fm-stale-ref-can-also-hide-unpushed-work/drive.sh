#!/usr/bin/env bash
# Live drive of bin/fm-unpushed-work.sh against real git worktrees in a throwaway HOME.
set -u
S=$1; T=$(mktemp -d); export HOME=$T/home; mkdir -p $HOME
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q --bare $T/origin.git
git clone -q $T/origin.git $T/seed 2>/dev/null; git -C $T/seed checkout -q -b main; git -C $T/seed commit -q --allow-empty -m init; git -C $T/seed push -q origin main 2>/dev/null
git --git-dir=$T/origin.git symbolic-ref HEAD refs/heads/main
mk(){ git clone -q $T/origin.git "$1" 2>/dev/null; }
TH=$HOME/.treehouse/proj
mkdir -p $TH/a $TH/b $TH/c $TH/d
mk $TH/a/slot1; mk $TH/b/slot2; mk $TH/c/slot3; mk $TH/d/slot4
# slot1: never-pushed branch
git -C $TH/a/slot1 checkout -q -b feat-never; git -C $TH/a/slot1 commit -q --allow-empty -m wip
# slot2: pushed branch then 2 commits ahead
git -C $TH/b/slot2 checkout -q -b feat-ahead; git -C $TH/b/slot2 commit -q --allow-empty -m one
git -C $TH/b/slot2 push -q -u origin feat-ahead 2>/dev/null
git -C $TH/b/slot2 commit -q --allow-empty -m two; git -C $TH/b/slot2 commit -q --allow-empty -m three
# slot3, slot4: clean (slot4 sorts last)
run(){ echo "\$ fm-unpushed-work.sh $*"; "$S" "$@"; echo "[exit $?]"; echo; }
echo "== 1. local scan: never-pushed + ahead-of-pushed reported, clean slots silent"
run --snap $T/snap
echo "== 2. same sweep again with --snap: no repeat"
git -C $TH/a/slot1 commit -q --allow-empty -m more   # counts change, key does not
run --snap $T/snap
echo "== 3. all clean: silent"
git -C $TH/a/slot1 push -q origin feat-never 2>/dev/null; git -C $TH/b/slot2 push -q 2>/dev/null
git -C $TH/a/slot1 fetch -q; git -C $TH/b/slot2 fetch -q
run --snap $T/snap
echo "== 4. remote host via ssh-like shim (re-parses argv through a login shell like OpenSSH)"
git -C $TH/d/slot4 checkout -q -b feat-remote; git -C $TH/d/slot4 commit -q --allow-empty -m r
cat > $T/fakessh <<'SH'
#!/bin/sh
while [ "$1" = -o ]; do shift 2; done; shift
exec sh -c "$*"
SH
chmod +x $T/fakessh
FM_UNPUSHED_SSH=$T/fakessh run --host borrowed-box
echo "== 5. unreachable remote, REAL ssh (connection refused on 127.0.0.1:22): must stay silent on stdout"
out=$("$S" --host nobody@127.0.0.1 --snap $T/snap 2>$T/err); rc=$?
echo "stdout=[$out] exit=$rc stderr=$(cat $T/err)"; echo "snapshot after failure: $(cat $T/snap 2>/dev/null | tr '\n' '|')"
echo
echo "== 6. unreachable remote, REAL ssh to a non-resolving host"
out=$("$S" --host no-such-host.invalid 2>$T/err); rc=$?
echo "stdout=[$out] exit=$rc stderr=$(cat $T/err)"
echo
echo "== 7. no push happened: origin branches"
git --git-dir=$T/origin.git branch -a | sed 's/^/  /'
rm -rf "$T"
