#!/bin/bash
# Renders the site's app screenshots from the real SwiftUI views, using the same
# story as the launch film: "Ship my app", five websites, two hours.
#
# It copies scripts/check-ui.swift into .build, swaps the generic fixture data
# (example.com, 30 minutes, …) for the film's, compiles it beside the app's
# sources and renders. Nothing in Sources/ or scripts/ is changed.
#
#   launch/scripts/render-screens.sh
#
# Step windows are 800 pt wide: at 720 the onboarding wordmark sits 11 pt from the
# zoom button, at 800 the app's own layout gives it room. The page's .lights match.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/launch/site/assets/ui"
WORK="$ROOT/.build/launch-screens"
mkdir -p "$WORK" "$OUT"

python3 - "$ROOT/scripts/check-ui.swift" "$WORK/check-ui.swift" <<'EOF'
import sys
src = open(sys.argv[1]).read()
D = '["reddit.com", "twitter.com", "x.com", "youtu.be", "youtube.com"]'
swaps = [
    # New block and review: the film's five websites, two hours, named.
    ('            model.chosen = ["example.com", "youtube.com"]\n            model.amount = 30; model.multiplier = 1',
     f'            model.chosen = {D}\n            model.amount = 2; model.multiplier = 60\n            model.draftName = "Ship my app"'),
    # Active: that block, just started (it unlocks when the review said it would), and nothing else.
    ('        if state.hasPrefix("active") {', '        if state.hasPrefix("active") && state != "active-aim" {'),
    ('            policy.commitments.append(Commitment(domains: ["x.com", "twitter.com", "instagram.com"], createdAt: Date().addingTimeInterval(-2400),\n                                                 endsAt: Date().addingTimeInterval(3000)))',
     f'            policy.commitments.append(Commitment(domains: {D}, createdAt: Date(),\n                                                 endsAt: Date().addingTimeInterval(120 * 60), name: "Ship my app"))'),
    # Activity: apps that exist on a stock developer Mac, so none shows as a bundle ID.
    ('("com.hnc.discord", nil, 1300), ("com.apple.dt.xcode", nil, 5200),\n                                                       ("com.apple.finder", nil, 300)]',
     '("com.apple.MobileSMS", nil, 1320), ("com.apple.dt.Xcode", nil, 5220),\n                                                       ("com.apple.Music", nil, 720)]'),
    # Notice: unlocks when the menu says it does.
    ('until: Date().addingTimeInterval(5400)', 'until: Date().addingTimeInterval(120 * 60)'),
]
for old, new in swaps:
    assert src.count(old) == 1, f"fixture changed upstream; update launch/scripts/render-screens.sh: {old[:60]}"
    src = src.replace(old, new)
src = src.replace("Date()", "Date(timeIntervalSince1970: TimeInterval(ProcessInfo.processInfo.environment[\"STEADFAST_CAPTURE_TIME\"]!)!)")
open(sys.argv[2], "w").write(src)
EOF

python3 - "$ROOT/Sources/SteadfastApp/Model.swift" "$WORK/Model.swift" <<'EOF'
import sys
src = open(sys.argv[1]).read()
old = 'var currentTime: Date { _ = tick; return max(Date(), snapshot?.now ?? .distantPast) }'
new = 'var currentTime: Date { _ = tick; return Date(timeIntervalSince1970: TimeInterval(ProcessInfo.processInfo.environment["STEADFAST_CAPTURE_TIME"]!)!) }'
assert src.count(old) == 1
open(sys.argv[2], "w").write(src.replace(old, new))
EOF

swift build --package-path "$ROOT" -c release >/dev/null
BIN="$(swift build --package-path "$ROOT" -c release --show-bin-path)"
SOURCES=()
for source in "$ROOT"/Sources/SteadfastApp/*.swift; do
  case "$(basename "$source")" in
    main.swift) ;;
    Model.swift) SOURCES+=("$WORK/Model.swift") ;;
    *) SOURCES+=("$source") ;;
  esac
done
swiftc -swift-version 6 -parse-as-library -default-isolation MainActor -I "$BIN" \
  "${SOURCES[@]}" "$WORK/check-ui.swift" "$BIN/SteadfastCore.o" -o "$WORK/ui"

export STEADFAST_CAPTURE_TIME="$(date +%s)"
export STEADFAST_TEST_SERVICE=dev.local.steadfast.test.ui.unavailable
render() { "$WORK/ui" --light "$@" >/dev/null; }
render --width 800 --height 712 --state onboarding-blocklist --output "$OUT/onboarding-blocklist.png"
render --width 800 --height 712 --state selected   --output "$OUT/selected.png"
# These four use the same capture timestamp for ends at / unlocks at.
render --width 1100 --height 760 --state review    --output "$WORK/review.png"
render --width 800 --height 712 --state active-aim --output "$OUT/active-aim.png"
render --width 420 --height 520 --state active-aim --menu --output "$WORK/menu.png"
render --width 420 --height 200 --state notice-blocked-aim --output "$WORK/notice.png"
render --width 720 --height 820 --state activity   --output "$WORK/activity.png"
render --width 720 --height 640 --state progress   --output "$WORK/progress.png"
render --width 720 --height 640 --state routines   --output "$WORK/routines.png"

# crop <in> <out> <x> <y> <width> <height>, in @2x pixels
crop() { sips --cropOffset "$4" "$3" -c "$6" "$5" "$1" --out "$2" >/dev/null; }
crop "$WORK/review.png"   "$OUT/review.png"         580 366 1040 788   # the sheet
crop "$WORK/menu.png"     "$OUT/menu.png"           119 207  602 626   # the panel
crop "$WORK/notice.png"   "$OUT/notice.png"          60 124  721 154   # the card
crop "$WORK/activity.png" "$OUT/activity-crop.png"   40 650 1360 816   # day, search, four apps
crop "$WORK/progress.png" "$OUT/progress-crop.png"   60 262 1320 878   # heading and year ring
crop "$WORK/routines.png" "$OUT/routines-crop.png"   40 148 1360 560   # heading and two routines
echo "rendered into $OUT"
