#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$(mktemp -d)"
NAME="dev.local.steadfast.test.client.$$"
DOMAIN="gui/$(id -u)"
cleanup() {
  launchctl bootout "$DOMAIN/$NAME" >/dev/null 2>&1 || true
  rm -rf "$CHECK"
}
trap cleanup EXIT
swiftc -swift-version 6 -parse-as-library "$ROOT/Sources/SteadfastCore/"*.swift "$ROOT/scripts/check-client.swift" -o "$CHECK/client-check"
cat > "$CHECK/service.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$NAME</string>
<key>ProgramArguments</key><array><string>$CHECK/client-check</string><string>--server</string><string>$NAME</string></array>
<key>MachServices</key><dict><key>$NAME</key><true/></dict>
</dict></plist>
PLIST
launchctl bootstrap "$DOMAIN" "$CHECK/service.plist"
"$CHECK/client-check" --client "$NAME"
