"""Distinct uses-clause spellings bind one dependency, including generic PPUs."""
from pathlib import Path
import os
import subprocess


def multiple_alias_scope(command: list[str], work: Path) -> None:
    case = work / 'multiple-aliases'
    case.mkdir()
    common = command + [f'-Fu{case}', f'-FU{case}', f'-FE{case}']
    args = common + ['-UaOne=physical', '-UaTwo=physical', '-UaThree=physical',
                      '-UaSpec.One=physical', '-UaSpec.Two=physical']

    def build(source: Path, success=True, error='Duplicate identifier', options=None):
        invocation = args if options is None else common + options
        result = subprocess.run(invocation + [str(source)], cwd=case, capture_output=True,
                                text=True, errors='replace', timeout=30)
        text = result.stdout + result.stderr
        source.with_suffix('.log').write_text(text)
        if success != (result.returncode == 0):
            raise RuntimeError(f'{source.name}: unexpected build result\n{text[-2500:]}')
        if not success and error not in text:
            raise RuntimeError(f'{source.name}: wrong rejection\n{text[-2500:]}')

    def execute(source: Path):
        result = subprocess.run([str(source.with_suffix('.exe' if os.name == 'nt' else ''))],
                                cwd=case, capture_output=True, text=True, timeout=10)
        if result.returncode or result.stdout.strip() != 'MULTIPLE_ALIAS_OK':
            raise RuntimeError(f'{source.name}: {result.returncode} {result.stdout} {result.stderr}')

    physical = case / 'physical.pas'
    physical.write_text('''unit physical;
interface
type TPayload = record Value: Integer; end;
const Marker = 42;
var InitCount: Integer;
implementation
initialization Inc(InitCount);
finalization If InitCount <> 1 then Halt(9);
end.
''')
    (case / 'other.pas').write_text(
        'unit other; interface const Marker = 11; implementation end.\n')
    for index, (units, expected) in enumerate([
            ('One, Two', 42), ('Two, One', 42), ('One, physical', 42),
            ('physical, Two', 42), ('Spec.One, Spec.Two', 42),
            ('Spec.Two, Two', 42), ('One, other, Two', 11), ('other, Two, One', 42)]):
        first = next(name.strip() for name in units.split(',') if name.strip() != 'other')
        last = units.split(',')[-1].strip()
        source = case / f'alias_{index}.dpr'
        source.write_text(f'''program alias_{index};
uses {units};
var P: {first}.TPayload;
begin
  P.Value := {last}.Marker;
  If (P.Value <> 42) or (Marker <> {expected}) or ({last}.InitCount <> 1) then Halt(1);
  Writeln('MULTIPLE_ALIAS_OK');
end.
''')
        build(source)
        execute(source)
    # The first physical occurrence determines precedence, as with Delphi's
    # unit aliases. Repeating a qualifier is still a source error.
    for index, units in enumerate(('One, One', 'One, Two, two', 'physical, physical')):
        source = case / f'duplicate_{index}.dpr'
        source.write_text(f'program duplicate_{index}; uses {units}; begin end.\n')
        build(source, False)
    generic = case / 'alias_generic.pas'
    generic.write_text('''unit alias_generic;
interface
uses One, Two, other;
type TAliasValue<T> = record
  function Read(const Value: One.TPayload): Integer;
end;
implementation
uses Three, Spec.Two;
function TAliasValue<T>.Read(const Value: One.TPayload): Integer;
begin Result := Value.Value + Two.Marker + Three.Marker + Spec.Two.Marker; end;
end.
''')
    build(generic)
    source = case / 'generic_consumer.dpr'
    source.write_text('''program generic_consumer;
uses alias_generic, physical;
var G: TAliasValue<Integer>; P: physical.TPayload;
begin
  P.Value := 7;
  If (G.Read(P) <> 133) or (InitCount <> 1) then Halt(2);
  Writeln('MULTIPLE_ALIAS_OK');
end.
''')
    # Prove the qualified names survive the PPU; source recompilation cannot
    # silently make the test pass.
    for path in (physical, generic):
        path.rename(path.with_suffix('.hidden'))
    try:
        build(source)
        execute(source)
        # The library's physical bindings belong to its PPU, not the caller's
        # alias options. The alternative target is itself a library dependency.
        for index, options in enumerate(([], ['-UaOne=other', '-UaTwo=other',
                '-UaThree=other', '-UaSpec.One=other', '-UaSpec.Two=other'])):
            consumer = case / f'consumer_options_{index}.dpr'
            consumer.write_text(source.read_text())
            build(consumer, options=options)
            execute(consumer)
    finally:
        for path in (physical, generic):
            path.with_suffix('.hidden').rename(path)
    private = case / 'private_generic.pas'
    private.write_text('''unit private_generic;
interface
type TPrivate<T> = record function Read: Integer; end;
implementation
var Secret: Integer;
function TPrivate<T>.Read: Integer;
begin Result := Secret; end;
end.
''')
    build(private, False, 'Generic template in interface section references symbol in implementation section')
    # A namespace lookup must not make another unit's implementation public.
    (case / 'private_unit.pas').write_text('''unit private_unit;
interface const PublicValue = 7;
implementation var Secret: Integer;
end.
''')
    leak = case / 'private_leak.dpr'
    leak.write_text('program private_leak; uses private_unit; begin Writeln(private_unit.Secret); end.\n')
    build(leak, False, 'Identifier not found')
    self_use = case / 'self_use.pas'
    self_use.write_text('unit self_use; interface uses self_use; implementation end.\n')
    build(self_use, False)
    # Variants is added implicitly after the uses clause; serializing its unit
    # binding must include that late dependency in the owning unit map.
    late = case / 'late_variant.pas'
    late.write_text('''unit late_variant;
interface function Value: Integer;
implementation
function Value: Integer;
var V: Variant;
begin V := 42; Result := V; end;
end.
''')
    build(late)
    late.rename(late.with_suffix('.hidden'))
    consumer = case / 'late_consumer.dpr'
    consumer.write_text("program late_consumer; uses late_variant; begin "
                        "If Value <> 42 then Halt(1); Writeln('MULTIPLE_ALIAS_OK'); end.\n")
    build(consumer)
    execute(consumer)
    namespace_alias_scope(command, work)
    print('MULTIPLE_ALIAS_GATE_PASS')


def namespace_alias_scope(command: list[str], work: Path) -> None:
    case = work / 'namespace-aliases'
    case.mkdir()
    (case / 'Spec.physical.pas').write_text(
        'unit Spec.physical; interface const Marker=42; implementation end.\n')
    (case / 'other.pas').write_text('unit other; interface const Marker=17; implementation end.\n')
    clause = case / 'clause.pas'
    clause.write_text('''unit clause;
interface uses One, other;
function Value: Integer;
implementation uses Two;
function Value: Integer; begin Result := Marker; end;
end.
''')
    args = command + [f'-Fu{case}', f'-FU{case}', f'-FE{case}',
                      '-FNSpec', '-UaOne=physical', '-UaTwo=physical']
    duplicate = case / 'namespace_duplicate.pas'
    duplicate.write_text('unit namespace_duplicate; interface uses One,other; '
                         'implementation uses One; end.\n')
    result = subprocess.run(args + [str(duplicate)], cwd=case, capture_output=True, text=True, timeout=30)
    if result.returncode == 0 or 'Duplicate identifier' not in result.stdout + result.stderr:
        raise RuntimeError('Namespace expansion concealed a duplicate uses qualifier')
    for phase in ('source', 'ppu'):
        main = case / (phase + '.dpr')
        main.write_text('program probe; uses clause; begin If Value <> 17 then Halt(1); end.\n')
        result = subprocess.run(args + [str(main)], cwd=case, capture_output=True, text=True, timeout=30)
        (case / (phase + '.log')).write_text(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError('Namespaced aliases: ' + result.stdout + result.stderr)
        result = subprocess.run([str(main.with_suffix('.exe' if os.name == 'nt' else ''))],
                                cwd=case, capture_output=True, text=True, timeout=10)
        if result.returncode:
            raise RuntimeError('A second alias changed unqualified lookup precedence')
        if phase == 'source':
            for source in case.glob('*.pas'):
                source.rename(source.with_suffix('.hidden'))
