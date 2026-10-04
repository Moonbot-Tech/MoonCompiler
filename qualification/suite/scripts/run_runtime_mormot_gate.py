#!/usr/bin/env python3
"""The runtime/mormot units - System.Zip, System.Net.Mime,
System.Net.HttpClient - compiled from source against the installed toolchain
and mORMot, as an application build compiles them, and run: the Zip and Mime
contracts stand alone, the HTTP contract runs against a loopback HTTP/HTTPS
server that records what the client sent.

The hand-written mORMot base routines also run against their semantic contract.

The compiler and --rtl must belong to the same freshly rebuilt MoonCompiler.
The results directory must not exist. mORMot comes from the qualification
checkout (.qualification/deps/moonormot) or --mormot.
"""
import argparse
import gzip
import os
import re
from pathlib import Path
import shutil
import socket
import ssl
import subprocess
import sys
import threading
import traceback
import time
import zipfile
import zlib
from email import policy
from email.parser import BytesParser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--rtl', type=Path, required=True)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--results', type=Path, required=True)
    parser.add_argument('--option', action='append', default=[])
    parser.add_argument('--modes', nargs='+', default=['O-', 'O3'])
    parser.add_argument('--product-mm', action='store_true', help='use bundled product MM and automatic runtime prefix')
    parser.add_argument('--mormot', type=Path, help='mORMot source tree (default: the qualification checkout)')
    parser.add_argument('--http-executable', type=Path,
                        help='run this build of httpclient_contract against the servers instead of compiling one '
                             '(a Delphi build of the same source: the differential of the two clients); the '
                             'stand-alone contracts are skipped and the Python-side assertions still apply')
    args = parser.parse_args()
    root = args.root.resolve()
    out = args.results.resolve()
    out.mkdir(parents=True, exist_ok=False)
    compiler = args.compiler.resolve()
    link_options = []
    if os.name != 'nt':
        gcc_lib = subprocess.check_output(['gcc', '-print-file-name=libgcc_s.so'], text=True).strip()
        if Path(gcc_lib).is_file():
            link_options.append(f'-Fl{Path(gcc_lib).parent}')

    def run(command, directory, logfile, expected=0, env=None, timeout=180):
        p = subprocess.run([str(x) for x in command], cwd=directory, capture_output=True, timeout=timeout, env=env)
        text = (p.stdout + p.stderr).decode('utf-8', errors='replace')
        logfile.write_text(text, encoding='utf-8')
        if p.returncode != expected:
            raise AssertionError(f'{Path(str(command[0])).name} ... {Path(str(command[-1])).name}: '
                                 f'exit {p.returncode}, expected {expected}; {logfile}\n{text[-2500:]}')
        return text

    def compile_source(source, dest, opt):
        dest.mkdir(parents=True)
        mormot = (args.mormot or root / '.qualification/deps/moonormot').resolve()
        if not (mormot / 'core/mormot.core.base.pas').is_file():
            raise RuntimeError(f'MoonORMot tree is missing at {mormot}; run qualification/suite/runner.py prepare or pass --mormot')
        # the installed RTL and packages of the same toolchain (--rtl names
        # the rtl directory; its siblings are the packages)
        rtl = args.rtl.resolve()
        packages = sorted(p for p in rtl.parent.iterdir() if p.is_dir() and p != rtl)
        # runtime/mormot first: the units under test come from source, ahead
        # of any installed unit of the same name
        command = [compiler, '-n', '-B', f'-Fu{root / "runtime/mormot"}',
                   f'-Fu{rtl}', *[f'-Fu{p}' for p in packages],
                   *[f'-Fu{mormot / name}' for name in ('core', 'net', 'lib', 'crypt')],
                   f'-Fo{mormot}', f'-Fi{mormot}',
                   f'-Fl{mormot / "static" / ("x86_64-win64" if os.name == "nt" else "x86_64-linux")}',
                   f'-FU{dest}', f'-FE{dest}', '-dMOONCOMPILER_UNICODE_DEFAULT',
                   '-gl', '-gw3', '-Xs-', '-Xg-', f'-{opt}',
                   *link_options,
                   *(['-dMOONBOT_MM_PROFILE_REQUIRED', '-dFPCMM_BOOSTER', '-dFPCMM_MOONSHARD', '-dNOPATCHRTL',
                      f'--pinned-unit=mormot.core.fpcx64mm={root / "runtime/mm/mormot.core.fpcx64mm.pas"}']
                     if args.product_mm else ['-dMOONCOMPILER_VANILLA_RUNTIME']), *args.option,
                   root / 'qualification/suite/tests/smoke' / source]
        log = run(command, out, dest / 'compile.log', timeout=600)
        if args.product_mm and re.search(r'Warning:.*"OldMM".*initialized', log):
            raise AssertionError(f'product MM saved-manager initialization warning: {dest / "compile.log"}')
        return dest / (Path(source).stem + ('.exe' if os.name == 'nt' else ''))

    def check_written_archive(path):
        # the archive zip_contract wrote (Add x4, Close, Add in zmReadWrite,
        # Close) read by an independent implementation
        with zipfile.ZipFile(path) as archive:
            assert archive.testzip() is None, f'{path}: CRC or structure error'
            names = archive.namelist()
            assert names == ['data/big.bin', 'Файл.txt', 'empty.txt', 'dir/', 'appended.txt'], names
            infos = {i.filename: i for i in archive.infolist()}
            assert infos['data/big.bin'].compress_type == zipfile.ZIP_DEFLATED, 'big.bin not deflated'
            assert infos['data/big.bin'].file_size == 299000, infos['data/big.bin'].file_size
            assert infos['Файл.txt'].compress_type == zipfile.ZIP_STORED, 'Файл.txt not stored'
            assert infos['Файл.txt'].flag_bits & 0x800, 'no UTF-8 flag on the non-ASCII name'
            assert infos['empty.txt'].file_size == 0 and infos['dir/'].is_dir(), 'empty entry or directory entry'
            assert archive.read('Файл.txt') == b'small text' and archive.read('appended.txt') == b'small text', 'stored content'
            big = archive.read('data/big.bin')
            assert big == bytes((((i + 1000) * 7 + 3) ^ ((i + 1000) >> 6)) & 255 for i in range(299000)), 'deflated content'

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
        raise RuntimeError('OpenSSL command is required to create the loopback test certificate')

    # ------------------------------------------------------------------ server
    requests = []
    lock = threading.Lock()
    text = 'compressed text'.encode()
    big = bytes((i * 7) & 255 for i in range(1 << 20))

    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *_):
            pass

        def conn_id(self):
            # the client's ephemeral port identifies the TCP connection (an
            # object id would be recycled between connections)
            return self.client_address[1]

        def body(self):
            length = int(self.headers.get('Content-Length', '0') or '0')
            return self.rfile.read(length) if length else b''

        def reply(self, status, payload=b'', headers=(), reason=None, chunked=False):
            if reason is None:
                self.send_response(status)
            else:
                self.send_response(status, reason)
            for name, value in headers:
                self.send_header(name, value)
            if chunked:
                self.send_header('Transfer-Encoding', 'chunked')
                self.end_headers()
                for i in range(0, len(payload), 65536):
                    piece = payload[i:i + 65536]
                    self.wfile.write(f'{len(piece):x}\r\n'.encode() + piece + b'\r\n')
                self.wfile.write(b'0\r\n\r\n')
            else:
                self.send_header('Content-Length', str(len(payload)))
                self.end_headers()
                if self.command != 'HEAD':
                    self.wfile.write(payload)

        def handle_any(self):
            data = self.body()
            record = {'method': self.command, 'path': self.path, 'headers': dict(self.headers.items()),
                      'body': data, 'conn': self.conn_id(), 'time': time.time()}
            with lock:
                requests.append(record)
            path = self.path
            if path == '/processed-noresponse':
                self.close_connection = True
            elif path.startswith('/compressed-boundary/'):
                _, _, kind, size = path.split('/')
                payload = b'x' * int(size)
                if kind == 'gzip':
                    encoded = gzip.compress(payload)
                elif kind == 'zlib':
                    encoded = zlib.compress(payload)
                else:
                    encoder = zlib.compressobj(wbits=-15)
                    encoded = encoder.compress(payload) + encoder.flush()
                self.reply(200, encoded, [('Content-Encoding', 'gzip' if kind == 'gzip' else 'deflate')])
            elif path.startswith('/echo') or path == '/show' or path == '/redirect/target':
                lines = [f'{self.command} {path}']
                for name, value in self.headers.items():
                    lines.append(f'H:{name.lower()}={value}')
                if data:
                    lines.append('BODY=' + data.decode('utf-8', errors='replace'))
                self.reply(200, ('\n'.join(lines) + '\n').encode('utf-8'),
                           [('Content-Type', 'text/plain; charset=utf-8'), ('X-Test', 'yes'),
                            ('X-Spaced', '  padded value\t '), ('X-Empty', '')])
            elif path.startswith('/status/'):
                code = int(path.split('/')[2])
                if code == 204:
                    self.send_response(204)
                    self.send_header('X-Test', 'yes')
                    self.end_headers()
                else:
                    self.reply(code, f'status {code}'.encode(), [('Content-Type', 'text/plain')])
            elif path == '/redirect/dots':
                self.reply(302, b'', [('Location', '/a/../echo')])
            elif path == '/redirect/dots-abs':
                host = self.headers.get('Host', '')
                self.reply(302, b'', [('Location', f'http://{host}/a/../echo')])
            elif path == '/redirect/dots-proto':
                host = self.headers.get('Host', '')
                self.reply(302, b'', [('Location', f'//{host}/a/../echo')])
            elif path == '/redirect/cross-return':
                self.reply(302, b'', [('Location', f'http://127.0.0.1:{cross_http.server_port}/redirect/return-origin')])
            elif path == '/redirect/return-origin':
                self.reply(302, b'', [('Location', f'http://127.0.0.1:{plain.server_port}/echo')])
            elif path == '/redirect/cross-auth':
                self.reply(302, b'', [('Location', f'http://127.0.0.1:{cross_http.server_port}/echo')])
            elif path.startswith('/redirect/chain/'):
                left = int(path.rsplit('/', 1)[1]) - 1
                target = '/echo' if left == 0 else f'/redirect/chain/{left}'
                self.reply(302, b'moved', [('Location', target)])
            elif path.startswith('/redirect/relative/'):
                self.reply(302, b'', [('Location', '../target')])
            elif path == '/redirect/query':
                self.reply(302, b'', [('Location', '/echo?from=redirect')])
            elif path.startswith('/redirect/'):
                code = int(path.split('/')[2])
                self.reply(code, b'moved', [('Location', '/echo'), ('Content-Type', 'text/plain')])
            elif path == '/gzip':
                self.reply(200, gzip.compress(text), [('Content-Encoding', 'gzip'), ('Content-Type', 'text/plain'),
                                                       ('X-Accept-Encoding', self.headers.get('Accept-Encoding', ''))])
            elif path == '/gzip-cut':
                # a gzip member cut in half: not a complete stream
                payload = gzip.compress(text)
                self.reply(200, payload[:max(1, len(payload) // 2)],
                           [('Content-Encoding', 'gzip'), ('Content-Type', 'text/plain')])
            elif path == '/deflate':
                self.reply(200, zlib.compress(text), [('Content-Encoding', 'deflate'), ('Content-Type', 'text/plain'),
                                                       ('X-Accept-Encoding', self.headers.get('Accept-Encoding', ''))])
            elif path == '/deflate-raw':
                raw = zlib.compressobj(wbits=-15)
                self.reply(200, raw.compress(text) + raw.flush(), [('Content-Encoding', 'deflate'), ('Content-Type', 'text/plain')])
            elif path == '/charset1251':
                self.reply(200, 'Привет'.encode('cp1251'), [('Content-Type', 'text/plain; charset=windows-1251')])
            elif path == '/charset-quoted':
                self.reply(200, 'Привет'.encode('utf-8'), [('Content-Type', 'text/plain; charset="UTF-8"')])
            elif path == '/bom':
                self.reply(200, '﻿abc'.encode('utf-8'), [('Content-Type', 'text/plain')])
            elif path == '/cookies/set':
                self.reply(200, b'ok', [
                    ('Set-Cookie', 'sid=abc; Path=/; HttpOnly'),
                    ('Set-Cookie', 'pref=1; Path=/cookies; Expires=Fri, 31 Dec 2038 23:59:59 GMT'),
                ])
            elif path == '/cookies/replace':
                self.reply(200, b'ok', [('Set-Cookie', 'sid=def; Path=/')])
            elif path == '/cookies/show':
                self.reply(200, self.headers.get('Cookie', '').encode(), [('Content-Type', 'text/plain')])
            elif path == '/big':
                self.reply(200, big, [('Content-Type', 'application/octet-stream')])
            elif path == '/digest':
                # the request body's length and FNV-1a, for uploads too big to echo
                h = 2166136261
                for byte in data:
                    h = ((h ^ byte) * 16777619) & 0xFFFFFFFF
                self.reply(200, f'len={len(data)} fnv={h:08X}'.encode(), [('Content-Type', 'text/plain')])
            elif path == '/bad-utf8':
                # two stray bytes, a valid two-byte sequence, a truncated three-byte one
                self.reply(200, b'ab\xff\xfecd\xd0\x9f\xe2\x82', [('Content-Type', 'text/plain; charset=utf-8')])
            elif path == '/big-chunked':
                self.reply(200, big, [('Content-Type', 'application/octet-stream')], chunked=True)
            elif path == '/conn':
                self.reply(200, b'c', [('X-Conn-Id', str(record['conn']))])
            elif path == '/conn-drop':
                # a keep-alive answer, then the server drops the idle connection
                # without a word (what an exchange does after its idle timeout)
                self.reply(200, b'c', [('X-Conn-Id', str(record['conn'])), ('Connection', 'keep-alive')])
                self.close_connection = True
            elif path == '/conn-after':
                self.reply(200, b'c', [('X-Conn-Id', str(record['conn']))])
            elif path in ('/lie-long-idle', '/lie-long-close'):
                # Content-Length promises 100 bytes, 50 arrive; then the server
                # either keeps the connection idle or closes it
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.send_header('Content-Length', '100')
                self.end_headers()
                self.wfile.write(b'x' * 50)
                self.wfile.flush()
                if path == '/lie-long-idle':
                    time.sleep(2.0)
                self.close_connection = True
            elif path == '/close-delimited':
                # no Content-Length, no chunking: the body ends with the connection
                # (RFC 7230 3.3.3); binary, with a bare LF, CR LF and NUL inside
                self.send_response(200)
                self.send_header('Content-Type', 'application/octet-stream')
                self.send_header('Connection', 'close')
                self.end_headers()
                self.wfile.write(b'line1\nline2\r\nbin\x00\x01\xff end')
                self.wfile.flush()
                self.close_connection = True
            elif path == '/lie-huge':
                # Content-Length claims 2 GB, 10 bytes arrive, the server stalls
                self.send_response(200)
                self.send_header('Content-Type', 'application/octet-stream')
                self.send_header('Content-Length', str(2 * 1024 * 1024 * 1024))
                self.end_headers()
                self.wfile.write(b'0123456789')
                self.wfile.flush()
                time.sleep(3.0)
                self.close_connection = True
            elif path == '/lie-short':
                # Content-Length promises 5 bytes, 10 arrive: the excess stays in
                # the connection in front of the next answer
                self.send_response(200)
                self.send_header('Content-Type', 'text/plain')
                self.send_header('Content-Length', '5')
                self.end_headers()
                self.wfile.write(b'ABCDEFGHIJ')
                self.wfile.flush()
            elif path == '/immediate-cancel':
                time.sleep(1.5)
                self.reply(200, b'cancelled too late')
            elif path == '/slow-headers':
                time.sleep(1.5)
                self.reply(200, b'late')
            elif path in ('/slow-body', '/slow-body-long'):
                self.send_response(200)
                self.send_header('Content-Length', '20')
                self.end_headers()
                self.wfile.write(b'0123456789')
                self.wfile.flush()
                time.sleep(1.5 if path == '/slow-body' else 4.0)
                try:
                    self.wfile.write(b'0123456789')
                except OSError:
                    pass
                self.close_connection = True
            elif path == '/upload':
                message = BytesParser(policy=policy.default).parsebytes(
                    b'Content-Type: ' + self.headers['Content-Type'].encode() + b'\r\n\r\n' + data)
                parts = list(message.iter_parts())
                fields = {p.get_param('name', header='Content-Disposition'): p for p in parts}
                caption = fields['caption'].get_payload(decode=True).decode('utf-8')
                photo = fields['photo']
                answer = (f'parts={len(parts)} caption={caption} photo={len(photo.get_payload(decode=True))} '
                          f'type={photo.get_content_type()}')
                record['upload'] = {'caption': caption, 'photo': photo.get_payload(decode=True),
                                    'filename': photo.get_filename(), 'type': photo.get_content_type()}
                self.reply(200, answer.encode('utf-8'), [('Content-Type', 'text/plain; charset=utf-8')])
            else:
                self.reply(404, b'no such path')

        do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_HEAD = handle_any

    def make_certificate(name, subject_alt):
        key = root / 'packages/fcl-hash/tests/private-key.pem'
        certificate = out / f'{name}.pem'
        run([openssl_command(), 'req', '-x509', '-new', '-key', key, '-out', certificate,
             '-days', '1', '-subj', '/CN=localhost', '-addext', f'subjectAltName={subject_alt}'],
            out, out / f'{name}.log')
        return key, certificate

    class QuietServer(ThreadingHTTPServer):
        # the client drops connections on purpose (timeouts, aborts, cancel,
        # refused certificates): socket errors stay quiet; anything else is a
        # bug of this server and is printed, or a client failure would be
        # blamed on the client
        def handle_error(self, request, client_address):
            if not isinstance(sys.exc_info()[1], OSError):
                print(f'SERVER ERROR for {client_address}:', file=sys.stderr)
                traceback.print_exc()

    def tls_server(key, certificate):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certificate, key)
        server = QuietServer(('127.0.0.1', 0), Handler)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        return server

    plain = QuietServer(('127.0.0.1', 0), Handler)
    cross_http = QuietServer(('127.0.0.1', 0), Handler)
    key, certificate = make_certificate('loopback-certificate', 'DNS:localhost,IP:127.0.0.1')
    _, other_certificate = make_certificate('other-host-certificate', 'DNS:other.invalid')
    secure = tls_server(key, certificate)
    other = tls_server(key, other_certificate)
    refused = socket.socket()
    refused.bind(('127.0.0.1', 0))
    refused_port = refused.getsockname()[1]
    refused.close()   # nothing listens there any more
    threads = [threading.Thread(target=s.serve_forever, daemon=True) for s in (plain, cross_http, secure, other)]
    for t in threads:
        t.start()
    results = []
    try:
        for opt in (['foreign'] if args.http_executable else args.modes):
            # the stand-alone contracts first
            for contract, marker in (() if args.http_executable else
                                     (('mormot_asm_contract.dpr', 'MORMOT_ASM_CONTRACT_PASS'),
                                      ('zip_contract.pas', 'ZIP_CONTRACT_PASS'),
                                      ('mime_contract.pas', 'MIME_CONTRACT_PASS'))):
                exe = compile_source(contract, out / f'{Path(contract).stem}-{opt}', opt)
                directory = out / f'run-{Path(contract).stem}-{opt}'
                directory.mkdir()
                written = directory / 'written.zip'
                output = run([exe] + ([str(written)] if contract.startswith('zip') else []),
                             directory, directory / 'run.log')
                assert marker in output, output[-2000:]
                if contract.startswith('zip'):
                    check_written_archive(written)
                    with zipfile.ZipFile(str(written) + '.descriptors.zip') as archive:
                        assert archive.testzip() is None
                        assert archive.read('stored') == archive.read('deflated') == b'abc'
                        assert archive.read('empty') == archive.read('added1') == archive.read('added2') == b''
                        assert len(archive.infolist()) == 5
                results.append(f'{Path(contract).stem}/{opt}: pass')
            if args.http_executable:
                executable = args.http_executable.resolve()
            else:
                executable = compile_source('httpclient_contract.pas', out / f'contract-{opt}', opt)
            for trust in (('untrusted', 'trusted') if os.name != 'nt' else ('untrusted',)):
                directory = out / f'run-{opt}-{trust}'
                directory.mkdir()
                before = len(requests)
                env = dict(os.environ)
                if trust == 'trusted':
                    # trust only this fixture, in this child process
                    env['SSL_CERT_FILE'] = str(certificate)
                started = time.perf_counter()
                try:
                    stdout = run([executable, f'http://127.0.0.1:{plain.server_port}',
                                  f'https://localhost:{secure.server_port}',
                                  f'https://localhost:{other.server_port}' if trust == 'trusted' else '-',
                                  trust, str(refused_port)], directory, directory / 'run.log', env=env)
                except AssertionError:
                    for r in requests[before:]:
                        print('DEBUG', f"{r['time']:.3f}", r['method'], r['path'], r['conn'], file=sys.stderr)
                    raise
                elapsed = time.perf_counter() - started
                assert 'HTTPCLIENT_CONTRACT_PASS' in stdout, stdout[-2000:]
                observed = requests[before:]
                # what the client sent
                uploads = [r for r in observed if r['path'] == '/upload']
                assert len(uploads) == 1 and uploads[0]['upload']['caption'] == 'Фото → тест'
                assert uploads[0]['upload']['photo'] == bytes((i * 31 + 7) & 255 for i in range(70000))
                assert uploads[0]['upload']['filename'].startswith('httpclient-upload-')
                assert uploads[0]['upload']['type'] == 'image/x-test'
                conns = [r['conn'] for r in observed if r['path'] == '/conn']
                assert len(conns) == 5 and len(set(conns)) == 1, conns
                # after each dropped connection the next request rode a new one, once
                drops = [i for i, r in enumerate(observed) if r['path'] == '/conn-drop']
                assert len(drops) == 2, drops
                for i in drops:
                    assert observed[i + 1]['conn'] != observed[i]['conn'], (observed[i], observed[i + 1])
                assert len([r for r in observed if r['path'] == '/conn-after']) == 1
                # a request the server answered in part (headers, then a stalled body)
                # or too late is never sent a second time
                for path in ('/slow-body', '/slow-headers', '/lie-long-idle', '/lie-long-close', '/lie-huge'):
                    assert len([r for r in observed if r['path'] == path]) == 1, (path, [r['path'] for r in observed])
                assert len([r for r in observed if r['body'] == b'after-drop']) <= 1, 'the POST after a drop was replayed'
                for request in observed:
                    if request['path'] == '/redirect/return-origin':
                        assert request['headers'].get('Authorization') is None
                        assert request['headers'].get('Cookie') is None
                for method in ('POST', 'PATCH'):
                    assert len([r for r in observed if r['path'] == '/processed-noresponse' and r['method'] == method]) == 1
                no_ua = [r for r in observed if r['path'] == '/echo' and 'User-Agent' not in r['headers']]
                assert no_ua, 'the request without User-Agent did not arrive'
                forms = [r for r in observed if r['method'] == 'POST' and r['path'] == '/echo'
                         and r['headers'].get('Content-Type', '').startswith('application/x-www-form-urlencoded')]
                assert len(forms) == 3, len(forms)
                assert parse_qs(forms[0]['body'].decode()) == {'a': ['1'], 'b': ['Привет мир'], 'c': ['x&y=z']}
                assert parse_qs(forms[1]['body'].decode('cp1251'), encoding='cp1251') == {'a': ['1'], 'b': ['Привет мир'], 'c': ['x&y=z']}
                redirected_post = [r for r in observed if r['path'] == '/echo' and r['method'] == 'GET'
                                   and 'Content-Length' in r['headers']]
                assert not redirected_post, 'a GET after a redirect carried Content-Length'
                results.append(f'{opt}/{trust}: requests={len(observed)} elapsed={elapsed:.1f}s')
    finally:
        for s in (plain, cross_http, secure, other):
            s.shutdown()
            s.server_close()
    (out / 'summary.txt').write_text('\n'.join(results) + '\n', encoding='utf-8')
    print('RUNTIME_MORMOT_GATE_PASS ' + '; '.join(results))
    return 0


if __name__ == '__main__':
    sys.exit(main())
