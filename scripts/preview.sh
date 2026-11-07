#!/bin/bash
# Run the real app with a disposable service and separate app preferences.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
python3 - <<'PY'
from pathlib import Path
import os, plistlib, shutil, signal, socket, subprocess, tempfile

root = Path.cwd()
binary = Path(subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], text=True).strip())
with tempfile.TemporaryDirectory(prefix='steadfast-preview-') as temp:
    base = Path(temp)
    app = base / 'Steadfast Preview.app'
    macos = app / 'Contents/MacOS'
    macos.mkdir(parents=True)
    shutil.copy2(binary / 'Steadfast', macos / 'Steadfast')
    shutil.copy2(binary / 'steadfastd', base / 'steadfastd')
    identifier = 'dev.local.steadfast.preview.' + str(os.getpid())
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': identifier, 'CFBundleName': 'Steadfast Preview',
        'CFBundleExecutable': 'Steadfast', 'CFBundlePackageType': 'APPL',
        'LSMinimumSystemVersion': '26.0', 'NSHighResolutionCapable': True}))
    label = 'dev.local.steadfast.test.preview.' + str(os.getpid())
    domain = 'gui/' + str(os.getuid())
    with socket.socket() as connection:
        connection.bind(('127.0.0.1', 0))
        port = connection.getsockname()[1]
    plist = base / 'service.plist'
    plist.write_bytes(plistlib.dumps({'Label': label,
        'ProgramArguments': [str(base / 'steadfastd'), '--sandbox', str(base / 'state'), label],
        'EnvironmentVariables': {'STEADFAST_TEST_DNS_PORT': str(port)},
        'MachServices': {label: True}, 'RunAtLoad': True,
        'KeepAlive': {'SuccessfulExit': False}, 'ProcessType': 'Adaptive',
        'StandardErrorPath': str(base / 'service.log')}))
    client = None
    try:
        subprocess.run(['launchctl', 'bootstrap', domain, str(plist)], check=True)
        client = subprocess.Popen(['open', '-W', '-n',
            '--env', 'STEADFAST_TEST_SERVICE=' + label,
            '--env', 'STEADFAST_ACTIVITY_FILE=' + str(base / 'outcomes.json'),
            str(app), '--args', '--preview'])
        print('preview app: ' + identifier, flush=True)
        print('disposable service: ' + label, flush=True)
        print('close the preview with command-q to remove its temporary service and files.', flush=True)
        client.wait()
    except KeyboardInterrupt:
        pass
    finally:
        processes = subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True)
        executable = (macos / 'Steadfast').resolve()
        for line in processes.splitlines():
            parts = line.strip().split(maxsplit=1)
            if len(parts) == 2 and Path(parts[1]).resolve() == executable:
                try: os.kill(int(parts[0]), signal.SIGTERM)
                except ProcessLookupError: pass
        if client is not None:
            client.wait(timeout=10)
        subprocess.run(['launchctl', 'bootout', domain + '/' + label], capture_output=True)
        subprocess.run(['defaults', 'delete', identifier], capture_output=True)
PY
