#!/usr/bin/env python3
"""Measure actual model validation and core work. Build release first."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
binaries = Path(subprocess.check_output(['swift', 'build', '--package-path', str(root), '-c', 'release', '--show-bin-path'], text=True).strip())
with tempfile.TemporaryDirectory(prefix='steadfast-latency-') as directory:
    executable = Path(directory) / 'benchmark'
    model_sources = [str(path) for path in sorted((root / 'Sources/SteadfastApp').glob('*.swift')) if path.name != 'main.swift']
    subprocess.run(['swiftc', '-O', '-parse-as-library', '-default-isolation', 'MainActor', '-I', str(binaries), *model_sources, str(root / 'scripts/benchmark-latency.swift'), str(binaries / 'SteadfastCore.o'), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
