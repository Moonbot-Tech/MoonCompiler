#!/usr/bin/env python3
"""Cross-unit RTTI ABI corpus with independent values and source-free PPUs."""
import argparse, hashlib, json, os, re, subprocess
from pathlib import Path

TYPES = '''unit AuditTypes;
interface
uses System.SysUtils;
type
  TPair = record A, B: Int64; end;
  TBig = record A, B, C, D, E: Int64; end;
  TIntArray = array of Int64;
  IAudit = interface ['{61AC37CC-935B-4C9B-B2AA-CB83DCF49AE9}']
    function Value: Int64;
  end;
  TAudit = class(TInterfacedObject, IAudit)
    function Value: Int64;
    destructor Destroy; override;
  end;
  TMarkAttribute = class(TCustomAttribute)
    Code: Integer;
    constructor Create(N: Integer);
  end;
var Destroyed, Raised: Integer;
implementation
constructor TMarkAttribute.Create(N: Integer); begin Code := N; end;
function TAudit.Value: Int64; begin Result := 4093; end;
destructor TAudit.Destroy; begin Inc(Destroyed); inherited; end;
end.
'''

METHODS = [
 ('Eight', 'function Eight(A,B,C,D,E,F,G,H: Int64): Int64', 'Result := A+3*B+5*C+7*D+11*E+13*F+17*G+19*H', '[Int64(2),Int64(3),Int64(5),Int64(7),Int64(11),Int64(13),Int64(17),Int64(19)]', '.AsInt64 = 1025'),
 ('Floats', 'function Floats(A,B,C,D,E,F,G,H,I,J: Double): Double', 'Result := A+2*B+3*C+4*D+5*E+6*F+7*G+8*H+9*I+10*J', '[Double(1),Double(2),Double(3),Double(4),Double(5),Double(6),Double(7),Double(8),Double(9),Double(10)]', '.AsExtended = 385'),
 ('Mixed', 'function Mixed(A: Int64; B: Double; const C: UnicodeString; D: Int64; E: Double; const F: UnicodeString; G: Int64; H: Double): UnicodeString', "If (A<>11) or (B<>2.5) or (C<>'alpha') or (D<>37) or (E<>8.25) or (F<>'omega') or (G<>101) or (H<>0.125) then raise Exception.Create('mixed input'); Result := C+'-'+F+'-TAG'", "[Int64(11),Double(2.5),UnicodeString('alpha'),Int64(37),Double(8.25),UnicodeString('omega'),Int64(101),Double(0.125)]", ".AsString = 'alpha-omega-TAG'"),
 ('Records', 'function Records(A: TPair; B: TBig; N: Int64): TBig', 'Result.A:=A.A+B.A+N; Result.B:=A.B+B.B; Result.C:=B.C*3; Result.D:=B.D*5; Result.E:=B.E*7', '[TValue.From<TPair>(Pair),TValue.From<TBig>(Big),Int64(31)]', ''),
 ('ArraySum', 'function ArraySum(const A: array of Int64): Int64', 'Result:=0; for var I:=0 to High(A) do Result:=Result+A[I]*(I+1)', '[TValue.From<TIntArray>(Numbers)]', '.AsInt64 = 154'),
 ('InterfaceValue', 'function InterfaceValue(const A: IAudit; N: Int64): Int64', 'Result:=A.Value+N', '[TValue.From<IAudit>(Intf),Int64(19)]', '.AsInt64 = 4112'),
 ('Managed', 'function Managed(const S: UnicodeString; A,B,C,D,E,F,G: Int64): UnicodeString', "Result:=S+':'+IntToStr(A+B*2+C*3+D*4+E*5+F*6+G*7)", "[UnicodeString('Ж©'),Int64(1),Int64(2),Int64(3),Int64(4),Int64(5),Int64(6),Int64(7)]", ".AsString = 'Ж©:140'"),
 ('Mutate', 'procedure Mutate(var N: Int64; out S: UnicodeString; const A: TIntArray)', "N:=N+A[0]+A[High(A)]; S:='changed-TAG'", '', ''),
 ('Throwing', 'function Throwing(N: Int64): Int64', "Inc(Raised); raise Exception.Create('raised-TAG-'+IntToStr(N)); Result:=0", '', ''),
 ('StaticCall', 'class function StaticCall(A: Int64; B: Double; C: Int64; D: Double; E: Int64): Int64; static', 'Result:=A+C*3+E*7+Trunc(B*8)+Trunc(D*16)', '[Int64(11),Double(2.5),Int64(37),Double(8.25),Int64(101)]', '.AsInt64 = 981'),
]
PARAM_NAMES = ['A|B|C|D|E|F|G|H', 'A|B|C|D|E|F|G|H|I|J', 'A|B|C|D|E|F|G|H', 'A|B|N', 'A', 'A|N', 'S|A|B|C|D|E|F|G', 'N|S|A', 'N', 'A|B|C|D|E']

def unit(tag):
    declarations = '\n'.join('    [TMark('+str(i+101)+')]\n    '+decl+';' for i, (_,decl,*_) in enumerate(METHODS))
    bodies = []
    for name, decl, body, *_ in METHODS:
        decl = decl.replace('; static', '').replace(name+'(', 'TProbe.'+name+'(')
        bodies.append(decl+';\nbegin\n  '+body.replace('TAG',tag)+';\nend;')
    return 'unit Audit'+tag+';\ninterface\nuses System.SysUtils, AuditTypes;\n{$RTTI EXPLICIT METHODS([vcPublic])}\ntype TProbe = class\n  public\n'+declarations+'\nend;\nimplementation\n'+'\n'.join(bodies)+'\nend.\n'

def program(reverse):
    calls = []
    metadata = []
    for index, (name, *_) in enumerate(METHODS):
        metadata.append("  M:=R.GetMethod('"+name+"'); Check(M<>nil,Tag+' method "+name+"');\n"
          +"  Check((Length(M.GetAttributes)=1) and (M.GetAttributes[0] is TMarkAttribute),Tag+' attributes "+name+"');\n"
          +"  Check(TMarkAttribute(M.GetAttributes[0]).Code="+str(index+101)+",Tag+' attribute payload "+name+"');\n"
          +"  S:=''; for P in M.GetParameters do begin If S<>'' then S:=S+'|'; S:=S+P.Name; end;\n"
          +"  Check(S='"+PARAM_NAMES[index]+"',Tag+' parameter names "+name+"');")
    for name, _, _, argv, check in METHODS:
        if check:
            target = "TValue.Empty" if name == 'StaticCall' else 'O'
            check = check.replace('TAG', "'+Tag+'")
            calls.append("  Check(R.GetMethod('"+name+"').Invoke("+target+','+argv+')'+check+", Tag+' "+name+"');")
    return '''program InvokeCorpus;
uses {$IFDEF UNIX} ffi.manager, {$ENDIF} {$IFDEF AUDIT_REPORTS} Moon.Diagnostics, {$ENDIF} System.SysUtils, System.TypInfo, System.Rtti,
  AuditTypes, '''+('AuditB, AuditA' if reverse else 'AuditA, AuditB')+''';
procedure Check(B: Boolean; const Why: UnicodeString);
begin If not B then raise Exception.Create('CORPUS: '+Why); end;
var
  C: TRttiContext;
  Pair: TPair;
  Big, Got: TBig;
  Numbers: TIntArray;
  Intf: IAudit;
procedure Test(O: TObject; const Tag: UnicodeString);
var R: TRttiType; M: TRttiMethod; P: TRttiParameter; Args: array of TValue; V: TValue; N: Int64; S: UnicodeString;
{$IFDEF AUDIT_REPORTS} Saved: Exception; SavedContext: TObject; {$ENDIF}
begin
  R:=C.GetType(O.ClassInfo);
'''+ '\n'.join(metadata)+'\n'+ '\n'.join(calls)+'''
  V:=R.GetMethod('Records').Invoke(O,[TValue.From<TPair>(Pair),TValue.From<TBig>(Big),Int64(31)]);
  Got:=V.AsType<TBig>;
  Check((Got.A=37) and (Got.B=10) and (Got.C=21) and (Got.D=55) and (Got.E=91),Tag+' records');
  N:=101; S:='old'; SetLength(Args,3);
  Args[0]:=TValue.From<Int64>(N); Args[1]:=TValue.From<UnicodeString>(S); Args[2]:=TValue.From<TIntArray>(Numbers);
  R.GetMethod('Mutate').Invoke(O,Args);
  Check((Args[0].AsInt64=145) and (Args[1].AsString='changed-'+Tag),Tag+' var/out');
  {$IFDEF AUDIT_REPORTS} Saved:=nil; {$ENDIF}
  try
    R.GetMethod('Throwing').Invoke(O,[Int64(23)]);
    Check(False,Tag+' swallowed exception');
  except
    on E: Exception do begin
      Check(E.Message='raised-'+Tag+'-23',Tag+' exception payload');
      {$IFDEF AUDIT_REPORTS}
      Saved:=Exception(AcquireExceptionObject);
      SavedContext:=Saved.DiagnosticContext;
      Check(SavedContext<>nil,Tag+' captured Invoke origin');
      Check(WriteExceptionReport(Saved,Tag+'-caught')<>'',Tag+' caught report');
      {$ENDIF}
    end;
  end;
  {$IFDEF AUDIT_REPORTS}
  try
    Check(Saved.DiagnosticContext=SavedContext,Tag+' original snapshot survives ffi unwind');
    Check(WriteExceptionReport(Saved,Tag+'-acquired')<>'',Tag+' acquired report');
  finally
    Saved.Free;
  end;
  {$ENDIF}
  Writeln(Tag,'_PASS');
end;
var A: AuditA.TProbe; B: AuditB.TProbe;
begin
  {$IFDEF AUDIT_REPORTS}
  InitializeReports('reports',nil,'invoke-corpus');
  If ParamCount>0 then SetReportsEnabled(False);
  {$ENDIF}
  C:=TRttiContext.Create;
  Pair.A:=2; Pair.B:=5;
  Big.A:=4; Big.B:=5; Big.C:=7; Big.D:=11; Big.E:=13;
  SetLength(Numbers,3); Numbers[0]:=11; Numbers[1]:=22; Numbers[2]:=33;
  If ParamCount>0 then Numbers[1]:=23;
  Intf:=TAudit.Create;
  A:=AuditA.TProbe.Create; B:=AuditB.TProbe.Create;
  try
    Check(A.ClassType<>B.ClassType,'distinct VMT');
    Check(A.ClassInfo<>B.ClassInfo,'distinct TypeInfo');
    Test(A,'A'); Test(B,'B');
  finally
    A.Free; B.Free; Intf:=nil; C.Free;
  end;
  Check(Destroyed=1,'managed interface lifetime');
  Check(Raised=2,'reflective throw count');
  Writeln('INVOKE_CORPUS_PASS');
end.
'''

def main():
    ap=argparse.ArgumentParser(__doc__)
    ap.add_argument('--compiler', type=Path, required=True)
    ap.add_argument('--results', type=Path, required=True)
    ap.add_argument('--reports', action='store_true')
    args=ap.parse_args()
    compiler=args.compiler.resolve(strict=True)
    out=args.results.resolve(); out.mkdir(parents=True,exist_ok=False)
    backend=compiler.with_name('ppcx64'+('.exe' if os.name=='nt' else ''))
    evidence={'compiler':str(compiler),'sha256':hashlib.sha256(compiler.read_bytes()).hexdigest(),'backend':str(backend),'backend_sha256':hashlib.sha256(backend.read_bytes()).hexdigest(),'reports':args.reports,'matrix':[]}
    for release in (False,True):
      for reverse in (False,True):
        work=out/(('release' if release else 'debug')+('-reverse' if reverse else '-forward')); work.mkdir()
        for name,text in [('AuditTypes.pas',TYPES),('AuditA.pas',unit('A')),('AuditB.pas',unit('B')),('InvokeCorpus.dpr',program(reverse))]:
          (work/name).write_text(text,encoding='utf-8')
        common=[str(compiler),*(['-dRELEASE'] if release else []),*(['-dAUDIT_REPORTS'] if args.reports else []),'-Fu.','-FU.','-FE.']
        for name in (('AuditB','AuditA') if reverse else ('AuditA','AuditB')):
          p=subprocess.run(common+[name+'.pas'],cwd=work,capture_output=True,text=True,timeout=90)
          (work/(name+'.log')).write_text(p.stdout+p.stderr)
          assert p.returncode==0,(name,p.stdout,p.stderr)
        for name in ('AuditTypes','AuditA','AuditB'):
          (work/(name+'.pas')).rename(work/(name+'.pas.hidden'))
        p=subprocess.run(common+['InvokeCorpus.dpr'],cwd=work,capture_output=True,text=True,timeout=90)
        (work/'compile.log').write_text(p.stdout+p.stderr)
        assert p.returncode==0,(work,p.stdout,p.stderr)
        binary=work/('InvokeCorpus'+('.exe' if os.name=='nt' else ''))
        p=subprocess.run([str(binary)],cwd=work,capture_output=True,text=True,timeout=30)
        (work/'runtime.log').write_text(p.stdout+p.stderr)
        assert p.returncode==0 and p.stdout=='A_PASS\nB_PASS\nINVOKE_CORPUS_PASS\n',(work,p.returncode,p.stdout,p.stderr)
        report_rows=[]
        if args.reports:
          reports=list((work/'reports').glob('*.txt')); assert len(reports)==4,(work,reports)
          contexts={}
          for report in reports:
            text=report.read_text(encoding='utf-8')
            assert text.startswith('MOON_DIAGNOSTIC_REPORT 1\n') and text.endswith('MOON_DIAGNOSTIC_END\n'),report
            assert 'complete=True\n' in text and 'application_version=invoke-corpus\n' in text,report
            assert re.findall(r'^unwind_status=(.+)$',text,re.M)==['0'],report
            title=re.search(r'^title=(.+)$',text,re.M)[1]; tag=title[0]
            line=next(i for i,s in enumerate(unit(tag).splitlines(),1) if "raise Exception.Create('raised-" in s)
            method='TProbe.Throwing' if release else 'Throwing'
            assert re.search(r'  \$[0-9A-F]+ '+re.escape(method)+r' .*Audit'+tag+r'\.pas:'+str(line)+r'\b',text),(report,line,[s for s in text.splitlines() if s.startswith('  $')])
            caller=next(i for i,s in enumerate(program(reverse).splitlines(),1) if "R.GetMethod('Throwing').Invoke(O" in s)
            mainline=next(i for i,s in enumerate(program(reverse).splitlines(),1) if "Test(A,'A'); Test(B,'B')" in s)
            assert re.search(r' Test .*InvokeCorpus\.dpr:'+str(caller)+r'\b',text),(report,'Invoke caller lost')
            assert re.search(r' \$main .*InvokeCorpus\.dpr:'+str(mainline)+r'\b',text),(report,'main caller lost')
            assert 'exception_message=raised-'+tag+'-23\n' in text,report
            pcs=re.findall(r'^pc\[(.+)\]',text,re.M); assert pcs,(report,'no raw PCs')
            contexts.setdefault(tag,[]).append(pcs)
            report_rows.append({'file':report.name,'title':title,'origin_file':'Audit'+tag+'.pas','origin_line':line,'frames':len(pcs)})
          assert all(len(pcs)==2 and pcs[0]==pcs[1] for pcs in contexts.values()),'original snapshot changed after except'
        negative=subprocess.run([str(binary),'negative-values'],cwd=work,capture_output=True,text=True,timeout=30)
        (work/'negative.log').write_text(negative.stdout+negative.stderr)
        assert negative.returncode!=0 and 'CORPUS: A ArraySum' in negative.stdout+negative.stderr,(work,negative.returncode,negative.stdout,negative.stderr)
        evidence['matrix'].append({'release':release,'reverse':reverse,'output':p.stdout,'bytes':binary.stat().st_size,'negative_control_rejected':True,'reports':report_rows})
        (out/'results.json').write_text(json.dumps(evidence,indent=2))
        print('PASS',work.name,flush=True)
    print('INVOKE_CORPUS_GATE_PASS',flush=True)
if __name__=='__main__': main()
