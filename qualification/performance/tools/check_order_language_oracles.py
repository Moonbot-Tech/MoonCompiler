#!/usr/bin/env python3
"""Reject deliberately broken Linux controls before trusting their measurements."""
import argparse
import json
from pathlib import Path
import subprocess


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    a.output = a.output.resolve()
    a.output.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[1] / 'threads'
    c = (root / 'pulse_orders_native_workload.h').read_text()
    rust = (root / 'pulse_orders_rust.rs').read_text()
    controls = {
        'wrong-recipient': ('atomic_store(&workers[i].issued, round);', 'atomic_store(&workers[i].issued, round + 1);',
                            'assert_eq!(w.issued.load(SeqCst), row.received + 1,', 'assert_eq!(w.issued.load(SeqCst), row.received + 2,'),
        'early-timeout': ('static bool event_wait(event *e, int ms) {', 'static bool event_wait(event *e, int ms) {\n    if (ms == 2) return false;',
                          'fn wait(&self, milliseconds: Option<u64>) -> bool {', 'fn wait(&self, milliseconds: Option<u64>) -> bool {\n        if milliseconds == Some(2) { return false; }'),
        'dropped-log': ('++w->delivered;', 'w->delivered += 0;', 'delivered[id].count += 1;', 'delivered[id].count += 0;'),
        'early-exit': ('int n = selected_only ? signals : rounds;\n    for', 'int n = 1;\n    for',
                       'for step in 1..=n {', 'for step in 1..=1 {'),
    }
    results = []
    for language in ('c', 'cpp', 'rust'):
        for name, replacements in controls.items():
            source = rust if language == 'rust' else c
            old, new = replacements[2:] if language == 'rust' else replacements[:2]
            assert source.count(old) == 1
            path = a.output / (name + '-' + language + ('.rs' if language == 'rust' else '.cpp' if language == 'cpp' else '.c'))
            path.write_text(('#define ORDER_CPP_EVENT\n' if language == 'cpp' else '') + source.replace(old, new))
            binary = path.with_suffix('')
            command = (['rustc', '-O', str(path), '-o', str(binary)] if language == 'rust' else
                       ['g++' if language == 'cpp' else 'gcc', '-O2', '-pthread', '-std=c++20' if language == 'cpp' else '-std=c11', str(path), '-o', str(binary)])
            subprocess.run(command, capture_output=True, text=True, check=True)
            proc = subprocess.run([str(binary), 'orders', '1', '40', '2', '2'], capture_output=True, text=True, timeout=15)
            rejected = proc.returncode != 0 and 'verified=1' not in proc.stdout
            results.append(dict(language=language, control=name, rejected=rejected, returncode=proc.returncode,
                                stdout=proc.stdout, stderr=proc.stderr))
            (a.output / 'results.json').write_text(json.dumps(results, indent=2))
            assert rejected, results[-1]
            print(language, name, 'REJECTED', flush=True)


if __name__ == '__main__':
    main()
