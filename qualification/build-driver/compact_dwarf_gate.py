from pathlib import Path
import argparse, hashlib, json, os, re, shutil, subprocess

parser = argparse.ArgumentParser(description="Native compact DWARF ownership and deduplication gate")
parser.add_argument('--root', type=Path, required=True)
parser.add_argument('--compiler', type=Path, required=True)
parser.add_argument('--config', type=Path, required=True)
parser.add_argument('--results', type=Path, required=True)
parser.add_argument('--objdump', type=Path)
parser.add_argument('--objcopy', type=Path)
args = parser.parse_args()
compiler, config, project = args.compiler.resolve(), args.config.resolve(), args.root.resolve()
root = args.results.resolve()
root.mkdir(parents=True, exist_ok=False)
suffix = '.exe' if os.name == 'nt' else ''
helper = compiler.parent / ('mccompact' + suffix)
assert helper.is_file(), ('helper must belong to the specified compiler', helper)
assert subprocess.check_output([str(helper), '--version'], text=True).strip() == 'MoonCompiler compact DWARF helper 1'

def utility(name, explicit):
    if explicit:
        return str(explicit.resolve(strict=True))
    adjacent = compiler.parent / (name + suffix)
    if adjacent.is_file():
        return str(adjacent)
    installed = shutil.which(name)
    if not installed:
        raise RuntimeError('Specify --' + name + ' for the compiler binutils')
    return installed

objdump, objcopy = utility('objdump', args.objdump), utility('objcopy', args.objcopy)

def u(v):
 out=b''
 while v>=128:out+=bytes([(v&127)|128]);v>>=7
 return out+bytes([v])
def n(v,size=4):return v.to_bytes(size,'little')
def abbrev(code,tag,children,attrs):return u(code)+u(tag)+bytes([children])+b''.join(u(a)+u(f) for a,f in attrs)+b'\0\0'
ab=(abbrev(1,0x11,1,[(3,8),(0x25,8),(0x1b,8),(0x10,6)])+
    abbrev(2,0x2e,0,[(3,8),(0x11,1),(0x12,1)])+b'\0')
def cu(name,offset,methods,marker=True,compdir='/source'):
 body=n(3,2)+n(0)+n(8,1)+u(1)+name.encode()+b'\0'+(b'MoonCompiler [MCcompact1]' if marker else b'External')+b'\0'+compdir.encode()+b'\0'+n(offset)
 for name,lo,hi in methods:body+=u(2)+name.encode()+b'\0'+n(lo,8)+n(hi,8)
 return n(len(body)+1)+body+b'\0'
def line(file='Core.pas',lineno=9,flags=0,directory=''):
 h=bytes([1,1,251,14,13])+bytes([0,1,1,1,1,0,0,0,1,0,0,1])+(directory.encode()+b'\0' if directory else b'')+b'\0'+file.encode()+b'\0'+u(int(bool(directory)))+b'\0\0\0'
 seq=b'\0'+u(9)+b'\2'+n(0x1000,8)+b'\3'+u(lineno-1)
 if flags:seq+=b'\7'
 seq+=b'\1\0'+u(9)+b'\2'+n(0x1010,8)+b'\0\1\1'
 body=n(3,2)+n(len(h))+h+seq
 return n(len(body))+body
def arange(cuoffset):
 body=n(2,2)+n(cuoffset)+b'\x08\0'+b'\0'*4+n(0x1000,8)+n(16,8)+b'\0'*16
 return n(len(body))+body
cases=[('identical',{},'Checked',1,1),('file',{'file':'Other.pas'},'Checked',0,0),('line',{'lineno':10},'Checked',0,0),('flags',{'flags':1},'Checked',0,0),('alias',{},'Alias',0,0)]
results=[]
for name,changes,method,removed,seqremoved in cases:
 out=root/('synthetic-'+name);out.mkdir(exist_ok=True)
 l1,l2=line(),line(**changes)
 c1=cu('A',0,[('Checked',0x1000,0x1010)])
 c2=cu('B',len(l1),[(method,0x1000,0x1010)])
 data={'debug_info':c1+c2,'debug_line':l1+l2,'debug_abbrev':ab,'debug_aranges':arange(0)+arange(len(c1))}
 for k,v in data.items():(out/k).write_bytes(v)
 p=subprocess.run([str(helper),str(out)],capture_output=True,text=True)
 assert p.returncode==0,(name,p.stdout,p.stderr)
 stats=json.loads(p.stdout)
 assert stats['methods_removed']==removed and stats['sequences_removed']==seqremoved,(name,stats)
 results.append(dict(case=name,**stats))

for name,firstdir,seconddir,directory,expected in [
 ('relative-directory','/project/a','/project/b','src',0),
 ('absolute-directory','/project/a','/project/b','/common/src',1),
 ('drive-directory','C:/project/a','D:/project/b','src',0),
 ('drive-absolute-directory','C:/project/a','D:/project/b','E:/common/src',1),
 ('unc-directory','C:/project/a','D:/project/b',r'\\server\share\src',1)]:
 out=root/('synthetic-'+name);out.mkdir(exist_ok=True);l=line(directory=directory)
 c1=cu('A',0,[('Checked',0x1000,0x1010)],compdir=firstdir)
 c2=cu('B',len(l),[('Checked',0x1000,0x1010)],compdir=seconddir)
 for k,v in {'debug_info':c1+c2,'debug_line':l+l,'debug_abbrev':ab,'debug_aranges':arange(0)+arange(len(c1))}.items():(out/k).write_bytes(v)
 p=subprocess.run([str(helper),str(out)],capture_output=True,text=True)
 assert p.returncode==0,(name,p.stdout,p.stderr)
 stats=json.loads(p.stdout);assert stats['methods_removed']==expected,(name,stats)
 results.append(dict(case=name,**stats))


# Full-debug reference graphs cannot be partially rewritten. A global reference
# form is enough to require explicit failure in the raw-section test interface.
out = root/'synthetic-ref-addr'
out.mkdir()
for filename in ('debug_info', 'debug_line', 'debug_aranges'):
    shutil.copy2(root/'synthetic-identical'/filename, out/filename)
(out/'debug_abbrev').write_bytes(ab.replace(bytes([3, 8, 0x11, 1]), bytes([3, 0x10, 0x11, 1])))
process = subprocess.run([str(helper), str(out)], capture_output=True, text=True)
assert process.returncode != 0 and 'DW_FORM_ref_addr' in process.stderr, process
assert not list(out.glob('*.new')), 'unsupported input wrote partially transformed sections'
results.append(dict(case='ref_addr', rejected_without_output=True))

fixture = project/'qualification/suite/tests/generic-sharing/unwind'
matrix = []
for reverse in (False, True):
    for mode in ('compact', 'mixed', 'full'):
        out = root / (mode + ('-reverse' if reverse else '-forward'))
        shutil.copytree(fixture, out)
        program = out/'UnwindCheck.dpr'
        source = program.read_text()
        source = source.replace('  Inc(Symbolized);', "  Writeln('WHERE=', F, '|', S, '|', L);\n  Inc(Symbolized);")
        if reverse:
            source = source.replace('UnwindA, UnwindB', 'UnwindB, UnwindA')
        program.write_text(source)
        common = [str(compiler), '-n', '@'+str(config), '-dRELEASE', '-gl-', '-gw3',
                  '-Fu'+str(out), '-FU'+str(out), '-FE'+str(out)]
        for unit, optimization in (('UnwindA', '-O-'), ('UnwindB', '-O3'), ('UnwindCheck', '-O2')):
            compact = mode == 'compact' or mode == 'mixed' and unit != 'UnwindB'
            target = unit + ('.dpr' if unit == 'UnwindCheck' else '.pas')
            switch = '-goDWARFLINETABLESONLY' if compact else '-goNODWARFLINETABLESONLY'
            process = subprocess.run(common+[switch, optimization, target], cwd=out, capture_output=True)
            (out/(unit+'.log')).write_bytes(process.stdout+process.stderr)
            assert process.returncode == 0, (out, target, process.stdout[-4000:])
            if unit != 'UnwindCheck':
                (out/target).rename(out/(target+'.hidden'))
        binary = out/('UnwindCheck'+suffix)
        process = subprocess.run([str(binary)], cwd=out, capture_output=True, text=True, timeout=30)
        assert process.returncode == 0, (out, process.stdout, process.stderr)
        for expected in ('CLASS=TRUE', 'LEAF=TRUE', 'NORMAL=TRUE', 'CAUGHT=2', 'FINALIZED=4', 'SYMBOLIZED=2'):
            assert expected in process.stdout, (out, expected, process.stdout)
        locations = [line for line in process.stdout.splitlines() if line.startswith('WHERE=')]
        assert len(locations) == 2 and all('Checked|' in line and '|UnwindCore.pas|' in line for line in locations), locations
        dump = subprocess.check_output([objdump, '--dwarf=info', str(binary)], text=True, errors='replace')
        (out/'dwarf.txt').write_text(dump)
        methods = 0
        # Inspect each DIE independently; CU low/high attributes must never be
        # paired with method boundaries or a different DIE's missing attribute.
        for die in re.split(r'(?m)^\s*<\d+><[0-9a-f]+>:', dump):
            if not re.match(r'[^\n]*DW_TAG_subprogram', die):
                continue
            low = re.search(r'DW_AT_low_pc\s*:\s*(0x[0-9a-f]+)', die)
            high = re.search(r'DW_AT_high_pc\s*:\s*(0x[0-9a-f]+)', die)
            if low and high:
                lo, hi = int(low[1], 16), int(high[1], 16)
                assert hi >= lo, (out, lo, hi)
                assert lo != 0 or hi == 0, (out, 'mismatched discarded owner', lo, hi)
                methods += 1
        assert methods > 0, ('objdump format was not parsed', out)
        post = out/('UnwindCheck.second'+suffix)
        transformed = subprocess.run([str(helper), str(binary), str(post), objcopy], capture_output=True, text=True)
        assert transformed.returncode == 0, transformed
        if mode in ('full', 'mixed'):
            assert transformed.stdout.startswith('UNCHANGED:'), transformed.stdout
            assert binary.read_bytes() == post.read_bytes(), ('partial rewrite of full/mixed input', out)
        rerun = subprocess.run([str(post)], cwd=out, capture_output=True, text=True, timeout=30)
        assert rerun.returncode == 0 and rerun.stdout == process.stdout, (out, rerun.stdout, rerun.stderr)
        matrix.append(dict(reverse=reverse, mode=mode, methods=methods, lookup=locations,
                           helper=transformed.stdout.strip(), output=process.stdout))
        print('PASS', mode, 'reverse' if reverse else 'forward', flush=True)

evidence = dict(compiler=str(compiler), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
                helper=str(helper), helper_sha256=hashlib.sha256(helper.read_bytes()).hexdigest(),
                objdump=objdump, objcopy=objcopy, synthetic=results, matrix=matrix)
(root/'result.json').write_text(json.dumps(evidence, indent=2))
print('COMPACT_DWARF_GATE_PASS', flush=True)
