#!/usr/bin/env python3
"""Verify every measured Pulse body against its executable and report linked shape."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import linked_image
import pulse


def image_shapes(exe: Path):
    shapes = linked_image.ImageShapes(exe)
    return shapes.anchor, shapes


def root_signature(root: dict | None, callees: list[dict]) -> tuple:
    if root is None:
        return ()
    # R1 fixes procedure entries modulo 64. Keep the 4 KiB page offset so
    # distinct aligned line addresses remain distinct placements.
    return (
        root["begin"] % 4096,
        tuple(loop["target_mod64"] for loop in root.get("loops", [])),
        tuple(
            sorted(
                (
                    callee["name"],
                    callee["begin"] % 4096,
                    tuple(
                        loop["target_mod64"]
                        for loop in callee.get("loops", [])
                    ),
                )
                for callee in callees
            )
        ),
    )


def effective_signature(case: dict) -> tuple:
    return (
        root_signature(case["body"], case.get("direct_callees", [])),
        root_signature(
            case.get("work_body"), case.get("work_direct_callees", [])
        ),
    )


def check(result: Path, families: list[str]) -> list[dict]:
    collected, manifest = pulse.collect(result)
    programs = {record['program'] for record in manifest['runs']}
    if not programs:
        raise ValueError('no measured programs to verify')
    output = []
    for family in families:
        for program in sorted(programs):
            placements = []
            for suffix in ('', '1', '2', '3'):
                system = family + suffix
                records = [r for r in manifest['runs'] if r['system'] == system and r['program'] == program]
                identities = {(r.get('executable'), r.get('executable_sha256')) for r in records}
                if len(identities) != 1 or any(not name or not digest for name, digest in identities):
                    raise ValueError(f'{system}/{program}: missing or inconsistent executable identity')
                filename, digest = identities.pop()
                exe = pulse.ROOT / filename
                if not exe.is_file() or pulse.sha256(exe) != digest:
                    raise ValueError(f'{exe}: executable missing or changed')
                anchor, shapes = image_shapes(exe)
                cases = {}
                for (row_system, row_program, case), row in collected.items():
                    if (row_system, row_program) != (system, program):
                        continue
                    if not row['body_offsets']:
                        raise ValueError(f'{system}/{program}/{case}: missing measured body identity')
                    body = anchor + row['body_offsets'][0]
                    shape = shapes.get(body)
                    if shape is None or any(address % 64 != body % 64 for address in row['bodies']):
                        raise ValueError(f'{system}/{program}/{case}: measured body does not match executable')
                    # Indirect calls remain explicit: this is not a complete dynamic call graph.
                    callees = {call['target']: shapes[call['target']] for call in shape['calls']
                               if call['target'] in shapes}
                    cases[case] = {'body': shape, 'direct_callees': list(callees.values())}
                    if row['work_body_offsets']:
                        work_body = anchor + row['work_body_offsets'][0]
                        work_shape = shapes.get(work_body)
                        if work_shape is None or any(address % 64 != work_body % 64 for address in row['work_bodies']):
                            raise ValueError(f'{system}/{program}/{case}: worker body does not match executable')
                        cases[case]['work_body'] = work_shape
                        cases[case]['work_direct_callees'] = [shapes[call['target']] for call in work_shape['calls']
                                                             if call['target'] in shapes]
                    elif program == 'threads':
                        raise ValueError(f'{system}/{program}/{case}: missing worker code root')
                placements.append(cases)
            if any(set(item) != set(placements[0]) for item in placements):
                raise ValueError(f'{family}/{program}: measured case matrix differs')
            for case in sorted(placements[0]):
                rows = [placement[case]['body'] for placement in placements]
                if len({row['begin'] for row in rows}) != 4:
                    raise ValueError(f'{family}/{program}/{case}: body did not acquire four distinct addresses')
                if len({row['proof_sha256'] for row in rows}) != 1:
                    raise ValueError(f'{family}/{program}/{case}: body instructions changed across fillers')
                work_roots = [placement[case].get('work_body') for placement in placements]
                if any(work_roots):
                    if not all(work_roots) or len({row['begin'] for row in work_roots}) != 4:
                        raise ValueError(f'{family}/{program}/{case}: worker body did not acquire four distinct addresses')
                    if len({row['proof_sha256'] for row in work_roots}) != 1:
                        raise ValueError(f'{family}/{program}/{case}: worker instructions changed across fillers')
                for key in ('direct_callees', 'work_direct_callees'):
                    proofs = [{(callee['name'], callee['proof_sha256'])
                               for callee in placement[case].get(key, [])} for placement in placements]
                    if any(proof != proofs[0] for proof in proofs[1:]):
                        raise ValueError(f'{family}/{program}/{case}: {key} changed across fillers')
                signatures = [effective_signature(placement[case]) for placement in placements]
                if len(set(signatures)) < 2:
                    raise ValueError(
                        f'{family}/{program}/{case}: effective placement coverage '
                        f'collapsed to {len(set(signatures))}/4 signatures'
                    )
                output.append({'family': family, 'program': program, 'case': case,
                               'effective_signatures': signatures,
                               'placements': [placement[case] for placement in placements]})
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('result', type=Path)
    parser.add_argument('--families', default='B,C')
    args = parser.parse_args()
    rows = check(args.result, args.families.split(','))
    (args.result / 'program-placement.json').write_text(json.dumps(rows, indent=2) + '\n', encoding='utf-8')
    print(f'PROGRAM_PLACEMENT_PASS measured_cases={len(rows)}; body/calls/branches/loops reported')


if __name__ == '__main__':
    main()
