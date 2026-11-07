#!/bin/bash
set -euo pipefail
if [[ $# -ne 1 || "$1" != --interactive ]]; then
  echo 'this check needs a foreground test window. run with --interactive only when you want that window.' >&2
  exit 2
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
CHECK_DIR="$ROOT/.build/activity-check"
mkdir -p "$CHECK_DIR"
SOURCES=()
for source in "$ROOT"/Sources/SteadfastApp/*.swift; do
  [[ "$(basename "$source")" == main.swift ]] || SOURCES+=("$source")
done
swiftc -swift-version 6 -parse-as-library -default-isolation MainActor -I "$BIN" \
  "${SOURCES[@]}" "$ROOT/scripts/check-activity.swift" "$BIN/SteadfastCore.o" -o "$CHECK_DIR/check"
swiftc -swift-version 6 -default-isolation MainActor "$ROOT/scripts/activity-browser.swift" -o "$CHECK_DIR/browser"
python3 - "$CHECK_DIR" <<'PY'
from pathlib import Path
import os, plistlib, shutil, signal, subprocess, sys, tempfile
check = Path(sys.argv[1])
# Launch Services omits apps in the system temporary directory from URL handlers.
with tempfile.TemporaryDirectory(prefix='run-', dir=check) as temp:
    base = Path(temp)
    app = base / 'Steadfast Activity Check.app'
    macos = app / 'Contents/MacOS'
    macos.mkdir(parents=True)
    shutil.copy2(check / 'browser', macos / 'Browser')
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'org.steadfast.activitybrowser',
        'CFBundleVersion': '1',
        'CFBundleName': 'Steadfast Activity Check', 'CFBundleExecutable': 'Browser',
        'CFBundlePackageType': 'APPL',
        'CFBundleURLTypes': [{'CFBundleURLName': 'Disposable test pages', 'CFBundleURLSchemes': ['http', 'https'],
                             'CFBundleTypeRole': 'Viewer', 'LSHandlerRank': 'Alternate'}]}))
    subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister',
                    '-f', str(app)], check=True)
    browser = subprocess.Popen(['open', '-W', '-n', str(app)])
    try:
        subprocess.run([str(check / 'check'), str(base)], check=True, timeout=200)
    finally:
        for line in subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines():
            parts = line.strip().split(maxsplit=1)
            if len(parts) == 2 and Path(parts[1]).resolve() == (macos / 'Browser').resolve():
                try: os.kill(int(parts[0]), signal.SIGTERM)
                except ProcessLookupError: pass
        browser.wait(timeout=5)
        subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister',
                        '-u', str(app)], capture_output=True)
PY
