#!/usr/bin/env python3
"""Independent live-data graph, TLS, source-free PPU and DSO lifetime oracle."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess

TYPES = r'''unit GraphTypes;
interface
uses SysUtils, Classes;
type
  IToken = interface ['{8F9CA8D7-D417-4EF0-AE53-610125BA8292}']
    function Value: Integer;
  end;
  TToken = class(TInterfacedObject, IToken)
    function Value: Integer;
    destructor Destroy; override;
  end;
  TMarkAttribute = class(TCustomAttribute)
    Code: Integer;
    constructor Create(N: Integer);
  end;
  TTracked = record
    Text: UnicodeString;
    class operator Initialize(var R: TTracked);
    class operator Finalize(var R: TTracked);
  end;
  TGeneric<T> = class
  public type TInner = class end;
  public
    function Value(N: Integer): Integer;
  end;
  TCallback = function(N: Integer): Integer;
var Destroyed, RecordInit, RecordFinal: Integer;
threadvar ThreadMarker: NativeInt;
procedure Check(B: Boolean; const Why: UnicodeString);
implementation
procedure Check(B: Boolean; const Why: UnicodeString);
begin If not B then raise Exception.Create('GRAPH: '+Why); end;
function TToken.Value: Integer; begin Result:=4093; end;
destructor TToken.Destroy; begin InterlockedIncrement(Destroyed); inherited; end;
constructor TMarkAttribute.Create(N: Integer); begin Code:=N; end;
class operator TTracked.Initialize(var R: TTracked);
begin R.Text:='tracked'; InterlockedIncrement(RecordInit); end;
class operator TTracked.Finalize(var R: TTracked);
begin Check(R.Text='tracked','record finalizer payload'); InterlockedIncrement(RecordFinal); end;
function TGeneric<T>.Value(N: Integer): Integer; begin Result:=N*13+7; end;
initialization
  Writeln('TYPES_INIT');
finalization
  If (Destroyed<>4) or (RecordInit<>RecordFinal) or (RecordInit<>2) then begin
    Writeln('GRAPH_FINAL_FAIL ',Destroyed,' ',RecordInit,' ',RecordFinal); Halt(91);
  end;
  Writeln('TYPES_FINAL=4/2/2');
end.
'''

OWNER = r'''unit GraphOwner;
interface
uses SysUtils, Classes, TypInfo, GraphTypes;
{$RTTI EXPLICIT FIELDS([vcPrivate,vcPublic,vcPublished]) METHODS([vcPublic]) PROPERTIES([vcPublished])}
type
  [TMark(271)]
  TBeacon = class(TPersistent)
  private
    FNumber: Integer;
  public
    function Compute(N: Integer): Integer;
  published
    property Number: Integer read FNumber write FNumber;
  end;
var RegisteredClass: TPersistentClass; RegisteredCallback: TCallback;
function InnerInfo: PTypeInfo;
function BoxInfo: PTypeInfo;
function GlobalValue: Integer;
implementation
var Held: IToken; GlobalText: UnicodeString; GlobalArray: array of UnicodeString;
resourcestring ResourceMessage='resource alive';
function TBeacon.Compute(N: Integer): Integer; begin Result:=N+FNumber+Held.Value; end;
function Callback(N: Integer): Integer; begin Result:=N*17+Held.Value; end;
function WrongCallback(N: Integer): Integer; begin Result:=N; end;
function InnerInfo: PTypeInfo; begin Result:=TGeneric<Integer>.TInner.ClassInfo; end;
function BoxInfo: PTypeInfo; begin Result:=TGeneric<Integer>.ClassInfo; end;
function GlobalValue: Integer;
begin
  Check((GlobalText='global managed') and (Length(GlobalArray)=2) and
    (GlobalArray[0]='first') and (GlobalArray[1]=ResourceMessage),'global managed roots');
  Result:=Held.Value;
end;
initialization
  Held:=TToken.Create; GlobalText:='global managed'; SetLength(GlobalArray,2);
  GlobalArray[0]:='first'; GlobalArray[1]:=ResourceMessage;
  RegisteredClass:=TBeacon; RegisteredCallback:=Callback;
  {$IFDEF AUDIT_NEGATIVE} RegisteredCallback:=WrongCallback; {$ENDIF}
  Writeln('OWNER_INIT');
finalization
  Check(GlobalValue=4093,'finalization access');
  Held:=nil; SetLength(GlobalArray,0); GlobalText:='';
  Writeln('OWNER_FINAL');
end.
'''

PEER = r'''unit GraphPeer;
interface
uses SysUtils, Classes, TypInfo, GraphTypes;
function InnerInfo: PTypeInfo;
function BoxInfo: PTypeInfo;
implementation
var Held: IToken;
function InnerInfo: PTypeInfo; begin Result:=TGeneric<Integer>.TInner.ClassInfo; end;
function BoxInfo: PTypeInfo; begin Result:=TGeneric<Integer>.ClassInfo; end;
initialization Held:=TToken.Create; Writeln('PEER_INIT');
finalization Held:=nil; Writeln('PEER_FINAL');
end.
'''

HOST = r'''program OwnershipGraph;
uses {$IFDEF UNIX} cthreads, ffi.manager, {$ENDIF} SysUtils, Classes, SyncObjs, TypInfo, Rtti,
  GraphTypes, GraphOwner, GraphPeer;
type
  TStringBox = TGeneric<UnicodeString>;
  TWorker = class(TThread)
    Index: Integer;
    Error: UnicodeString;
    procedure Execute; override;
  end;
var Ready: Integer; Gate: TEvent;
procedure TWorker.Execute;
var Held: IToken; Tracked: TTracked;
begin
  try
    InterlockedIncrement(Ready);
    Check(ThreadMarker=0,'thread initial zero'); ThreadMarker:=Index;
    Held:=TToken.Create; Check(Held.Value=4093,'thread interface');
    Gate.WaitFor(10000);
    for var I:=1 to 1000 do begin
      Sleep(0); Check(ThreadMarker=Index,'thread isolation');
    end;
    try
      Check(Tracked.Text='tracked','record initialized');
      raise Exception.Create('worker-'+IntToStr(Index));
    except on E: Exception do Check(E.Message='worker-'+IntToStr(Index),'thread exception'); end;
  except on E: Exception do Error:=E.Message; end;
end;
var C: TRttiContext; R: TRttiType; O: TObject; Workers: array[0..1] of TWorker;
  Matches, I: Integer;
begin
  Check(RegisteredCallback(3)=4144,'registered callback');
  Check(GlobalValue=4093,'global interface');
  Check(GraphOwner.InnerInfo=GraphPeer.InnerInfo,'nested generic identity');
  Check(GraphOwner.BoxInfo=GraphPeer.BoxInfo,'generic identity');
  Check(GraphOwner.BoxInfo<>TStringBox.ClassInfo,'distinct specialization identity');
  C:=TRttiContext.Create;
  try
    R:=C.GetType(RegisteredClass.ClassInfo);
    Check((Length(R.GetAttributes)=1) and (R.GetAttributes[0] is TMarkAttribute),'class attribute kind');
    Check(TMarkAttribute(R.GetAttributes[0]).Code=271,'class attribute payload');
    Check(R.GetField('FNumber')<>nil,'private field reflection');
    Check(R.GetProperty('Number')<>nil,'published property');
    Matches:=0; for var T in C.GetTypes do If T.Handle=RegisteredClass.ClassInfo then Inc(Matches);
    Check(Matches=1,'discovery catalog exactly once');
    O:=RegisteredClass.Create;
    try
      R.GetProperty('Number').SetValue(O,83);
      Check(R.GetProperty('Number').GetValue(O).AsInteger=83,'property access');
      R.GetField('FNumber').SetValue(O,97);
      Check(R.GetProperty('Number').GetValue(O).AsInteger=97,'private field access');
      Check(R.GetMethod('Compute').Invoke(O,[Integer(11)]).AsInteger=4201,'reflective callback root');
    finally O.Free; end;
    ThreadMarker:=571; Gate:=TEvent.Create(nil,True,False,'');
    try
      for I:=0 to 1 do begin Workers[I]:=TWorker.Create(True); Workers[I].Index:=I+101; Workers[I].Start; end;
      while InterlockedCompareExchange(Ready,0,0)<>2 do Sleep(1);
      Check(ThreadMarker=571,'main TLS isolation'); Gate.SetEvent;
      for I:=0 to 1 do begin Workers[I].WaitFor; Check(Workers[I].Error='','worker result '+Workers[I].Error); Workers[I].Free; end;
    finally Gate.Free; end;
    Check((Destroyed=2) and (RecordInit=2) and (RecordFinal=2),'thread managed cleanup');
  finally C.Free; end;
  Writeln('GRAPH_PASS');
end.
'''

def main():
    ap=argparse.ArgumentParser(__doc__)
    ap.add_argument('--compiler',type=Path,required=True)
    ap.add_argument('--results',type=Path,required=True)
    ap.add_argument('--mode',action='append')
    a=ap.parse_args(); cc=a.compiler.resolve(); out=a.results.resolve(); out.mkdir(parents=True,exist_ok=False)
    win=os.name=='nt'; rows=[]
    matrix=[('release',['-dRELEASE']),('debug',[])]
    if not win:
      matrix += [('full-dwarf',['-dRELEASE','-goNODWARFLINETABLESONLY']),
                 ('external',['-dRELEASE','-Aas']),('pie',['-dRELEASE','-Cg','-k-pie'])]
    if a.mode: matrix=[v for v in matrix if v[0] in a.mode]
    assert matrix,'no selected modes'
    for label,flags in matrix:
      for reverse in (False,True):
        work=out/(label+('-reverse' if reverse else '-forward')); work.mkdir()
        src=HOST.replace('GraphOwner, GraphPeer','GraphPeer, GraphOwner') if reverse else HOST
        for name,body in [('GraphTypes.pas',TYPES),('GraphOwner.pas',OWNER),('GraphPeer.pas',PEER),('OwnershipGraph.dpr',src)]:
          (work/name).write_text(body,encoding='utf-8')
        common=[str(cc),*flags,'-Xs-','-Fu.','-FU.','-FE.']
        def run(cmd,name,expected=0):
          p=subprocess.run([str(x) for x in cmd],cwd=work,capture_output=True,text=True,timeout=45)
          (work/name).write_text(p.stdout+p.stderr)
          assert p.returncode==expected,(label,name,p.returncode,(p.stdout+p.stderr)[-3500:])
          return p.stdout
        for unit in (('GraphPeer','GraphOwner') if reverse else ('GraphOwner','GraphPeer')):
          run(common+[unit+'.pas'],unit+'.log')
        for unit in ('GraphTypes','GraphOwner','GraphPeer'):
          (work/(unit+'.pas')).rename(work/(unit+'.pas.hidden'))
        run(common+['OwnershipGraph.dpr'],'compile.log')
        binary=work/('OwnershipGraph.exe' if win else 'OwnershipGraph')
        actual=run([binary],'runtime.log')
        binary_size=binary.stat().st_size
        binary_hash=hashlib.sha256(binary.read_bytes()).hexdigest()
        middle=['PEER_INIT','OWNER_INIT'] if reverse else ['OWNER_INIT','PEER_INIT']
        expected='\n'.join(['TYPES_INIT',*middle,'GRAPH_PASS',*['OWNER_FINAL' if reverse else 'PEER_FINAL','PEER_FINAL' if reverse else 'OWNER_FINAL'],'TYPES_FINAL=4/2/2',''])
        assert actual==expected,(label,actual,expected)
        # Rebuild only the producer unit with a changed live callback target.
        # The unchanged source-free consumer must observe and reject that edge.
        (work/'GraphOwner.pas.hidden').rename(work/'GraphOwner.pas')
        run(common+['-dAUDIT_NEGATIVE','GraphOwner.pas'],'negative-producer.log')
        (work/'GraphOwner.pas').rename(work/'GraphOwner.pas.hidden')
        run(common+['OwnershipGraph.dpr'],'negative-link.log')
        p=subprocess.run([str(binary)],cwd=work,capture_output=True,text=True,timeout=20)
        (work/'negative-runtime.log').write_text(p.stdout+p.stderr)
        assert p.returncode!=0 and 'GRAPH: registered callback' in p.stdout+p.stderr,(label,p.returncode,p.stdout,p.stderr)
        rows.append(dict(mode=label,flags=flags,reverse=reverse,bytes=binary_size,binary_sha256=binary_hash,source_free=True,negative_rejected=True,output=actual))
        (out/'result.json').write_text(json.dumps(dict(compiler=str(cc),compiler_sha256=hashlib.sha256(cc.read_bytes()).hexdigest(),runner_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),cases=rows),indent=2))
        print('PASS',work.name,flush=True)
    print('OWNERSHIP_GRAPH_PASS',len(rows),flush=True)
if __name__=='__main__': main()
