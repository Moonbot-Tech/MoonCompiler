#!/usr/bin/env python3
"""Verify the helper belonging to this exact installed SDK, never PATH."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess

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
    return result

if __name__=='__main__':
    ap=argparse.ArgumentParser(__doc__);ap.add_argument('--toolchain',type=Path,required=True)
    args=ap.parse_args();print(json.dumps(verify_helper(args.toolchain),indent=2))
