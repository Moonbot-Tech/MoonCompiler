#!/usr/bin/env python3
"""Audit unpublished commit metadata against published contributor identities."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CYRILLIC = re.compile(r"[\u0400-\u052f]")
AI_ATTRIBUTION = re.compile(r"\b(?:claude|chatgpt|openai|cursor|copilot|gemini)\b", re.I)


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True,
                                   encoding="utf-8", errors="replace").strip()


def main() -> int:
    remote = git("rev-parse", "origin/main")
    public = git("ls-remote", "origin", "refs/heads/main").split()[0]
    if remote != public:
        raise ValueError(f"origin/main is stale: local {remote}, public {public}")
    # A contributor's latest accepted commit does not change the identities
    # allowed for the next release. Validate against published history.
    identities = set(git("log", "--format=%an <%ae>%n%cn <%ce>", "origin/main").splitlines())
    if not identities:
        raise ValueError("public main has no author/committer identities")
    commits = git("rev-list", "--reverse", "origin/main..HEAD").splitlines()
    problems = []
    for commit in commits:
        fields = git("show", "-s", "--format=%an <%ae>%n%cn <%ce>%n%B", commit).splitlines()
        if len(fields) < 2:
            problems.append(f"{commit[:12]}: malformed commit")
            continue
        author, committer = fields[:2]
        message = "\n".join(fields[2:])
        if author not in identities or committer not in identities:
            problems.append(f"{commit[:12]}: author/committer absent from published history")
        if CYRILLIC.search(message) or CYRILLIC.search(author + committer):
            problems.append(f"{commit[:12]}: Cyrillic metadata")
        trailers = "\n".join(line for line in message.splitlines()
                             if re.match(r"(?i)(co-authored-by|authored-by|generated-by):", line))
        if AI_ATTRIBUTION.search(author + committer + "\n" + trailers):
            problems.append(f"{commit[:12]}: AI attribution in metadata")
    if problems:
        print("HISTORY_AUDIT_FAIL")
        for problem in problems:
            print(problem)
        return 1
    print(f"HISTORY_AUDIT_PASS remote={remote} commits={len(commits)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"HISTORY_AUDIT_FAIL {error}", file=sys.stderr)
        raise SystemExit(1)
