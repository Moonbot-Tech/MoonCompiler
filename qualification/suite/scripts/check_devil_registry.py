#!/usr/bin/env python3
"""Keep every Devil finding represented by the complete public registry.

The registry has three structural views that must describe the same set:

  * `findings/dvl-NNNN-*/` — the analysis directory;
  * `FINDINGS_JOURNAL.md` — the finding list grouped by meaning;
  * `STATUS.md` — the status table.

The active known-output registry is a fourth, semantic view: every masked
difference must remain an explicitly accepted deviation in `KNOWN_ISSUES.md`.
The check also rejects a journal entry without an analysis directory, a
directory without `FINDING.md`, and a generator source that explicitly disables
a shape because of a dvl finding. It belongs in every gate because it performs
no build and completes in a fraction of a second.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

from qualification_contracts import (
    LOCKS_PATH,
    MANIFEST_PATH,
    load_json,
    require_retirement_only,
    validate_focused_gate,
    validate_resident_layer,
)

DEVIL = Path(__file__).resolve().parents[1] / "tests" / "devil"
ID_RE = re.compile(r"dvl-(\d{4})")


def ids_in(text: str) -> set[str]:
    return set(ID_RE.findall(text))


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--devil", type=Path, default=DEVIL)
    args = p.parse_args()
    devil = args.devil.resolve()

    manifest = load_json(MANIFEST_PATH)
    locks = load_json(LOCKS_PATH)
    validate_focused_gate(manifest, locks, "win64-repairs")
    layer, _ = validate_resident_layer(manifest, locks)
    require_retirement_only(manifest)

    findings = devil / "findings"
    journal = devil / "FINDINGS_JOURNAL.md"
    status = devil / "STATUS.md"
    known_registry = devil / "known_findings.json"
    known_issues = (MANIFEST_PATH.parent / layer["known_issues"]).resolve()
    generator = Path(__file__).with_name("generate_devil.py")

    folders: dict[str, Path] = {}
    for path in sorted(findings.iterdir()) if findings.is_dir() else []:
        if not path.is_dir():
            continue
        m = ID_RE.match(path.name)
        if m:
            folders[m.group(1)] = path

    problems: list[str] = []

    status_text = status.read_text(encoding="utf-8") if status.is_file() else ""
    for key in ("source", "runner", "readme"):
        target = (MANIFEST_PATH.parent / layer[key]).resolve()
        relative = os.path.relpath(target, status.parent).replace("\\", "/")
        if f"]({relative})" not in status_text:
            problems.append(f"STATUS misses resident {key} link: {relative}")

    for number, path in folders.items():
        if not (path / "FINDING.md").is_file():
            problems.append(
                "dvl-%s: directory has no analysis (%s)" % (number, path.name)
            )

    # Findings deliberately retained without a dedicated analysis directory.
    excused = devil / "findings" / "UNANALYZED.md"
    without_folder = (ids_in(excused.read_text(encoding="utf-8"))
                      if excused.is_file() else set())

    in_journal = ids_in(journal.read_text(encoding="utf-8")) if journal.is_file() else set()
    in_status = ids_in(status_text)

    known_data = load_json(known_registry)
    known_entries = known_data.get("known", [])
    if not isinstance(known_entries, list):
        problems.append("known_findings.json: 'known' must be an array")
        known_entries = []
    active_known: set[str] = set()
    for entry in known_entries:
        match = (ID_RE.fullmatch(str(entry.get("id", "")))
                 if isinstance(entry, dict) else None)
        if match is None:
            problems.append("known_findings.json: every entry must have a dvl-NNNN id")
            continue
        active_known.add(match.group(1))

    known_issues_text = (known_issues.read_text(encoding="utf-8")
                         if known_issues.is_file() else "")
    accepted_marker = "## Devil: accepted deviations"
    if accepted_marker not in known_issues_text:
        problems.append("KNOWN_ISSUES misses the Devil accepted-deviations section")
        accepted_ids: set[str] = set()
    else:
        accepted_section = known_issues_text.split(accepted_marker, 1)[1]
        accepted_section = accepted_section.split("\n## ", 1)[0]
        accepted_ids = ids_in(accepted_section)

    for number in sorted(active_known - accepted_ids):
        problems.append(
            "dvl-%s: active known-output mask is not an accepted deviation"
            % number
        )

    if generator.is_file():
        for line_number, line in enumerate(
            generator.read_text(encoding="utf-8").splitlines(), 1
        ):
            if re.search(r"\b(?:disabled|deregistered|removed)\b.*\bdvl-\d{4}\b",
                         line, re.IGNORECASE):
                problems.append(
                    "generate_devil.py:%d explicitly disables a dvl shape" % line_number
                )

    for number in sorted(folders):
        if number not in in_journal:
            problems.append("dvl-%s: analyzed but absent from the journal" % number)
        if number not in in_status:
            problems.append(
                "dvl-%s: analyzed but absent from the STATUS table" % number
            )

    # A documented id must either have an analysis directory or be explicitly
    # listed in UNANALYZED.md.
    for number in sorted(in_journal - set(folders) - without_folder):
        problems.append(
            "dvl-%s: journal entry has no findings analysis" % number
        )

    for number in sorted(active_known - set(folders) - without_folder):
        problems.append(
            "dvl-%s: active known-output mask has no findings analysis" % number
        )

    if problems:
        for line in problems:
            print("  NEW " + line)
        print("DEVIL_REGISTRY FINDINGS folders=%d problems=%d"
              % (len(folders), len(problems)))
        sys.exit(1)
    print("DEVIL_REGISTRY OK folders=%d excused=%d"
          % (len(folders), len(without_folder)))


if __name__ == "__main__":
    main()
