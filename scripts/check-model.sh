#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build --package-path "$ROOT" -c release >/dev/null
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
# Every app source but the entry point, so the model links whatever it grows to use.
SOURCES=()
for source in "$ROOT"/Sources/SteadfastApp/*.swift; do
  [[ "$(basename "$source")" == main.swift ]] || SOURCES+=("$source")
done
swiftc -swift-version 6 -parse-as-library -default-isolation MainActor -I "$BIN" \
 "${SOURCES[@]}" "$ROOT/scripts/check-model.swift" \
 "$BIN/SteadfastCore.o" -o "$CHECK/check-model"
# An isolated service name: never the installed service or this Mac's saved data.
STEADFAST_TEST_SERVICE="${STEADFAST_TEST_SERVICE:-dev.local.steadfast.test.model.unavailable}" "$CHECK/check-model"
