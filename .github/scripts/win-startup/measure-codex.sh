#!/usr/bin/env bash
# #1613: time from launching `codex` through the agmsg PATH shim until the
# (fake) TUI is exec'd, for several refs, alternating so drift hits all of them.
#
# usage: measure-codex.sh <repo> <ref> [<ref> ...]
# Needs: git, node, sqlite3, a bash with EPOCHREALTIME (Git Bash and bash 5 have it).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$here/common.sh"
repo="$1"; shift
refs=("$@")
runs="${RUNS:-3}"
work="${WORK:-$(mktemp -d)}"
mkdir -p "$work"

# A fake `codex`: --version, an app-server that prints the banner and listens
# (node, so it also runs where python is not on PATH), and anything else is "the TUI".
cat > "$work/listener.js" <<'EOF'
const net = require('net');
const s = net.createServer((c) => c.destroy());
s.listen(0, '127.0.0.1', () => {
  console.log('codex app-server (WebSockets)');
  console.log('  listening on: ws://127.0.0.1:' + s.address().port);
});
setTimeout(() => process.exit(0), 90000);
EOF
mkdir -p "$work/real"
cat > "$work/real/codex" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  --version) echo "codex-cli 0.162.1"; exit 0 ;;
  app-server)
    node "$work/listener.js" &
    child=\$!
    trap 'kill "\$child" 2>/dev/null' TERM INT
    wait "\$child"
    ;;
  *) date +%s.%N > "\$TUI_FILE" ;;
esac
EOF
chmod +x "$work/real/codex"

declare -A results
for r in $(seq 1 "$runs"); do
  for ref in "${refs[@]}"; do
    id="$(printf '%s' "$ref" | tr '/.' '__')"
    skill="$work/skill-$id-$r"
    proj="$work/proj-$id-$r"
    mkdir -p "$proj" "$work/bin-$id-$r"
    make_skill "$repo" "$ref" "$skill"
    export AGMSG_STORAGE_PATH="$skill/store" AGMSG_SELF_NAME=off CODEX_HOME="$work/codexhome"
    mkdir -p "$CODEX_HOME"
    ln -sf "$skill/scripts/drivers/types/codex/codex-shim.sh" "$work/bin-$id-$r/codex"
    bash "$skill/scripts/join.sh" ci seat codex "$proj" >/dev/null 2>&1
    PATH="$work/bin-$id-$r:$work/real:$PATH" \
      bash "$skill/scripts/delivery.sh" set monitor codex "$proj" >/dev/null 2>&1

    # Pieces, each timed on its own.
    a=$(now); bash "$skill/scripts/delivery.sh" status codex "$proj" >/dev/null 2>&1; b=$(now)
    t_status=$(elapsed "$a" "$b")
    a=$(now); PATH="$work/bin-$id-$r:$work/real:$PATH" bash "$skill/scripts/delivery.sh" set monitor codex "$proj" >/dev/null 2>&1; b=$(now)
    t_set=$(elapsed "$a" "$b")

    # The whole launch: shim -> monitor -> exec of the fake TUI.
    export TUI_FILE="$work/tui-$id-$r"; rm -f "$TUI_FILE"
    trace="$work/trace-$id-$r.log"
    a=$(now)
    ( cd "$proj" && env PATH="$work/bin-$id-$r:$work/real:$PATH" \
        SHELLOPTS=xtrace PS4='+T ${EPOCHREALTIME} ${BASH_SOURCE##*/}:${LINENO} ' codex ) 2> "$trace"
    b=$(now)
    if [ -f "$TUI_FILE" ]; then t_launch=$(elapsed "$a" "$(cat "$TUI_FILE")"); else t_launch="no-TUI"; fi
    n_status=$(grep -c 'delivery.sh.* status\|delivery_script.*status' "$trace" || true)
    n_lines=$(wc -l < "$trace" | tr -d ' ')
    echo "run $r  $ref: launch=${t_launch}s  (delivery status alone ${t_status}s, set monitor alone ${t_set}s, trace lines $n_lines)"
    results["$ref"]+="$t_launch "
    results["status:$ref"]+="$t_status "
    results["set:$ref"]+="$t_set "
  done
done

summary "### #1613 codex launch through the shim (windows-latest, fake codex), seconds"
summary "| ref | launch (median) | launch (all runs) | status alone (median) | set monitor alone (median) |"
summary "| --- | ---: | --- | ---: | ---: |"
for ref in "${refs[@]}"; do
  m=$(printf '%s\n' ${results["$ref"]} | grep -E '^[0-9.]+$' | median)
  ms=$(printf '%s\n' ${results["status:$ref"]} | median)
  mt=$(printf '%s\n' ${results["set:$ref"]} | median)
  summary "| $ref | $m | ${results["$ref"]} | $ms | $mt |"
done
