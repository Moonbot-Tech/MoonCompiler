"""Private DefId changes must invalidate dependent PPUs while preserving the interface CRC."""
from pathlib import Path
import argparse
import json
import os
import re
import shutil
import struct
import subprocess
from reload_cycles import check_reload_cycles
from indirect_reload_cycles import check_indirect_reload_cycles


def run(command, cwd, log):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, errors='replace', timeout=60)
    text = result.stdout + result.stderr
    log.write_text(text)
    assert result.returncode == 0, (command, text[-3000:])
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    assert not output.exists(), 'Use a new output directory'
    output.mkdir(parents=True)
    fixtures = Path(__file__).resolve().parent
    shutil.copy2(fixtures/'consumer.pas', output/'consumer.pas')
    command = [str(args.compiler.resolve()), '-n', '@'+str(args.config.resolve()), '-O2',
               '-Fu'+str(output), '-FU'+str(output), '-FE'+str(output), '-vu']
    rows = []
    for phase, fixture in [('initial', 'before'), ('changed', 'after'), ('reversed', 'before')]:
        shutil.copy2(fixtures/('provider_'+fixture+'.pas'), output/'provider.pas')
        run(command+['-B', str(output/'provider.pas')], output, output/(phase+'-provider.log'))
        data = (output/'provider.ppu').read_bytes()
        assert data[:3] == b'PPU' and data[3:6] == b'208', 'Unexpected PPU header'
        # tentryheader is 20 bytes; tppuheader starts with full and interface CRC.
        full_crc, interface_crc = struct.unpack_from('<II', data, 20)
        program = output/('main_'+phase+'.dpr')
        program.write_text('program main_'+phase+';\n{$mode delphi}\nuses consumer;\n'
                           'begin\n  WriteLn(ConsumerValue);\n  if ConsumerValue<>23 then Halt(1);\nend.\n')
        log = run(command+[str(program)], output, output/(phase+'-main.log'))
        assert re.search(r'^Compiling (?:.*[/\\])?consumer\.pas$', log, re.M), 'Consumer PPU was not rebuilt'
        executable = program.with_suffix('.exe' if os.name == 'nt' else '')
        assert run([str(executable)], output, output/(phase+'-run.log')).strip() == '23'
        rows.append(dict(phase=phase, full_crc=f'{full_crc:08X}', interface_crc=f'{interface_crc:08X}'))
    assert len({row['interface_crc'] for row in rows}) == 1, rows
    assert rows[0]['full_crc'] != rows[1]['full_crc'], rows
    assert rows[0]['full_crc'] == rows[2]['full_crc'], rows
    (output/'result.json').write_text(json.dumps(rows, indent=2))
    check_reload_cycles(command, output/'reload-cycles', run)
    check_indirect_reload_cycles(command, output/'indirect-reload-cycles', run)
    print('PPU_PRIVATE_CRC_GATE_PASS', len(rows))


if __name__ == '__main__':
    main()
