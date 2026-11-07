#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build --package-path "$ROOT" -c release >/dev/null
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
CHECK_DIR="$ROOT/.build/ui-check"
mkdir -p "$CHECK_DIR"
CHECK_BIN="$CHECK_DIR/steadfast-ui-check"

SOURCES=()
for source in "$ROOT"/Sources/SteadfastApp/*.swift; do
  [[ "$(basename "$source")" == main.swift ]] || SOURCES+=("$source")
done

NEEDS_REBUILD=0
if [[ ! -f "$CHECK_BIN" ]]; then
  NEEDS_REBUILD=1
else
  for s in "${SOURCES[@]}" "$ROOT/scripts/check-ui.swift" "$BIN/SteadfastCore.o"; do
    if [[ "$s" -nt "$CHECK_BIN" ]]; then
      NEEDS_REBUILD=1
      break
    fi
  done
fi

if [[ "$NEEDS_REBUILD" -eq 1 ]]; then
  swiftc -swift-version 6 -parse-as-library -default-isolation MainActor -I "$BIN" \
    "${SOURCES[@]}" "$ROOT/scripts/check-ui.swift" "$BIN/SteadfastCore.o" -o "$CHECK_BIN"
fi

STEADFAST_TEST_SERVICE="${STEADFAST_TEST_SERVICE:-dev.local.steadfast.test.ui.unavailable}" \
  "$CHECK_BIN" "$@"
