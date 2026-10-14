#!/usr/bin/env bash
# usage: fmlab-drive.sh <code-root> <state-dir> <action...>
set -u
ROOT=$1; STATE=$2; shift 2
S=$(cat /tmp/fmlab-session)
export PATH="/tmp/fmlab-fakebin:$PATH" HERDR_SESSION="$S"
. "$ROOT/bin/fm-supervise-daemon.sh"
fm_backend_source herdr || { echo "no herdr adapter"; exit 2; }
export LOG="$STATE/daemon.log" FM_SUPERVISOR_BACKEND=herdr FM_SUPERVISOR_TARGET="$S:w1:p1" \
  FM_ESCALATE_BATCH_SECS=0 FM_INJECT_CONFIRM_SLEEP=0.5 FM_INJECT_CONFIRM_RETRIES=6 FM_DAEMON_PRIMARY_HARNESS=claude \
  FM_STATE_OVERRIDE="$STATE"
mkdir -p "$STATE"
case "$1" in
  classify) printf 'composer_state=%s\n' "$(fm_backend_composer_state herdr "$FM_SUPERVISOR_TARGET")" ;;
  glyph) cap=$(fm_backend_herdr_visible_capture_ansi "$FM_SUPERVISOR_TARGET"); printf 'glyph_row_proof=%s\n' "$(FM_COMPOSER_GHOST_LUMA_MAX=0 fm_composer_claude_glyph_row_proof styled=1 "$cap")" ;;
  enter) afk_enter "$STATE" ;;
  add) escalate_add "$STATE" "$2" ;;
  flush) escalate_flush "$STATE"; echo "escalate_flush rc=$?" ;;
  send) out=$(fm_backend_herdr_send_text_submit "$FM_SUPERVISOR_TARGET" "$2" 3 0.4 0.4); echo "send_text_submit(no opt-in)=$out" ;;
esac
