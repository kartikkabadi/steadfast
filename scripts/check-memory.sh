#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
swiftc -O -parse-as-library -swift-version 6 -target arm64-apple-macos26.0 -default-isolation MainActor \
 "$ROOT/Sources/SteadfastApp/MemoryPressure.swift" "$ROOT/scripts/check-memory.swift" -o "$CHECK/check-memory"
"$CHECK/check-memory" "$@"
