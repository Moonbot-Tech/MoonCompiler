"""Win64 Delphi unit spellings share the installed API units and their types.

Called by unit_scope_gate with the plain product fpc, also for release archives.
The public list is the Delphi 12.2 Winapi headers implemented by rtl,
rtl-extra and winunits-base, not all of Delphi's Windows API.
"""

from pathlib import Path
import subprocess


UNITS = (
    'Windows', 'Messages', 'WinSock', 'WinSock2', 'ActiveX', 'CommCtrl', 'CommDlg',
    'DwmApi', 'FlatSB', 'ImageHlp', 'Imm', 'MMSystem', 'MultiMon', 'Nb30', 'Ole2',
    'RichEdit', 'ShellAPI', 'SHFolder', 'ShlObj', 'ShLwApi', 'UrlMon', 'UxTheme',
    'WinHTTP', 'WinInet', 'WinSpool', 'AccCtrl', 'AclAPI', 'Cpl', 'Dlgs', 'IpExport',
    'IpHlpApi', 'IpRtrMib', 'IpTypes', 'PsAPI', 'Qos', 'RegStr', 'TlHelp32',
    'UserEnv', 'WinCred', 'Winsafer', 'WinSvc', 'WTSApi32',
)
PROBE = Path(__file__).with_name('winapi_scope_probe.dpr')
PLAIN = '''unit winapi_plain;
interface
uses %s;
procedure ChangeTime(var Time: Winapi.Windows.TFileTime);
procedure ChangeMessage(var Message: Winapi.Messages.TMessage);
procedure ChangeStatus(var Status: Winapi.WinSvc.TServiceStatus);
procedure ChangeCounters(var Counters: Winapi.PsAPI.TProcessMemoryCounters);
procedure ChangeThread(var Thread: Winapi.TlHelp32.TThreadEntry32);
implementation
procedure ChangeTime(var Time: Winapi.Windows.TFileTime); begin Time.dwLowDateTime := 37; end;
procedure ChangeMessage(var Message: Winapi.Messages.TMessage); begin Message.Msg := WM_USER + 17; end;
procedure ChangeStatus(var Status: Winapi.WinSvc.TServiceStatus); begin Status.dwCurrentState := 7; end;
procedure ChangeCounters(var Counters: Winapi.PsAPI.TProcessMemoryCounters); begin Counters.cb := SizeOf(Counters); end;
procedure ChangeThread(var Thread: Winapi.TlHelp32.TThreadEntry32); begin Thread.dwSize := SizeOf(Thread); end;
end.
'''
GENERIC = '''unit winapi_generic;
interface
uses PsAPI;
type TApiValue<T> = record
  Value: T;
  function CounterSize(const Counters: Winapi.PsAPI.TProcessMemoryCounters): Longword;
end;
implementation
function TApiValue<T>.CounterSize(const Counters: Winapi.PsAPI.TProcessMemoryCounters): Longword;
begin Result := Counters.cb; end;
end.
'''


def checked(command: list[str], work: Path, marker: str | None = None) -> None:
    result = subprocess.run(command, cwd=work, capture_output=True, text=True,
                            encoding='utf-8', errors='replace', timeout=900)
    output = result.stdout + result.stderr
    if result.returncode or (marker is not None and marker not in output):
        raise RuntimeError(f'Winapi scope: exit {result.returncode}: {command}\n{output[-4000:]}')


def ppu_consumer(args: list[str], probe: Path, work: Path, sources: list[Path]) -> None:
    # Make source recompilation impossible, independently of compiler log spelling.
    for source in sources:
        source.rename(source.with_suffix('.hidden'))
    try:
        checked([*args, str(probe)], work)
    finally:
        for source in sources:
            source.with_suffix('.hidden').rename(source)


def alias_scope(fpc: Path, work: Path) -> None:
    """Reverse aliases bind to the actual module; explicit unit bindings win.

    This synthetic contract runs on both targets, independently of Windows API.
    """
    source = work / 'aliases'
    source.mkdir()
    (source / 'physical.pas').write_text('''unit physical;
interface
type TPayload = record Value: Integer; end;
const Marker = 19;
var InitCount: Integer;
implementation
initialization Inc(InitCount);
end.
''', encoding='utf-8')
    (source / 'alias_generic.pas').write_text('''unit alias_generic;
interface
uses Logical;
type TAliasValue<T> = record
  function ReadValue(const P: Spec.Logical.TPayload): Integer;
end;
implementation
function TAliasValue<T>.ReadValue(const P: Spec.Logical.TPayload): Integer;
begin Result := P.Value + Spec.Logical.Marker; end;
end.
''', encoding='utf-8')
    probe = source / 'alias_probe.dpr'
    probe.write_text('''program alias_probe;
uses physical, alias_generic;
var G: TAliasValue<Integer>; P: Spec.Logical.TPayload;
begin
  P.Value := 23;
  If (G.ReadValue(P) <> 42) or (physical.InitCount <> 1) then Halt(1);
  Writeln('ALIAS_SCOPE_PASS');
end.
''', encoding='utf-8')
    for profile, options in (('debug', []), ('release', ['-dRELEASE'])):
        out = source / profile
        out.mkdir()
        args = [str(fpc), *options, '-UaLogical=physical', '-UaSpec.Logical=physical',
                f'-Fu{source}', f'-FU{out}', f'-FE{out}']
        checked([*args, str(source / 'alias_generic.pas')], out)
        ppu_consumer(args, probe, out, [source / 'alias_generic.pas', source / 'physical.pas'])
        checked([str(out / ('alias_probe.exe' if fpc.suffix == '.exe' else 'alias_probe'))], out,
                'ALIAS_SCOPE_PASS')
    # A configured reverse alias must not hide an explicit project unit,
    # including the namespace/unitsym combination created by a nested unit.
    (source / 'system.sysutils.pas').write_text(
        'unit System.SysUtils;\ninterface\nconst ProjectMarker = 1953;\nimplementation\nend.\n', encoding='utf-8')
    (source / 'system.sysutils.child.pas').write_text(
        'unit System.SysUtils.Child;\ninterface\nimplementation\nend.\n', encoding='utf-8')
    shadow = source / 'alias_shadow.dpr'
    for units in ('System.SysUtils, SysUtils', 'SysUtils, System.SysUtils',
                  'System.SysUtils, System.SysUtils.Child, SysUtils',
                  'SysUtils, System.SysUtils.Child, System.SysUtils'):
        shadow.write_text(f'program alias_shadow;\nuses {units};\nbegin\n'
                          '  If System.SysUtils.ProjectMarker <> 1953 then Halt(1);\n'
                          "  Writeln('ALIAS_SHADOW_PASS');\nend.\n", encoding='utf-8')
        checked([str(fpc), str(shadow)], work)
        checked([str(source / ('alias_shadow.exe' if fpc.suffix == '.exe' else 'alias_shadow'))], work,
                'ALIAS_SHADOW_PASS')
    print('ALIAS SCOPE: PASS (physical identity, qualified name after short alias, generic PPU, '
          'one initialization, project unit priority in both orders and under a namespace)')


def winapi_scope(fpc: Path, work: Path) -> None:
    source = work / 'winapi'
    source.mkdir()
    (source / 'winapi_plain.pas').write_text(PLAIN % ', '.join(UNITS), encoding='utf-8')
    (source / 'winapi_generic.pas').write_text(GENERIC, encoding='utf-8')
    # All qualified spellings are imported through a separate source unit too:
    # its graph and winapi_plain's graph must reach the same physical modules.
    (source / 'winapi_qualified.pas').write_text(
        'unit winapi_qualified;\ninterface\nuses ' + ', '.join('Winapi.' + name for name in UNITS) +
        ';\nimplementation\nend.\n', encoding='utf-8')
    probe = source / PROBE.name
    probe.write_text(PROBE.read_text(encoding='utf-8').replace(
        'winapi_plain, winapi_generic;', 'winapi_plain, winapi_generic, winapi_qualified;'), encoding='utf-8')
    for profile, options in (('debug', []), ('release', ['-dRELEASE'])):
        out = source / profile
        out.mkdir()
        args = [str(fpc), *options, f'-Fu{source}', f'-FU{out}', f'-FE{out}']
        sources = [source / (unit + '.pas') for unit in ('winapi_plain', 'winapi_generic', 'winapi_qualified')]
        for unit in sources:
            checked([*args, str(unit)], out)
        ppu_consumer(args, probe, out, sources)
        checked([str(out / 'winapi_scope_probe.exe')], out, 'WINAPI_SCOPE_PASS')
        services = Path(__file__).with_name('winapi_services_probe.dpr').read_text()
        for spelling in ('Windows', 'Winapi.Windows', 'Windows, Winapi.Windows'):
            stem = 'services_' + str(len(spelling))
            service_probe = source / (stem + '.dpr')
            service_probe.write_text(services.replace('uses Windows;', 'uses ' + spelling + ';'))
            checked([*args, str(service_probe)], out)
            checked([str(out / (stem + '.exe'))], out, 'WINAPI_SERVICES_OK')

    # A configured alias must yield to the project's own qualified source unit.
    own = work / 'winapi-own'
    own.mkdir()
    (own / 'winapi.windows.pas').write_text(
        'unit Winapi.Windows;\ninterface\nconst ProjectMarker = 1952;\nimplementation\nend.\n', encoding='utf-8')
    own_probe = own / 'own.dpr'
    for units in ('Windows, Winapi.Windows', 'Winapi.Windows, Windows'):
        own_probe.write_text(f'program own;\nuses {units};\nbegin\n'
                             '  If Winapi.Windows.ProjectMarker <> 1952 then Halt(1);\n'
                             "  Writeln('WINAPI_OWN_PASS');\nend.\n", encoding='utf-8')
        checked([str(fpc), str(own_probe)], work)
        checked([str(own / 'own.exe')], work, 'WINAPI_OWN_PASS')

    # Explicit aliases in .mooncompiler keep overriding the configured mapping.
    alternate = own / 'alternate.pas'
    alternate.write_text('unit alternate;\ninterface\nconst ProjectMarker = 1954;\nimplementation\nend.\n',
                         encoding='utf-8')
    (own / 'own.mooncompiler').write_text('-UaWinapi.Windows=alternate\n', encoding='utf-8')
    own_probe.write_text(own_probe.read_text(encoding='utf-8').replace(
        'Winapi.Windows, Windows', 'Winapi.Windows').replace('1952', '1954'), encoding='utf-8')
    checked([str(fpc), '-B', str(own_probe)], work)
    checked([str(own / 'own.exe')], work, 'WINAPI_OWN_PASS')

    # Negative control: redirecting Windows to a missing unit must fail the probe.
    result = subprocess.run([str(fpc), '-UaWinapi.Windows=Winapi.MissingGateUnit', str(probe)],
                            cwd=source, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=900)
    if result.returncode == 0 or "Can't find unit Winapi.MissingGateUnit" not in result.stdout:
        raise RuntimeError('Winapi scope negative control did not reject the missing binding')
    print(f'WINAPI SCOPE: PASS ({len(UNITS)} qualified/plain units, Debug/Release, var types, generic PPU, '
          'project unit and project alias)')
