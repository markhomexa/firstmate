#!/usr/bin/env bash
# Live driver: runs the real bin/fm-teardown.sh from the gate worktree against a
# disposable lab FM_HOME, with real bare git remotes (origin + fork). Only the
# post-check side services (treehouse pool return, tmux, gh, no-mistakes) are
# stubbed so nothing touches the real fleet or GitHub.
set -u
REPO=$1; shift
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$REPO/bin/fm-lab-home.sh" create "$LAB" >/dev/null
mkdir -p "$LAB/tmux" "$LAB/fakebin" "$LAB/remotes"
for c in treehouse tmux; do printf '#!/usr/bin/env bash\nexit 0\n' > "$LAB/fakebin/$c"; done
cat > "$LAB/fakebin/gh-axi" <<'SH'
#!/usr/bin/env bash
case "${1:-} ${2:-}" in
  "pr list") printf '%s\n' "count: 0 (showing first 0)" "pull_requests[]: []"; exit 0;;
  "pr view") echo "error: pull request not found" >&2; exit 1;;
esac; exit 0
SH
cat > "$LAB/fakebin/gh" <<'SH'
#!/usr/bin/env bash
[ "${1:-} ${2:-}" = "pr view" ] && { echo "error: not found" >&2; exit 1; }; exit 0
SH
printf '#!/usr/bin/env bash\nexit 0\n' > "$LAB/fakebin/no-mistakes"
chmod +x "$LAB/fakebin"/*
touch "$LAB/state/.last-watcher-beat"
R=$LAB/remotes
git init -q --bare "$R/origin.git"; git -C "$R/origin.git" symbolic-ref HEAD refs/heads/main
git clone -q "$R/origin.git" "$R/_seed" 2>/dev/null
git -C "$R/_seed" -c user.email=t@t -c user.name=t commit -q --allow-empty -m baseline
git -C "$R/_seed" push -q origin main; rm -rf "$R/_seed"
PROJ=$LAB/projects/proj
git clone -q "$R/origin.git" "$PROJ"; git -C "$PROJ" remote set-head origin main
git init -q --bare "$R/fork.git"; git -C "$PROJ" remote add fork "$R/fork.git"
export LAB PROJ R REPO
lane() {  # id -> creates worktree + meta
  local id=$1 wt=$LAB/wt-$1
  git -C "$PROJ" worktree add -q -b "fm/$id" "$wt" main
  printf 'window=fm-lab:fm-%s\nendpoint_task_id=%s\nworktree=%s\nproject=%s\nkind=ship\nmode=no-mistakes\nspawn_gen=lab-%s\n' \
    "$id" "$id" "$wt" "$PROJ" "$id" > "$LAB/state/$id.meta"
  echo "$wt"
}
commit() { printf '%s\n' "$3" > "$1/$2"; git -C "$1" add "$2"; git -C "$1" -c user.email=t@t -c user.name=t commit -q -m "$3"; }
teardown() {
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
      -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
      FM_HOME="$LAB" TMUX_TMPDIR="$LAB/tmux" PATH="$LAB/fakebin:$PATH" "$@" \
      "$REPO/bin/fm-teardown.sh" "$id"
}
