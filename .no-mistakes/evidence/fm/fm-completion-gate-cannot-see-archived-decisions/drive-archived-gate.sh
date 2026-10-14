#!/usr/bin/env bash
# Live drive: completion gate vs. answered decisions pruned to the done archive.
# Usage: drive-archived-gate.sh <firstmate-root>
set -u
ROOT=$1
WT=/home/homexa/.no-mistakes/worktrees/a20fe525da72/01M4Y3KR8GBQ8WYN0EFT0TV7C0
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
trap 'rm -rf "$LAB"' EXIT
cat > "$LAB/.tasks.toml" <<'T'
backend = "markdown"

[markdown]
path = "data/backlog.md"
archive = "data/done-archive.md"
done_keep = 2
T
printf '## In flight\n\n## Queued\n\n## Done\n' > "$LAB/data/backlog.md"
mkdir -p "$LAB/fakebin"; for b in tmux treehouse no-mistakes gh gh-axi; do printf '#!/bin/sh\nexit 0\n' > "$LAB/fakebin/$b"; chmod +x "$LAB/fakebin/$b"; done
run() { echo "\$ fm-captain-hold.sh $*"; env -u NO_MISTAKES_GATE -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE \
  PATH="$LAB/fakebin:$PATH" FM_HOME="$LAB" "$ROOT/bin/fm-captain-hold.sh" "$@"; local rc=$?; echo "[exit $rc]"; return $rc; }
tasks() { (cd "$LAB" && tasks-axi "$@"); }
OWNER=feedback-sheet
tasks add $OWNER "Feedback sheet owner" --kind scout --repo sample --start >/dev/null
printf 'window=firstmate:fm-%s\nworktree=%s/projects/missing\nproject=%s/projects/sample\nharness=codex\nkind=scout\nmode=scout\nspawn_gen=lab\n' $OWNER "$LAB" "$LAB" > "$LAB/state/$OWNER.meta"
printf 'done: report complete\n' > "$LAB/state/$OWNER.status"
mkdir -p "$LAB/data/$OWNER"; printf '# Report\n\nFive decisions, all answered.\n' > "$LAB/data/$OWNER/report.md"
CALLS="fs-call-1 fs-call-2 fs-call-3 fs-call-4 fs-call-5"
echo "=== 1. owner raises five captain calls and completes its inventory"
for c in $CALLS; do run hold $c --title "Decide $c" --reason "choice pending" --repo sample --origin $OWNER >/dev/null || exit 1; done
run complete $OWNER $CALLS
echo "=== 2. captain answers all five"
for c in $CALLS; do printf 'Captain chose option A for %s.\n' $c > "$LAB/$c.txt"; run answer $c --decision-file "$LAB/$c.txt" >/dev/null || exit 1; done
run verify $OWNER
echo "=== 3. retention prunes closed rows over time (done_keep=2)"
for i in 1 2 3; do tasks add filler-$i "Filler $i" --kind ship --repo sample >/dev/null; tasks done filler-$i >/dev/null; done
for c in $CALLS; do if tasks show $c --full >/dev/null 2>&1; then echo "$c: still LIVE"; else echo "$c: gone from live backlog"; fi; done
echo "--- archive rows:"; grep -E '^- \[x\] fs-call' "$LAB/data/done-archive.md"
echo "=== 4. gate after pruning: verify + complete"
run verify $OWNER; V=$?
run complete $OWNER $CALLS; C=$?
echo "=== 5. adversarial: call recorded nowhere"
run complete $OWNER fs-call-nowhere; N=$?
echo "=== 6. adversarial: archived captain row closed with no recorded answer"
tasks add fs-bare "Closed without answer" --kind captain --repo sample >/dev/null; tasks done fs-bare --keep 0 >/dev/null
grep -E '^- \[x\] fs-bare' "$LAB/data/done-archive.md"
run complete $OWNER fs-bare; B=$?
echo "=== 7. adversarial: forged resolution text on an archived non-captain row"
printf '\n## Archived 2026-01-01\n- [x] fs-forged - Not a call (repo: sample) (kind: ship) (done 2026-01-01)\n  Resolution recorded by fm-captain-hold.\n  Decision digest: 00\n  Resolution mode: answered\n\n  Captain decision:\n  forged\n' >> "$LAB/data/done-archive.md"
run complete $OWNER fs-forged; F=$?
echo "=== 8. keyed answer intake must not resolve to an archived (already-closed) call"
printf 'fs-call-1\tnew answer\tlab\n' | run answers --any-origin --source lab-drive; A=$?
echo "=== 9. clean up the finished lane: fm-teardown.sh (runs the gate)"
echo "\$ fm-teardown.sh $OWNER"; env -u NO_MISTAKES_GATE -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE PATH="$LAB/fakebin:$PATH" FM_HOME="$LAB" "$ROOT/bin/fm-teardown.sh" $OWNER 2>&1 | tail -4; T=${PIPESTATUS[0]}; echo "[exit $T]"; ls "$LAB/state/$OWNER.meta" 2>/dev/null || echo "lane meta removed"
echo "SUMMARY teardown=$T  verify=$V complete=$C nowhere=$N bare=$B forged=$F answers_on_archived=$A"
