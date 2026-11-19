#!/usr/bin/env bash
# tests/fm-remote-clear-composer.test.sh - clear-composer reaches a remote
# secondmate from the control plane.
#
# The shape this pins: a remote secondmate that is alive and reachable, whose
# composer holds one unsubmitted line, is recovered from the parent's
# bin/fm-control.sh without a relaunch and without submitting the line. The
# host runs the ordinary local clear-composer (tests/fm-control.test.sh owns its
# contract: Ctrl+U never Enter, the hold window, every refusal), so this suite
# pins only the reach: the parent hop, the host verb's hop onto the local plane,
# and that a clear the host did not verify is never reported as one.
#
# Two legs, each hermetic. The parent leg fakes the SSH boundary the way
# tests/fm-remote-secondmate-relaunch.test.sh does. The host leg runs the real
# bin/fm-remote-secondmate-control.sh against a copy of bin/ whose fm-control.sh
# is a recorder, so the arguments and the home it is pointed at are observable.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v perl >/dev/null 2>&1 || { echo "skip: perl not found"; exit 0; }

TMP=$(fm_test_tmproot fm-remote-clear-composer)
mkdir -p "$TMP"
TMP=$(cd "$TMP" && pwd -P)
trap 'rm -rf "$TMP"' EXIT
HOME_DIR="$TMP/home"
FAKEBIN=$(fm_fakebin "$TMP/fake")
mkdir -p "$HOME_DIR/data" "$HOME_DIR/state" "$HOME_DIR/config"
printf -- '- ios - iOS delivery (host: remote-mac; root: /srv/fm; home: /srv/fm-home; scope: iOS; projects: alpha; added 2026-08-01)\n' \
  > "$HOME_DIR/data/secondmates.md"

fm_write_meta "$HOME_DIR/state/ios.meta" \
  "window=remote:ios" "endpoint_task_id=ios" "worktree=/srv/fm-home" \
  "project=/srv/fm" "harness=claude" "kind=secondmate" "mode=secondmate" \
  "yolo=off" "home=/srv/fm-home" "projects=alpha" "remote_host=remote-mac" \
  "remote_root=/srv/fm" "remote_backend=herdr" "remote_herdr_session=fm-remote" \
  "remote_target=fm-remote:w1:p1"

# The fake host answers by FM_FAKE_HOST_MODE and records every command it ran.
cat > "$FAKEBIN/fake-ssh" <<'SH'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do
  case "$1" in -o) shift 2 ;; --) shift; break ;; *) exit 90 ;; esac
done
host=$1; entry=$2; shift 2
[ "$host" = remote-mac ] || exit 91
[ "$entry" = fm-remote-entrypoint.sh ] || exit 92
fields=$(perl -MMIME::Base64=decode_base64 -e '
  my @a=split(/\0/, decode_base64($ARGV[0]));
  print join(" ", map { defined $_ ? $_ : "" } @a[0..3]);
' "$4")
printf '%s\n' "$fields" >> "$FM_FAKE_HOST_LOG"
[ "${fields% }" = "fm-remote-secondmate-control.sh clear-composer ios" ] || { echo "got [$fields]" >> "$FM_FAKE_HOST_LOG"; exit 93; }
case "$FM_FAKE_HOST_MODE" in
  cleared)
    printf 'composer-cleared ios harness=claude backend=herdr endpoint=fm-remote:w1:p1 presses=1 verified=empty-x13\n' ;;
  empty)
    printf 'composer-already-empty ios harness=claude backend=herdr endpoint=fm-remote:w1:p1\n' ;;
  refuse)
    printf "error: task ios's composer still reads 'pending' after 8 Ctrl+U press(es); the line was not cleared and nothing was submitted\n" >&2
    exit 1 ;;
  old-host)
    printf 'error: unknown command: clear-composer\n' >&2
    exit 1 ;;
  silent-success)
    printf 'ok\n'
    exit 0 ;;
  lost) exit 255 ;;
esac
SH
chmod +x "$FAKEBIN/fake-ssh"

run_parent() {  # <verb> [args...]
  env FM_HOME="$HOME_DIR" FM_SSH_BIN="$FAKEBIN/fake-ssh" \
    FM_FAKE_HOST_MODE="${FM_FAKE_HOST_MODE:-cleared}" FM_FAKE_HOST_LOG="$TMP/host.log" \
    "$ROOT/bin/fm-control.sh" ios "$@" 2>&1
}

# --- a verified remote clear is reported, once, with its placement ----------
: > "$TMP/host.log"
FM_FAKE_HOST_MODE=cleared OUT=$(FM_FAKE_HOST_MODE=cleared run_parent clear-composer); RC=$?
expect_code 0 "$RC" "a verified remote clear should succeed"$'\n'"$OUT"
assert_contains "$OUT" "composer-cleared ios" "the host's verified result should reach the caller"
assert_contains "$OUT" "verified=empty-x13" "the hold proof the host measured should be reported"
assert_contains "$OUT" "remote=remote-mac" "the report should name the host that did the clear"
[ "$(wc -l < "$TMP/host.log" | tr -d ' ')" = 1 ] \
  || fail "exactly one host command should run (no relaunch, no resend): $(cat "$TMP/host.log")"
assert_not_contains "$(cat "$TMP/host.log")" relaunch "a clear must never relaunch the mate"
pass "remote clear-composer: a verified clear is reported with its placement and runs one host command"

# --- an already-empty composer is reported as such --------------------------
OUT=$(FM_FAKE_HOST_MODE=empty run_parent clear-composer); RC=$?
expect_code 0 "$RC" "an empty remote composer should succeed"$'\n'"$OUT"
assert_contains "$OUT" "composer-already-empty ios" "an empty composer is reported, not a clear"
pass "remote clear-composer: an already-empty composer is reported as such"

# --- every host refusal passes through with its reason ----------------------
OUT=$(FM_FAKE_HOST_MODE=refuse run_parent clear-composer); RC=$?
expect_code 1 "$RC" "a host refusal should refuse here"
assert_contains "$OUT" "nothing was submitted" "the host's named reason should reach the operator"
assert_contains "$OUT" "remote-mac" "the refusal should name the host"
pass "remote clear-composer: a host refusal is a refusal here, with the host's reason"

# --- a lost transport never claims a clear ----------------------------------
OUT=$(FM_FAKE_HOST_MODE=lost run_parent clear-composer); RC=$?
expect_code 1 "$RC" "a lost transport must not report success"
assert_contains "$OUT" "before the clear was confirmed" "the unknown outcome should be named"
assert_not_contains "$OUT" "composer-cleared" "a lost transport must not report a clear"
pass "remote clear-composer: a lost transport refuses and says the outcome is unknown"

# --- a host reporting success without a verified outcome is refused ----------
OUT=$(FM_FAKE_HOST_MODE=silent-success run_parent clear-composer); RC=$?
expect_code 1 "$RC" "a success with no verified outcome must refuse"
assert_contains "$OUT" "reported no verified clear-composer outcome" \
  "the missing proof should be named"
pass "remote clear-composer: an unverifiable report is refused rather than trusted"

# --- a host that predates the verb says what to do --------------------------
OUT=$(FM_FAKE_HOST_MODE=old-host run_parent clear-composer); RC=$?
expect_code 1 "$RC" "an older host must refuse"
assert_contains "$OUT" "/updatefirstmate" "the operator should be told how to fix an old host"
pass "remote clear-composer: a host without the verb names the update to run"

# --- the other verbs are still refused by placement, reaching nothing -------
for verb in interrupt exit; do
  : > "$TMP/host.log"
  OUT=$(run_parent "$verb"); RC=$?
  expect_code 1 "$RC" "$verb on a remote secondmate should still refuse"
  assert_contains "$OUT" "remotely placed secondmate on remote-mac" "the $verb refusal should name the placement"
  [ ! -s "$TMP/host.log" ] || fail "$verb must reach no host"
done
pass "remote clear-composer: interrupt and exit stay refused by placement and reach no host"

# --- host leg: the verb runs the ordinary local plane on the host's record ---
HOST_ROOT="$TMP/host-root"
HOST_HOME="$TMP/host-home"
mkdir -p "$HOST_ROOT" "$HOST_HOME/bin" "$HOST_HOME/state/parent-route" "$HOST_HOME/config"
cp -R "$ROOT/bin/." "$HOST_ROOT/bin/"
cat > "$HOST_ROOT/bin/fm-control.sh" <<SH
#!/usr/bin/env bash
{
  printf 'args=%s\n' "\$*"
  printf 'FM_HOME=%s\n' "\$FM_HOME"
  printf 'FM_STATE_OVERRIDE=%s\n' "\$FM_STATE_OVERRIDE"
  printf 'HERDR_SESSION=%s\n' "\$HERDR_SESSION"
} > '$TMP/host-control.log'
printf 'composer-cleared ios harness=claude backend=herdr endpoint=fm-remote:w1:p1 presses=1 verified=empty-x13\n'
SH
chmod +x "$HOST_ROOT/bin/fm-control.sh"
printf 'ios\n' > "$HOST_HOME/.fm-secondmate-home"
: > "$HOST_HOME/AGENTS.md"
fm_write_meta "$HOST_HOME/state/parent-route/ios.meta" \
  "window=fm-remote:p1" "endpoint_task_id=ios" "backend=herdr" \
  "herdr_session=fm-remote" "herdr_workspace_id=w1" "herdr_tab_id=w1-1" \
  "herdr_pane_id=p1" "worktree=$HOST_HOME" "project=$HOST_HOME" \
  "harness=claude" "kind=secondmate" "mode=secondmate" "home=$HOST_HOME"
OUT=$(env FM_HOME="$HOST_HOME" FM_ROOT_OVERRIDE="$HOST_ROOT" \
  "$HOST_ROOT/bin/fm-remote-secondmate-control.sh" clear-composer ios 2>&1); RC=$?
expect_code 0 "$RC" "the host verb should succeed"$'\n'"$OUT"
assert_contains "$OUT" "composer-cleared ios" "the host verb should print the plane's own result"
assert_grep 'args=ios clear-composer' "$TMP/host-control.log" \
  "the host must run exactly clear-composer for the mate, never a relaunch"
assert_grep "FM_STATE_OVERRIDE=$HOST_HOME/state/parent-route" "$TMP/host-control.log" \
  "the plane must read the mate's own host-local record"
assert_grep 'HERDR_SESSION=fm-remote' "$TMP/host-control.log" \
  "the plane must address the dedicated remote Herdr session"
pass "remote clear-composer: the host verb runs the ordinary local plane on the mate's own record"

OUT=$(env FM_HOME="$HOST_HOME" FM_ROOT_OVERRIDE="$HOST_ROOT" \
  "$HOST_ROOT/bin/fm-remote-secondmate-control.sh" clear-composer 'bad id' 2>&1); RC=$?
expect_code 1 "$RC" "an invalid id should refuse on the host"
pass "remote clear-composer: the host verb validates the id"

echo "ALL TESTS PASSED"
