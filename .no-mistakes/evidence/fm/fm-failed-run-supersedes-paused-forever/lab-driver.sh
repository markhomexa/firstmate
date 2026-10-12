#!/usr/bin/env bash
set -u
ROOT=$1; BASE=$2; LAB=$3; TD=$4
eval "$(sed -n 82,281p "$ROOT/tests/fm-crew-state.test.sh")"
W=$LAB/work; rm -rf "$W"; mkdir -p "$W"
git init -q -b fm/lab-crew "$W/wt"; git -C "$W/wt" -c user.email=l@l -c user.name=l commit -q --allow-empty -m init
HEAD_SHA=$(git -C "$W/wt" rev-parse HEAD); SHORT=${HEAD_SHA:0:8}
make_fakebin "$W" >/dev/null
export NM_HOME=$W/nm; mkdir -p "$NM_HOME"
# real runs schema copied from the operator's no-mistakes DB (read-only), run row ended at 1790301450 (the real failed run's updated_at)
python3 -I - "$NM_HOME/state.sqlite" <<'PY'
import sqlite3,sys
src=sqlite3.connect('file:/home/homexa/.no-mistakes/state.sqlite?mode=ro',uri=True)
sql=src.execute("select sql from sqlite_master where name='runs'").fetchone()[0].replace('REFERENCES repos(id) ON DELETE CASCADE','')
db=sqlite3.connect(sys.argv[1]); db.execute(sql)
db.execute("insert into runs(id,repo_id,branch,head_sha,base_sha,status,created_at,updated_at) values('01M3B1A1DYP1K0E19KY27D1P8H','r','fm/lab-crew','x','y','failed',1790300000,1790301450)"); db.commit()
PY
# real captured axi status of failed run 01M3B1A1DYP1K0E19KY27D1P8H, rewritten onto the lab branch/head
REAL=$(cd /home/homexa/.treehouse/Yapii-9609e6/6/Yapii && env -u NM_HOME no-mistakes axi status 2>/dev/null | sed -n "/^run:/,\$p")
REAL=$(printf '%s\n' "$REAL" | sed -e "s#fm/tx-date-to-calendar-event#fm/lab-crew#g" -e "s#c198299be60c92630a04f4a2046d5ecff0eba1c7#$HEAD_SHA#g" -e "s#51c2b163ddf13c03b5039d108b826440d4947ea3#$HEAD_SHA#g" -e "s#head: c198299b#head: $SHORT#")
echo "captured status lines: $(printf "%s\n" "$REAL" | wc -l); head: $(printf "%s\n" "$REAL" | grep -m1 "  head:")"
export FM_FAKE_AXI_STATUS="$REAL" FM_FAKE_AXI_STATUS_RUN="$REAL" FM_FAKE_RUNS_LIST=""
export FM_FAKE_PR_STATE=OPEN FM_FAKE_PR_MERGED=false
S=$LAB/state; printf 'window=fm:fm-labcrew\nworktree=%s\nkind=ship\n' "$W/wt" > $S/labcrew.meta
run(){ ${TRACE:-} env -u TMUX -u FM_STATE_OVERRIDE -u FM_ROOT_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE PATH="$W/fakebin:$PATH" TMUX_TMPDIR="$TD" FM_HOME=$LAB "$1/bin/fm-crew-state.sh" labcrew 2>&1; }
both(){ echo "  base   (a1ecefb): $(run $BASE)"; echo "  target (cecd196): $(run $ROOT)"; }
case_(){ echo; echo "## $1"; rm -f $S/labcrew.status; [ -z "$2" ] || printf '%b' "$2" > $S/labcrew.status; [ -f $S/labcrew.status ] && sed 's/^/  status> /' $S/labcrew.status; both; }
echo "run record: 01M3B1A1DYP1K0E19KY27D1P8H status=failed updated_at=1790301450 (real values)"
case_ "S1 incident: failed run, worker later declares paused" 'paused [at=1791700000]: waiting on the follow-up review\n'
case_ "S2 guard: paused stamped BEFORE run ended" 'paused [at=1790300000]: waiting on my own validation round\n'
case_ "S3 guard: failed run, no status log" ''
case_ "S4 guard: later working line after earlier pause" 'paused [at=1790300000]: waiting\nworking [at=1791700000]: resumed\n'
case_ "S5 guard: later done line alone (unmerged PR unknown)" 'done [at=1791700000]: shipped\n'
printf 'pr=https://github.com/o/r/pull/77\n' >> $S/labcrew.meta
export FM_FAKE_PR_STATE=MERGED FM_FAKE_PR_MERGED=true
case_ "S6 incident: failed run, recorded PR merged" ''
export FM_FAKE_PR_STATE=OPEN FM_FAKE_PR_MERGED=false
case_ "S7 guard: failed run, recorded PR still open" ''
sed -i '/^pr=/d' $S/labcrew.meta
C=${REAL/outcome: failed/outcome: cancelled}; C=${C/status: failed/status: cancelled}; export FM_FAKE_AXI_STATUS="$C" FM_FAKE_AXI_STATUS_RUN="$C"
case_ "S8 guard: cancelled run + later paused" 'paused [at=1791700000]: waiting on the follow-up review\n'
