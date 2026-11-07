#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$(mktemp -d)"
trap 'rm -rf "$CHECK"' EXIT
cp "$ROOT/scripts/check-auth.swift" "$CHECK/main.swift"
swiftc -swift-version 6 "$ROOT/Sources/SteadfastCore/"*.swift "$CHECK/main.swift" -o "$CHECK/auth-check"
codesign --force --sign - --identifier dev.local.steadfast.auth-check "$CHECK/auth-check"
CDHASH="$(codesign -dv --verbose=4 "$CHECK/auth-check" 2>&1 | sed -n 's/^CDHash=//p')"
[[ "$CDHASH" =~ ^[a-fA-F0-9]{40}$ ]]
"$CHECK/auth-check" "$CDHASH"
"$CHECK/auth-check" "$CDHASH" --deny
