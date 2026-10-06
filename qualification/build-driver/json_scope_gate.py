"""Private JSON dependencies must not capture a consumer's ordinary unit names."""
from pathlib import Path
import subprocess


def json_scope(fpc: Path, work: Path) -> None:
    root = work / 'json'
    root.mkdir()
    names = ('JsonReader', 'JsonScanner', 'fpjson')
    for placement in ('program', 'search-path'):
        folder = root / placement
        folder.mkdir()
        units = folder if placement == 'program' else folder / 'own'
        units.mkdir(exist_ok=True)
        for index, name in enumerate(names):
            (units / (name.lower() + '.pas')).write_text(
                f'unit {name}; interface const ProjectMarker = {index + 41}; implementation end.\n',
                encoding='utf-8')
        for reverse in (False, True):
            for release in (False, True):
                out = folder / f'{int(reverse)}-{int(release)}'
                out.mkdir()
                used = ['System.JSON', 'System.JSON.Readers', *names]
                if reverse:
                    used.reverse()
                probe = folder / 'json_scope.dpr'
                probe.write_text('program json_scope;\nuses ' + ', '.join(used) + ''';
var Value: TJSONValue;
begin
  If (JsonReader.ProjectMarker <> 41) or (JsonScanner.ProjectMarker <> 42) or
    (fpjson.ProjectMarker <> 43) then Halt(1);
  Value := TJSONObject.ParseJSONValue('{"a":[1,true,"text"]}');
  try
    If (Value = nil) or (Value.ToJSON <> '{"a":[1,true,"text"]}') then Halt(2);
  finally
    Value.Free;
  end;
  Writeln('JSON_SCOPE_PASS');
end.
''', encoding='utf-8')
                command = [str(fpc), '-B', f'-Fu{units}', f'-FU{out}', f'-FE{out}']
                if release:
                    command.append('-dRELEASE')
                # Only installed PPUs can satisfy System.JSON: no package source paths.
                for invocation in (command + [str(probe)],
                                   [str(out / ('json_scope.exe' if fpc.suffix == '.exe' else 'json_scope'))]):
                    result = subprocess.run(invocation, cwd=folder, capture_output=True, text=True,
                                            encoding='utf-8', errors='replace', timeout=30)
                    (out / ('compile.log' if len(invocation) > 1 else 'run.log')).write_text(
                        result.stdout + result.stderr, encoding='utf-8')
                    if result.returncode or (len(invocation) == 1 and result.stdout.strip() != 'JSON_SCOPE_PASS'):
                        raise RuntimeError(f'JSON namespace contract failed: {invocation}\n{result.stdout}{result.stderr}')
    print('JSON SCOPE: PASS (three project unit names, both uses orders, two paths, Debug/Release, installed PPUs)')
