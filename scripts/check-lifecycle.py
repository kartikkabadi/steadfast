#!/usr/bin/env python3
"""Close the packaged app's window and check that its menu bar control remains."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = r'''
import AppKit
import ApplicationServices

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return value
}
func windows(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
}
func until(_ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(8)
    repeat {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return false
}

guard AXIsProcessTrusted() else {
    fputs("the native lifecycle check requires accessibility access\n", stderr)
    exit(2)
}
let pid = Int32(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
guard until({ !windows(app).isEmpty && attribute(app, kAXExtrasMenuBarAttribute) != nil }),
      let window = windows(app).first,
      let button = attribute(window, kAXCloseButtonAttribute) else { exit(3) }
guard AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success,
      until({ windows(app).isEmpty }), kill(pid, 0) == 0,
      attribute(app, kAXExtrasMenuBarAttribute) != nil else { exit(4) }
'''

with tempfile.TemporaryDirectory(prefix='steadfast-lifecycle-') as directory:
    temp = Path(directory)
    fixture = temp / 'check.swift'
    fixture.write_text(source)
    checker = temp / 'check'
    subprocess.run(['swiftc', str(fixture), '-o', str(checker)], check=True)
    app = temp / 'Steadfast.app'
    shutil.copytree(root / 'dist/Steadfast.app', app)
    info = app / 'Contents/Info.plist'
    metadata = plistlib.loads(info.read_bytes())
    metadata['CFBundleIdentifier'] = 'dev.local.steadfast.lifecycle-check'
    info.write_bytes(plistlib.dumps(metadata))
    subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
    env = dict(os.environ, STEADFAST_TEST_SERVICE='dev.local.steadfast.test.lifecycle')
    process = subprocess.Popen([app / 'Contents/MacOS/Steadfast'], env=env)
    try:
        subprocess.run([checker, str(process.pid)], check=True, timeout=20)
        print('pass: the native window closes and the app and menu bar control stay available')
    finally:
        if process.poll() is None:
            process.terminate()
        process.wait(timeout=10)
