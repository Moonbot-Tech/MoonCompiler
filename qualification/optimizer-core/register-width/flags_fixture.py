"""ISA-level proof only: inline ASM bypasses the FPC peephole optimizer.

Tests original MOVQ, repaired MOVL-self, and deliberately invalid ANDL-self
with live CF (ADC) and CF/ZF/SF/OF (SETcc). It cannot establish Pascal-level
reachability of either MOV-to-AND rewrite. No instruction bytes are patched.
"""
import argparse,json,os,subprocess
from pathlib import Path
from structural_gate import sha

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--compiler',type=Path,required=True)
    ap.add_argument('--config',type=Path,required=True)
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--exe-suffix',default='.exe' if os.name=='nt' else '')
    a=ap.parse_args();root=a.output.resolve();root.mkdir(parents=True,exist_ok=False)
    lines=['program flags_fixture;','{$mode delphi}{$asmmode intel}',
           '{$Q-}{$R-}']
    expected=[]
    for consumer in ['adc','setcc']:
        for b in [1,3,5]:
            for variant,ins in [('original','mov rcx,r8'),('repair','mov ecx,ecx'),('negative','and ecx,ecx')]:
                name=f'{consumer}_{b}_{variant}'
                lines += [f'function {name}:QWord; assembler; nostackframe;',
                          'asm','mov rcx,$fffffffffffffffc',f'mov r9,{b}',
                          'mov rax,0','cmp r9,3','mov r8d,ecx',ins]
                if consumer=='adc':
                    lines += ['adc rax,0']
                    original=int(b<3);want=0 if variant=='negative' else original
                else:
                    lines += ['setb al','sete dl','setl r8b','movzx eax,al',
                              'movzx edx,dl','shl edx,1','or eax,edx',
                              'movzx r8d,r8b','shl r8d,2','or eax,r8d']
                    original=int(b<3)+2*int(b==3)+4*int(b<3)
                    want=4 if variant=='negative' else original
                lines += ['end;']
                expected.append(dict(name=name,consumer=consumer,variant=variant,expected=want,
                                     semantic_expected=original))
    for name, instruction, want in [
        ('shift0', 'shl ecx,0', 1),
        ('shift32', 'shl ecx,32', 1),
        ('partial_shift', 'shl cx,1', 0xffffffff00000002),
        ('partial_mov', 'mov cx,2', 0xffffffff00000002),
    ]:
        lines += [f'function upper_{name}:QWord; assembler; nostackframe;',
                  'asm', 'mov rcx,$ffffffff00000001', instruction,
                  'mov rax,rcx', 'end;']
        expected.append(dict(name='upper_'+name,consumer='upper',variant=name,
                             expected=want,semantic_expected=want))
    lines += ['begin']+[f"Writeln('{r['name']} ',{r['name']});" for r in expected]+['end.']
    source=root/'flags_fixture.pas';source.write_text('\n'.join(lines)+'\n')
    exe=root/('flags_fixture'+a.exe_suffix)
    cmd=[str(a.compiler.resolve()),'-n','@'+str(a.config.resolve()),'-O3','-al',
         '-FU'+str(root),'-FE'+str(root),'-o'+str(exe),str(source)]
    p=subprocess.run(cmd,cwd=root,capture_output=True,text=True,timeout=120)
    (root/'compile.log').write_text(p.stdout+p.stderr)
    if p.returncode:raise RuntimeError('compile failed')
    p=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30)
    (root/'run.txt').write_text(p.stdout+p.stderr)
    if p.returncode:raise RuntimeError('run failed')
    rows=p.stdout.splitlines()
    if len(rows)!=len(expected):raise RuntimeError('row count')
    for row,want in zip(rows,expected):
        name,value=row.split()
        if name!=want['name'] or int(value)!=want['expected']:raise RuntimeError('ISA oracle failure: '+row)
        want['actual']=int(value)
    controls={c:sum(r['variant']=='negative' and r['actual']!=r['semantic_expected'] for r in expected if r['consumer']==c) for c in ['adc','setcc']}
    if not all(controls.values()):raise RuntimeError('negative control failed to discriminate')
    report=dict(scope='ISA fixture; not proof of optimizer reachability',compiler_sha256=sha(a.compiler),
                command=cmd,negative_controls=controls,results=expected)
    (root/'report.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(dict(rows=len(expected),negative_controls=controls,passed=True)))

if __name__=='__main__':main()
