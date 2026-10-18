from pathlib import Path
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('tree', type=Path)
parser.add_argument('out', type=Path)
args = parser.parse_args()
source = (args.tree / 'net/mormot.net.sock.pas').read_text(encoding='utf-8')

def body(start, end):
    return start + source.rsplit(start, 1)[1].split(end, 1)[0]

methods = [
    body('function NetLastError(AnotherNonFatal: integer; Error: system.PInteger): TNetResult;',
         'function NetLastErrorMsg('),
    body('function NetCheck(res: integer): TNetResult;', 'function ToText('),
    body('function NetEventsToNetResult(ev: TNetEvents): TNetResult;', '{ ENetSock }'),
    body('function TNetAddr.SocketConnect(socket: TNetSocket; ms: integer): TNetResult;',
         'function TNetAddr.SocketBind(').replace('mormot.core.os.GetTickCount64', 'StandTick'),
]
args.out.mkdir(parents=True, exist_ok=True)
(args.out / 'connect_implementations.inc').write_text('\n'.join(methods), encoding='utf-8', newline='\n')
print('Exact SocketConnect/error classification bodies extracted from', args.tree)
