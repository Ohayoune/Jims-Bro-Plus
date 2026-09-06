#!/usr/bin/env python3
"""Compile Core and execute the actual test bodies with portable assertion adapters.
No XCTest or Simulator is involved. Use xcodebuild for authoritative iOS checks.
Usage: python3 tools/check_core.py [--filter ImportTests]
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--filter', default='')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
build = root / 'build' / 'core-checks'
build.mkdir(parents=True, exist_ok=True)
sources = sorted((root / 'JimmsBro' / 'Core').glob('*.swift')) + sorted((root / 'JimmsBro' / 'Store').glob('*.swift'))
tests = sorted(p for p in (root / 'JimmsBroTests').glob('*.swift') if p.name != 'ProjectSkeletonTests.swift')
calls = []
for p in tests:
    text = p.read_text()
    cls = re.search(r'final class (\w+): XCTestCase', text)
    if not cls:
        continue
    for match in re.finditer(r'func (test\w+)\(\)\s*(async)?\s*(throws)?\s*\{', text):
        name = cls[1] + '.' + match[1]
        if args.filter and args.filter not in name:
            continue
        call = ('try ' if match[3] else '') + ('await ' if match[2] else '') + cls[1] + '().' + match[1] + '()'
        runner_fn = 'await CoreChecks.runAsync' if match[2] else 'CoreChecks.run'
        calls.append(f'{runner_fn}("{name}") {{ {call} }}')
if not calls:
    sys.exit('No test bodies matched; refusing an empty green run.')
runner = build / 'CoreCheckRunner.swift'
runner.write_text('@main struct CoreCheckRunner { static func main() async {\n' + '\n'.join(calls) + '\nCoreChecks.finish()\n} }\n')
env = os.environ.copy()
env.setdefault('DEVELOPER_DIR', '/Library/Developer/CommandLineTools')
env['JIMMSBRO_FIXTURE_ROOT'] = str(root)
cache = build / 'module-cache'
command = ['swiftc', '-swift-version', '5', '-Onone', '-g', '-D', 'CORE_CHECKS', '-module-cache-path', str(cache), '-o', str(build / 'CoreChecks')]
command += [str(p) for p in sources + tests] + [str(root / 'tools' / 'CoreCheckSupport.swift'), str(runner)]
compiled = subprocess.run(command, env=env, cwd=root)
if compiled.returncode:
    sys.exit(compiled.returncode)
sys.exit(subprocess.run([str(build / 'CoreChecks')], env=env, cwd=root).returncode)
