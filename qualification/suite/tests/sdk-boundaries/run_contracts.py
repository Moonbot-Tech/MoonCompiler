"""Portable SDK/source regression runner; privileged exhaustion is an explicit opt-in."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--compiler', type=Path, required=True)
parser.add_argument('--source', type=Path, required=True, help='MoonCompiler source root for exact CPU body fixtures')
parser.add_argument('--mormot', type=Path, required=True)
parser.add_argument('--socket-tree', type=Path, help='Optional selected socket source tree, containing net/')
parser.add_argument('--runtime', type=Path, help='Optional runtime/mormot source override')
parser.add_argument('--classes', type=Path, help='Optional rebuilt Classes PPU directory before full SDK integration')
parser.add_argument('--static', type=Path, help='Optional native object directory')
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--modes', nargs='+', choices=['debug', 'o2', 'release'], default=['debug', 'o2', 'release'])
parser.add_argument('--exhaustion', action='store_true', help='Linux only: use sudo -n unshare --net')
args = parser.parse_args()
if os.name == "nt":
    import ctypes
    ctypes.windll.kernel32.SetErrorMode(3)
args.out.mkdir(parents=True, exist_ok=False)
socket_tree = args.socket_tree or args.mormot
generated = args.out / 'generated'
subprocess.run([sys.executable, HERE / 'prepare_cpu_fixture.py', args.source, generated], check=True)
subprocess.run([sys.executable, HERE / 'prepare_connect_fixture.py', socket_tree, generated], check=True)
target = 'x86_64-win64' if os.name == 'nt' else 'x86_64-linux'
native = ['-Fu' + str(socket_tree / 'net'), '-Fu' + str(args.mormot / '*'),
          '-Fi' + str(args.mormot / 'net'), '-Fi' + str(args.mormot),
          '-Fl' + str(args.static or args.mormot / 'static' / target)]
if args.runtime:
    native.insert(0, '-Fu' + str(args.runtime))
base = ['-Fu' + str(args.classes)] if args.classes else []
results = []

def run(command, log, timeout):
    completed = subprocess.run([str(item) for item in command], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, encoding='utf-8', errors='replace', timeout=timeout)
    log.write_text(completed.stdout, encoding='utf-8')
    return completed

def case(name, mode, marker, flags=(), fixture=None):
    directory = args.out / name / mode
    units = directory / 'units'
    units.mkdir(parents=True)
    mode_flags = {'debug': [], 'o2': ['-O2'], 'release': ['-dRELEASE']}[mode]
    source = HERE / (name + '.dpr')
    build = run([args.compiler, *flags, '-FE' + str(directory), '-FU' + str(units), *mode_flags, source],
                directory / 'build.log', 180)
    if build.returncode:
        results.append(dict(name=name, mode=mode, passed=False, build=build.returncode))
        return
    executable = directory / (name + ('.exe' if os.name == 'nt' else ''))
    command = [executable] if fixture is None else [*fixture, executable]
    execution = run(command, directory / 'run.log', 30)
    results.append(dict(name=name, mode=mode, passed=execution.returncode == 0 and marker in execution.stdout,
                        exit=execution.returncode, output=execution.stdout))

for mode in args.modes:
    case('cpu_fixture_contract', mode, 'CPU_FIXTURE_CONTRACT checks=67 failures=0', ['-Fi' + str(generated)])
    case('connect_fixture_contract', mode, 'CONNECT_FIXTURE_CONTRACT checks=35 failures=0', ['-Fi' + str(generated)])
    if os.name == 'nt':
        case('current_thread_handle_contract', mode, 'CURRENT_THREAD_HANDLE_CONTRACT_PASS', base)
    case('socket_connect_native_immediate', mode, 'SOCKET_CONNECT_NATIVE_IMMEDIATE_PASS', native)
    case('http_connect_contract', mode, 'HTTP_CONNECT_CONTRACT_PASS', native,
         [sys.executable, HERE / 'check_http_connect.py'])
    if os.name != 'nt':
        case('RtlSystemCpuTimes', mode, 'SYSTEM_CPU_PASS', base)
    if args.exhaustion:
        if os.name == 'nt':
            raise SystemExit('--exhaustion requires Linux')
        case('http_port_exhaustion_contract', mode, 'PORT_EXHAUSTION_RECOVERED', native,
             ['sudo', '-n', 'unshare', '--net', sys.executable, HERE / 'check_port_exhaustion.py'])

report = dict(
    provenance={
        'compiler': str(args.compiler),
        'compiler_sha256': hashlib.sha256(args.compiler.read_bytes()).hexdigest(),
        'source': str(args.source), 'mormot': str(args.mormot), 'socket_tree': str(socket_tree),
        'socket_sha256': hashlib.sha256((socket_tree / 'net/mormot.net.sock.pas').read_bytes()).hexdigest(),
        'exhaustion': args.exhaustion,
    }, results=results)
(args.out / 'results.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
for item in results:
    print(item['name'], item['mode'], 'PASS' if item['passed'] else 'FAIL')
if not all(item['passed'] for item in results):
    raise SystemExit(1)
print('SDK_CONTRACTS_PASS', len(results))
