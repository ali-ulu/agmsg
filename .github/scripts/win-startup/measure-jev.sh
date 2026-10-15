#!/usr/bin/env bash
# #1584: time of the jev ext-tool `handle` on its own (payload on stdin, a
# loopback fake endpoint), for several refs, alternating.
#
# usage: measure-jev.sh <repo> <ref> [<ref> ...]
# Needs: git, node, jq, curl.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$here/common.sh"
repo="$1"; shift
refs=("$@")
runs="${RUNS:-3}"
work="${WORK:-$(mktemp -d)}"
mkdir -p "$work"

cat > "$work/endpoint.js" <<'EOF'
const http = require('http');
const resp = {
  answers: {
    kind: { choice: 'bug', probabilities: { bug: 0.9 }, confidence: 0.8 },
    effort: { choice: 'low', probabilities: { low: 0.9 }, confidence: 0.8 },
  },
  usage: { cost: 0.0001 },
};
const s = http.createServer((req, res) => {
  req.on('data', () => {});
  req.on('end', () => {
    const b = JSON.stringify(resp);
    res.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(b) });
    res.end(b);
  });
});
s.listen(0, '127.0.0.1', () => console.log(s.address().port));
EOF
node "$work/endpoint.js" > "$work/port" 2>/dev/null &
srv=$!
for _ in $(seq 1 50); do [ -s "$work/port" ] && break; sleep 0.2; done
export AGMSG_JEV_API_BASE="http://127.0.0.1:$(tr -d '\r\n' < "$work/port")"
printf 'k-secret-123\n' > "$work/key"
printf 'key_file=%s\n' "$work/key" > "$work/conf"
body='{"state":"s","questions":{"kind":{"criteria":{"bug":"x","feature":"y","chore":"z","doc":"w"}},"effort":{"criteria":{"low":"a","mid":"b","high":"c"}}}}'
payload="$(jq -cn --arg b "$body" --arg c "$work/conf" '{team:"t",from:"a",to:"jev",body:$b,message_id:"1",config_path:$c}')"

declare -A results
for r in $(seq 1 "$runs"); do
  for ref in "${refs[@]}"; do
    id="$(printf '%s' "$ref" | tr '/.' '__')"
    dest="$work/skill-$id-$r"
    mkdir -p "$dest"
    git -C "$repo" archive "$ref" scripts/drivers/ext-tools/jev | tar -x -C "$dest"
    h="$dest/scripts/drivers/ext-tools/jev/handle"
    a=$(now); out="$(printf '%s' "$payload" | bash "$h" 2>&1)"; rc=$?; b=$(now)
    t=$(elapsed "$a" "$b")
    echo "run $r  $ref: handle=${t}s rc=$rc  $(printf '%s' "$out" | head -c 100 | tr '\n' '|')"
    results["$ref"]+="$t "
  done
done
kill "$srv" 2>/dev/null

summary "### #1584 jev handle alone (windows-latest, loopback endpoint, 2 questions), seconds"
summary "| ref | handle (median) | handle (all runs) |"
summary "| --- | ---: | --- |"
for ref in "${refs[@]}"; do
  m=$(printf '%s\n' ${results["$ref"]} | median)
  summary "| $ref | $m | ${results["$ref"]} |"
done
