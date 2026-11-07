#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build -c release
python3 - <<'PY'
from pathlib import Path
import hashlib, os, plistlib, shutil, socket, subprocess, tempfile

root = Path.cwd()
binary = Path(subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], text=True).strip())
sources = sorted((root / 'Sources/SteadfastApp').glob('*.swift'))
output = root / '.build/experience-check'
subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', '-default-isolation', 'MainActor',
                '-I', str(binary), *(str(p) for p in sources if p.name != 'main.swift'),
                str(root / 'scripts/check-experience.swift'), str(binary / 'SteadfastCore.o'), '-o', str(output)], check=True)
hosts_before = hashlib.sha256(Path('/etc/hosts').read_bytes()).hexdigest()
with tempfile.TemporaryDirectory(prefix='steadfast-experience-') as temp:
    base = Path(temp)
    label = 'dev.local.steadfast.test.experience.' + str(os.getpid())
    domain = 'gui/' + str(os.getuid())
    shutil.copy2(binary / 'steadfastd', base / 'steadfastd')
    with socket.socket() as connection:
        connection.bind(('127.0.0.1', 0))
        port = connection.getsockname()[1]
    plist = base / 'service.plist'
    log = base / 'service.log'
    plist.write_bytes(plistlib.dumps({'Label': label,
        'ProgramArguments': [str(base / 'steadfastd'), '--sandbox', str(base / 'state'), label],
        'EnvironmentVariables': {'STEADFAST_TEST_DNS_PORT': str(port)},
        'MachServices': {label: True}, 'RunAtLoad': True,
        'KeepAlive': {'SuccessfulExit': False}, 'ProcessType': 'Adaptive',
        'StandardErrorPath': str(log)}))
    try:
        subprocess.run(['launchctl', 'bootstrap', domain, str(plist)], check=True)
        result = subprocess.run([str(output), str(base)],
            env={**os.environ, 'STEADFAST_TEST_SERVICE': label}, timeout=150)
        if result.returncode:
            if log.exists(): print(log.read_text())
            raise SystemExit(result.returncode)
    finally:
        subprocess.run(['launchctl', 'bootout', domain + '/' + label], capture_output=True)
        assert hashlib.sha256(Path('/etc/hosts').read_bytes()).hexdigest() == hosts_before, 'system hosts changed'
PY
