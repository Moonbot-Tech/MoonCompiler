"""Fail-closed layout acceptance over a declared matrix; standard library only."""
import argparse
import collections
import csv
import hashlib
import itertools
import json
import math
from pathlib import Path
import re
import statistics


SAMPLE = re.compile(r'^S (\S+) c(\d+) (\S+) p(\d+) d(\d+) r(\d+) ([0-9.]+)$')
DONE = re.compile(r'^INPROC_DONE func=(\S+) family=(\d+) drivers=(\d+) entries=(\d+) rounds=(\d+) length_case=(\d+)$')
FIELDS = ('cpu', 'file', 'group', 'case', 'tag', 'pos', 'driver', 'refphase', 'ref', 'candidate', 'loss', 'aa')
KEY_FIELDS = FIELDS[:8]


class InvalidEvidence(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidEvidence(message)


def unique(values, name, kind=str):
    require(isinstance(values, list) and values, f'{name}: nonempty list required')
    require(all(type(value) is kind for value in values), f'{name}: wrong value type')
    require(len(values) == len(set(values)), f'{name}: duplicate values')
    return tuple(values)


def finite(value, name, positive=False):
    require(type(value) in (int, float), f'{name}: number required')
    require(math.isfinite(value) and (value > 0 if positive else value >= 0), f'{name}: invalid number')
    return float(value)


def load_spec(manifest, base):
    require(manifest.get('schema') == 1, 'unsupported manifest schema')
    cpus = unique(manifest.get('cpus'), 'cpus')
    processes = unique(manifest.get('processes'), 'processes')
    require(len(processes) >= 2, 'at least two independently launched processes required')
    axes = {name: unique(manifest.get(name), name, int) for name in ('rounds', 'positions', 'drivers')}
    require(all(value >= 0 for name in ('positions', 'drivers') for value in axes[name]), 'negative placement')
    require(all(value > 0 for value in axes['rounds']), 'round numbers must be positive')
    require(len(axes['rounds']) >= 3, 'at least three rounds required')
    limits = manifest.get('limits', {})
    defaults = {'aa': 1, 'loss': 5, 'gain': 10, 'dispersion': 2,
                'monitor_mean': 2, 'monitor_peak': 20, 'counter_uncertainty': 1}
    limits = {name: finite(limits.get(name, default), 'limit ' + name) for name, default in defaults.items()}
    require(limits['aa'] <= 1 and limits['loss'] <= 5 and limits['gain'] >= 10, 'thresholds weaken user acceptance criteria')
    require(limits['dispersion'] <= 2, 'dispersion limit weakens acceptance criteria')
    require(limits['monitor_mean'] <= 2 and limits['monitor_peak'] <= 20, 'monitor limits weaken acceptance criteria')
    require(limits['counter_uncertainty'] < 100, 'invalid counter uncertainty')
    variants = manifest.get('expected_variants', {})
    require(set(variants) == set(cpus), 'expected_variants must declare every CPU exactly once')
    require(all(type(value) is int and value > 0 for value in variants.values()), 'invalid expected_variants')
    identity = manifest.get('cpu_identity', {})
    require(set(identity) == set(cpus), 'cpu_identity must declare every CPU exactly once')
    for cpu, item in identity.items():
        require(isinstance(item, dict) and isinstance(item.get('brand'), str) and item['brand'], cpu + ': brand required')
        require(type(item.get('affinity_cpu')) is int and item['affinity_cpu'] >= 0, cpu + ': affinity_cpu required')
    groups = {}
    require(isinstance(manifest.get('groups'), list) and manifest['groups'], 'no declared groups')
    for item in manifest['groups']:
        name = item.get('name')
        require(isinstance(name, str) and name and name not in groups, 'missing or duplicate group name')
        group = {axis: unique(item.get(axis), name + ' ' + axis, int if axis in ('cases', 'refphases') else str)
                 for axis in ('cases', 'tags', 'refphases')}
        group['cpus'] = unique(item.get('cpus', list(cpus)), name + ' cpus')
        require(set(group['cpus']) == set(cpus), name + ': every declared CPU is required for every group')
        require(all(value >= 0 for axis in ('cases', 'refphases') for value in group[axis]), name + ': negative case or phase')
        require(not any(tag.startswith(('refp', 'aap')) for tag in group['tags']), name + ': reserved candidate tag')
        group['alltags'] = group['tags'] + tuple(f'{prefix}{phase}' for phase in group['refphases'] for prefix in ('refp', 'aap'))
        groups[name] = group
    profile = manifest.get('profile', 'acceptance')
    require(profile in ('acceptance', 'probe'), 'unknown evidence profile')
    if profile == 'acceptance':
        require(set(axes['positions']) == set(range(0, 4096, 64)), 'acceptance requires all 64 positions including 0')
        require(set(axes['drivers']) == {0, 32}, 'acceptance requires driver phases 0/32')
    runs, paths = [], set()
    require(isinstance(manifest.get('runs'), list) and manifest['runs'], 'no declared runs')
    for entry in manifest['runs']:
        run = dict(entry)
        require(run.get('cpu') in cpus and run.get('process') in processes, 'run has undeclared CPU or process')
        run['cases'] = unique(run.get('cases'), 'run cases', int)
        require(run.get('accepted') is True and type(run.get('exit_code')) is int and run['exit_code'] == 0,
                'run was rejected or lacks successful exit status')
        for metric in ('monitor_mean', 'monitor_peak'):
            require(finite(run.get(metric), metric) <= limits[metric], 'run monitor limit exceeded: ' + metric)
        require(isinstance(run.get('raw'), str) and run['raw'], 'run raw path required')
        run['path'] = (base / run['raw']).resolve()
        require(run['path'] not in paths, 'same raw file assigned to multiple launches')
        require(run['path'].is_file(), 'missing raw file: ' + str(run['path']))
        paths.add(run['path'])
        runs.append(run)
    expected = set()
    for name, group in groups.items():
        expected.update(itertools.product(group['cpus'], processes, [name], group['cases'], group['alltags'],
                                          axes['positions'], axes['drivers'], axes['rounds']))
    return cpus, processes, axes, limits, variants, groups, runs, expected, identity


def parse_runs(spec):
    cpus, processes, axes, limits, variants, groups, runs, expected, identity = spec
    observed, origins, hashes, filemap, owners = {}, {}, set(), set(), {}
    for run in runs:
        path, cpu, process = run['path'], run['cpu'], run['process']
        content = path.read_bytes()
        digest = hashlib.sha256(content).hexdigest()
        require(digest not in hashes, 'identical raw evidence reused across launches')
        hashes.add(digest)
        if 'raw_sha256' in run:
            require(digest == run['raw_sha256'], 'raw SHA256 mismatch: ' + str(path))
        require((cpu, path.name) not in filemap, 'ambiguous CSV filename within CPU')
        filemap.add((cpu, path.name))
        counts, completed, measured, headers = collections.defaultdict(list), {}, set(), 0
        for line_number, line in enumerate(content.decode('utf-8', errors='strict').splitlines(), 1):
            if line.startswith('# asmstand2 '):
                headers += 1
                brand = re.search(r'\bcpu="([^"]+)"', line)
                affinity = re.search(r'\baffinity_cpu=(\d+)\b', line)
                require(brand is not None and affinity is not None, f'{path}: malformed CPU identity header')
                require(brand[1] == identity[cpu]['brand'] and int(affinity[1]) == identity[cpu]['affinity_cpu'],
                        f'{path}: CPU brand or affinity disagrees with manifest')
            if line.startswith(('ORACLE_', 'GEOMETRY_')) and not line.startswith(('ORACLE_OK ', 'GEOMETRY_OK ')):
                raise InvalidEvidence(f'{path}:{line_number}: correctness failure')
            for name in ('ORACLE_OK', 'GEOMETRY_OK'):
                if line.startswith(name):
                    match = re.fullmatch(name + r' (\d+)/(\d+)', line)
                    require(match is not None, f'{path}:{line_number}: malformed {name}')
                    counts[name].append(tuple(map(int, match.groups())))
            match = SAMPLE.fullmatch(line)
            if line.startswith('S '):
                require(match is not None, f'{path}:{line_number}: malformed sample')
            if match:
                name, case, tag, position, driver, round_number, value = match.groups()
                if name not in groups:
                    continue
                case, position, driver, round_number = map(int, (case, position, driver, round_number))
                require(case in run['cases'], f'{path}:{line_number}: case absent from run declaration')
                owner = cpu, process, name, case
                require(owner not in owners or owners[owner] == path, f'{path}: same process/group/case split across raw launches')
                owners[owner] = path
                key = cpu, process, name, case, tag, position, driver, round_number
                require(key in expected, f'{path}:{line_number}: undeclared matrix cell {key}')
                require(key not in observed, f'{path}:{line_number}: duplicate round or process evidence {key}')
                observed[key] = finite(float(value), str(key), positive=True)
                origins[key[:-1]] = path.name
                measured.add((name, case))
            match = DONE.fullmatch(line)
            if line.startswith('INPROC_DONE'):
                require(match is not None, f'{path}:{line_number}: malformed completion')
            if match:
                name, family, drivers, entries, rounds, case = match.groups()
                if name not in groups:
                    continue
                key = name, int(case)
                require(key not in completed, f'{path}:{line_number}: duplicate completion')
                group = groups[name]
                expected_counts = len(axes['positions']), len(axes['drivers']), len(group['alltags']) * len(axes['positions']) * len(axes['drivers']), len(axes['rounds'])
                require(tuple(map(int, (family, drivers, entries, rounds))) == expected_counts,
                        f'{path}:{line_number}: completion counts disagree with manifest')
                completed[key] = True
        for name in ('ORACLE_OK', 'GEOMETRY_OK'):
            require(counts[name] == [(variants[cpu], variants[cpu])], f'{path}: missing, repeated or partial {name}')
        require(headers == 1, f'{path}: missing or repeated CPU identity header')
        require(measured, f'{path}: no declared group measured')
        require(set(completed) == measured, f'{path}: missing or extraneous INPROC_DONE')
    missing = expected - observed.keys()
    require(not missing, f'incomplete matrix: {len(missing)} missing samples; example {next(iter(missing), None)}')
    medians, dispersion = {}, {}
    for key in observed:
        cell = key[:-1]
        if cell not in medians:
            values = [observed[cell + (round_number,)] for round_number in axes['rounds']]
            medians[cell] = statistics.median(values)
            q25, _, q75 = statistics.quantiles(values, n=4, method='inclusive')
            dispersion[cell] = 100 * (q75 / q25 - 1)
    rows = []
    for name, group in groups.items():
        for cpu, process, case, tag, position, driver, phase in itertools.product(
                group['cpus'], processes, group['cases'], group['tags'], axes['positions'], axes['drivers'], group['refphases']):
            prefix = cpu, process, name, case
            suffix = position, driver
            candidate = medians[prefix + (tag,) + suffix]
            ref = medians[prefix + (f'refp{phase}',) + suffix]
            aa = medians[prefix + (f'aap{phase}',) + suffix]
            file = origins[prefix + (tag,) + suffix]
            rows.append(dict(cpu=cpu, process=process, file=file, group=name, case=case, tag=tag, pos=position,
                             driver=driver, refphase=phase, ref=ref, candidate=candidate,
                             loss=100 * (candidate / ref - 1), aa=100 * abs(aa / ref - 1),
                             ref_dispersion=dispersion[prefix + (f'refp{phase}',) + suffix],
                             control_dispersion=dispersion[prefix + (f'aap{phase}',) + suffix],
                             candidate_dispersion=dispersion[prefix + (tag,) + suffix]))
    return rows


def verify_csv(path, rows):
    expected = {tuple(row[field] for field in KEY_FIELDS): row for row in rows}
    observed = set()
    with path.open(newline='', encoding='utf-8-sig') as stream:
        reader = csv.DictReader(stream)
        require(reader.fieldnames is not None and set(FIELDS) <= set(reader.fieldnames), 'CSV missing required columns')
        for row in reader:
            for field in ('case', 'pos', 'driver', 'refphase'):
                row[field] = int(row[field])
            key = tuple(row[field] for field in KEY_FIELDS)
            require(key in expected and key not in observed, 'CSV unexpected or duplicate cell: ' + str(key))
            observed.add(key)
            for field in ('ref', 'candidate', 'loss', 'aa'):
                value = float(row[field])
                require(math.isfinite(value) and math.isclose(value, expected[key][field], rel_tol=1e-9, abs_tol=1e-7),
                        'CSV disagrees with raw: ' + str(key) + ' ' + field)
    require(observed == expected.keys(), f'CSV missing {len(expected.keys() - observed)} comparisons')


def judge(manifest, base, cells=None):
    spec = load_spec(manifest, base)
    rows = parse_runs(spec)
    if cells is not None:
        verify_csv(cells, rows)
    limits, groups = spec[3], spec[5]
    acceptance_eligible = manifest.get('profile', 'acceptance') == 'acceptance' and len(spec[1]) >= 3
    results = []
    for name, group in groups.items():
        for tag in group['tags']:
            values = [row for row in rows if row['group'] == name and row['tag'] == tag]
            paired = collections.defaultdict(list)
            for row in values:
                uncertainty = (1 + row['aa'] / 100) / (1 - limits['counter_uncertainty'] / 100)
                row['upper_loss'] = 100 * (row['candidate'] / row['ref'] * uncertainty - 1)
                row['lower_loss'] = 100 * (row['candidate'] / row['ref'] / uncertainty - 1)
                key = tuple(row[field] for field in ('cpu', 'case', 'pos', 'driver', 'refphase'))
                paired[key].append(row)
            noisy = [row for row in values if row['aa'] > limits['aa'] or
                     max(row[field] for field in ('ref_dispersion', 'control_dispersion', 'candidate_dispersion')) > limits['dispersion']]
            hard = [cell for cell in paired.values() if all(
                row['aa'] <= limits['aa'] and row['lower_loss'] > limits['loss'] and
                max(row[field] for field in ('ref_dispersion', 'control_dispersion', 'candidate_dispersion')) <= limits['dispersion']
                for row in cell)]
            reproduced_gain = any(all(row['upper_loss'] < -limits['gain'] for row in cell) for cell in paired.values())
            all_faster = all(row['upper_loss'] < 0 for row in values)
            within_loss = all(row['upper_loss'] <= limits['loss'] for row in values)
            verdict = 'REJECT' if hard else 'UNPROVEN'
            if acceptance_eligible and not hard and not noisy and (all_faster or (within_loss and reproduced_gain)):
                verdict = 'ACCEPT'
            worst = max(values, key=lambda row: row['upper_loss'])
            results.append(dict(group=name, tag=tag, verdict=verdict, comparisons=len(values), noisy=len(noisy),
                                hard_cells=len(hard), reproduced_gain=reproduced_gain, all_faster=all_faster, worst=worst))
    return dict(status='ACCEPT' if all(result['verdict'] == 'ACCEPT' for result in results) else 'KEEP_OLD',
                results=results, comparisons=len(rows), acceptance_eligible=acceptance_eligible,
                unit='One driver sweep; cycles are not normalized primitive-call latency.',
                scope='Declared CPU/case/entry/caller matrix only; no arbitrary-context guarantee.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--cells', type=Path, help='Optional existing audit CSV to verify against raw')
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    try:
        manifest = json.loads(args.manifest.read_text(encoding='utf-8-sig'))
        report = judge(manifest, args.manifest.resolve().parent, args.cells)
    except (InvalidEvidence, OSError, UnicodeError, ValueError, KeyError, TypeError) as error:
        report = dict(status='INVALID', error=str(error))
    output = json.dumps(report, ensure_ascii=False, indent=2) + '\n'
    if args.out:
        args.out.write_text(output, encoding='utf-8')
    print(output, end='')
    return 0 if report['status'] == 'ACCEPT' else 2 if report['status'] == 'INVALID' else 1


if __name__ == '__main__':
    raise SystemExit(main())
