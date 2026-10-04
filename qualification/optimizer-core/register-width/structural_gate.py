"""Width/dataflow qualification: independently evaluate every generated Pascal result.

Example: python structural_gate.py --compiler old=old-ppcx64.exe
  --compiler new=new-helper-ppcx64.exe --config stand.cfg --output structural-run
Exit 1 means at least one compiler/mode disagrees with the independent oracle.
Expected failures in an old compiler still deliberately produce exit 1.
"""
from pathlib import Path
from collections import Counter
import argparse, hashlib, itertools, json, os, subprocess

MASK = (1 << 64) - 1
TYPES = [('Byte',8,False),('ShortInt',8,True),('Word',16,False),
         ('SmallInt',16,True),('Cardinal',32,False),('LongInt',32,True),
         ('QWord',64,False),('Int64',64,True)]
INPUTS = [(-4,1),(-1,3),(0,4),(1,-1),(127,0),(128,3),(32768,-4),
          (0x1234567880000001,-4),(0x1234567800000000,3),
          (0x1234567800000001,1),(0xFFFFFFFF,5),(0x100000001,-1),
          (-(1<<63),1),((1<<63)-1,3)]

def i64(v):
    v &= MASK
    return v - (1 << 64) if v & (1 << 63) else v

def cast(v, bits, signed):
    v &= (1 << bits) - 1
    return v - (1 << bits) if signed and v & (1 << (bits-1)) else v

def oracle(case, a, b):
    # No compiled program supplies expected values: this is a bit-vector model.
    y = cast(a, case['bits'], case['signed'])
    c, acc = a, i64(a ^ b)
    test = {'lt': b < 3, 'ge': b >= 3, 'eq': b == 3}[case['condition']]
    family = case['family']
    if family in ('select', 'flagbool', 'call'):
        if test: c = i64(y)  # call's noinline typed consumer returns Int64(y)
    else:
        if test: c = i64(c + 1)
    if (test if family == 'flagbool' else c > 2):
        acc = i64(acc + (c if case['increment'] == 'C' else y))
    if family == 'address':
        idx = y & 0xffffffff
        return i64(acc + c + (idx * 101 + 7 if idx < 16 else y))
    return i64(acc + c + y)

def generate(root):
    cases = []
    lines = ['program width_structural;', '{$mode delphi}{$Q-}{$R-}',
             'type TTable=array[0..15] of Int64; PTable=^TTable;']
    for typ,_,_ in TYPES: lines += [f'PValue{typ}=^{typ};']
    for typ,_,_ in TYPES:
        lines += [f'function Consume{typ}(V:{typ}):Int64; noinline;',
                  'begin Result:=Int64(V); end;']
    for (typ,bits,signed), (condition,op), inc, order, family in itertools.product(
            TYPES,[('lt','<'),('ge','>='),('eq','=')],['C','Y'],[0,1],
            ['select','flagbool','address','call','store_reload']):
        name = f'F{len(cases):04}'
        case = dict(name=name,typ=typ,bits=bits,signed=signed,condition=condition,
                    increment=inc,order=order,family=family)
        castline=f'Y:={typ}(A);'
        prefix=f'C:=A; Acc:=B xor A; {castline}'
        if order: prefix=f'{castline} C:=A; Acc:=B xor A;'
        pred=f'B {op} 3'
        if family == 'flagbool':
            body=f'Test:={pred}; if Test then C:=Y; if Test then Inc(Acc,{inc}); Result:=Acc+C+Y;'
        elif family == 'select':
            body=f'if {pred} then C:=Y; if C>2 then Inc(Acc,{inc}); Result:=Acc+C+Y;'
        elif family == 'call':
            body=f'if {pred} then C:=Consume{typ}(Y); if C>2 then Inc(Acc,{inc}); Result:=Acc+C+Y;'
        elif family == 'store_reload':
            body=f'PValue{typ}(Q)^:=Y; if {pred} then Inc(C); Y:=PValue{typ}(Q)^; if C>2 then Inc(Acc,{inc}); Result:=Acc+C+Y;'
        else:
            body=f'if {pred} then Inc(C); Idx:=Cardinal(Y); if C>2 then Inc(Acc,{inc}); if Idx<16 then Result:=Acc+C+P[Idx] else Result:=Acc+C+Y;'
        lines += [f'function {name}(P:PTable; Q:Pointer; A,B:Int64):Int64; noinline;',
                  f'var Y:{typ}; C,Acc:Int64; Idx:NativeUInt; Test:Boolean;',
                  'begin '+prefix+' '+body+' end;']
        cases.append(case)
    lines += ['var T:TTable; Q:QWord; I:Integer;']
    expected=[]
    for j,(a,b) in enumerate(INPUTS):
        lines += [f'procedure RunInput{j};', 'begin']
        for case in cases:
            name=case['name']
            lines += [f"Q:=0; Writeln('{name} {j} ',{name}(@T,@Q,Int64(${a&MASK:016X}),Int64(${b&MASK:016X})));" ]
            expected.append(dict(function=name,input=j,expected=oracle(case,a,b)))
        lines += ['end;']
    lines += ['begin', 'for I:=0 to 15 do T[I]:=I*101+7;']
    lines += [f'RunInput{j};' for j in range(len(INPUTS))]
    lines += ['end.']
    source=root/'width_structural.pas'
    source.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    (root/'manifest.json').write_text(json.dumps(dict(cases=cases,inputs=INPUTS,expected=expected),indent=2))
    return source,cases,expected

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--compiler',action='append',required=True,help='label=path')
    ap.add_argument('--config',type=Path,required=True)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--exe-suffix',default='.exe' if os.name=='nt' else '',
                    help='native executable suffix; use empty string on Linux')
    args=ap.parse_args()
    root=args.output.resolve()
    root.mkdir(parents=True,exist_ok=False)
    source,cases,expected=generate(root)
    byname={c['name']:c for c in cases}
    report=dict(functions=len(cases),inputs=len(INPUTS),rows=len(expected),
                source=str(source),source_sha256=sha(source),config_sha256=sha(args.config),runs=[])
    for spec in args.compiler:
        label,compiler=spec.split('=',1)
        compiler=Path(compiler).resolve()
        for opt in ['O-','O2','O3']:
            dest=root/(label+'-'+opt)
            dest.mkdir()
            executable=dest/('width_structural'+args.exe_suffix)
            cmd=[str(compiler),'-n','@'+str(args.config.resolve()),'-Mdelphi','-'+opt,
                 '-al','-FU'+str(dest),'-FE'+str(dest),'-o'+str(executable),str(source)]
            p=subprocess.run(cmd,cwd=dest,capture_output=True,text=True,timeout=180)
            (dest/'compile.log').write_text(p.stdout+p.stderr)
            if p.returncode: raise RuntimeError(str(dest)+' compilation failed')
            p=subprocess.run([str(executable)],capture_output=True,text=True,timeout=45)
            (dest/'run.txt').write_text(p.stdout+p.stderr)
            if p.returncode: raise RuntimeError(str(dest)+' execution failed')
            actual=p.stdout.splitlines()
            if len(actual)!=len(expected): raise RuntimeError('row count mismatch: '+str(dest))
            failures=[]
            counts=Counter()
            for row,want in zip(actual,expected):
                function,index,value=row.split()
                if function!=want['function'] or int(index)!=want['input']:
                    raise RuntimeError('function/input identity mismatch: '+row)
                case=byname[function]
                if int(value)!=want['expected']:
                    failure=dict(want,actual=int(value),case=case)
                    failures.append(failure)
                    counts[case['family']+'/'+case['typ']]+=1
            run=dict(label=label,opt=opt,compiler=str(compiler),compiler_sha256=sha(compiler),
                     command=cmd,rows=len(actual),wrong=len(failures),categories=dict(counts),failures=failures)
            report['runs'].append(run)
            (root/'report.json').write_text(json.dumps(report,indent=2))
            print(json.dumps({k:run[k] for k in ['label','opt','rows','wrong','categories']}),flush=True)
    return int(any(r['wrong'] for r in report['runs']))

if __name__=='__main__': raise SystemExit(main())
