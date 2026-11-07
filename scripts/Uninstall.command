#!/bin/bash
set -euo pipefail

# Read the privileged operations before requesting authentication, so sudo
# never reads this potentially user-writable script after its password prompt.
ROOT_SCRIPT="$(/bin/cat <<'ROOT'
set -euo pipefail
APP='/Applications/Steadfast.app'
STATE='/Library/Application Support/Steadfast'
PLIST='/Library/LaunchDaemons/dev.local.steadfast.service.plist'
PIN="$STATE/client.requirement"
RUNTIME_PIN="$STATE/client.runtime-requirement"
[[ -x "$APP/Contents/MacOS/Steadfast" && -f "$PIN" && -f "$RUNTIME_PIN" ]] || {
  echo 'the installed app or its signing requirements are missing. see the recovery instructions in README.md.' >&2; exit 1
}
# /Applications can be writable by administrators. Copy first, then verify and
# execute only the root-owned copy, so an app replacement cannot run as root.
STAGING="$(/usr/bin/mktemp -d /private/var/root/steadfast-uninstall.XXXXXX)"
trap '/bin/rm -rf "$STAGING"' EXIT
/usr/bin/ditto "$APP" "$STAGING/Steadfast.app"
APP="$STAGING/Steadfast.app"
/usr/bin/codesign --verify --deep --strict -R "$PIN" "$APP"
/usr/bin/codesign --verify --strict -R "$RUNTIME_PIN" "$APP"
# The service must be reachable and every commitment must have expired.
"$APP/Contents/MacOS/Steadfast" --can-uninstall
/bin/launchctl bootout system "$PLIST"
# The service cleans hosts/resolvers before authorizing uninstall.
/bin/rm -f /Library/PrivilegedHelperTools/dev.local.steadfastd /Library/PrivilegedHelperTools/dev.local.steadfast.service "$PLIST"
/bin/rm -rf "$STATE" /Applications/Steadfast.app
echo 'steadfast was uninstalled.'
ROOT
)"
if [[ $EUID -ne 0 ]]; then exec /usr/bin/sudo /bin/bash -c "$ROOT_SCRIPT"; fi
exec /bin/bash -c "$ROOT_SCRIPT"
