#!/usr/bin/env python3
"""negative_controls.py - RTL-test/semantic/dictionary_flat_semantic.dpr must fail
against a sabotaged dictionary.

Each variant copies packages/rtl-generics/src, plants one deliberate defect in
inc/generics.dictionaries.inc, compiles the semantic test against the copy
(o2, the RTL-test options) and requires that the PASS marker is absent and
that the failing check names the section meant to catch the defect.  A test
that stays green here proves nothing.

    python negative_controls.py            # all variants
    python negative_controls.py crc-hash   # one variant
"""
import importlib.util
import re
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
SRC = ROOT / 'packages' / 'rtl-generics' / 'src'
spec = importlib.util.spec_from_file_location('rtlrun', ROOT / 'RTL-test' / 'run.py')
rtlrun = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rtlrun)
STEM = 'dictionary_flat_semantic'
SOURCE = rtlrun.SEMANTIC / (STEM + '.dpr')
IMPL = 'inc/generics.dictionaries.inc'

# name: (edits as (regex, replacement), substrings one of which the failing
# check must contain - the first section of the test that trips)
VARIANTS = {
    # the hash of the default comparer (CRC of the key bytes) for ordinals and pointers
    'crc-hash': ([
        (r"    case SizeOf\(TKey\) of\r?\n      1, 2, 4:\r?\n        begin\r?\n          case SizeOf\(TKey\) of",
         "    if GetTypeKind(TKey) <> tkClass then\r\n    begin\r\n"
         "      Result := THashFactory.GetHashCode(@AKey, SizeOf(TKey), 0);\r\n      Exit;\r\n    end;\r\n"
         "    case SizeOf(TKey) of\r\n      1, 2, 4:\r\n        begin\r\n          case SizeOf(TKey) of"),
    ], ('cluster cost',)),
    # notifications always on: the flag never clears
    'notify-always': ([
        (r"  FNotify := FNotifyOverride or Assigned\(FOnKeyNotify\) or Assigned\(FOnValueNotify\);",
         "  FNotify := True;"),
    ], ('inactive',)),
    # override detection lost: a descendant's KeyNotify/ValueNotify are skipped
    'notify-never': ([
        (r"  FNotify := FNotifyOverride or Assigned\(FOnKeyNotify\) or Assigned\(FOnValueNotify\);",
         "  FNotify := Assigned(FOnKeyNotify) or Assigned(FOnValueNotify);"),
    ], ('without a handler', 'owned key')),
    # flat detection lost: everything on the comparer path
    'never-flat': ([
        (r"  FFlat := FlatKind and\r?\n    \(Pointer\(FEqualityComparer\) = Pointer\(TEqualityComparer<TKey>.Default\(THashFactory\)\)\);",
         "  FFlat := False;"),
    ], ('Flat',)),
    # the flat lookup trusts the stored hash and never compares the key
    'flat-equals-broken': ([
        (r"      4: Result := PCardinal\(@ALeft\)\^ = PCardinal\(@ARight\)\^;", "      4: Result := True;"),
        (r"          Result := PQWord\(@ALeft\)\^ = PQWord\(@ARight\)\^;", "          Result := True;"),
    ], ('collid',)),
    # the SetValue fast path drops the assignment (reachable through a base-class reference)
    'setvalue-lost': ([
        (r"  if not FNotify then\r?\n  begin\r?\n    AValue := ANewValue;\r?\n    Exit;\r?\n  end;",
         "  if not FNotify then\r\n    Exit;"),
    ], ('base update', 'last value wins')),
    # object keys hashed and compared by address only: an overridden Equals/GetHashCode is ignored
    'object-identity': ([
        (r"      if \(GetTypeKind\(TKey\) = tkClass\) and \(LWide <> 0\) and",
         "      if False and"),
        (r"          if \(GetTypeKind\(TKey\) = tkClass\) and not Result and",
         "          if False and"),
    ], ('equal instance',)),
    # the reservation of Create(N) lost again: the load factor set after the inherited constructor
    'capacity-lost': ([
        (r"  FMaxLoadFactor := TProbeSequence.DEFAULT_LOAD_FACTOR;\r?\n  inherited Create\(ACapacity, AComparer\);",
         "  inherited Create(ACapacity, AComparer);\r\n  FMaxLoadFactor := TProbeSequence.DEFAULT_LOAD_FACTOR;"),
    ], ('without a rehash',)),
    # Capacity back to a slot count: N items no longer fit
    'capacity-slots': ([
        (r"    while \(Round\(LSize \* LFactor\) < ACapacity\) and \(LSize < \$40000000\) do",
         "    while LSize < ACapacity do"),
    ], ('without a rehash', 'reserves room')),
    # ExtractPair of a missing key loses the key
    'extract-default-key': ([
        (r"  Result.Key := AKey;\r?\n  if LIndex < 0 then\r?\n    Result.Value := Default\(TValue\)",
         "  Result.Key := AKey;\r\n  if LIndex < 0 then\r\n    Exit(Default(TPair<TKey, TValue>))"),
    ], ('requested key',)),
    # the copy constructor raises on a repeated key instead of merging
    'copy-add': ([
        (r"  Create\(AComparer\);\r?\n  for LItem in ACollection do\r?\n    AddOrSetPair\(LItem\);",
         "  Create(AComparer);\r\n  for LItem in ACollection do\r\n    Add(LItem);"),
    ], ('Duplicates',)),
    # a nil comparer stored as is (crash on first use in the base, a lost flat path here)
    'nil-comparer': ([
        (r"  if AComparer = nil then\r?\n    FEqualityComparer := TEqualityComparer<TKey>.Default\(THashFactory\)\r?\n  else\r?\n    FEqualityComparer := AComparer;",
         "  FEqualityComparer := AComparer;"),
    ], ('nil comparer',)),
}


def main() -> int:
    compiler, config, target, suffix = rtlrun.toolchain()
    only = sys.argv[1:] or list(VARIANTS)
    failures = 0
    for name in only:
        edits, expect = VARIANTS[name]
        work = Path(tempfile.mkdtemp(prefix='negctl-', dir=ROOT ))
        try:
            copy = work / 'generics'
            shutil.copytree(SRC, copy)
            path = copy / IMPL
            text = path.read_text(encoding='ascii')
            for pattern, replacement in edits:
                text, count = re.subn(pattern, lambda m: replacement, text, count=1)
                if count != 1:
                    raise RuntimeError(f'{name}: the source no longer matches {pattern!r}')
            path.write_text(text, encoding='ascii', newline='')
            output = work / 'out'
            output.mkdir()
            command = [
                str(compiler), '-n', f'@{config}', *rtlrun.LANGUAGE, *target, '-Rintel',
                '-dMOONBOT_MM_PROFILE_REQUIRED', '-dFPCMM_BOOSTER', '-dFPCMM_MOONSHARD',
                f'--pinned-unit=mormot.core.fpcx64mm={rtlrun.MM}',
                '--required-first-unit=mormot.core.fpcx64mm',
                *rtlrun.NAMESPACES,
                f'-Fu{rtlrun.SEMANTIC}', f'-Fi{rtlrun.SEMANTIC}',
                f'-Fu{copy}', f'-Fi{copy / "inc"}',
                f'-FU{output}', f'-FE{output}', *rtlrun.MODES['o2'],
                str(SOURCE),
            ]
            compiled = rtlrun.execute(command, copy)
            if compiled.returncode != 0:
                print(compiled.stdout[-3000:])
                print(f'{name}: COMPILE FAILED')
                failures += 1
                continue
            if 'generics.collections.pas' not in compiled.stdout:
                print(f'{name}: the sabotaged copy was not compiled')
                failures += 1
                continue
            run = rtlrun.execute([str(output / f'{STEM}{suffix}')])
            tail = run.stdout.strip().splitlines()[-1] if run.stdout.strip() else ''
            if 'DICTIONARY_FLAT_PASS' in run.stdout:
                print(f'{name}: FALSE GREEN - the test passed against the sabotaged dictionary')
                failures += 1
            elif not any(e.lower() in tail.lower() for e in expect):
                print(f'{name}: failed elsewhere: {tail}')
                failures += 1
            else:
                print(f'{name}: caught -> {tail}')
        finally:
            shutil.rmtree(work, ignore_errors=True)
    print('NEGATIVE_CONTROLS', 'OK' if failures == 0 else f'FAILURES={failures}')
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
