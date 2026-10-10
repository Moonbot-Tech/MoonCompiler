"""Indirect PPU waits must be broken without losing source or generic state."""
import os
import shutil


def check_helper_generic_reload_cycles(command, output, run):
    output.mkdir()
    for mode in ('delphi', 'unleashed'):
        for hops in (1, 3):
            for reverse_uses in (False, True):
                case = output / f'{mode}-{hops}-{int(reverse_uses)}'
                case.mkdir()
                options = command + ['-Fu'+str(case), '-FU'+str(case), '-FE'+str(case)]
                previous = {}
                # Body, public layout, indirect interface, simultaneous edits,
                # then complete reversal. Unchanged sources keep their timestamps.
                phases = [(7, 11, 0, False, 0), (8, 11, 0, False, 0),
                          (8, 11, 0, True, 0), (8, 11, 3, True, 0),
                          (9, 13, 4, True, 5), (7, 11, 0, False, 0)]
                for phase, (a, d, offset, layout, bonus) in enumerate(phases):
                    sources = {}
                    for unit, value in [('source_a', a), ('source_d', d)]:
                        fields = 'One, Two: Int64;' if layout else 'One: Integer;'
                        sources[unit] = f'''unit {unit};
{{$mode {mode}}}
interface
uses generic_b;
type TPublicRecord = record {fields} end;
function Value: Integer;
function Exercise: Integer;
implementation
uses {'source_d' if unit == 'source_a' else 'source_a'};
function Value: Integer; begin Result := {value}; end;
function Exercise: Integer;
var Item: TBox<TPublicRecord>;
begin
  Item := TBox<TPublicRecord>.Create;
  try Result := Item.ReadValue + SizeOf(TPublicRecord) + TObject.ProbeHelper; finally Item.Free; end;
end;
end.
'''
                    sources['generic_b'] = f'''unit generic_b;
{{$mode {mode}}}
interface
uses bridge0;
type TTestHelper = class helper for TObject
  class function ProbeHelper: Integer; static;
end;
TBox<T> = class
  function ReadValue: Integer;
end;
implementation
class function TTestHelper.ProbeHelper: Integer; begin Result := 23; end;
function TBox<T>.ReadValue: Integer; begin Result := BridgeValue + {bonus}; end;
end.
'''
                    for i in range(hops):
                        dependency = f'bridge{i+1}' if i + 1 < hops else 'source_a, source_d'
                        expression = f'bridge{i+1}.BridgeValue' if i + 1 < hops else 'source_a.Value + source_d.Value'
                        # Changing a const in an indirectly used interface must
                        # invalidate its generic consumers, including old PPUs.
                        sources[f'bridge{i}'] = f'''unit bridge{i};
{{$mode {mode}}}
interface
const Delta = {offset if i == 0 else 0};
function BridgeValue: Integer;
implementation
uses {dependency};
function BridgeValue: Integer; begin Result := {expression} + Delta; end;
end.
'''
                    for name, text in sources.items():
                        if previous.get(name) != text:
                            path = case / (name+'.pas')
                            path.write_text(text)
                            os.utime(path, (1700000000 + phase*4,) * 2)
                    previous = sources
                    units = 'generic_b, source_d, source_a' if reverse_uses else 'source_a, source_d, generic_b'
                    expected = a + d + offset + bonus + (16 if layout else 4) + 23
                    main = case/f'main_{phase}.dpr'
                    main.write_text(f'''program main;
{{$mode {mode}}}
uses {units};
begin
  if (source_a.Exercise <> {expected}) or (source_d.Exercise <> {expected}) then Halt(1);
  Writeln('INDIRECT_CYCLE_OK');
end.
''')
                    if phase == 1:
                        # Keep the original PPU set for diagnosis if a later
                        # source/PPU transition fails.
                        snapshot = case/'initial-ppus'
                        snapshot.mkdir()
                        for ppu in case.glob('*.ppu'):
                            shutil.copy2(ppu, snapshot/ppu.name)
                    run(options+[str(main)], case, case/f'{phase}-build.log')
                    executable = main.with_suffix('.exe' if os.name == 'nt' else '')
                    assert run([str(executable)], case, case/f'{phase}-run.log').strip() == 'INDIRECT_CYCLE_OK'
                    warm_executable = case / ('warm_' + executable.name)
                    warm = run(options+['-o'+str(warm_executable),str(main)], case, case/f'{phase}-warm.log').lower()
                    assert not any('parsing interface of unit '+name in warm for name in sources), 'Unchanged source rebuilt'
                    assert run([str(warm_executable)], case, case/f'{phase}-warm-run.log').strip() == 'INDIRECT_CYCLE_OK'
