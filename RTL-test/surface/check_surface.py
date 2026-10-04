#!/usr/bin/env python3
"""Keep reviewed RTL unit surfaces synchronized with executable tests."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).with_name("manifest.json")
SCOPE = Path(__file__).with_name("scope.json")
DECLARATION = re.compile(
    r"^\s*(?:(?:class|generic)\s+)*(function|procedure|constructor|destructor|operator)\s+",
    re.IGNORECASE,
)
NAME = re.compile(
    r"^\s*(?:(?:class|generic)\s+)*(?:function|procedure|constructor|destructor)\s+"
    r"([A-Za-z_][A-Za-z0-9_.$]*)|"
    r"^\s*(?:(?:class|generic)\s+)*operator\s+"
    r"(\*\*|:=|<>|<=|>=|><|[+\-*/=<>]|[A-Za-z_][A-Za-z0-9_]*)",
    re.IGNORECASE,
)
INCLUDE = re.compile(
    r"(?is)(?:\{\s*\$i(?:nclude)?\s+([^}\s]+)\s*\}|"
    r"\(\*\s*\$i(?:nclude)?\s+([^*)\s]+)\s*\*\))"
)


def mask_comments_and_strings(source: str) -> str:
    """Replace Pascal comments and string contents while preserving newlines."""
    out: list[str] = []
    i = 0
    state = "code"
    while i < len(source):
        char = source[i]
        pair = source[i : i + 2]
        if state == "code":
            if pair == "//":
                out.extend("  ")
                i += 2
                state = "line_comment"
            elif pair == "(*":
                out.extend("  ")
                i += 2
                state = "paren_comment"
            elif char == "{":
                out.append(" ")
                i += 1
                state = "brace_comment"
            elif char == "'":
                out.append("'")
                i += 1
                state = "string"
            else:
                out.append(char)
                i += 1
        elif state == "line_comment":
            out.append("\n" if char == "\n" else " ")
            i += 1
            if char == "\n":
                state = "code"
        elif state == "paren_comment":
            if pair == "*)":
                out.extend("  ")
                i += 2
                state = "code"
            else:
                out.append("\n" if char == "\n" else " ")
                i += 1
        elif state == "brace_comment":
            out.append("\n" if char == "\n" else " ")
            i += 1
            if char == "}":
                state = "code"
        else:
            if pair == "''":
                out.extend("  ")
                i += 2
            elif char == "'":
                out.append("'")
                i += 1
                state = "code"
            else:
                out.append("\n" if char == "\n" else " ")
                i += 1
    return "".join(out)


def expand_includes(
    source_path: Path, include_dirs: list[Path], stack: tuple[Path, ...] = ()
) -> str:
    source_path = source_path.resolve()
    if source_path in stack:
        chain = " -> ".join(str(item) for item in stack + (source_path,))
        raise ValueError(f"recursive include: {chain}")
    source = source_path.read_text(encoding="utf-8")

    def replace(match: re.Match[str]) -> str:
        name = match.group(1) or match.group(2)
        candidates = [source_path.parent / name]
        candidates.extend(directory / name for directory in include_dirs)
        included = next((path for path in candidates if path.is_file()), None)
        if included is None:
            raise ValueError(f"{source_path}: cannot resolve include {name}")
        return expand_includes(included, include_dirs, stack + (source_path,))

    return INCLUDE.sub(replace, source)


def section(source: str, name: str) -> str:
    masked = mask_comments_and_strings(source)
    interface = re.search(r"(?im)^\s*interface\s*$", masked)
    implementation = re.search(r"(?im)^\s*implementation\s*$", masked)
    if interface is None or implementation is None or interface.end() >= implementation.start():
        raise ValueError("source is not a Pascal unit with interface/implementation sections")
    if name == "interface":
        return masked[interface.end() : implementation.start()]
    return masked[implementation.end() :]


def declarations(source: str, section_name: str) -> list[dict[str, object]]:
    lines = section(source, section_name).splitlines()
    result: list[dict[str, object]] = []
    index = 0
    while index < len(lines):
        if not DECLARATION.match(lines[index]):
            index += 1
            continue
        first_line = index + 1
        parts = [lines[index].strip()]
        while declaration_end(" ".join(parts)) is None and index + 1 < len(lines):
            index += 1
            parts.append(lines[index].strip())
        joined = " ".join(parts)
        end = declaration_end(joined)
        if end is None:
            raise ValueError(f"unterminated routine declaration at line {first_line}")
        signature = joined[:end]
        signature = re.sub(r"\s+", " ", signature).strip()
        match = NAME.match(signature)
        if match is None:
            raise ValueError(f"cannot extract routine name from {signature!r}")
        result.append(
            {
                "line": first_line,
                "name": match.group(1) or match.group(2),
                "signature": signature,
            }
        )
        index += 1
    return result


def declaration_end(value: str) -> int | None:
    parentheses = 0
    brackets = 0
    for index, char in enumerate(value):
        if char == "(":
            parentheses += 1
        elif char == ")":
            parentheses -= 1
        elif char == "[":
            brackets += 1
        elif char == "]":
            brackets -= 1
        elif char == ";" and parentheses == 0 and brackets == 0:
            return index
    return None


def fingerprint(items: list[dict[str, object]]) -> str:
    payload = "\n".join(str(item["signature"]).casefold() for item in items)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def unit_facts(source_path: Path, include_dirs: list[Path] | None = None) -> dict[str, object]:
    source = expand_includes(source_path, include_dirs or [])
    public = declarations(source, "interface")
    implementation = declarations(source, "implementation")
    return {
        "public_count": len(public),
        "public_sha256": fingerprint(public),
        "implementation_count": len(implementation),
        "implementation_sha256": fingerprint(implementation),
        "public": public,
        "implementation": implementation,
    }


def name_use_count(name: str, tests: str) -> int:
    if name in {"**", ":=", "+", "-", "*", "/", "=", "<", ">", "<=", ">="}:
        return tests.count(name)
    return len(
        re.findall(rf"(?i)(?<![A-Za-z0-9_]){re.escape(name)}(?![A-Za-z0-9_])", tests)
    )


def insufficient_uses(
    public: list[dict[str, object]], test_text: str
) -> list[tuple[str, int, int]]:
    overloads: dict[str, int] = {}
    for item in public:
        name = str(item["name"])
        overloads[name] = overloads.get(name, 0) + 1
    return sorted(
        (
            (name, expected, name_use_count(name, test_text))
            for name, expected in overloads.items()
            if name_use_count(name, test_text) < expected
        ),
        key=lambda value: value[0].casefold(),
    )


def product_scope() -> dict[str, str]:
    scope = json.loads(SCOPE.read_text(encoding="utf-8"))
    result: dict[str, str] = {}
    for package in scope["packages"]:
        for unit in package["units"]:
            key = unit.casefold()
            if key in result:
                raise ValueError(f"duplicate product unit {unit}")
            result[key] = package["id"]
    return result


def check_manifest(verbose: bool, require_complete: bool) -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    scope = product_scope()
    errors: list[str] = []
    closed: set[str] = set()
    total_public = 0
    total_implementation = 0
    for unit in manifest["units"]:
        ppu = unit["ppu"].casefold()
        if ppu not in scope:
            errors.append(f"{unit['id']}: {unit['ppu']} is not in product scope")
        if ppu in closed:
            errors.append(f"{unit['id']}: duplicate closure for {unit['ppu']}")
        closed.add(ppu)
        source_path = ROOT / unit["source"]
        include_dirs = [ROOT / value for value in unit.get("include_dirs", [])]
        facts = unit_facts(source_path, include_dirs)
        total_public += int(facts["public_count"])
        total_implementation += int(facts["implementation_count"])
        for field in (
            "public_count",
            "public_sha256",
            "implementation_count",
            "implementation_sha256",
        ):
            if facts[field] != unit[field]:
                errors.append(
                    f"{unit['id']}: {field} drifted: manifest={unit[field]} source={facts[field]}"
                )
        test_paths = [ROOT / value for value in unit["tests"]]
        missing_files = [str(path.relative_to(ROOT)) for path in test_paths if not path.is_file()]
        if missing_files:
            errors.append(f"{unit['id']}: missing tests: {', '.join(missing_files)}")
            continue
        test_text = mask_comments_and_strings(
            "\n".join(path.read_text(encoding="utf-8") for path in test_paths)
        )
        insufficient = insufficient_uses(facts["public"], test_text)
        if insufficient:
            errors.append(
                f"{unit['id']}: public overloads lack enough named executable call sites: "
                + ", ".join(
                    f"{name}({actual}/{expected})"
                    for name, expected, actual in insufficient
                )
            )
        if verbose:
            print(
                f"SURFACE_UNIT {unit['id']} public={facts['public_count']} "
                f"implementation={facts['implementation_count']} tests={len(test_paths)}"
            )
    open_units = sorted(set(scope) - closed)
    unknown_units = sorted(closed - set(scope))
    if unknown_units:
        errors.append("closed units outside product scope: " + ", ".join(unknown_units))
    if require_complete and open_units:
        errors.append(
            f"product RTL is not closed: {len(open_units)} unit(s) still open"
        )
    for error in errors:
        print(f"SURFACE_FAIL {error}")
    if errors:
        return 1
    print(f"SURFACE_SCOPE total={len(scope)} closed={len(closed)} open={len(open_units)}")
    if verbose and open_units:
        print("SURFACE_OPEN " + ", ".join(open_units))
    print(f"SURFACE_CLOSED_OK public={total_public} implementation={total_implementation}")
    return 0


def dump_unit(path: Path, test_roots: list[Path], include_dirs: list[Path]) -> int:
    facts = unit_facts(path, include_dirs)
    summary = {key: value for key, value in facts.items() if key not in {"public", "implementation"}}
    print(json.dumps(summary, indent=2))
    for item in facts["public"]:
        print(f"PUBLIC {item['line']:5} {item['signature']}")
    for item in facts["implementation"]:
        print(f"IMPL   {item['line']:5} {item['signature']}")
    if test_roots:
        paths: list[Path] = []
        for root in test_roots:
            resolved = root if root.is_absolute() else ROOT / root
            if resolved.is_dir():
                paths.extend(resolved.rglob("*.dpr"))
                paths.extend(resolved.rglob("*.pas"))
                paths.extend(resolved.rglob("*.pp"))
            elif resolved.is_file():
                paths.append(resolved)
        test_text = mask_comments_and_strings(
            "\n".join(item.read_text(encoding="utf-8") for item in sorted(set(paths)))
        )
        for name, expected, tape in insufficient_uses(facts["public"], test_text):
            print(f"MISSING {name} calls={tape} declarations={expected}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dump", type=Path, help="print the routine inventory for one unit")
    parser.add_argument(
        "--against-tests",
        nargs="*",
        type=Path,
        default=[],
        help="with --dump, report declarations lacking enough call sites",
    )
    parser.add_argument(
        "--include-dir",
        action="append",
        type=Path,
        default=[],
        help="include search directory used while expanding a unit",
    )
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument(
        "--require-complete",
        action="store_true",
        help="fail until every product RTL unit has executable surface coverage",
    )
    args = parser.parse_args()
    if args.dump is not None:
        path = args.dump if args.dump.is_absolute() else ROOT / args.dump
        include_dirs = [item if item.is_absolute() else ROOT / item for item in args.include_dir]
        return dump_unit(path, args.against_tests, include_dirs)
    return check_manifest(args.verbose, args.require_complete)


if __name__ == "__main__":
    sys.exit(main())
