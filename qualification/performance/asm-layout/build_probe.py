"""Build the frozen 2026-09-28 manual-layout review probe; requires MoonCompiler and MoonORMot."""
from pathlib import Path
import argparse, gzip, hashlib, subprocess

root=Path(__file__).resolve().parent
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--compiler',required=True,type=Path)
ap.add_argument('--output',required=True,type=Path)
ap.add_argument('--rounds',type=int,default=7)
ap.add_argument('--batch-us',type=int,default=1000)
ap.add_argument('--fpc-arg',action='append',default=[])
args=ap.parse_args()
if args.rounds<3 or args.batch_us<100: ap.error('at least 3 rounds and 100 us are required')
out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
src=gzip.decompress((root/'probe.pas.gz').read_bytes()).decode('utf-8')
src=src.replace('FamilyRounds = 7;',f'FamilyRounds = {args.rounds};')
src=src.replace('BatchNs := 1000000;',f'BatchNs := {args.batch_us*1000};')
path=out/'manual_layout_probe.pas';path.write_text(src,encoding='utf-8')
cmd=[str(args.compiler.resolve()),'-B','-dRELEASE',f'-Fu{root}',f'-Fu{root.parent / "common"}',
     f'-FE{out}',f'-FU{out}',*args.fpc_arg,str(path)]
with (out/'build.log').open('w',encoding='utf-8') as log:
    subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True,cwd=out)
print('source_sha256='+hashlib.sha256(path.read_bytes()).hexdigest())
