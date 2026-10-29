import collections
import json
from pathlib import Path
import statistics
import sys

rows = [json.loads(line) for line in Path(sys.argv[1]).read_text().splitlines()]
groups = collections.defaultdict(dict)
for row in rows:
    key = tuple(row[x] for x in ('encoding', 'count', 'profile', 'hit_percent', 'same_pointer'))
    groups[key][row['repeat'], row['variant']] = row
summary = []
for key, group in groups.items():
    repeats = sorted({repeat for repeat, variant in group})
    assert len(repeats) == 3
    pairs = [(group[r, 'copied-rtl'], group[r, 'fused']) for r in repeats]
    item = dict(zip(('encoding', 'count', 'profile', 'hit_percent', 'same_pointer'), key))
    for metric in ('lookup_ns', 'lookup_cpu_ns', 'enum_ns', 'enum_cpu_ns', 'build_ns'):
        item[metric + '_ratio'] = statistics.median(b[metric] / a[metric] for a, b in pairs)
        item[metric + '_control'] = statistics.median(a[metric] for a, b in pairs)
        item[metric + '_fused'] = statistics.median(b[metric] for a, b in pairs)
    assert all(a['table_live_bytes'] == b['table_live_bytes'] for a, b in pairs)
    assert all(b['lookup_allocations'] == 0 for a, b in pairs)
    summary.append(item)
Path(sys.argv[1]).with_suffix('.summary.json').write_text(json.dumps(summary, indent=2))
for metric in ('lookup_cpu_ns', 'enum_cpu_ns'):
    print(metric, 'range', min(x[metric + '_ratio'] for x in summary), max(x[metric + '_ratio'] for x in summary))
    for item in sorted(summary, key=lambda x: x[metric + '_ratio'], reverse=True)[:8]:
        print({k: item[k] for k in ('encoding', 'count', 'profile', 'hit_percent', 'same_pointer', metric + '_ratio')})
print('ASCII90 independent')
for item in summary:
    if item['profile'] == 0 and item['hit_percent'] == 90 and item['same_pointer'] == 0:
        print(item)
