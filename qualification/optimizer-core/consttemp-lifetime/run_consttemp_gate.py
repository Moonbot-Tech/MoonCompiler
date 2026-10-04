#!/usr/bin/env python3
"""Persistent const-temp lifetime: goto/PIC and source-isolated PPU consumer."""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess

HERE = Path(__file__).resolve().parent

def execute(command, cwd, log):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, errors='replace')
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(str(command) + '\n' + (result.stdout + result.stderr)[-2500:])
    return result.stdout

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    win = os.name == 'nt'
    rows = []
    for mode in ('O-', 'O2', 'O3'):
        for pic in ((False,) if win else (False, True)):
            out = args.output.resolve()/(mode+('-pic' if pic else ''))
            units, consumer = out/'units', out/'consumer'
            units.mkdir(parents=True, exist_ok=True)
            consumer.mkdir(exist_ok=True)
            producer = out/'producer'
            producer.mkdir(exist_ok=True)
            producer_source = producer/'consttemp_unit.pas'
            shutil.copy2(HERE/'consttemp_unit.pas', producer_source)
            common = [str(args.compiler.resolve()), '-n', '@'+str(args.config.resolve()), '-'+mode]
            if pic:
                common += ['-Cg']
            execute(common+['-B', '-FE'+str(out), '-FU'+str(out), str(HERE/'consttemp_minimal.dpr')], out, out/'minimal-build.log')
            binary = out/('consttemp_minimal.exe' if win else 'consttemp_minimal')
            assert execute([str(binary)], out, out/'minimal-run.log').strip() == 'CONSTTEMP_PASS'
            execute(common+['-B', '-FU'+str(units), str(producer_source)], out, out/'producer.log')
            producer_source.rename(producer/'consttemp_unit.hidden')
            shutil.copy2(HERE/'consttemp_ppu.dpr', consumer/'consttemp_ppu.dpr')
            log = execute(common+['-vu', '-Fu'+str(units), '-FU'+str(consumer), '-FE'+str(consumer), str(consumer/'consttemp_ppu.dpr')], consumer, out/'consumer.log')
            assert not (consumer/'consttemp_unit.pas').exists()
            assert 'Compiling '+str(HERE/'consttemp_unit.pas') not in log
            binary = consumer/('consttemp_ppu.exe' if win else 'consttemp_ppu')
            assert execute([str(binary)], consumer, out/'ppu-run.log').strip() == 'CONSTTEMP_PASS'
            rows.append(dict(mode=mode, pic=pic, minimal=True, ppu=True,
                             ppu_sha256=hashlib.sha256((units/'consttemp_unit.ppu').read_bytes()).hexdigest()))
    (args.output/'results.json').write_text(json.dumps(rows, indent=2))
    print('CONSTTEMP_GATE_PASS', len(rows), 'minimal and PPU')

if __name__ == '__main__':
    main()
