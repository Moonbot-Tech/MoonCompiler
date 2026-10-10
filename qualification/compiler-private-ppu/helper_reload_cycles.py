"""A suspended source unit must not retain helpers from a replaced dependency."""
import os
import shutil


def check_helper_reload_cycles(command, output, run):
    output.mkdir()
    # First graph is the reduced release-2.4.2 AV. Vary loading order and
    # interface/implementation edges without compiling an application corpus.
    graphs = [(False, False, True, 0), (False, False, True, 1),
              (False, False, True, 2), (False, True, True, 0),
              (True, False, True, 0), (True, True, True, 1),
              (False, False, False, 0), (True, True, False, 2)]
    for kind in ('record', 'class'):
        for index, (helper_edge, bridge_interface, public_helper, order) in enumerate(graphs):
            case = output / f'{kind}-{index}'
            case.mkdir()
            options = command + [f'-Fu{case}', f'-FU{case}', f'-FE{case}']
            previous = {}
            for phase, (value, wide) in enumerate(((7, False), (8, False), (8, True), (7, False))):
                fields = 'One, Two: Int64' if wide else 'One: Integer'
                sources = {
                    'base': f'''unit base; {{$mode delphi}}
interface type TItem = {kind} Value: Integer; end;
implementation end.
''',
                    'helpers': f'''unit helpers; {{$mode delphi}}
interface uses base{', tail' if helper_edge else ''};
type TItemHelper = {kind} helper for TItem
  function ReadValue: Integer;
end;
implementation uses edited;
function TItemHelper.ReadValue: Integer;
begin Result := edited.Value + Value; end;
end.
''',
                    'edited': f'''unit edited; {{$mode delphi}}
interface uses base{', helpers' if public_helper else ''};
type TPublic = record {fields}; end;
function Value: Integer;
function Exercise: Integer;
implementation uses bridge{', helpers' if not public_helper else ''};
function Value: Integer; begin Result := {value}; end;
function Exercise: Integer;
var Item: TItem;
begin
  {'Item := TItem.Create;' if kind == 'class' else ''}
  Item.Value := 23;
  Result := Item.ReadValue + SizeOf(TPublic);
  {'Item.Free;' if kind == 'class' else ''}
end;
end.
''',
                    'bridge': f'''unit bridge; {{$mode delphi}}
interface {'uses edited;' if bridge_interface else ''}
function BridgeValue: Integer;
implementation uses tail{', edited' if not bridge_interface else ''};
function BridgeValue: Integer; begin Result := edited.Value; end;
end.
''',
                    'tail': 'unit tail; {$mode delphi} interface const Stamp=1; implementation uses edited; end.\n',
                }
                for name, text in sources.items():
                    if previous.get(name) != text:
                        path = case / (name + '.pas')
                        path.write_text(text)
                        os.utime(path, (1700000000 + phase * 4,) * 2)
                previous = sources
                main = case / f'main_{phase}.dpr'
                units = ('edited, helpers, bridge, tail', 'helpers, edited, bridge, tail',
                         'tail, edited, helpers, bridge')[order]
                main.write_text(f'''program main_{phase}; {{$mode delphi}}
uses {units};
begin
  If edited.Exercise <> {value + 23 + (16 if wide else 4)} then Halt(1);
  Writeln('HELPER_RELOAD_OK');
end.
''')
                if phase == 1:
                    snapshot = case / 'initial-ppus'
                    snapshot.mkdir()
                    for ppu in case.glob('*.ppu'):
                        shutil.copy2(ppu, snapshot / ppu.name)
                run(options + [str(main)], case, case / f'{phase}-build.log')
                executable = main.with_suffix('.exe' if os.name == 'nt' else '')
                assert run([str(executable)], case, case / f'{phase}-run.log').strip() == 'HELPER_RELOAD_OK'
                warm_executable = case / ('warm_' + executable.name)
                warm = run(options + ['-o' + str(warm_executable), str(main)], case, case / f'{phase}-warm.log').lower()
                assert not any('parsing interface of unit ' + name in warm for name in sources), 'Unchanged unit rebuilt'
                assert run([str(warm_executable)], case, case / f'{phase}-warm-run.log').strip() == 'HELPER_RELOAD_OK'
            # The last cache must also be usable without any of its sources.
            for name in sources:
                (case / (name + '.pas')).rename(case / (name + '.hidden'))
            source_free = case / ('source_free_' + executable.name)
            run(options + ['-o' + str(source_free), str(main)], case, case / 'source-free-build.log')
            assert run([str(source_free)], case, case / 'source-free-run.log').strip() == 'HELPER_RELOAD_OK'
    print('HELPER_RELOAD_GATE_PASS', len(graphs) * 2 * 4)
