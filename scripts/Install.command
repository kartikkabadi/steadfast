#!/bin/bash
set -euo pipefail
if [[ $# -eq 1 && $EUID -eq 0 ]]; then
  APP="$1"
elif [[ $# -ne 0 ]]; then
  echo 'unexpected installer arguments' >&2; exit 2
else
  HERE="$(cd "$(dirname "$0")" && pwd)"
  if [[ "$HERE" == */Steadfast.app/Contents/Resources ]]; then
    APP="${HERE%/Contents/Resources}"
  else
    APP="$HERE/Steadfast.app"
  fi
fi
if [[ $EUID -ne 0 ]]; then
  echo 'steadfast installs a root-owned background service, independent of the window app.'
  echo 'it changes /etc/hosts and /etc/resolver only after you start a commitment,'
  echo 'and closes apps you block only while their block runs.'
  echo 'administrator authentication is required.'
  CERT='@RELEASE_CERT@'
  [[ "$CERT" =~ ^[A-Fa-f0-9]{40}$ ]] || { echo 'use a packaged steadfast installer' >&2; exit 1; }
  exec /usr/bin/sudo /bin/bash -c '
    set -euo pipefail
    source_app="$1"
    cert="$2"
    stage="$(/usr/bin/mktemp -d /private/var/root/.steadfast-verify.XXXXXX)"
    trap '\''/bin/rm -rf "$stage"'\'' EXIT
    /usr/bin/ditto "$source_app" "$stage/Steadfast.app"
    /usr/sbin/chown -R root:wheel "$stage"
    /bin/chmod -R go-w "$stage"
    app="$stage/Steadfast.app"
    /usr/bin/codesign --verify --deep --strict "$app"
    /usr/bin/codesign --verify --strict -R "=identifier \"dev.local.steadfast\" and certificate root = H\"$cert\"" "$app"
    /usr/bin/codesign --verify --strict -R "=identifier \"dev.local.steadfast.service\" and certificate root = H\"$cert\"" "$app/Contents/Resources/steadfastd"
    /bin/bash "$app/Contents/Resources/Install.command" "$app"
  ' steadfast-install "$APP" "$CERT"
fi
STATE='/Library/Application Support/Steadfast'
SERVICE='/Library/PrivilegedHelperTools/dev.local.steadfastd'
PLIST='/Library/LaunchDaemons/dev.local.steadfast.service.plist'
DEST='/Applications/Steadfast.app'
POLICY="$STATE/policy.json"
PIN="$STATE/client.requirement"
RUNTIME_PIN="$STATE/client.runtime-requirement"
for path in "$STATE" "$SERVICE" "$PLIST" "$DEST" "$POLICY" "$PIN" "$RUNTIME_PIN"; do
  [[ ! -L "$path" ]] || { echo "refusing a symbolic link at $path" >&2; exit 1; }
done
# Stage a complete replacement, so old resources cannot survive an update.
STAGING="$(/usr/bin/mktemp -d /private/var/root/.steadfast-install.XXXXXX)"
trap '/bin/rm -rf "$STAGING"' EXIT
/usr/bin/ditto "$APP" "$STAGING/Steadfast.app"
/usr/sbin/chown -R root:wheel "$STAGING"
/bin/chmod -R go-w "$STAGING"
APP="$STAGING/Steadfast.app"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/codesign --verify --strict "$APP/Contents/Resources/steadfastd"
CERT='@RELEASE_CERT@'
[[ "$CERT" =~ ^[A-Fa-f0-9]{40}$ ]] || { echo 'use a packaged steadfast installer' >&2; exit 1; }
REQUIREMENT="identifier \"dev.local.steadfast\" and certificate root = H\"$CERT\""
/usr/bin/codesign --verify --strict -R "=$REQUIREMENT" "$APP"
/usr/bin/codesign --verify --strict -R "=identifier \"dev.local.steadfast.service\" and certificate root = H\"$CERT\"" "$APP/Contents/Resources/steadfastd"
/usr/bin/xattr -dr com.apple.quarantine "$APP"
if [[ -f "$PIN" ]]; then
  REQUIREMENT="$(/bin/cat "$PIN")"
  # An update must remain authorized by the original installation.
  /usr/bin/codesign --verify --strict -R "$PIN" "$APP"
elif [[ -e "$POLICY" ]]; then
  echo 'the policy has no client signing requirement. restore client.requirement from your original installation before repairing.' >&2
  exit 1
fi
/usr/bin/printf '%s\n' "$REQUIREMENT" > "$STAGING/client.requirement"
# Bind live connections to these verified executable bytes, without repeating
# certificate-chain trust evaluation on every new XPC session.
CDHASH="$(/usr/bin/codesign -dv --verbose=4 "$APP" 2>&1 | /usr/bin/sed -n 's/^CDHash=//p')"
[[ "$CDHASH" =~ ^[a-fA-F0-9]{40}$ ]] || { echo 'missing executable code hash' >&2; exit 1; }
/usr/bin/printf 'cdhash H"%s"\n' "$CDHASH" > "$STAGING/client.runtime-requirement"
cat > "$STAGING/service.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>dev.local.steadfast.service</string>
<key>ProgramArguments</key><array><string>/Library/PrivilegedHelperTools/dev.local.steadfastd</string></array>
<key>MachServices</key><dict><key>dev.local.steadfast.service</key><true/></dict>
<key>RunAtLoad</key><true/><key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
<key>ThrottleInterval</key><integer>10</integer>
<key>ProcessType</key><string>Adaptive</string>
<key>StandardErrorPath</key><string>/Library/Application Support/Steadfast/service.log</string>
</dict></plist>
PLIST
LOADED=false
if /bin/launchctl print system/dev.local.steadfast.service >/dev/null 2>&1; then LOADED=true; fi
RESTART=false
if [[ "$LOADED" == false ]] || ! /usr/bin/cmp -s "$APP/Contents/Resources/steadfastd" "$SERVICE" || ! /usr/bin/cmp -s "$STAGING/service.plist" "$PLIST" || ! /usr/bin/cmp -s "$STAGING/client.requirement" "$PIN" || ! /usr/bin/cmp -s "$STAGING/client.runtime-requirement" "$RUNTIME_PIN"; then RESTART=true; fi
for pair in "$DEST|Previous.app" "$SERVICE|previous.helper" "$PLIST|previous.plist" "$PIN|previous.requirement" "$RUNTIME_PIN|previous.runtime-requirement"; do
  path="${pair%|*}"; backup="${pair#*|}"
  if [[ -e "$path" ]]; then /usr/bin/ditto "$path" "$STAGING/$backup"; fi
done
CHANGED=false
SERVICE_CHANGED=false
finish() {
  result=$?
  trap - EXIT
  if [[ $result -ne 0 && "$CHANGED" == true ]]; then
    if [[ ! -e "$STAGING/previous.helper" ]]; then
      echo 'the new installation was kept for repair so any commitments accepted during setup remain enforced.' >&2
    else
      echo 'update failed; restoring the previous installation without changing commitments.' >&2
      if [[ "$SERVICE_CHANGED" == true ]]; then /bin/launchctl bootout system/dev.local.steadfast.service >/dev/null 2>&1 || true; fi
      restored=true
      for pair in "$DEST|Previous.app" "$SERVICE|previous.helper" "$PLIST|previous.plist" "$PIN|previous.requirement" "$RUNTIME_PIN|previous.runtime-requirement"; do
        path="${pair%|*}"; backup="${pair#*|}"
        if ! /bin/rm -rf "$path"; then restored=false; fi
        if [[ -e "$STAGING/$backup" ]]; then
          if ! /usr/bin/ditto "$STAGING/$backup" "$path"; then restored=false; fi
        fi
      done
      if [[ "$SERVICE_CHANGED" == true && "$LOADED" == true ]]; then
        if ! /bin/launchctl bootstrap system "$PLIST"; then restored=false; fi
      fi
      if [[ "$restored" == false ]]; then
        echo "could not fully restore the installation. backups remain at $STAGING" >&2
        exit "$result"
      fi
    fi
  fi
  /bin/rm -rf "$STAGING"
  exit "$result"
}
trap finish EXIT
CHANGED=true
if [[ "$RESTART" == true && "$LOADED" == true ]]; then
  SERVICE_CHANGED=true
  /bin/launchctl bootout system/dev.local.steadfast.service
fi
/bin/mkdir -p "$STATE" /Library/PrivilegedHelperTools
/usr/sbin/chown root:wheel "$STATE"
/bin/chmod 700 "$STATE"
/bin/rm -rf "$DEST"
/bin/mv "$APP" "$DEST"
if [[ "$RESTART" == true ]]; then
  # Avoid the reserved .service bundle suffix for a standalone executable.
  /usr/bin/install -o root -g wheel -m 755 "$DEST/Contents/Resources/steadfastd" "$SERVICE"
  /usr/bin/install -o root -g wheel -m 600 "$STAGING/client.requirement" "$PIN"
  /usr/bin/install -o root -g wheel -m 600 "$STAGING/client.runtime-requirement" "$RUNTIME_PIN"
  /usr/bin/install -o root -g wheel -m 644 "$STAGING/service.plist" "$PLIST"
  SERVICE_CHANGED=true
  /bin/launchctl bootstrap system "$PLIST"
fi
# Verify the installed client's production XPC connection before reporting success.
STATUS="$STAGING/status.json"
CLIENT=(/usr/bin/env -u STEADFAST_TEST_SERVICE "$DEST/Contents/MacOS/Steadfast")
if [[ "${SUDO_UID:-0}" =~ ^[0-9]+$ && "${SUDO_UID:-0}" -ne 0 ]]; then
  CLIENT=(/usr/bin/sudo -u "#${SUDO_UID}" "${CLIENT[@]}")
fi
# The first authenticated connection can wait for macOS signing services.
for _ in {1..2}; do
  if "${CLIENT[@]}" --request-json '{"action":"status"}' > "$STATUS" 2> "$STAGING/status.error"; then
    if [[ "$(/usr/bin/plutil -extract sandbox raw -o - "$STATUS")" == false ]] && ! /usr/bin/plutil -extract enforcementError raw -o - "$STATUS" >/dev/null 2>&1; then
      /bin/rm -f /Library/PrivilegedHelperTools/dev.local.steadfast.service
      echo 'installed and verified. open /Applications/Steadfast.app and choose your websites.'
      exit 0
    fi
  fi
  /bin/sleep 1
done
echo 'the production service did not become healthy.' >&2
/bin/cat "$STAGING/status.error" >&2
/bin/cat "$STATUS" >&2
echo 'inspect /Library/Application Support/Steadfast/service.log and launchctl print system/dev.local.steadfast.service.' >&2
exit 1
