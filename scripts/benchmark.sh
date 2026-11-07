#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
swiftc -O -parse-as-library "$ROOT/Sources/SteadfastCore/Policy.swift" "$ROOT/scripts/benchmark.swift" -o "$CHECK/benchmark"
"$CHECK/benchmark"
