#!/usr/bin/env python3
"""Verify the helper belonging to this exact installed SDK, never PATH."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,shutil,sys,tempfile

def verify_paths(compiler: Path, helper: Path) -> dict:
    win=os.name=='nt'
    objcopy=str(compiler.parent/'objcopy.exe') if win else shutil.which('objcopy')
    assert objcopy,'objcopy missing'
    with tempfile.TemporaryDirectory(prefix='mccompact-gate-') as temporary:
        work=Path(temporary)
        def run(args, expected=0):
            p=subprocess.run([str(x) for x in args],cwd=work,capture_output=True,timeout=60)
            assert p.returncode==expected,(args,p.returncode,p.stdout,p.stderr)
            return (p.stdout+p.stderr).decode('utf-8')
        # Link the compiler's emitted script ourselves: obtain real compact-form
        # DWARF before the compiler would automatically invoke this helper.
        (work/'Probe.pas').write_text("program Probe; uses SysUtils; begin Writeln('HELPER_RUNTIME_PASS'); end.")
        run([compiler,'-dRELEASE','-dMOONCOMPILER_VANILLA_RUNTIME','-Cn','-Xe','-Xs-','-FU.','-FE.','Probe.pas'])
        run(['cmd.exe','/d','/c','ppas.bat'] if win else ['sh','ppas.sh'])
        image=work/('Probe.exe' if win else 'Probe')
        assert run([image]).strip()=='HELPER_RUNTIME_PASS'
        if not win: image.chmod(0o751)
        original=image.read_bytes()
        def argument(path):
            return '\\\\?\\'+str(path) if win else str(path)
        result={}
        long_parent=work/('каталог-'+'п'*20)/'destination-output'
        long_parent.mkdir(parents=True)
        for parent_label,parent in [('short',work),('unicode-parent',long_parent)]:
            foreign=parent/'.mccompact-foreign'
            foreign.mkdir();(foreign/'sentinel').write_bytes(b'foreign data')
            for leaf_label,leaf in [('short','input'),('unicode-leaf','я'*(130 if win else 80))]:
                source=parent/(leaf+'.exe');source.write_bytes(original)
                if not win: source.chmod(0o751)
                key=parent_label+'-'+leaf_label
                for label,tool in [('compact',objcopy),('fallback',sys.executable)]:
                    output=parent/(leaf+'.exe.mccompact-new')
                    message=run([helper,argument(source),argument(output),tool])
                    assert source.read_bytes()==original,'input changed'
                    assert win or output.stat().st_mode&0o777==source.stat().st_mode&0o777,'output mode changed'
                    if label=='compact':
                        assert message.startswith('COMPACT '),message
                        assert output.read_bytes()!=original,'no actual transformation'
                    else:
                        assert message.startswith('UNCHANGED:'),message
                        assert output.read_bytes()==original,'fallback changed bytes'
                    executable=work/(key+'-'+label+('.exe' if win else ''))
                    output.rename(executable)
                    assert run([executable]).strip()=='HELPER_RUNTIME_PASS'
                    assert set(parent.glob('.mccompact-*'))=={foreign},'owned workspace leaked'
                    assert (foreign/'sentinel').read_bytes()==b'foreign data'
                    result[key+'-'+label]=message.strip()
            # Distinct outputs in one directory must not share a workspace.
            processes=[]
            for index in range(3):
                output=parent/('parallel-'+str(index)+'.exe')
                processes.append((output,subprocess.Popen([str(helper),argument(source),argument(output),objcopy],cwd=work,stdout=subprocess.PIPE,stderr=subprocess.PIPE)))
            for output,process in processes:
                stdout,stderr=process.communicate(timeout=60)
                assert process.returncode==0 and stdout.decode('utf-8').startswith('COMPACT '),(stdout,stderr)
                assert run([output]).strip()=='HELPER_RUNTIME_PASS'
                assert win or output.stat().st_mode&0o777==source.stat().st_mode&0o777
            assert set(parent.glob('.mccompact-*'))=={foreign},'parallel workspace leaked'
            result[parent_label+'-parallel']=len(processes)
        # Existing output is never ours; reject without changing its contents.
        output=work/'occupied-file';output.write_bytes(b'foreign data')
        p=subprocess.run([str(helper),str(source),str(output),objcopy],cwd=work,capture_output=True,timeout=60)
        assert p.returncode!=0 and output.read_bytes()==b'foreign data'
        if not win:
            # Arrange an exact PID collision before exec, without a timing race.
            for directory in (False,True):
                def occupy():
                    path=work/('.mccompact-'+str(os.getpid()))
                    if directory:
                        path.mkdir();path=path/'sentinel'
                    path.write_bytes(b'foreign data')
                output=work/('collision-dir' if directory else 'collision-file')
                p=subprocess.Popen([str(helper),str(source),str(output),objcopy],cwd=work,stdout=subprocess.PIPE,stderr=subprocess.PIPE,preexec_fn=occupy)
                stdout,stderr=p.communicate(timeout=60)
                foreign=work/('.mccompact-'+str(p.pid))
                sentinel=foreign/'sentinel' if directory else foreign
                assert p.returncode==0 and b'UNCHANGED: cannot create temporary directory' in stdout,(stdout,stderr)
                assert sentinel.read_bytes()==b'foreign data'
                assert output.read_bytes()==original and output.stat().st_mode&0o777==0o751
            result['collision-file-and-directory']='preserved'
        assert source.read_bytes()==original

        return result

def verify_helper(toolchain: Path) -> dict:
    toolchain=toolchain.resolve()
    win=os.name=='nt'
    relative=Path('bin/x86_64-win64' if win else 'bin')
    filename='mccompact.exe' if win else 'mccompact'
    compilername='ppcx64.exe' if win else 'ppcx64'
    record=dict(line.split('=',1) for line in (toolchain/'profile.txt').read_text().splitlines() if '=' in line)
    expected=record['compact_helper_sha256']
    result={}
    for profile in ('product','ide'):
        base=toolchain if profile=='product' else toolchain/'ide'
        compiler=(base/relative/compilername).resolve(strict=True)
        helper=(compiler.parent/filename).resolve(strict=True)
        assert helper.is_relative_to(base.resolve()),(profile,'helper escaped the SDK',helper)
        digest=hashlib.sha256(helper.read_bytes()).hexdigest()
        assert digest==expected,(profile,'installed helper does not match profile record',digest,expected)
        output=subprocess.check_output([str(helper),'--version'],text=True,timeout=10).strip()
        assert output=='MoonCompiler compact DWARF helper 1',(profile,output)
        result[profile]=dict(compiler=str(compiler),helper=str(helper),sha256=digest,version=output)
    result['paths']=verify_paths(Path(result['product']['compiler']),Path(result['product']['helper']))
    return result

if __name__=='__main__':
    ap=argparse.ArgumentParser(__doc__);ap.add_argument('--toolchain',type=Path,required=True)
    args=ap.parse_args();print(json.dumps(verify_helper(args.toolchain),indent=2))
