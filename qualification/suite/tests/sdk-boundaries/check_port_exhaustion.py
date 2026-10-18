"""Exercise sync/async EADDRNOTAVAIL and recovery in a private network namespace."""
from http.server import BaseHTTPRequestHandler, HTTPServer
import argparse
import os
from pathlib import Path
import select
import signal
import socket
import subprocess
import threading

parser = argparse.ArgumentParser()
parser.add_argument('probe', type=Path)
parser.add_argument('--user')
args = parser.parse_args()
probe = args.probe.resolve(strict=True)
assert os.geteuid() == 0, 'Use sudo unshare --net'
assert os.readlink('/proc/self/ns/net') != os.readlink('/proc/1/ns/net'), 'Refusing host network namespace'
subprocess.run(['ip', 'link', 'set', 'lo', 'up'], check=True)
Path('/proc/sys/net/ipv4/ip_local_port_range').write_text('43000 43001')

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        assert self.path == '/probe'
        self.send_response(200)
        self.send_header('Content-Length', '2')
        self.end_headers()
        self.wfile.write(b'{}')

    def log_message(self, *args):
        pass

with HTTPServer(('127.0.0.1', 29080), Handler) as server:
    listener = threading.Thread(target=server.serve_forever, daemon=True)
    listener.start()
    reserved = []
    process = None
    try:
        for port in (43000, 43001):
            item = socket.socket()
            reserved.append(item)
            item.bind(('127.0.0.1', port))
            item.listen()
        command = [str(probe), 'http://127.0.0.1:29080/probe']
        if args.user:
            command = ['runuser', '-u', args.user, '--'] + command
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, text=True, start_new_session=True)
        assert select.select([process.stdout], [], [], 15)[0], 'No exhaustion result'
        line = process.stdout.readline()
        if line.strip() != 'PORT_EXHAUSTION_DETECTED':
            output, _ = process.communicate(timeout=15)
            raise AssertionError(line + output)
        print(line, end='', flush=True)
        for item in reserved:
            item.close()
        output, _ = process.communicate('resume\n', timeout=15)
        assert process.returncode == 0 and 'PORT_EXHAUSTION_RECOVERED' in output, output
        print(output, end='')
    finally:
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        for item in reserved:
            item.close()
        server.shutdown()
        listener.join()
