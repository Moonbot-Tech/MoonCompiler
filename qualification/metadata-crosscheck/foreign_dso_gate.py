#!/usr/bin/env python3
"""Foreign ELF TLS, loader lifetime, callback exceptions and native unwinding."""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess

NATIVE = r'''
#include <stdint.h>
#include <stdio.h>
#include <execinfo.h>
static int initialized, before, after;
static __thread long tls_word=739;
__attribute__((constructor)) static void initialize(void) { initialized=271; }
__attribute__((destructor)) static void finalize(void) {
  FILE *f=fopen("native-finalized.marker","w");
  if(f) { fputs("NATIVE_FINAL=271\n",f); fclose(f); }
}
long audit_state(int which) { return which==0?initialized:which==1?before:after; }
long audit_tls(long n) { long previous=tls_word; tls_word=n; return previous; }
__attribute__((noinline)) long audit_enter(long (*callback)(long),long n) {
  volatile long values[31];
  for(int i=0;i<31;i++) values[i]=i+1;
  before=31; after=0;
  long value=callback(n);
  after=97;
  return value+values[0]+values[30];
}
__attribute__((noinline)) long audit_trace(uintptr_t *out,long capacity) {
  return backtrace((void **)out,(int)capacity);
}
'''

HOST = r'''program ForeignGraph;
uses cthreads, SysUtils, Classes, Dynlibs;
type
  TCallback=function(N: Int64): Int64; cdecl;
  TEnter=function(Callback: TCallback; N: Int64): Int64; cdecl;
  TState=function(Index: Integer): Int64; cdecl;
  TTls=function(N: Int64): Int64; cdecl;
  TTrace=function(Buffer: Pointer; Capacity: Int64): Int64; cdecl;
  IToken=interface ['{1C10A40C-2A11-4AE2-A43F-9AF494B632D5}'] end;
  TToken=class(TInterfacedObject,IToken) destructor Destroy; override; end;
var EnterNative: TEnter; StateNative: TState; TlsNative: TTls; TraceNative: TTrace;
  ThrowNow: Boolean; Destroyed, HostFinalized: Integer;
procedure Check(B: Boolean; const Why: UnicodeString);
begin If not B then raise Exception.Create('FOREIGN: '+Why); end;
destructor TToken.Destroy; begin Inc(Destroyed); inherited; end;
function Callback(N: Int64): Int64; cdecl; public name 'AuditPascalCallback';
var Token: IToken; PCs: array[0..63] of PtrUInt; Count: Int64;
begin
  Token:=TToken.Create;
  Check(StateNative(1)=31,'native before callback');
  If ThrowNow then raise Exception.Create('foreign-pascal-'+IntToStr(N));
  Count:=TraceNative(@PCs[0],Length(PCs)); Check(Count>=4,'native unwind depth');
  for var I:=0 to Count-1 do Writeln('PC=',HexStr(PCs[I],16));
  Result:=N+41;
end;
procedure HostAnchor; public name 'AuditHostAnchor';
var S: UnicodeString;
begin
  S:='host alive';
  try
    Check(EnterNative(Callback,23)=96,'foreign callback result');
    Check(StateNative(2)=97,'native after callback');
  finally
    Check(S='host alive','host managed cleanup'); Inc(HostFinalized);
  end;
end;
type TTlsWorker=class(TThread)
  Error: UnicodeString;
  procedure Execute; override;
end;
procedure TTlsWorker.Execute;
begin
  try
    Check(TlsNative(101)=739,'native new-thread TLS initial');
    Check(TlsNative(103)=101,'native new-thread TLS store');
  except on E: Exception do Error:=E.Message; end;
end;
var LibraryHandle: TLibHandle; Thread: TTlsWorker;
begin
  LibraryHandle:=LoadLibrary('./libForeignGraph.so'); Check(LibraryHandle<>NilHandle,'native DSO load');
  EnterNative:=TEnter(GetProcedureAddress(LibraryHandle,'audit_enter'));
  StateNative:=TState(GetProcedureAddress(LibraryHandle,'audit_state'));
  TlsNative:=TTls(GetProcedureAddress(LibraryHandle,'audit_tls'));
  TraceNative:=TTrace(GetProcedureAddress(LibraryHandle,'audit_trace'));
  Check(Assigned(EnterNative) and Assigned(StateNative) and Assigned(TlsNative) and Assigned(TraceNative),'native exports');
  Check(StateNative(0)=271,'native constructor');
  Check(TlsNative(571)=739,'native main TLS initial');
  Thread:=TTlsWorker.Create(True); Thread.Start; Thread.WaitFor;
  Check(Thread.Error='','native TLS thread '+Thread.Error); Thread.Free;
  Check(TlsNative(577)=571,'native main TLS survives thread');
  Writeln('ANCHOR=',HexStr(PtrUInt(@HostAnchor),16));
  Writeln('C_ENTER=',HexStr(PtrUInt(GetProcedureAddress(LibraryHandle,'audit_enter')),16));
  Writeln('C_TRACE=',HexStr(PtrUInt(GetProcedureAddress(LibraryHandle,'audit_trace')),16));
  HostAnchor; ThrowNow:=True;
  try
    HostAnchor; Check(False,'exception swallowed');
  except on E: Exception do Check(E.Message='foreign-pascal-23','foreign exception payload'); end;
  Check((StateNative(1)=31) and (StateNative(2)=0),'foreign exception skips normal continuation');
  Check((Destroyed=2) and (HostFinalized=2),'foreign exception cleanup counts');
  Check(UnloadLibrary(LibraryHandle),'native DSO unload');
  Check(FileExists('native-finalized.marker'),'native DSO finalization on unload');
  Writeln('FOREIGN_PASS=2/2');
end.
'''

PLUGIN = r'''unit PluginState;
interface
uses {$IFDEF UNIX} ffi.manager, {$ENDIF} SysUtils, TypInfo, Rtti;
type
  TMarkAttribute=class(TCustomAttribute)
    Code: Integer;
    constructor Create(N: Integer);
  end;
  TGeneric<T>=class
  public class function Value(N: Integer): Integer; static;
  end;
  [TMark(337)]
  TBeacon=class
  public function Value(N: Integer): Integer;
  end;
  IToken=interface ['{7833D5F5-252C-402F-99E1-876EA2D4D20C}'] end;
  TToken=class(TInterfacedObject,IToken) destructor Destroy; override; end;
function RunPlugin: Integer; cdecl;
implementation
var Held: IToken; Text: UnicodeString; Destroyed, Calls: Integer;
constructor TMarkAttribute.Create(N: Integer); begin Code:=N; end;
class function TGeneric<T>.Value(N: Integer): Integer; begin Result:=N*13+7; end;
function TBeacon.Value(N: Integer): Integer; begin Result:=TGeneric<Integer>.Value(N); end;
destructor TToken.Destroy; begin Inc(Destroyed); inherited; end;
function RunPlugin: Integer; cdecl;
var C: TRttiContext; R: TRttiType; O: TBeacon; Matches: Integer;
begin
  Result:=-1; If (Text<>'plugin managed') or (Held=nil) then Exit;
  C:=TRttiContext.Create;
  try
    R:=C.GetType(TBeacon.ClassInfo); Result:=-2;
    If (Length(R.GetAttributes)<>1) or not(R.GetAttributes[0] is TMarkAttribute) then Exit;
    Result:=-3; If TMarkAttribute(R.GetAttributes[0]).Code<>337 then Exit;
    Matches:=0; for var T in C.GetTypes do If T.Handle=TBeacon.ClassInfo then Inc(Matches);
    Result:=-100-Matches; If Matches<>1 then Exit;
    O:=TBeacon.Create;
    try Result:=R.GetMethod('Value').Invoke(O,[Integer(31)]).AsInteger;
    finally O.Free; end;
    Inc(Calls);
  finally C.Free; end;
end;
initialization
  Held:=TToken.Create; Text:='plugin managed';
finalization
  Held:=nil; Text:='';
  If (Destroyed<>1) or (Calls<>2) then Halt(92);
  Writeln('PASCAL_PLUGIN_FINAL=1/2');
end.
'''

LOADER = r'''program PascalGraphLoader;
uses {$IFDEF UNIX} cthreads, {$ENDIF} SysUtils,Dynlibs;
type TRun=function: Integer; cdecl;
var Handle: TLibHandle; Run: TRun; Got: Integer;
begin
  Handle:=LoadLibrary({$IFDEF UNIX}'./libPascalGraphPlugin.so'{$ELSE}'PascalGraphPlugin.dll'{$ENDIF});
  If Handle=NilHandle then Halt(1);
  Run:=TRun(GetProcedureAddress(Handle,'RunPlugin'));
  If not Assigned(Run) then Halt(2);
  for var J:=1 to 2 do begin Got:=Run(); If Got<>410 then begin Writeln('PLUGIN_BAD=',Got); Halt(3); end; end;
  If not UnloadLibrary(Handle) then Halt(4);
  Writeln('PASCAL_DSO_PASS=1/2');
end.
'''

def main():
    ap=argparse.ArgumentParser(__doc__); ap.add_argument('--compiler',type=Path,required=True); ap.add_argument('--results',type=Path,required=True); ap.add_argument('--mode',action='append')
    a=ap.parse_args(); cc=a.compiler.resolve(); out=a.results.resolve(); out.mkdir(parents=True,exist_ok=False)
    win=os.name=='nt'; rows=[]
    matrix=[('release',['-dRELEASE']),('debug',[])]
    if not win:
      matrix += [('full-dwarf',['-dRELEASE','-goNODWARFLINETABLESONLY']),
                 ('external',['-dRELEASE','-Aas']),('pie',['-dRELEASE','-Cg','-k-pie'])]
    if a.mode: matrix=[v for v in matrix if v[0] in a.mode]
    assert matrix,'no selected modes'
    for label,flags in matrix:
      work=out/label; work.mkdir()
      def run(cmd,name):
        p=subprocess.run([str(x) for x in cmd],cwd=work,capture_output=True,text=True,timeout=60)
        (work/name).write_text(p.stdout+p.stderr)
        assert p.returncode==0,(label,name,p.returncode,(p.stdout+p.stderr)[-3500:])
        return p.stdout
      common=[cc,*flags,'-Xs-','-FU.','-FE.']
      row=dict(mode=label,flags=flags)
      if not win:
        (work/'native.c').write_text(NATIVE); (work/'ForeignGraph.dpr').write_text(HOST)
        run(['gcc','-O2','-fPIC','-shared','-fexceptions','-fasynchronous-unwind-tables','-ffunction-sections','-fdata-sections','-Wl,--gc-sections','native.c','-o','libForeignGraph.so'],'native-build.log')
        run(common+['ForeignGraph.dpr'],'host-build.log')
        runtime=run([work/'ForeignGraph'],'native-runtime.log')
        assert runtime.endswith('FOREIGN_PASS=2/2\n'),runtime
        assert (work/'native-finalized.marker').read_text()=='NATIVE_FINAL=271\n'
        nm=run(['nm','--defined-only',work/'ForeignGraph'],'symbols.log')
        symbols=[(int(addr,16),name) for addr,name in re.findall(r'^([0-9a-f]+) [TtWw] (.+)$',nm,re.M)]
        exports={name:int(base,16) for base,name in re.findall(
          r'^([0-9a-f]+) [Tt] (AuditHostAnchor|AuditPascalCallback)$',nm,re.M)}
        spans={name:(base,min(addr for addr,_ in symbols if addr>base)-base) for name,base in exports.items()}
        assert len(spans)==2,spans
        slide=int(re.search(r'^ANCHOR=([0-9A-F]+)$',runtime,re.M)[1],16)-spans['AuditHostAnchor'][0]
        spans={name:(base+slide,size) for name,(base,size) in spans.items()}
        native=run(['nm','-D','-S','--defined-only',work/'libForeignGraph.so'],'native-symbols.log')
        for name,frame_label in [('audit_enter','C_ENTER'),('audit_trace','C_TRACE')]:
          size=int(re.search(r'^[0-9a-f]+ ([0-9a-f]+) T '+name+'$',native,re.M)[1],16)
          base=int(re.search(r'^'+frame_label+r'=([0-9A-F]+)$',runtime,re.M)[1],16)
          spans[name]=(base,size)
        assert all(size>0 for _,size in spans.values()),spans
        pcs=[int(pc,16) for pc in re.findall(r'^PC=([0-9A-F]+)$',runtime,re.M)]
        def chain(values):
          return [name for pc in values for name,(base,size) in spans.items() if base<=pc<base+size]
        expected=['audit_trace','AuditPascalCallback','audit_enter','AuditHostAnchor']
        assert chain(pcs)==expected,(spans,pcs,chain(pcs))
        assert chain(pcs[:1])!=expected,'truncated-chain negative control accepted'
        row.update(native_frames=len(pcs),chain=chain(pcs),negative_chain_rejected=True,native_constructor=True,native_destructor=True,native_tls=True,foreign_exception_cleanup='2/2')
      (work/'PluginState.pas').write_text(PLUGIN); (work/'PascalGraphPlugin.dpr').write_text('library PascalGraphPlugin; uses PluginState; exports RunPlugin; begin end.'); (work/'PascalGraphLoader.dpr').write_text(LOADER)
      run([v for v in common if v!='-k-pie']+['-Cg','PascalGraphPlugin.dpr'],'pascal-plugin-build.log')
      run(common+['PascalGraphLoader.dpr'],'pascal-loader-build.log')
      for repeat in range(3):
        runtime=run([work/('PascalGraphLoader.exe' if win else 'PascalGraphLoader')],f'pascal-dso-runtime-{repeat}.log')
        assert sorted(runtime.splitlines())==['PASCAL_DSO_PASS=1/2','PASCAL_PLUGIN_FINAL=1/2'],runtime
      images=['PascalGraphPlugin.dll','PascalGraphLoader.exe'] if win else ['libForeignGraph.so','ForeignGraph','libPascalGraphPlugin.so','PascalGraphLoader']
      row['images_sha256']={name:hashlib.sha256((work/name).read_bytes()).hexdigest() for name in images}
      row['pascal_loads']=3; row['reflective_calls']=6; row['pascal_finalizations']=3; rows.append(row)
      (out/'result.json').write_text(json.dumps(dict(compiler=str(cc),compiler_sha256=hashlib.sha256(cc.read_bytes()).hexdigest(),runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),cases=rows),indent=2))
      print('PASS',label,flush=True)
    print('FOREIGN_DSO_PASS',len(rows),flush=True)
if __name__=='__main__': main()
