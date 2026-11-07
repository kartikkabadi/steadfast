#!/usr/bin/env python3
"""Run the real installer against disposable paths and simulated system tools."""
import os
import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).with_name('Install.command').read_text()
PLIST = SOURCE.split("<<'PLIST'\n", 1)[1].split('\nPLIST\n', 1)[0] + '\n'

MOCK = r'''#!/usr/bin/env python3
import json, os, pathlib, shutil, subprocess, sys
root = pathlib.Path(os.environ['FIXTURE'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
if name == 'codesign':
    if '-dv' in args:
        print('Signature=certificate', file=sys.stderr)
        print('CDHash=' + os.environ.get('CDHASH', 'a' * 40), file=sys.stderr)
    elif '-d' in args:
        print('designated => pin-new', file=sys.stderr)
    elif '-R' in args:
        requirement = args[args.index('-R') + 1]
        if not requirement.startswith('=') and not pathlib.Path(requirement).is_file():
            sys.exit('invalid requirement specification')
        if os.environ.get('INCOMPATIBLE') == '1': sys.exit(1)
elif name == 'launchctl':
    with (root / 'calls').open('a') as output: output.write(' '.join(args) + '\n')
    loaded = root / 'loaded'
    if args[0] == 'print': sys.exit(0 if loaded.exists() else 1)
    if args[0] == 'bootout': loaded.unlink(missing_ok=True)
    if args[0] == 'bootstrap':
        if os.environ.get('FAIL_BOOTSTRAP') == '1' and not (root / 'failed').exists():
            (root / 'failed').touch(); sys.exit(1)
        loaded.touch()
elif name == 'install':
    mode = int(args[args.index('-m') + 1], 8)
    shutil.copyfile(args[-2], args[-1]); os.chmod(args[-1], mode)
elif name == 'plutil':
    data = json.loads(pathlib.Path(args[-1]).read_text())
    key = args[args.index('-extract') + 1]
    if key not in data: sys.exit(1)
    print(str(data[key]).lower())
'''


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='steadfast-installer-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.tools = self.root / 'tools'
        self.tools.mkdir()
        for name in ['codesign', 'launchctl', 'install', 'plutil']:
            path = self.tools / name
            path.write_text(MOCK)
            path.chmod(0o755)
        self.state = self.root / 'Library/Application Support/Steadfast'
        self.state.mkdir(parents=True)
        self.policy = self.state / 'policy.json'
        self.policy.write_bytes(b'active policy must remain byte-for-byte unchanged\n')
        self.pin = self.state / 'client.requirement'
        self.pin.write_text('pin-old\n')
        self.runtime_pin = self.state / 'client.runtime-requirement'
        self.runtime_pin.write_text('cdhash H"' + 'a' * 40 + '"\n')
        self.helper = self.root / 'Library/PrivilegedHelperTools/dev.local.steadfastd'
        self.helper.parent.mkdir()
        self.helper.write_text('old helper')
        self.plist = self.root / 'Library/LaunchDaemons/dev.local.steadfast.service.plist'
        self.plist.parent.mkdir()
        self.expected_plist = PLIST.replace('/Library', str(self.root / 'Library'))
        self.plist.write_text(self.expected_plist)
        self.dest = self.root / 'Applications/Steadfast.app'
        self.make_app(self.dest, 'old helper', 'old app')
        (self.root / 'loaded').touch()
        self.distribution = self.root / 'distribution'
        self.make_app(self.distribution / 'Steadfast.app', 'new helper', 'new app')
        script = SOURCE.replace('@RELEASE_CERT@', 'b' * 40).replace('if [[ $EUID -ne 0 ]]; then', 'if false; then')
        script = script.replace('/Applications', str(self.root / 'Applications'))
        script = script.replace('/Library', str(self.root / 'Library'))
        for name, original in [('codesign', '/usr/bin/codesign'), ('launchctl', '/bin/launchctl'), ('install', '/usr/bin/install'), ('plutil', '/usr/bin/plutil')]:
            script = script.replace(original, str(self.tools / name))
        script = script.replace('/usr/sbin/chown', '/usr/bin/true')
        script = script.replace('/bin/sleep', '/usr/bin/true')
        self.script = self.distribution / 'Install.command'
        self.script.write_text(script)

    def make_app(self, path, helper, version):
        (path / 'Contents/Resources').mkdir(parents=True)
        (path / 'Contents/Resources/steadfastd').write_text(helper)
        (path / 'Contents/MacOS').mkdir()
        binary = path / 'Contents/MacOS/Steadfast'
        binary.write_text('#!/bin/bash\nif [[ "${HEALTH_ERROR:-0}" == 1 ]]; then echo \'{"sandbox":false,"enforcementError":"failed"}\'; else echo \'{"sandbox":false}\'; fi\n')
        binary.chmod(0o755)
        (path / 'version').write_text(version)

    def run_installer(self, **environment):
        env = dict(os.environ, FIXTURE=str(self.root), SUDO_UID='0', **environment)
        # Leave enough time for all simulated health retries and rollback.
        return subprocess.run(['/bin/bash', str(self.script)], env=env, text=True, capture_output=True, timeout=90)

    def assert_preserved(self):
        self.assertEqual(self.policy.read_bytes(), b'active policy must remain byte-for-byte unchanged\n')
        self.assertEqual(self.pin.read_text(), 'pin-old\n')

    def test_on_demand_job_restarts_failures_and_keeps_mach_endpoint(self):
        job = plistlib.loads(PLIST.encode())
        self.assertEqual(job['KeepAlive'], {'SuccessfulExit': False})
        self.assertTrue(job['RunAtLoad'])
        self.assertTrue(job['MachServices']['dev.local.steadfast.service'])
        self.assertEqual(job['ProcessType'], 'Adaptive')

    def test_signed_upgrade_preserves_policy_and_pin(self):
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_preserved()
        self.assertEqual(self.helper.read_text(), 'new helper')
        self.assertEqual((self.dest / 'version').read_text(), 'new app')
        self.assertTrue((self.root / 'loaded').exists())
        self.assertEqual(self.runtime_pin.read_text(), 'cdhash H"' + 'a' * 40 + '"\n')

    def test_new_app_hash_restarts_unchanged_helper(self):
        (self.distribution / 'Steadfast.app/Contents/Resources/steadfastd').write_text('old helper')
        result = self.run_installer(CDHASH='b' * 40)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_preserved()
        self.assertIn('bootstrap', (self.root / 'calls').read_text())
        self.assertEqual(self.runtime_pin.read_text(), 'cdhash H"' + 'b' * 40 + '"\n')

    def test_invalid_hash_leaves_installation_untouched(self):
        result = self.run_installer(CDHASH='invalid')
        self.assertNotEqual(result.returncode, 0)
        self.assert_preserved()
        self.assertEqual((self.dest / 'version').read_text(), 'old app')
        self.assertFalse((self.root / 'calls').exists())

    def test_failed_migration_restores_absent_runtime_pin(self):
        self.runtime_pin.unlink()
        result = self.run_installer(HEALTH_ERROR='1')
        self.assertNotEqual(result.returncode, 0)
        self.assert_preserved()
        self.assertFalse(self.runtime_pin.exists())
        self.assertEqual((self.dest / 'version').read_text(), 'old app')
        self.assertTrue((self.root / 'loaded').exists())

    def test_unchanged_helper_does_not_restart_service(self):
        (self.distribution / 'Steadfast.app/Contents/Resources/steadfastd').write_text('old helper')
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = (self.root / 'calls').read_text()
        self.assertNotIn('bootout', calls)
        self.assertNotIn('bootstrap', calls)
        self.assert_preserved()

    def test_signer_mismatch_leaves_installation_untouched(self):
        result = self.run_installer(INCOMPATIBLE='1')
        self.assertNotEqual(result.returncode, 0)
        self.assert_preserved()
        self.assertEqual(self.helper.read_text(), 'old helper')
        self.assertEqual((self.dest / 'version').read_text(), 'old app')
        self.assertFalse((self.root / 'calls').exists())

    def test_failed_start_restores_previous_installation_and_job(self):
        result = self.run_installer(FAIL_BOOTSTRAP='1')
        self.assertNotEqual(result.returncode, 0)
        self.assert_preserved()
        self.assertEqual(self.helper.read_text(), 'old helper')
        self.assertEqual(self.plist.read_text(), self.expected_plist)
        self.assertEqual((self.dest / 'version').read_text(), 'old app')
        self.assertTrue((self.root / 'loaded').exists())
        self.assertIn('restoring the previous installation', result.stderr)

    def test_unhealthy_upgrade_restores_previous_installation_and_job(self):
        result = self.run_installer(HEALTH_ERROR='1', CDHASH='b' * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assert_preserved()
        self.assertEqual(self.helper.read_text(), 'old helper')
        self.assertEqual(self.plist.read_text(), self.expected_plist)
        self.assertEqual((self.dest / 'version').read_text(), 'old app')
        self.assertTrue((self.root / 'loaded').exists())
        self.assertEqual(self.runtime_pin.read_text(), 'cdhash H"' + 'a' * 40 + '"\n')

    def test_missing_pin_does_not_replace_an_existing_policy(self):
        self.pin.unlink()
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.policy.read_bytes(), b'active policy must remain byte-for-byte unchanged\n')
        self.assertEqual(self.helper.read_text(), 'old helper')
        self.assertFalse((self.root / 'calls').exists())


if __name__ == '__main__':
    unittest.main()
