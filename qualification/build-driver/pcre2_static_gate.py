"""Check installed regex linkage and absence of the engine in an unrelated program."""
from pathlib import Path
import re
import subprocess


def static_regex(fpc: Path, objdump: str, work: Path) -> None:
    folder = work / 'static-regex'
    folder.mkdir()
    imports = {}
    sizes = {}
    for enabled in (False, True):
        name = 'regex' if enabled else 'plain'
        out = folder / name
        out.mkdir()
        source = out / 'probe.dpr'
        source.write_text('program probe;\nuses SysUtils' +
                          (', System.RegularExpressions' if enabled else '') + ';\nbegin\n' +
                          ("  If not TRegEx.IsMatch('abc123', '^abc\\d+$') then Halt(1);\n" if enabled else '') +
                          "  Writeln('STATIC_REGEX_PASS');\nend.\n", encoding='utf-8')
        exe = out / ('probe.exe' if fpc.suffix == '.exe' else 'probe')
        for command in ([str(fpc), '-dRELEASE', '-Xm', f'-FU{out}', f'-FE{out}', str(source)], [str(exe)]):
            result = subprocess.run(command, cwd=out, capture_output=True, text=True,
                                    encoding='utf-8', errors='replace', timeout=30)
            (out / ('compile.log' if len(command) > 1 else 'run.log')).write_text(
                result.stdout + result.stderr, encoding='utf-8')
            if result.returncode or (len(command) == 1 and result.stdout.strip() != 'STATIC_REGEX_PASS'):
                raise RuntimeError(f'Static regex probe failed: {command}\n{result.stdout}{result.stderr}')
        image = subprocess.check_output([objdump, '-p', str(exe)], text=True, encoding='utf-8', errors='replace')
        imports[name] = set(re.findall(r'(?:DLL Name:|NEEDED)\s+(\S+)', image))
        sizes[name] = exe.stat().st_size
        maps = list(out.glob('*.map'))
        if len(maps) != 1 or ('moon_pcre_pcre2_compile_16' in maps[0].read_text(errors='replace')) != enabled:
            raise RuntimeError(f'Incorrect static engine inclusion in {name}')
    added = imports['regex'] - imports['plain']
    if any(re.search(r'pcre|libgcc|libstdc|msvcrt|ucrt', name, re.I) for name in added):
        raise RuntimeError(f'Unexpected external regex dependency: {sorted(added)}')
    print(f'STATIC REGEX: PASS (plain={sizes["plain"]} bytes, regex={sizes["regex"]} bytes; '
          f'added imports={sorted(added)})')
