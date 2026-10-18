"""Real loopback HTTP success/refusal plus TCP backlog saturation for pending connect."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import argparse
from pathlib import Path
import select
import socket
import subprocess
import threading

parser = argparse.ArgumentParser()
parser.add_argument('probe', type=Path)
args = parser.parse_args()

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Length', '2')
        self.end_headers()
        self.wfile.write(b'{}')

    def log_message(self, *args):
        pass

with ThreadingHTTPServer(('127.0.0.1', 0), Handler) as server, socket.socket() as refused, socket.socket() as pending:
    listener = threading.Thread(target=server.serve_forever, daemon=True)
    listener.start()
    refused.bind(('127.0.0.1', 0))
    pending.bind(('127.0.0.1', 0))
    pending.listen(0)
    fillers = []
    try:
        for _ in range(64):
            filler = socket.socket()
            fillers.append(filler)
            filler.setblocking(False)
            filler.connect_ex(pending.getsockname())
            _, writable, _ = select.select([], [filler], [], 0.15)
            if not writable:
                assert filler.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR) == 0
                break
        else:
            raise AssertionError('Could not create a pending connection on this OS')
        urls = [f'http://127.0.0.1:{item}/probe' for item in
                (server.server_address[1], refused.getsockname()[1], pending.getsockname()[1])]
        result = subprocess.run([str(args.probe.resolve(strict=True)), *urls],
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=15)
        print(result.stdout, end='')
        assert result.returncode == 0 and 'HTTP_CONNECT_CONTRACT_PASS' in result.stdout
    finally:
        for filler in fillers:
            filler.close()
        server.shutdown()
        listener.join()
