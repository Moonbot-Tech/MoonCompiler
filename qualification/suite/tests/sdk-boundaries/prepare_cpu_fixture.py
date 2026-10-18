from pathlib import Path
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('tree', type=Path)
parser.add_argument('out', type=Path)
args = parser.parse_args()

unix = (args.tree / 'rtl/unix/classes.pp').read_text(encoding='utf-8')
common = (args.tree / 'rtl/objpas/classes/classes.inc').read_text(encoding='utf-8')
reader = unix.split('class function TThread.GetSystemTimes(', 1)[1].split('{$ENDIF}', 1)[0]
usage = common.split('class function TThread.GetCPUUsage(', 1)[1].split('class function TThread.GetTickCount:', 1)[0]
args.out.mkdir(parents=True, exist_ok=True)
(args.out / 'cpu_implementations.inc').write_text(
    'class function TThread.GetSystemTimes(' + reader + '\n' +
    'class function TThread.GetCPUUsage(' + usage,
    encoding='utf-8', newline='\n')

print('Exact GetSystemTimes/GetCPUUsage bodies extracted from', args.tree)
