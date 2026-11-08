#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"
DIST="$ROOT/dist"
mkdir -p "$DIST"
STAGING="$(/usr/bin/mktemp -d "$DIST/.steadfast-build.XXXXXX")"
trap '/bin/rm -rf "$STAGING"' EXIT
APP="$STAGING/Steadfast.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Steadfast" "$APP/Contents/MacOS/Steadfast"
cp "$BIN/steadfastd" "$APP/Contents/Resources/steadfastd"
/usr/bin/strip -S "$APP/Contents/MacOS/Steadfast" "$APP/Contents/Resources/steadfastd"
cp "$ROOT/scripts/Uninstall.command" "$APP/Contents/Resources/Uninstall.command"
cp "$ROOT/scripts/Uninstall.command" "$DIST/Uninstall.command"
swift "$ROOT/scripts/build-icon.swift" "$ROOT/Icon/Steadfast.png" "$STAGING/AppIcon.iconset"
/usr/bin/iconutil -c icns "$STAGING/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.local.steadfast</string>
<key>CFBundleName</key><string>steadfast</string>
<key>CFBundleDisplayName</key><string>steadfast</string>
<key>CFBundleExecutable</key><string>Steadfast</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.1</string>
<key>CFBundleVersion</key><string>27</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
chmod +x "$DIST/Uninstall.command" "$APP/Contents/Resources/Uninstall.command"
KEYCHAIN="$("$ROOT/scripts/signing-identity.sh")"
CERT="$(/usr/bin/security find-certificate -c 'Steadfast Release' -Z "$KEYCHAIN" | /usr/bin/awk '/SHA-1 hash:/ {print $3; exit}')"
[[ "$CERT" =~ ^[A-Fa-f0-9]{40}$ ]] || { echo 'steadfast release certificate missing' >&2; exit 1; }
PIN="$ROOT/scripts/release-cert.sha1"
[[ -f "$PIN" && "$CERT" == "$(/bin/cat "$PIN")" ]] || {
  echo 'the keychain certificate does not match the pinned release certificate' >&2
  exit 1
}
SITE='https://github.com/kartikkabadi/steadfast/releases/latest/download'
/usr/libexec/PlistBuddy -c "Add :SteadfastSiteURL string $SITE" "$APP/Contents/Info.plist"
/usr/bin/sed "s/@RELEASE_CERT@/$CERT/g" "$ROOT/scripts/Install.command" > "$APP/Contents/Resources/Install.command"
{
  printf '#!/bin/bash\nexec /bin/bash -s -- --in-app <<\x27STEADFAST_INSTALL\x27\n'
  /usr/bin/sed -e "s|@RELEASE_SITE@|$SITE|g" -e "s/@RELEASE_CERT@/$CERT/g" "$ROOT/scripts/install.sh"
  printf 'STEADFAST_INSTALL\n'
} > "$APP/Contents/Resources/Update.command"
/bin/chmod 755 "$APP/Contents/Resources/"{Install,Update}.command
SIGN=(--force --keychain "$KEYCHAIN" --sign "$CERT" --timestamp=none --options runtime)
/usr/bin/codesign "${SIGN[@]}" --identifier dev.local.steadfast.service "$APP/Contents/Resources/steadfastd"
/usr/bin/codesign "${SIGN[@]}" "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/codesign --verify --strict -R="identifier \"dev.local.steadfast\" and certificate root = H\"$CERT\"" "$APP"
/bin/cp "$APP/Contents/Resources/Install.command" "$DIST/Install.command"
/bin/rm -rf "$DIST/Steadfast.app"
/bin/mv "$APP" "$DIST/Steadfast.app"
echo "built $DIST/Steadfast.app"
