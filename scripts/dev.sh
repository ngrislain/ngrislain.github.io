#!/usr/bin/env bash
# Build the site, serve it, and rebuild whenever a source file changes.
#
#   ./scripts/dev.sh                 # http://localhost:8000
#   PORT=9000 ./scripts/dev.sh       # another port
#   BIND=0.0.0.0 ./scripts/dev.sh    # reachable from other devices
#   VERBOSE=1 ./scripts/dev.sh       # show lake output even when it succeeds
#
# Needs nothing the build does not already need: lake and python3. If fswatch
# happens to be installed it is used, otherwise the script polls once a second.
#
# `lake update` is deliberately not in the loop. It refetches dependencies and
# rewrites lake-manifest.json and lean-toolchain, so run it by hand when you
# actually mean to move the toolchain.

set -uo pipefail

PORT="${PORT:-8000}"
BIND="${BIND:-127.0.0.1}"
INTERVAL="${INTERVAL:-1}"
VERBOSE="${VERBOSE:-}"

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# Everything the site is generated from. build/ and .lake/ are left out on
# purpose: they change during a build and would retrigger it forever.
WATCH=(Site static lakefile.lean lean-toolchain)

lock=".dev.lock"
if [[ -f "$lock" ]]; then
  other=$(cat "$lock" 2>/dev/null)
  if [[ -n "$other" ]] && kill -0 "$other" 2>/dev/null; then
    echo "dev.sh is already running as pid $other." >&2
    echo "Two of them rebuild into the same build/ and corrupt each other." >&2
    echo "Stop that one first, or: kill $other" >&2
    exit 1
  fi
  echo "clearing a stale $lock from pid ${other:-?}" >&2
fi
echo $$ > "$lock"

stamp=$(mktemp)
fifo=$(mktemp -u)
server=""
watcher=""
cleanup() {
  trap - EXIT INT TERM
  [[ -n "$server" ]] && kill "$server" 2>/dev/null
  [[ -n "$watcher" ]] && kill "$watcher" 2>/dev/null
  [[ "$(cat "$lock" 2>/dev/null)" == "$$" ]] && rm -f "$lock"
  rm -f "$stamp" "$fifo"
}
trap cleanup EXIT INT TERM

log() { printf '\033[2m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }

# A successful build says almost nothing, so a long watch session stays
# readable. Everything lake printed is kept and shown only if it fails.
build() {
  local started=$SECONDS status output
  log "building..."
  if [[ -n "$VERBOSE" ]]; then
    lake exe ngrislain-github-io --output build
    status=$?
  else
    output=$(lake exe ngrislain-github-io --output build 2>&1)
    status=$?
  fi
  if (( status == 0 )); then
    log "ready in $((SECONDS - started))s on http://${BIND}:${PORT}"
  else
    [[ -n "${output:-}" ]] && printf '%s\n' "$output" >&2
    log "build failed, still serving the last good copy"
  fi
}

build

python3 -m http.server "$PORT" --directory build --bind "$BIND" >/dev/null 2>&1 &
server=$!
sleep 0.4
if ! kill -0 "$server" 2>/dev/null; then
  server=""
  log "could not serve on port $PORT, is something already using it? (set PORT=)"
  exit 1
fi
if command -v fswatch >/dev/null 2>&1; then
  log "watching ${WATCH[*]} with fswatch, ctrl-c to stop"
  # -o collapses each batch of changes into a single line. After building,
  # drain whatever piled up while the build was running, so one edit does not
  # queue a second rebuild.
  mkfifo "$fifo"
  fswatch -o -r --latency 0.5 "${WATCH[@]}" > "$fifo" &
  watcher=$!
  while read -r _; do
    build
    while read -r -t 0.1 _; do :; done
  done < "$fifo"
else
  log "watching ${WATCH[*]}, polling every ${INTERVAL}s, ctrl-c to stop"
  touch "$stamp"
  while sleep "$INTERVAL"; do
    if [[ -n "$(find "${WATCH[@]}" -type f -newer "$stamp" -print -quit 2>/dev/null)" ]]; then
      touch "$stamp"
      build
    fi
  done
fi
