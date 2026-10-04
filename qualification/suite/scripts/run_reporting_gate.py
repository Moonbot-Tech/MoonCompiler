#!/usr/bin/env python3
"""Compile isolated diagnostic tests and check actual reports, not just exit codes.

The compiler and --rtl must belong to the same freshly rebuilt MoonCompiler.
The result directory must not exist. Nothing is deleted or rewritten in a checkout.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import time
import threading
import ssl
import zipfile
from email import policy
from email.parser import BytesParser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# An exception nobody handles ends the program as in Delphi: the handler of
# SysUtils reports it and halts with 1.  A program without SysUtils ends with
# System's runtime error 217; with the product runtime there is none, the
# compiler adds the monitor unit (fpwinmonitor/fpmonitor) and SysUtils with it
# to every program.  The exit code 1 is also what a test's own Halt(1) gives,
# so every such case checks the report of its exception too.
UNHANDLED_EXIT = 1
UNHANDLED_EXIT_WITHOUT_SYSUTILS = 217


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--rtl', type=Path, required=True)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--results', type=Path, required=True)
    parser.add_argument('--option', action='append', default=[])
    parser.add_argument('--jobs', type=int, default=1, help='parallel independent correctness cases')
    parser.add_argument('--product-mm', action='store_true', help='use bundled product MM and automatic runtime prefix')
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    root = args.root.resolve()
    out = args.results.resolve()
    out.mkdir(parents=True, exist_ok=False)
    compiler = args.compiler.resolve()
    results = []
    link_options = []
    if os.name != 'nt':
        gcc_lib = subprocess.check_output(['gcc', '-print-file-name=libgcc_s.so'], text=True).strip()
        if not Path(gcc_lib).is_file():
            raise RuntimeError('GCC libgcc_s development linker input is missing')
        link_options.append(f'-Fl{Path(gcc_lib).parent}')
    # the installed RTL and every installed package of the same toolchain, as
    # the toolchain's configuration names them (units/<target>/*): --rtl
    # names the rtl directory, its siblings are the packages.  Not a list of
    # the packages these tests happen to need today - MoonORMot compresses
    # through System.ZLib (vcl-compat) under this compiler, and a hand list
    # of packages misses whatever the next dependency is.
    rtl = args.rtl.resolve()
    packages = [f'-Fu{p}' for p in sorted(p for p in rtl.parent.iterdir() if p.is_dir() and p != rtl)]

    def run(command, directory, logfile, expected=0, env=None):
        p = subprocess.run([str(x) for x in command], cwd=directory, capture_output=True, timeout=90, env=env)
        text = (p.stdout + p.stderr).decode('utf-8', errors='replace')
        logfile.write_text(text, encoding='utf-8')
        if p.returncode != expected:
            raise AssertionError(f'{command}: exit {p.returncode}, expected {expected}; {logfile}\n{text[-1800:]}')
        return text

    def compile_source(source, dest, opt, defines=()):
        dest.mkdir()
        mormot = root / '.qualification/deps/moonormot'
        mormot_src = mormot
        # runtime/mormot: MoonORMot.Need, the version floor the Moon.Diagnostics
        # units name in their uses (it lives with the other units over mORMot)
        command = [compiler, '-n', '-B', f'-Fu{rtl}', f'-Fu{root / "runtime/reporting"}',
                   f'-Fu{root / "runtime/mormot"}',
                   *[f'-Fu{mormot / name}' for name in ('core', 'net', 'lib', 'crypt')],
                   f'-Fo{mormot_src}', f'-Fi{mormot_src}',
                   f'-Fl{mormot / "static" / ("x86_64-win64" if os.name == "nt" else "x86_64-linux")}',
                   *packages,
                   f'-Fu{root / "qualification/suite/tests/smoke"}',
                   f'-FU{dest}', f'-FE{dest}', '-dMOONCOMPILER_UNICODE_DEFAULT',
                   '-gl', '-gw3', '-Xs-', '-Xg-', f'-{opt}',
                   *link_options,
                   *(['-dMOONBOT_MM_PROFILE_REQUIRED', '-dFPCMM_BOOSTER', '-dFPCMM_MOONSHARD', '-dNOPATCHRTL',
                      f'--pinned-unit=mormot.core.fpcx64mm={root / "runtime/mm/mormot.core.fpcx64mm.pas"}']
                     if args.product_mm else ['-dMOONCOMPILER_VANILLA_RUNTIME']), *args.option,
                   *[f'-d{define}' for define in defines], root / 'qualification/suite/tests/smoke' / source]
        run(command, dest, dest / 'compile.log')
        return dest / (Path(source).stem + ('.exe' if os.name == 'nt' else ''))

    def openssl_command():
        executable = shutil.which('openssl')
        if executable:
            return executable
        if os.name == 'nt':
            git = shutil.which('git')
            if git:
                bundled = Path(git).resolve().parents[1] / 'mingw64/bin/openssl.exe'
                if bundled.is_file():
                    return bundled
        raise RuntimeError('OpenSSL command is required to create the reporting-gate test certificate')

    def delivery_checks(opt, rows):
        requests = []
        response_outcomes = []
        both_posts = threading.Barrier(2)

        class Receiver(BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.1'

            def log_message(self, *_):
                pass

            def do_POST(self):
                body = self.rfile.read(int(self.headers['Content-Length']))
                message = BytesParser(policy=policy.default).parsebytes(
                    b'Content-Type: ' + self.headers['Content-Type'].encode() + b'\r\n\r\n' + body)
                parts = list(message.iter_parts())
                requests.append((self.path, parts))
                if self.path == '/concurrent':
                    both_posts.wait(timeout=8)  # network I/O must not hold the report lock
                if self.path == '/timeout':
                    time.sleep(0.6)
                status = 500 if self.path == '/reject' else (302 if self.path == '/redirect' else 200)
                reply = b'<EurekaLogStatus>0</EurekaLogStatus>'
                if self.path == '/bad-ack':
                    reply = b'<EurekaLogStatus>-1</EurekaLogStatus>'
                if self.path == '/huge-reply':
                    reply = b'x' * 70000
                self.send_response(status)
                self.send_header('Content-Length', str(len(reply)))
                self.send_header('Location', '/must-not-follow')
                self.send_header('Connection', 'close')
                self.end_headers()
                try:
                    self.wfile.write(reply)
                    response_outcomes.append((self.path, 'sent'))
                except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError) as error:
                    response_outcomes.append((self.path, type(error).__name__))

        executable = compile_source('diagnostic_delivery.pas', out / f'delivery-{opt}', opt,
                                    ['MOON_DIAGNOSTICS_TEST'])
        attachment = out / f'delivery-{opt}-attachment.bin'
        attachment.write_bytes(bytes(range(256)) * 4096)
        random_attachment = out / f'delivery-{opt}-random.bin'
        random_attachment.write_bytes(os.urandom(1024 * 1024))
        server = ThreadingHTTPServer(('127.0.0.1', 0), Receiver)
        # Reuse the repository's published test key; do not generate credentials.
        key = root / 'packages/fcl-hash/tests/private-key.pem'
        certificate = out / f'delivery-{opt}-certificate.pem'
        run([openssl_command(), 'req', '-x509', '-new', '-key', key, '-out', certificate,
             '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
            out, out / f'delivery-{opt}-certificate.log')
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(certificate, key)
        tls_server = ThreadingHTTPServer(('127.0.0.1', 0), Receiver)
        tls_server.socket = tls.wrap_socket(tls_server.socket, server_side=True)
        tls_thread = threading.Thread(target=tls_server.serve_forever, daemon=True)
        tls_thread.start()
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            modes = ('saved-only', 'handled', 'caught', 'manual', 'unhandled', 'unsafe-name', 'long-name',
                     'name-error', 'reject', 'redirect', 'bad-ack', 'timeout', 'huge-reply', 'concurrent',
                     'write-failure', 'custom-field', 'default-path', 'untrusted-tls',
                     'zip-failure', 'zip-failure-after-write', 'zip-collision', 'zip-partial-write', 'zip-random')
            if os.name != 'nt':
                modes += ('trusted-tls',)
            for mode in modes:
                directory = out / f'delivery-{opt}-{mode}'
                directory.mkdir()
                exe = directory / executable.name
                shutil.copy2(executable, exe)
                destination = directory / ('BugReports' if mode == 'default-path' else 'reports')
                before = len(requests)
                responses_before = len(response_outcomes)
                url = f'http://127.0.0.1:{server.server_port}/{mode}'
                if mode == 'saved-only':
                    url = '-'
                if mode in ('untrusted-tls', 'trusted-tls'):
                    url = f'https://127.0.0.1:{tls_server.server_port}/{mode}'
                # Trust only this fixture in this child process. No machine trust
                # store change and no bypass of mORMot's certificate verification.
                env = dict(os.environ, SSL_CERT_FILE=str(certificate)) if mode == 'trusted-tls' else None
                ack = '-' if mode == 'custom-field' else '<EurekaLogStatus>0</EurekaLogStatus>'
                data_file = random_attachment if mode in ('zip-random', 'zip-failure-after-write') else attachment
                started = time.perf_counter()
                stdout = run([exe, mode, '-' if mode == 'default-path' else destination, url,
                              150 if mode == 'timeout' else 5000, ack, data_file,
                              'my_report' if mode == 'custom-field' else '-'], directory,
                             directory / 'run.log', UNHANDLED_EXIT if mode == 'unhandled' else 0, env=env)
                elapsed = time.perf_counter() - started
                reports = list(destination.glob('*.txt'))
                expected = 0 if mode == 'handled' else (2 if mode == 'concurrent' else 1)
                assert len(reports) == expected, (mode, reports)
                observed = requests[before:]
                packing_failed = mode in ('zip-failure', 'zip-failure-after-write', 'zip-collision')
                expected_posts = 0 if packing_failed or mode in (
                    'saved-only', 'handled', 'write-failure', 'untrusted-tls') else expected
                assert len(observed) == expected_posts, (mode, len(observed), expected_posts)
                for path, parts in observed:
                    assert path == '/' + mode and len(parts) == 1
                    part = parts[0]
                    assert part.get_param('name', header='Content-Disposition') == (
                        'my_report' if mode == 'custom-field' else 'el_upload_file_0')
                    archive = destination / part.get_filename()
                    assert archive.suffix == '.zip' and part.get_content_type() == 'application/zip'
                    report = archive.with_suffix('.txt')
                    assert report in reports, (mode, part.get_filename(), reports)
                    assert part.get_payload(decode=True) == archive.read_bytes(), 'uploaded bytes differ from closed ZIP'
                for report in reports:
                    text = report.read_text(encoding='utf-8')
                    if mode != 'write-failure':
                        assert text.endswith('MOON_DIAGNOSTIC_END\n')
                        assert data_file.read_bytes().hex().upper() in text.replace('\n', '')
                    archive = report.with_suffix('.zip')
                    if mode == 'zip-collision':
                        assert archive.read_bytes() == b'*', 'existing ZIP overwritten or deleted'
                    elif packing_failed or mode in ('saved-only', 'write-failure'):
                        assert not archive.exists(), 'incomplete archive left behind'
                    else:
                        with zipfile.ZipFile(archive) as packed:
                            assert packed.namelist() == ['report.txt']
                            assert packed.read('report.txt') == report.read_bytes(), 'ZIP content/CRC mismatch'
                            assert packed.getinfo('report.txt').compress_type == zipfile.ZIP_DEFLATED
                        assert archive.stat().st_size < report.stat().st_size, 'report was not compressed'
                        if os.name != 'nt':
                            assert archive.stat().st_mode & 0o777 == 0o600
                    if mode not in ('unsafe-name', 'long-name', 'name-error'):
                        assert report.name.startswith('Бот → [U_42]' + ('_XR' if mode == 'manual' else '') + '_V123-')
                    if mode == 'unsafe-name':
                        assert not any(c in report.name for c in '<>:"/\\|?*\n')
                    if mode == 'long-name':
                        assert len(report.name.encode()) <= 255
                    if mode == 'name-error':
                        assert report.name.startswith('report-') and 'filename_error=' in text
                    delivery = report.with_name(report.name + '.delivery')
                    if mode in ('saved-only', 'write-failure'):
                        assert not delivery.exists()
                    else:
                        state = delivery.read_text(encoding='utf-8')
                        sent = not packing_failed and mode not in (
                            'reject', 'redirect', 'bad-ack', 'timeout', 'huge-reply', 'untrusted-tls')
                        assert f'sent={sent}\n' in state, (
                            mode, state, response_outcomes[responses_before:])
                        if mode == 'untrusted-tls' and os.name == 'nt':
                            assert '80090325' in state, 'failure was not SChannel untrusted-root rejection'
                        assert 'http://' not in state and '<EurekaLogStatus>' not in state
                if mode == 'timeout':
                    assert elapsed < 3, ('timeout not bounded', elapsed)
                if mode == 'unhandled':
                    assert 'An unhandled exception occurred' in stdout
                    assert 'delivery original exception' in stdout
                else:
                    assert 'DIAGNOSTIC_DELIVERY_PASS' in stdout
                rows.append({'optimization': opt, 'case': f'delivery-{mode}', 'reports': expected})
                print(f'PASS {opt} delivery-{mode}', flush=True)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            tls_server.shutdown()
            tls_server.server_close()
            tls_thread.join()

    def profile_checks(opt):
        rows = []
        executable = compile_source('diagnostic_reports.pas', out / opt, opt)
        # Only executable + test attachment enter the deployment directory.
        # There is no adjacent map/debug file, source or PPU to rescue symbol lookup.
        deploy = out / f'{opt}-standalone'
        deploy.mkdir()
        exe = deploy / executable.name
        shutil.copy2(executable, exe)
        attachment = deploy / 'application-data.bin'
        attachment.write_bytes(bytes(range(256)))
        modes = ['caught', 'worker', 'manual', 'busy-main', 'hardware', 'unhandled',
                 'deep', 'reusable', 'concurrent', 'report-failure', 'software-external']
        if os.name != 'nt':
            modes.extend(['blocked', 'native-thread'])
        for mode in modes:
            destination = deploy / mode
            started = time.perf_counter()
            stdout = run([exe, mode, destination, '0', attachment], deploy, deploy / f'{mode}.log',
                         UNHANDLED_EXIT if mode == 'unhandled' else 0)
            elapsed = time.perf_counter() - started
            reports = sorted(destination.glob('*.txt'))
            expected_reports = 8 if mode == 'concurrent' else (2 if mode in ('caught', 'report-failure') else 1)
            assert len(reports) == expected_reports, (opt, mode, reports)
            contents = [f.read_text(encoding='utf-8') for f in reports]
            if mode == 'report-failure':
                assert all(c.endswith('MOON_DIAGNOSTIC_END\n') for c in contents)
                failed = [c for c in contents if 'title=callback failure retained' in c]
                assert len(failed) == 1 and 'complete=False' in failed[0]
                assert 'application_data_error=' in failed[0] and 'pc[$' in failed[0]
                contents = [c for c in contents if 'title=next report works' in c]
                assert len(contents) == 1
            for text in contents:
                assert text.startswith('MOON_DIAGNOSTIC_REPORT 1\n'), (opt, mode)
                assert text.endswith('MOON_DIAGNOSTIC_END\n'), (opt, mode)
                assert 'application_version=diagnostic-test-1\n' in text
                assert re.search(r'^os=.+$', text, re.M)
                assert re.search(r'^uptime_ms_since_init=\d+$', text, re.M)
                assert 'custom=Диагностика → ✓' in text, (opt, mode)
                assert bytes(range(256)).hex().upper() in text, (opt, mode, 'attachment')
                if mode == 'blocked':
                    assert 'complete=False' in text and 'unavailable or exited' in text
                else:
                    assert 'complete=True' in text and 'unavailable or exited' not in text, (opt, mode, text[:600])
                    assert not re.search(r'unwind_status=[^0]', text), (opt, mode)
                if mode in ('manual', 'busy-main', 'blocked', 'native-thread', 'report-failure'):
                    minimum_threads = 1 if mode == 'report-failure' else 2
                    assert len(re.findall(r'^\[thread ', text, re.M)) >= minimum_threads, (opt, mode)
                    assert 'RAX=' not in text, (opt, mode, 'manual registers are unnecessary')
                else:
                    assert 'exception_message=' in text and 'RIP=$' in text, (opt, mode)
            text = '\n'.join(contents)
            if mode == 'caught':
                # O3 legitimately inlines both tiny wrappers into RunCaught.
                assert any(f' {name} ' in text for name in ('OriginLeaf', 'OriginParent', 'RunCaught'))
                assert 'original error → 42' in text
                pcs = [re.findall(r'^pc\[(.+)\]', c, re.M) for c in contents]
                assert pcs[0] == pcs[1], 'acquired/reraised context changed'
            if mode == 'manual':
                assert 'WorkerSpinLeaf' in text, 'sleeping worker callers were lost'
            if mode == 'busy-main':
                assert 'MainBusyLeaf' in text, 'hung main not sampled'
            if mode == 'hardware':
                assert 'HardwareLeaf' in text and 'hardware=True' in text
                assert 'EF CD AB 89 67 45 23 01' in text, 'original stack sentinel not captured'
            if mode == 'software-external':
                assert 'hardware=False' in text, 'exception class is not proof of a hardware fault'
            if mode in ('deep', 'reusable'):
                assert text.count(' DeepRaise ') >= 40, 'deep caller chain truncated'
            if mode == 'native-thread':
                assert 'NativeWorker' in text, 'native pthread was not captured'
            if mode != 'unhandled':
                assert f'DIAGNOSTICS_TEST_PASS {mode}' in stdout
            else:
                assert 'An unhandled exception occurred' in stdout and 'original error' in stdout, (opt, stdout)
            rows.append({'optimization': opt, 'case': mode, 'reports': len(reports), 'seconds': elapsed})
            print(f'PASS {opt} {mode}', flush=True)

        executable = compile_source('diagnostic_resilience.pas', out / f'resilience-{opt}', opt,
                                    ['MOON_DIAGNOSTICS_TEST'])
        for mode in ('symbols', 'partial-write', 'write-failure', 'close-failure', 'missing-attachment',
                     'reentry', 'unhandled-write-failure'):
            destination = out / f'resilience-{opt}-{mode}'
            expected_exit = UNHANDLED_EXIT if mode == 'unhandled-write-failure' else 0
            stdout = run([executable, mode, destination], out, out / f'resilience-{opt}-{mode}.log', expected_exit)
            reports = sorted(destination.glob('*.txt'))
            write_failure = mode in ('write-failure', 'close-failure')
            assert len(reports) == (2 if mode == 'symbols' or write_failure else 1), (opt, mode, reports)
            contents = [path.read_text(encoding='utf-8') for path in reports]
            complete_files = [c for c in contents if c.endswith('MOON_DIAGNOSTIC_END\n')]
            assert len(complete_files) == (0 if expected_exit else (1 if write_failure else len(contents)))
            for text in contents:
                assert 'pc[$' in text and 'RIP=$' in text and 'resilience original exception' in text
                assert 'application_version=resilience-build-1\n' in text
                assert 'changed-after-initialization' not in text
            for text in complete_files:
                assert 'payload=Начало → ' + 'x' * 50000 + ' ✓ конец\n' in text
                assert 'after_payload=present\n' in text
            if mode == 'symbols':
                assert 'RAW_CONTEXT_ALREADY_ON_DISK' in stdout
                assert sum('symbolization_error=' in c and 'complete=False' in c for c in contents) == 1
                assert sum('symbolization_error=' not in c and 'complete=True' in c for c in contents) == 1
                assert re.findall(r'^pc\[(.+)\]', contents[0], re.M) == re.findall(r'^pc\[(.+)\]', contents[1], re.M)
            elif mode == 'missing-attachment':
                assert 'complete=False' in contents[0] and 'application_data_error=' in contents[0]
                assert 'after_missing_attachment=' not in contents[0]
            else:
                assert all('complete=True' in c for c in complete_files)
            if expected_exit:
                assert 'An unhandled exception occurred' in stdout
                assert 'resilience original exception' in stdout
            else:
                assert f'DIAGNOSTIC_RESILIENCE_PASS {mode}' in stdout
            rows.append({'optimization': opt, 'case': f'resilience-{mode}', 'reports': len(reports)})
            print(f'PASS {opt} resilience-{mode}', flush=True)

        delivery_checks(opt, rows)

        executable = compile_source('diagnostic_switches.pas', out / f'switches-{opt}', opt)
        for mode in ('states', 'manual-disabled-worker', 'disabled-worker-fatal', 'disabled-main-fatal'):
            destination = out / f'switches-{opt}-{mode}'
            expected_exit = UNHANDLED_EXIT if mode == 'disabled-main-fatal' else 0
            text = run([executable, mode, destination], out, out / f'switches-{opt}-{mode}.log', expected_exit)
            reports = list(destination.glob('*.txt'))
            assert len(reports) == (1 if mode == 'manual-disabled-worker' else 0), (opt, mode, reports)
            if reports:
                report = reports[0].read_text(encoding='utf-8')
                assert report.endswith('MOON_DIAGNOSTIC_END\n') and 'complete=True' in report
                assert re.search(r' Execute .*diagnostic_switches\.pas:', report), \
                    'disabled worker excluded from explicit all-thread snapshot'
            if expected_exit:
                assert 'An unhandled exception occurred' in text and 'disabled main fatal' in text, \
                    'normal RTL fatal exception lost'
            else:
                assert 'DIAGNOSTIC_SWITCHES_PASS' in text
            rows.append({'optimization': opt, 'case': f'switches-{mode}', 'reports': len(reports)})
            print(f'PASS {opt} switches-{mode}', flush=True)

        return rows

    # Profiles own their executables, reports, attachments and HTTP/TLS receivers.
    # Keep each profile's stateful checks in their original order.
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for rows in pool.map(profile_checks, ('O-', 'O2', 'O3')):
            results.extend(rows)

    if os.name != 'nt':
        for opt in ('O-', 'O2', 'O3'):
            executable = compile_source('diagnostic_cfi_asm.pas', out / f'cfi-{opt}', opt)
            destination = out / f'cfi-reports-{opt}'
            text = run([executable, destination], out, out / f'cfi-{opt}.log')
            assert 'CFI_ASM_PASS' in text
            reports = list(destination.glob('*.txt'))
            assert len(reports) == 1
            text = reports[0].read_text(encoding='utf-8')
            assert ' ASMBridge ' in text and 'complete=True' in text
            results.append({'optimization': opt, 'case': 'asm-cfi', 'reports': 1})
        # An absolute RSP offset is not meaningful inside a caller's frame.
        # Reject that new directive in inline ASM; do not disable inlining.
        # The units of mORMot come as the O3 build above left them in its
        # unit directory; the toolchain's own units from where they are
        # installed.
        p = subprocess.run([str(compiler), '-n', '-B', '-O3', '-dILLEGAL_INLINE',
                            '-dMOONCOMPILER_VANILLA_RUNTIME', f'-Fu{rtl}', *packages,
                            f'-Fu{root / "runtime/reporting"}', f'-FU{out / "cfi-O3"}',
                            str(root / 'qualification/suite/tests/smoke/diagnostic_cfi_asm.pas')],
                           cwd=out, capture_output=True, timeout=90)
        text = (p.stdout + p.stderr).decode('utf-8', errors='replace')
        (out / 'cfi-inline-negative.log').write_text(text, encoding='utf-8')
        assert p.returncode != 0 and 'Assembler syntax error' in text, text
        results.append({'optimization': 'O3', 'case': 'asm-cfi-inline-rejected', 'reports': 0})

    # Existing semantics must hold both before activation and while original
    # exception contexts are attached. Generated copies differ only by an
    # initialization unit in uses; tracked regression sources remain untouched.
    impact = [
        (root / 'tests/test/cg/tmoonfinallymanagedresults1.pp', 0, 'ok'),
        (root / 'tests/test/cg/tmoonexceptioncapture1.pp', 0, ''),
        (root / 'tests/test/cg/tdelphiinlineexceptreg1.pp', 0, ''),
        (root / 'qualification/suite/tests/smoke/anonymous_exception_capture_matrix.pas', 0,
         'EXCEPTION_CAPTURE_MATRIX_OK'),
        (root / 'qualification/suite/tests/smoke/exception_capture_initfinal.pas', 0,
         'unit-init\nprogram-body\nunit-final'),
    ]
    # traise1-6 end with an exception nobody handles, of a class of their own.
    # SysUtils comes with the product runtime, and into the active copies with
    # Moon.Diagnostics: its handler reports the object and ends the program with
    # 1, and the report tells that exit from the test's own Halt(1).  Only a
    # baseline copy on the vanilla runtime has no SysUtils: runtime error 217.
    unhandled = [root / f'tests/test/cg/traise{i}.pp' for i in range(1, 7)]
    impact_cases = []
    for active in (False, True):
        source_dir = out / ('impact-active-sources' if active else 'impact-baseline-sources')
        source_dir.mkdir()
        if active:
            (source_dir / 'diagnostic_enable.pas').write_text(
                'unit diagnostic_enable;\ninterface\nimplementation\nuses Moon.Diagnostics;\n'
                'initialization\nInitializeReports(ParamStr(1));\nend.\n', encoding='utf-8')
        cases = impact + [(source, UNHANDLED_EXIT, 'is not of class Exception.') if active or args.product_mm
                          else (source, UNHANDLED_EXIT_WITHOUT_SYSUTILS, '') for source in unhandled]
        for source, expected, marker in cases:
            content = source.read_text(encoding='utf-8-sig')
            if active:
                if re.search(r'^uses\b', content, re.M | re.I):
                    content, replacements = re.subn(r'^uses\b', 'uses diagnostic_enable,', content, count=1, flags=re.M | re.I)
                else:
                    content, replacements = re.subn(r'^Type\b', 'uses diagnostic_enable;\nType', content, count=1, flags=re.M | re.I)
                if replacements != 1:
                    raise RuntimeError(f'Cannot activate reporting in regression copy: {source}')
            generated = source_dir / source.name
            generated.write_text(content, encoding='utf-8')
            for opt in ('O-', 'O2', 'O3'):
                impact_cases.append((active, generated, opt, expected, marker))

    def impact_check(case):
        active, source, opt, expected, marker = case
        name = f'impact-{int(active)}-{source.stem}-{opt}'
        executable = compile_source(source, out / name, opt)
        text = run([executable, out / (name + '-reports')], executable.parent, out / (name + '.log'), expected)
        assert marker in text.replace('\r\n', '\n'), (name, text)
        if active:
            assert (out / (name + '-reports')).is_dir(), 'report initialization was not executed'
        assert not list((out / (name + '-reports')).glob('*.txt')), name
        return {'optimization': opt, 'case': source.stem, 'capture_active': active}

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results.extend(pool.map(impact_check, impact_cases))
    for active in (False, True):
        print(f'PASS existing exception/lifetime regressions: capture={active}', flush=True)

    # All correctness workers have joined before collecting timing samples.
    executables = {label: compile_source('diagnostic_raise_bench.pas', out / f'bench-{label}', 'O3', defines)
                   for label, defines in [('baseline', []), ('capture', ['REPORTING'])]}
    samples = {label: [] for label in ('baseline', 'capture', 'thread-off', 'global-off', 'toggle')}
    for i in range(7):
        labels = list(samples)
        labels = labels[i % len(labels):] + labels[:i % len(labels)]
        for label in labels:
            executable = executables['baseline' if label == 'baseline' else 'capture']
            text = run([executable, 3000000 if label == 'toggle' else 30000, out / 'bench-reports', label],
                       out, out / f'bench-{label}-{i}.log')
            samples[label].append(float(re.search(r'NS_PER_(?:RAISE|TOGGLE_PAIR)=([\d.]+)', text).group(1)))
    benchmarks = {label: {'median_ns': statistics.median(values), 'samples_ns': values}
                  for label, values in samples.items()}
    assert not list((out / 'bench-reports').glob('*.txt')), 'caught throws must not create automatic reports'
    summary = {'cases': results, 'benchmark': benchmarks, 'compiler': str(compiler),
               'rtl': str(args.rtl.resolve()), 'product_mm': args.product_mm}
    (out / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    print(f'REPORTING_GATE_PASS {len(results)} cases; {benchmarks}', flush=True)


if __name__ == '__main__':
    main()
