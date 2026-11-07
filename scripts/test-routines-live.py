#!/usr/bin/env python3
"""Exercise routines and real scheduled starts through a disposable XPC service."""
from pathlib import Path
from datetime import datetime, timedelta
import hashlib, json, os, plistlib, re, shutil, subprocess, tempfile, time, uuid

root = Path(__file__).resolve().parents[1]
binary = Path(subprocess.check_output(['swift', 'build', '-c', 'release', '--show-bin-path'], text=True).strip())
base = Path(tempfile.mkdtemp(prefix='steadfast-routines-live-'))
for executable in ['Steadfast', 'steadfastd']:
    shutil.copy2(binary / executable, base / executable)
label = 'dev.local.steadfast.test.routines.' + str(os.getpid())
domain = 'gui/' + str(os.getuid())
state = base / 'state'
state.mkdir()
reference = 978307200
before = hashlib.sha256(Path('/etc/hosts').read_bytes()).hexdigest()
legacy_id = str(uuid.uuid4()).upper()
(state / 'policy.json').write_text(json.dumps({
    'commitments': [{'id': legacy_id, 'domains': ['legacy.example'], 'createdAt': time.time() - reference - 180,
                     'endsAt': time.time() - reference - 120}], 'lastObserved': time.time() - reference - 120
}))
plist = base / 'service.plist'
plist.write_bytes(plistlib.dumps({'Label': label,
    'ProgramArguments': [str(base / 'steadfastd'), '--sandbox', str(state), label],
    'MachServices': {label: True}, 'RunAtLoad': True, 'KeepAlive': {'SuccessfulExit': False},
    'ProcessType': 'Adaptive', 'StandardErrorPath': str(base / 'service.log')}))
env = {**os.environ, 'STEADFAST_TEST_SERVICE': label}
checks = []

def rpc(action, **values):
    return subprocess.run([str(base / 'Steadfast'), '--request-json', json.dumps({'action': action, **values})],
                          env=env, capture_output=True, text=True, timeout=65)

def send(action, **values):
    result = rpc(action, **values)
    if result.returncode: raise RuntimeError(f'{action} exited {result.returncode}: {result.stderr} {result.stdout}')
    return json.loads(result.stdout)

def check(value, description):
    if not value: raise AssertionError(description)
    checks.append(description)
    print('pass: ' + description, flush=True)

def dns(name):
    return subprocess.check_output(['dig', '@127.0.0.1', '-p', '55353', name, '+time=1', '+tries=1'], text=True, timeout=4)

def service_pid():
    result = subprocess.run(['launchctl', 'print', domain + '/' + label], capture_output=True, text=True)
    match = re.search(r'\bpid = ([0-9]+)', result.stdout)
    return int(match[1]) if match else None

try:
    subprocess.run(['launchctl', 'bootstrap', domain, str(plist)], check=True)
    initial = send('status')
    check(initial.get('enforcementError') is None and initial['sandbox'], 'sandbox starts healthy')
    check(initial['policy']['commitments'][0]['id'] == legacy_id and initial['policy']['routines'] == [],
          'legacy policy loads with its completed session intact')
    routine_id = str(uuid.uuid4()).upper()
    routine = {'id': routine_id, 'name': 'reading', 'domains': ['www.example.org', 'example.org'],
               'minutes': 30, 'createdAt': time.time() - reference}
    saved = send('save-routine', routine=routine)
    check(saved['policy']['routines'][0]['domains'] == ['example.org'], 'saving a routine normalizes its websites')
    routine = saved['policy']['routines'][0]
    routine.update(name='deep work', minutes=60)
    saved = send('save-routine', routine=routine)
    check(len(saved['policy']['routines']) == 1 and saved['policy']['routines'][0]['name'] == 'deep work',
          'editing replaces the same routine without duplicates')
    invalid = dict(routine, minutes=0)
    check(rpc('save-routine', routine=invalid).returncode != 0, 'service rejects invalid routine durations')
    check(send('status')['policy']['routines'][0]['minutes'] == 60, 'rejected edit preserves the saved routine')
    send('delete-routine', routineID=routine_id)
    check(not send('status')['policy']['routines'], 'routine deletion persists')
    imported = {key: routine[key] for key in ('id', 'name', 'domains', 'minutes')}
    synced = send('sync-routines', routineSync={'expected': [], 'desired': [imported]})
    check(synced['policy']['routines'][0]['id'] == routine_id, 'routine sync imports into the real service')
    check(rpc('sync-routines', routineSync={'expected': [], 'desired': []}).returncode != 0,
          'routine sync cannot overwrite a concurrent local edit')
    send('sync-routines', routineSync={'expected': [imported], 'desired': []})

    start = (datetime.now().astimezone() + timedelta(minutes=1)).replace(second=0, microsecond=0)
    if start.timestamp() - time.time() < 15:
        start += timedelta(minutes=1)
    schedule_id = str(uuid.uuid4()).upper()
    scheduled = {'id': schedule_id, 'name': 'scheduled focus', 'domains': ['scheduled.example', 'timed.example'],
                 'minutes': 1, 'createdAt': time.time() - reference,
                 'schedule': {'weekdays': [start.isoweekday() % 7 + 1],
                              'startMinute': start.hour * 60 + start.minute, 'enabled': True}}
    saved = send('save-routine', routine=scheduled)
    check(len(saved['policy']['routines']) == 1, 'weekly schedule is stored by the background service')
    template = {key: scheduled[key] for key in ('id', 'name', 'domains', 'minutes')}
    check(rpc('sync-routines', routineSync={'expected': [template], 'desired': []}).returncode != 0,
          'remote deletion cannot change an enabled local schedule')
    occurrence = start.timestamp() - reference
    skip_request = dict(routineID=schedule_id, scheduledStart=occurrence)
    check(rpc('skip-run', **dict(skip_request, scheduledStart=occurrence + 60)).returncode != 0,
          'service rejects a skip for the wrong occurrence')
    check(send('skip-run', **skip_request)['policy']['routines'][0]['skippedStart'] == occurrence,
          'the exact next occurrence can be skipped')
    check('skippedStart' not in send('restore-run', **skip_request)['policy']['routines'][0],
          'restoring the skipped occurrence makes it eligible again')
    skipped_id = str(uuid.uuid4()).upper()
    send('save-routine', routine=dict(scheduled, id=skipped_id, name='skip once', domains=['skipped.example']))
    send('skip-run', routineID=skipped_id, scheduledStart=occurrence)
    check(rpc('prepare-uninstall').returncode != 0, 'enabled schedules prevent accidental uninstall')
    manual = send('commit', domains=['scheduled.example'], minutes=1, name='manual focus')
    manual_block = next(item for item in manual['policy']['commitments'] if item.get('name') == 'manual focus')
    print('waiting for an actual scheduled start with no client running...', flush=True)
    while time.time() < start.timestamp() + 2:
        time.sleep(min(1, max(.01, start.timestamp() + 2 - time.time())))
    check('status: NXDOMAIN' in dns('timed.example'), 'schedule starts DNS blocking without an app or status request')
    running = send('status')
    check(not any(item.get('routineID') == skipped_id for item in running['policy']['commitments'])
          and not (state / 'resolver' / 'skipped.example').exists(), 'a skipped run leaves dns and history untouched')
    send('delete-routine', routineID=skipped_id)
    starts = [item for item in running['policy']['commitments'] if item.get('routineID') == schedule_id]
    check(len(starts) == 1 and starts[0]['name'] == 'scheduled focus', 'automatic session is recorded once with its routine name')
    check(abs(starts[0]['endsAt'] + reference - start.timestamp() - 60) < .01, 'scheduled end uses the intended window')
    preserved = next(item for item in running['policy']['commitments'] if item['id'] == manual_block['id'])
    check(preserved == manual_block, 'overlapping schedule leaves the manual commitment unchanged')
    old_pid = service_pid()
    subprocess.run(['launchctl', 'kill', 'SIGKILL', domain + '/' + label], check=True)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline and (service_pid() is None or service_pid() == old_pid): time.sleep(.1)
    restarted = send('status')
    check(len([item for item in restarted['policy']['commitments'] if item.get('routineID') == schedule_id]) == 1,
          'service restart preserves the session and does not start it twice')
    check('status: NXDOMAIN' in dns('timed.example'), 'scheduled DNS blocking survives service restart')
    updated = restarted['policy']['routines'][0]
    updated['schedule']['enabled'] = False
    paused = send('save-routine', routine=updated)
    check(not paused['policy']['routines'][0]['schedule']['enabled'], 'schedule can be turned off')
    check('status: NXDOMAIN' in dns('timed.example'), 'turning off future starts preserves the active block')
    send('delete-routine', routineID=schedule_id)
    check('status: NXDOMAIN' in dns('timed.example'), 'deleting a routine preserves its active block')
    end = starts[0]['endsAt'] + reference
    print('waiting for the actual scheduled session to finish...', flush=True)
    while time.time() < end + 2: time.sleep(min(1, max(.01, end + 2 - time.time())))
    finished = send('status')
    check(all(item['endsAt'] <= finished['now'] for item in finished['policy']['commitments']), 'all timed sessions finish')
    check(len(finished['policy']['commitments']) == 3, 'legacy, manual, and scheduled sessions remain in history')
    check(not (state / 'resolver' / 'timed.example').exists(), 'scheduled resolver is removed at expiry')
    check((state / 'hosts').read_text() == '127.0.0.1 localhost\n::1 localhost\n', 'sandbox hosts are restored after expiry')
    check(rpc('prepare-uninstall').returncode == 0, 'uninstall is allowed after schedules are off and blocks finish')
    long_block = dict(domains=['long.example'], minutes=1441)
    check(rpc('commit', **long_block).returncode != 0 and not (state / 'resolver' / 'long.example').exists(),
          'an unconfirmed long block never takes effect')
    confirmed = send('commit', **long_block, confirmedLongBlock=True)
    check(confirmed.get('enforcementError') is None and (state / 'resolver' / 'long.example').exists(),
          'the service installs the confirmed long-block resolver')
    check('status: NXDOMAIN' in dns('long.example'), 'a confirmed long block is enforced')
    check(hashlib.sha256(Path('/etc/hosts').read_bytes()).hexdigest() == before, 'real system hosts configuration is unchanged')
    report = {'result': 'passed', 'checks': checks, 'scope': 'real sandbox XPC, schedule clock, DNS, restart and history'}
    output = root / 'outputs/completion/routines-live.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'checks': len(checks), 'result': 'passed'}), flush=True)
except Exception:
    log = base / 'service.log'
    if log.exists(): print(log.read_text(), flush=True)
    print(f'service pid on failure: {service_pid()}', flush=True)
    raise
finally:
    subprocess.run(['launchctl', 'bootout', domain, str(plist)], capture_output=True)
    shutil.rmtree(base)
