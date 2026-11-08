#!/bin/bash
# Captures the README collages from the real app renders in site/assets/ui
# (run render-screens.sh first). Output: docs/images/*.jpg at 2400 px wide.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/launch/collage"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
WORK="$ROOT/.build/launch-collage"
mkdir -p "$WORK" "$ROOT/docs/images"

shoot() { # page height
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --allow-file-access-from-files --window-size="1200,$2" \
    --screenshot="$WORK/$1.png" "file://$HERE/$1.html" >/dev/null 2>&1
  sips -s format jpeg -s formatOptions 88 "$WORK/$1.png" --out "$ROOT/docs/images/$1.jpg" >/dev/null
  echo "docs/images/$1.jpg"
}
shoot hero 675
shoot features 882
