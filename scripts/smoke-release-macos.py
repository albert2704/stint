#!/usr/bin/env python3
"""Check release bootstrap on a disposable GitHub Mac, never a user's profile."""
import os
import pathlib
import plistlib
import subprocess
import sys
import time

if os.environ.get('GITHUB_ACTIONS') != 'true' or not os.environ.get('RUNNER_TEMP'):
    raise SystemExit('Release bootstrap checks run only on disposable GitHub runners.')
app = pathlib.Path(sys.argv[1]).resolve()
log = pathlib.Path(sys.argv[2])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
bundle_id = info['CFBundleIdentifier']
support = pathlib.Path.home() / 'Library/Containers' / bundle_id / 'Data/Library/Application Support/Stint'
if support.exists():
    raise SystemExit('Expected a clean CI profile; the Stint data folder already exists.')
with log.open('w') as output:
    process = subprocess.Popen([str(app / 'Contents/MacOS' / info['CFBundleExecutable'])], stdout=output, stderr=subprocess.STDOUT)
    try:
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError(f'Stint exited during launch with code {process.returncode}.')
            if support.is_dir():
                break
            time.sleep(0.5)
        else:
            raise RuntimeError('Flutter/native bootstrap did not create the sandbox data directory.')
        time.sleep(3)
        if process.poll() is not None:
            raise RuntimeError(f'Stint exited after bootstrap with code {process.returncode}.')
        print('Release process remained alive and Flutter/native bootstrap created its sandbox data directory.')
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
print(log.read_text())
