#!/usr/bin/env python3
"""Index every cached official FPC issue against official Git history/tests.

This is a mechanical evidence index, not a semantic issue verdict.  It keeps
all tracker rows and exposes the smaller sets that still need human scope and
reproducer review.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
ISSUE_DIR = ROOT / "cache" / "issues" / "fpc"
REPO = ROOT / "repos" / "fpc"
FIXTURES = ROOT / "fixtures" / "known"
OUT = ROOT / "research"
FPC_3_2_2_RELEASED_AT = "2021-05-15T15:38:31.000Z"

ISSUE_REF_RE = re.compile(
    r"(?ix)"
    r"(?:"
    r"(?:fix(?:e[sd])?|bug(?:\s*(?:id|report))?|issue|mantis|upstream)"
    r"[\s:#!()\[\]-]*"
    r"|(?:work_items|issues)/"
    r"|\#"
    r"|\bi(?=\d{5}\b)"
    r")"
    r"(\d{2,6})"
)
TEST_REF_RE = re.compile(
    r"(?i)(?:bug|issue|mantis|work_items|issues)[^\r\n\d]{0,24}(\d{2,6})"
)
WEB_TEST_RE = re.compile(r"^tests/webtb[fs]/tw(\d+)[^/]*\.pp$", re.I)
FIXTURE_RE = re.compile(r"^fpc_(\d+)_.*\.pas$", re.I)
PASCAL_SOURCE_SUFFIXES = {".dpr", ".lpr", ".p", ".pas", ".pp"}

NON_X64_TARGET_RE = re.compile(
    r"(?i)\b(?:aarch64|arm(?:el|hf)?|powerpc|ppc|m68k|riscv|wasm|avr|"
    r"sparc|mips|loongarch|xtensa|i8086|msdos|go32v2|macos|darwin|"
    r"freebsd|android|ios)\b"
)
X64_TARGET_RE = re.compile(r"(?i)\b(?:x86[_-]?64|amd64|win64|linux|windows)\b")
CODEGEN_RE = re.compile(
    r"(?i)\b(?:wrong\s+code|miscompil|code\s+generation|optimizer|optimis|"
    r"regvar|register\s+alloc|incorrect\s+(?:result|value|code)|-O[1234]|"
    r"inline|overflow|corrupt|wrong\s+(?:result|value))\b"
)
FEATURE_RE = re.compile(r"(?i)\b(?:feature request|\bfr\s*:|enhancement|support for)\b")


def git(*args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(REPO), *args],
        text=True,
        errors="replace",
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_issues() -> list[dict]:
    rows: list[dict] = []
    for page_path in sorted(ISSUE_DIR.glob("page-*.json")):
        page = int(page_path.stem.split("-")[1])
        with page_path.open(encoding="utf-8") as stream:
            page_rows = json.load(stream)
        for ordinal, row in enumerate(page_rows, 1):
            row = dict(row)
            row["snapshot_page"] = page
            row["snapshot_ordinal"] = ordinal
            rows.append(row)
    return rows


def test_path_refs() -> dict[int, set[str]]:
    refs: dict[int, set[str]] = defaultdict(set)
    for path in git("ls-tree", "-r", "--name-only", "HEAD", "tests").splitlines():
        match = WEB_TEST_RE.match(path)
        if match:
            refs[int(match.group(1))].add(path)

    grep = subprocess.run(
        [
            "git", "-C", str(REPO), "grep", "-n", "-I", "-i", "-E",
            r"(bug|issue|mantis|work_items).{0,40}[0-9][0-9]", "HEAD", "--", "tests",
        ],
        text=True,
        errors="replace",
        stdout=subprocess.PIPE,
        check=False,
    )
    for line in grep.stdout.splitlines():
        if line.startswith("HEAD:"):
            line = line.removeprefix("HEAD:")
        path, _, remainder = line.partition(":")
        _, _, content = remainder.partition(":")
        for match in TEST_REF_RE.finditer(content):
            refs[int(match.group(1))].add(path)
    return refs


def fixture_refs() -> dict[int, set[str]]:
    refs: dict[int, set[str]] = defaultdict(set)
    for path in sorted(FIXTURES.glob("fpc_*.pas")):
        match = FIXTURE_RE.match(path.name)
        if match:
            refs[int(match.group(1))].add(str(path.relative_to(ROOT)))
    return refs


def commit_refs(valid_ids: set[int]) -> dict[int, list[dict[str, str]]]:
    refs: dict[int, list[dict[str, str]]] = defaultdict(list)
    raw = git(
        "log", "main", "origin/fixes_3_2", "--format=%H%x1f%ad%x1f%s%x1f%b%x1e",
        "--date=iso-strict",
    )
    seen: set[tuple[int, str]] = set()
    for record in raw.split("\x1e"):
        fields = record.strip("\r\n ").split("\x1f", 3)
        if len(fields) != 4:
            continue
        commit, date, subject, body = fields
        for match in ISSUE_REF_RE.finditer(subject + "\n" + body):
            issue = int(match.group(1))
            key = (issue, commit)
            if issue not in valid_ids or key in seen:
                continue
            seen.add(key)
            refs[issue].append({"commit": commit, "date": date, "subject": subject})
    return refs


def commit_test_paths(commits: set[str]) -> dict[str, set[str]]:
    paths: dict[str, set[str]] = defaultdict(set)
    current = ""
    raw = git(
        "log", "main", "origin/fixes_3_2", "--format=@@%H", "--name-only",
        "--diff-filter=AMR", "--", "tests",
    )
    for line in raw.splitlines():
        if line.startswith("@@"):
            current = line[2:]
        elif (
            current in commits
            and line
            and Path(line).suffix.lower() in PASCAL_SOURCE_SUFFIXES
        ):
            paths[current].add(line)
    return paths


def category(labels: list[str]) -> str:
    if "Category::Compiler" in labels:
        return "compiler"
    if "Category::RTL" in labels or "rtl" in [x.lower() for x in labels]:
        return "rtl"
    return "other"


def auto_scope(row: dict) -> str:
    labels = row.get("labels") or []
    if category(labels) != "compiler":
        return "non_compiler"
    label_text = " ".join(labels).lower()
    if "resolution::not a bug" in label_text:
        return "not_a_bug_label"
    if "resolution::duplicate" in label_text:
        return "duplicate_label"
    text = (row.get("title") or "") + "\n" + (row.get("description") or "")
    if NON_X64_TARGET_RE.search(text) and not X64_TARGET_RE.search(text):
        return "other_target_only"
    if FEATURE_RE.search(row.get("title") or ""):
        return "feature_request"
    if CODEGEN_RE.search(text):
        return "x64_codegen_review"
    return "x64_compatibility_review"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    issues = load_issues()
    valid_ids = {int(row["iid"]) for row in issues}
    tests = test_path_refs()
    fixtures = fixture_refs()
    commits = commit_refs(valid_ids)
    commit_tests = commit_test_paths({
        reference["commit"]
        for references in commits.values()
        for reference in references
    })

    indexed: list[dict] = []
    for row in issues:
        issue = int(row["iid"])
        labels = row.get("labels") or []
        issue_commit_tests = sorted({
            path
            for reference in commits.get(issue, [])
            for path in commit_tests.get(reference["commit"], ())
        })
        indexed.append({
            "iid": issue,
            "created_at": row.get("created_at"),
            "closed_at": row.get("closed_at"),
            "post_3_2_2": (row.get("created_at") or "") >= FPC_3_2_2_RELEASED_AT,
            "description_sha256": hashlib.sha256(
                (row.get("description") or "").encode()
            ).hexdigest(),
            "snapshot_page": row["snapshot_page"],
            "snapshot_ordinal": row["snapshot_ordinal"],
            "state": row.get("state"),
            "title": row.get("title"),
            "labels": labels,
            "category": category(labels),
            "auto_scope": auto_scope(row),
            "web_url": row.get("web_url"),
            "updated_at": row.get("updated_at"),
            "upstream_test_paths": sorted(tests.get(issue, ())),
            "commit_test_paths": issue_commit_tests,
            "lab_fixture_paths": sorted(fixtures.get(issue, ())),
            "commit_refs": commits.get(issue, []),
        })

    index_path = OUT / "fpc_issue_index.jsonl"
    with index_path.open("w", encoding="utf-8") as stream:
        for row in indexed:
            stream.write(json.dumps(row, sort_keys=True) + "\n")

    review = [
        row for row in indexed
        if row["state"] == "opened" and row["auto_scope"].endswith("_review")
    ]
    review.sort(key=lambda row: (-row["iid"], row["title"]))
    review_path = OUT / "fpc_open_compiler_review.tsv"
    with review_path.open("w", encoding="utf-8") as stream:
        stream.write("iid\tauto_scope\ttests\tcommits\tfixtures\ttitle\n")
        for row in review:
            stream.write(
                f"{row['iid']}\t{row['auto_scope']}\t"
                f"{len(set(row['upstream_test_paths']) | set(row['commit_test_paths']))}\t"
                f"{len(row['commit_refs'])}\t"
                f"{len(row['lab_fixture_paths'])}\t{row['title'].replace(chr(9), ' ')}\n"
            )

    poststable_review = [
        row for row in indexed
        if row["post_3_2_2"] and row["category"] == "compiler"
    ]
    poststable_review.sort(key=lambda row: (-row["iid"], row["title"]))
    poststable_path = OUT / "fpc_poststable_compiler_review.tsv"
    with poststable_path.open("w", encoding="utf-8") as stream:
        stream.write("iid\tstate\tauto_scope\ttests\tcommits\tfixtures\ttitle\n")
        for row in poststable_review:
            stream.write(
                f"{row['iid']}\t{row['state']}\t{row['auto_scope']}\t"
                f"{len(set(row['upstream_test_paths']) | set(row['commit_test_paths']))}\t"
                f"{len(row['commit_refs'])}\t"
                f"{len(row['lab_fixture_paths'])}\t{row['title'].replace(chr(9), ' ')}\n"
            )

    counts: dict[str, int] = defaultdict(int)
    for row in indexed:
        counts[f"category:{row['category']}"] += 1
        counts[f"auto_scope:{row['auto_scope']}"] += 1
        if row["upstream_test_paths"]:
            counts["issues_with_upstream_tests"] += 1
        if row["commit_test_paths"]:
            counts["issues_with_commit_tests"] += 1
        if row["commit_refs"]:
            counts["issues_with_commit_refs"] += 1
        if row["lab_fixture_paths"]:
            counts["issues_with_lab_fixtures"] += 1
    summary = {
        "schema": 1,
        "repository_commit": git("rev-parse", "HEAD").strip(),
        "issue_entries": len(indexed),
        "issue_pages": len(list(ISSUE_DIR.glob("page-*.json"))),
        "issue_page_sha256": {
            path.name: sha256(path) for path in sorted(ISSUE_DIR.glob("page-*.json"))
        },
        "counts": dict(sorted(counts.items())),
        "open_review_rows": len(review),
        "post_3_2_2_compiler_rows": len(poststable_review),
        "index_sha256": sha256(index_path),
        "review_sha256": sha256(review_path),
        "post_3_2_2_review_sha256": sha256(poststable_path),
        "note": (
            "Git supplies commit messages/source/tests, not tracker issue bodies. "
            "Issue bodies and metadata come from the hashed official GitLab API snapshot. "
            "auto_scope is triage only; final applicability requires executable/manual review."
        ),
    }
    with (OUT / "fpc_issue_summary.json").open("w", encoding="utf-8") as stream:
        json.dump(summary, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
