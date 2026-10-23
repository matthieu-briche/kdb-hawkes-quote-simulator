#!/usr/bin/env bash
# End-to-end test of the real-time path: tick/tp.q -> tick/rdb.q, fed by feed.q.
# Usage (from the repository root, after `q hawkes_quotes.q`):  bash tests/tick_smoke.sh
#   MODE=udp bash tests/tick_smoke.sh   same test through UDP: feed.q -udp -> fh.q -> tp
#                                       (skipped if KDB-X or the dot.udp module is missing)
# Uses ports 15010/15011 (and UDP 15020) and a temporary journal directory; cleans up on exit.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d hdbq ] || { echo "hdbq/ missing: run 'q hawkes_quotes.q' first"; exit 1; }
DATE=${DATE:-2024.01.02}
TP=${TP_PORT:-15010}; RDB=${RDB_PORT:-15011}
MODE=${MODE:-tcp}
# unicast on the loopback by default: multicast needs a route, often missing in containers and CI
UDP_ADDR=${UDP_ADDR:-127.0.0.1:15020}
LOG=$(mktemp -d)
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; rm -rf "$LOG"; }
trap cleanup EXIT

if [ "$MODE" = udp ]; then
  if ! q tests/has_module.q dot.udp > /dev/null 2>&1 < /dev/null; then
    echo "tick smoke test (udp): SKIP, KDB-X with the dot.udp module is required"; exit 0
  fi
fi

q tick/tp.q "$LOG" -p "$TP" > "$LOG/tp.out" 2>&1 < /dev/null & pids+=($!)
sleep 1
q tick/rdb.q ":$TP" -p "$RDB" > "$LOG/rdb.out" 2>&1 < /dev/null & pids+=($!)
sleep 1
if [ "$MODE" = udp ]; then
  q fh.q "$UDP_ADDR" "$TP" > "$LOG/fh.out" 2>&1 < /dev/null & pids+=($!)
  sleep 1
  # the UDP feed is paced (udpRows*udpMax rows per 100 ms tick): about 15 s for one day
  q feed.q 100000 "$DATE" "$TP" -udp "$UDP_ADDR" > "$LOG/feed.out" 2>&1 < /dev/null & pids+=($!)
else
  # x100000: the 6h30 session is replayed in about a quarter of a second
  q feed.q 100000 "$DATE" "$TP" > "$LOG/feed.out" 2>&1 < /dev/null & pids+=($!)
fi

if q tests/tick_check.q "$RDB" "$DATE" 120 < /dev/null; then
  echo "tick smoke test ($MODE): PASS"
else
  echo "tick smoke test ($MODE): FAIL"
  for f in tp rdb fh feed; do
    if [ -f "$LOG/$f.out" ]; then echo "--- $f"; cat "$LOG/$f.out"; fi
  done
  exit 1
fi
