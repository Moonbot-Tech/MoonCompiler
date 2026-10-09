"""Re-enter parsed modules while a generic PPU waits for a source unit's CRC."""
from pathlib import Path
import os


SOURCE = '''unit cycle_a;
{$mode MODE}
{$modeswitch prefixedattributes}
interface
uses SysUtils, Rtti;
type MarkAttribute=class(TCustomAttribute)
  Tag:Integer;
  constructor Create(V:Integer);
end;
[Mark(37)] TMarked=class end;
function Value:Integer;
function Exercise:Integer;
implementation
uses cycle_b;
constructor MarkAttribute.Create(V:Integer); begin inherited Create; Tag:=V; end;
function Value:Integer; begin Result:=VALUE; end;
function Exercise:Integer;
var Item:TBox<Integer>; Context:TRttiContext; Attributes:TArray<TCustomAttribute>;
begin
  Item:=TBox<Integer>.Create;
  try Result:=Item.ReadValue; finally Item.Free; end;
  Context:=TRttiContext.Create;
  try
    Attributes:=Context.GetType(TypeInfo(TMarked)).GetAttributes;
    if (Length(Attributes)<>1) or (MarkAttribute(Attributes[0]).Tag<>37) then Halt(21);
  finally Context.Free; end;
  EXTRA
end;
end.
'''

GENERIC = '''unit cycle_b;
{$mode delphi}
interface
uses cycle_a;
type TBox<T>=class
  function ReadValue:Integer;
end;
implementation
function TBox<T>.ReadValue:Integer; begin Result:=Value; end;
end.
'''

EXTRA = '''
  var Count:=0;
  lock do Inc(Count);
  var Pending:=async Value;
  if await Pending<>Value then Halt(22);
  for parallel(2) var I:=1 to 8 do InterlockedIncrement(Count);
  if Count<>9 then Halt(23);
'''


def check_reload_cycles(command, output, run):
    output.mkdir()
    for mode in ('delphi', 'unleashed'):
        case = output / mode
        case.mkdir()
        source = case / 'cycle_a.pas'
        generic = case / 'cycle_b.pas'
        generic.write_text(GENERIC)
        os.utime(generic, (1700000000, 1700000000))
        options = command + ['-Fu'+str(case), '-FU'+str(case), '-FE'+str(case)]
        for phase, value in enumerate((7, 8, 7)):
            source.write_text(SOURCE.replace('MODE', mode).replace('VALUE', str(value))
                              .replace('EXTRA', EXTRA if mode == 'unleashed' else ''))
            os.utime(source, (1700000000+4*phase, 1700000000+4*phase))
            main = case / 'main.dpr'
            main.write_text('program main; uses {$ifdef unix}cthreads,{$endif}cycle_a,cycle_b; begin '
                            f'if Exercise<>{value} then Halt(20); WriteLn("CYCLE_OK"); end.'.replace('"', "'"))
            log = run(options+[str(main)], case, case/f'{phase}-build.log')
            if phase:
                assert log.lower().count('parsing interface of unit cycle_a') >= 2, \
                    'Fixture must actually discard and reparse the attributed source module'
            executable = main.with_suffix('.exe' if os.name == 'nt' else '')
            assert run([str(executable)], case, case/f'{phase}-run.log').strip() == 'CYCLE_OK'
            # A genuinely unchanged PPU-only consumer must remain usable too.
            warm = run(options+[str(main)], case, case/f'{phase}-warm.log')
            assert 'parsing interface of unit cycle_' not in warm.lower(), 'Warm consumer rebuilt a fixture unit'
            assert run([str(executable)], case, case/f'{phase}-warm-run.log').strip() == 'CYCLE_OK'
