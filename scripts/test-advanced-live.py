#!/usr/bin/env python3
"""Exercise shared-folder routines and quota enforcement through real sandbox services."""
from pathlib import Path
from datetime import datetime
import hashlib
import json
import os
import plistlib
import socket
import subprocess
import tempfile
import time
import uuid

root = Path(__file__).resolve().parents[1]
binary = Path(subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], text=True).strip())
gui = f'gui/{os.getuid()}'
reference = 978307200
before = hashlib.sha256(Path('/etc/hosts').read_bytes()).hexdigest()

def check(condition, message):
    if not condition:
        raise AssertionError(message)
    print('pass: ' + message, flush=True)

with tempfile.TemporaryDirectory(prefix='steadfast-advanced-live-') as temporary:
    folder = Path(temporary)
    shared = folder / 'shared'
    shared.mkdir()
    sources = root / 'Sources/SteadfastApp'
    harness = folder / 'sync'
    subprocess.run(['swiftc', '-swift-version', '6', '-parse-as-library', '-default-isolation', 'MainActor',
                    '-I', str(binary), *(str(path) for path in sorted(sources.glob('*.swift')) if path.name != 'main.swift'),
                    str(root / 'scripts/check-sync-live.swift'), str(binary / 'SteadfastCore.o'), '-o', str(harness)], check=True)

    labels, plists, ports = [], [], []
    try:
        for index in range(2):
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.bind(('127.0.0.1', 0))
                port = sock.getsockname()[1]
            ports.append(port)
            label = 'dev.local.steadfast.test.advanced.' + str(uuid.uuid4()).lower()
            labels.append(label)
            state = folder / str(index)
            state.mkdir()
            if index == 0:
                midnight = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
                (state / 'policy.json').write_text(json.dumps({'commitments': [], 'dailyLimits': [
                    {'domain': 'quota.example', 'minutes': 1, 'secondsUsed': 53, 'dayStart': midnight - reference}
                ]}))
                resolver = state / 'resolver'
                resolver.mkdir()
                (resolver / 'other-profile').write_bytes(b'\xff\x00\xfe')
                (resolver / 'other-directory').mkdir()
            plist = folder / f'{index}.plist'
            plists.append(plist)
            plist.write_bytes(plistlib.dumps({
                'Label': label, 'ProgramArguments': [str(binary / 'steadfastd'), '--sandbox', str(state), label],
                'MachServices': {label: True}, 'RunAtLoad': True, 'KeepAlive': {'SuccessfulExit': False},
                'EnvironmentVariables': {'STEADFAST_TEST_DNS_PORT': str(port)},
                'StandardErrorPath': str(state / 'service.log'),
            }))
            subprocess.run(['launchctl', 'bootstrap', gui, str(plist)], check=True)

        subprocess.run([str(harness), *labels, str(shared)], check=True, timeout=80)
        env = {**os.environ, 'STEADFAST_TEST_SERVICE': labels[0]}

        def rpc(action, **values):
            return subprocess.run([str(binary / 'Steadfast'), '--request-json', json.dumps({'action': action, **values})],
                                  env=env, capture_output=True, text=True, timeout=65)

        def send(action, **values):
            result = rpc(action, **values)
            if result.returncode:
                raise RuntimeError(result.stderr)
            return json.loads(result.stdout)

        def dns():
            result = subprocess.run(['dig', '@127.0.0.1', '-p', str(ports[0]), 'quota.example', '+time=1', '+tries=1'],
                                    capture_output=True, text=True, timeout=4)
            return result.stdout

        check('status: SERVFAIL' in dns(), 'unused quota leaves the domain unblocked by the sandbox')
        sample = {'domain': 'quota.example', 'endedAt': time.time() - reference, 'seconds': 8}
        reached = send('record-usage', usageSample=sample)
        check(reached['policy']['dailyLimits'][0]['secondsUsed'] >= 60, 'a current sample exhausts the remaining budget')
        check(reached.get('enforcementError') is None and 'status: NXDOMAIN' in dns(),
              'an exhausted daily limit blocks over real dns')
        check(send('record-usage', usageSample=sample)['policy']['dailyLimits'] == reached['policy']['dailyLimits'],
              'replaying an acknowledged sample cannot double-count')
        check(rpc('prepare-uninstall').returncode != 0, 'uninstall cannot leave an exhausted quota behind')
        check(rpc('record-usage', usageSample=dict(sample, endedAt=sample['endedAt'] - 60)).returncode != 0,
              'the service rejects stale usage')
        send('delete-limit', limit={'domain': 'quota.example', 'minutes': 1, 'secondsUsed': 0})
        check('status: SERVFAIL' in dns() and not (folder / '0/resolver/quota.example').exists(),
              'removing a daily limit removes only its own resolver rule')
        check((folder / '0/resolver/other-profile').read_bytes() == b'\xff\x00\xfe'
              and (folder / '0/resolver/other-directory').is_dir(),
              'cleanup preserves unrelated resolver directory entries')
        check(hashlib.sha256(Path('/etc/hosts').read_bytes()).hexdigest() == before, 'the real hosts file is unchanged')
    finally:
        for plist in plists:
            subprocess.run(['launchctl', 'bootout', gui, str(plist)], capture_output=True)
