#!/usr/bin/env bash
# Live driver: real bin/fm-watch.sh against a REAL isolated tmux server whose pane
# runs a process named `grok` (a live idle agent). Only the crew-state reader is a
# stub, because an attributed no-mistakes run cannot be conjured here.
set -u
WT=/home/homexa/.no-mistakes/worktrees/a20fe525da72/01M2WZ3586W1AHJ8F5DMS6HZVY
cd "$WT/tests"
. ./wake-helpers.sh
. "$ROOT/bin/fm-classify-lib.sh"
WATCH="$ROOT/bin/fm-watch.sh"; DRAIN="$ROOT/bin/fm-wake-drain.sh"
BASE=$(mktemp -d /tmp/fmlive/run.XXXX)
export TMUX_TMPDIR="$BASE/tmux"; mkdir -p "$TMUX_TMPDIR"; unset TMUX
mkdir -p "$BASE/agentbin"
cp "$(command -v bash)" "$BASE/agentbin/grok"
cat > "$BASE/crew-state" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${LIVE_CREW_STATE:-state: unknown · source: none · stub}"
SH
chmod +x "$BASE/crew-state"
ack() { local state=$1 err="$1/.drain.err" seq gen; awk -F "\t" '$3=="stale"{print $5}' "$state/.wake-queue" 2>/dev/null >> "$state/../all.log"
  FM_STATE_OVERRIDE="$state" "$DRAIN" >/dev/null 2>"$err" || return 1
  seq=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--ack-through \([0-9]*\) --recovery-generation.*/\1/p' "$err")
  gen=$(sed -n 's/^WAKE_ACK_REQUIRED:.*--recovery-generation \([A-Za-z0-9._-]*\)$/\1/p' "$err")
  FM_STATE_OVERRIDE="$state" "$DRAIN" --ack-through "$seq" --recovery-generation "$gen" >/dev/null; }
# round <state> <crew-state-line> <resurface-secs> <exit|absorb>
round() { local state=$1 verdict=$2 rs=$3 mode=$4 pid
  LIVE_CREW_STATE="$verdict" FM_WATCH_HANDLING_SUCCESSOR=1 FM_STATE_OVERRIDE="$state" \
    FM_CREW_STATE_BIN="$BASE/crew-state" FM_PAUSE_RESURFACE_SECS="$rs" FM_STALE_ESCALATE_SECS=1 \
    FM_POLL=1 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 \
    "$WATCH" >> "$state/../watch.out" 2>>"$state/../watch.err" &
  pid=$!
  if [ "$mode" = exit ]; then wait_for_exit "$pid" 150; return $?; fi
  sleep 6; if is_live_non_zombie "$pid"; then kill "$pid"; wait "$pid" 2>/dev/null; return 0; fi; wait "$pid"; return 1; }
payloads() { awk -F '\t' -v w="$2" '$3=="stale" && $4==w {print $5}' "$1/.wake-queue" 2>/dev/null; }
# lane <name> <status-line> <status-age> -> state dir; real tmux window test:fm-<name>
lane() { local name=$1 line=$2 age=$3 d="$BASE/$1"; mkdir -p "$d/state"
  tmux has-session -t test 2>/dev/null || tmux new-session -d -s test -n seed "exec sleep 100000"
  tmux new-window -d -t test: -n "fm-$name" "printf 'grok> waiting at the gate\\n'; exec $BASE/agentbin/grok -c \"read -r _\""
  printf 'window=test:fm-%s\nkind=ship\nharness=grok\nbackend=tmux\n' "$name" > "$d/state/$name.meta"
  printf '%s\n' "$line" > "$d/state/$name.status"
  touch -d "@$(( $(date +%s) - age ))" "$d/state/$name.status"
  FM_STATE_OVERRIDE="$d/state" bash -c '. "$1"; fm_wake_status_mark_current "$2" "$3"' _ "$ROOT/bin/fm-wake-lib.sh" "$d/state" "$d/state/$name.status"
  printf '%s\n' "$d/state"; }
export -f ack round payloads lane
export BASE ROOT WATCH DRAIN
echo "BASE=$BASE"
