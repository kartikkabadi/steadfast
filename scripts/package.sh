#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SITE='https://github.com/kartikkabadi/steadfast/releases/latest/download'
./scripts/build.sh
APP="$ROOT/dist/Steadfast.app"
CERT="$(cat scripts/release-cert.sha1)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="$ROOT/dist/release"
STAGING="$(mktemp -d "$ROOT/dist/.steadfast-release.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$OUT"
/usr/bin/ditto -c -k --norsrc --noextattr --noqtn --keepParent "$APP" "$STAGING/release.zip"
SHA="$(shasum -a 256 "$STAGING/release.zip" | awk '{print $1}')"
NAME="Steadfast-$VERSION-${SHA:0:12}.zip"
mv "$STAGING/release.zip" "$OUT/$NAME"
printf '{"version":"%s","sha256":"%s"}\n' "$VERSION" "$SHA" > "$STAGING/latest.json"
sed -e "s|@RELEASE_SITE@|$SITE|g" -e "s/@RELEASE_CERT@/$CERT/g" scripts/install.sh > "$STAGING/install.sh"
mv "$STAGING/install.sh" "$STAGING/latest.json" "$OUT/"
for old in "$OUT"/Steadfast-*.zip; do
  [[ -f "$old" && "${old##*/}" =~ ^Steadfast-[0-9]+\.[0-9]+\.[0-9]+-[0-9a-f]{12}\.zip$ ]] || continue
  [[ "${old##*/}" == "$NAME" ]] || rm -- "$old"
done
echo "release files are ready at $OUT"
