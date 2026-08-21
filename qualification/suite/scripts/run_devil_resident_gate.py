"""Gate for the hand-written `resident` layer.

The other Devil layers ask the compiler "did you compute this right?". This one
asks "does your code age right?" - and the gate is built around what must hold
for a long-lived program, not around a reference value.

Four independent oracles, none of which needs a golden answer:

  schedule    the root is a commutative fold of per-carrier digests, and every
              carrier's route is fixed by the seed. So for the same carriers and
              laps the root MUST NOT depend on how many threads ran. Any
              difference is a race - ours or the compiler's, and the layer is
              built to have none of its own.

  determinism the same binary run twice must produce identical output. Machine
              code we ship is expected to be reproducible; a drifting root here
              is the single most expensive kind of finding.

  rebuild     compiling again from the same sources must give a binary that
              behaves identically. Catches state that leaked from the build.

  profiles    debug/o1/o2/release must agree on every observable. Optimisation
              is allowed to change speed, never answers.

Plus the ladder: the program must stay green as it ages, so the same
configuration is run at growing lap counts.

Localisation is per stage: the program prints a commutative subtotal for every
stage, so a mismatch names the stage instead of just the run.

ASCII output only - the console this runs on is not UTF-8.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import devil_toolchain as tc  # noqa: E402

SUITE = Path(__file__).resolve().parent.parent
WORK = SUITE / "tests" / "resident"
PROGRAM = WORK / "resident.dpr"
PROFILES = ("debug", "o1", "o2", "release")

# Lines that describe the program's answers. Everything else (timings, counts
# that legitimately depend on the run shape) stays out of the comparison.
ANSWER_PREFIXES = (
    "RESIDENT_STAGES ",
    "RESIDENT_REGISTRY ",
    "RESIDENT_INITORDER ",
    "RESIDENT_STAGESUM ",
    "RESIDENT_CARRIER ",
    "RESIDENT_ROOT ",
    "RESIDENT_HANDLED ",
    "RESIDENT_VISITS ",
    "RESIDENT_BORN ",
    "RESIDENT_ALIVE ",
    "RESIDENT_DRIFTED ",
    "RESIDENT_CORRUPTED ",
    "RESIDENT_SHORT ",
    "RESIDENT_MISROUTED ",
    "RESIDENT_FAULTS ",
)

FAILURE_PREFIXES = ("RESIDENT_FAILURE", "RESIDENT_STAGEFAULT", "RESIDENT_STUCK")


class Run:
    """One execution, reduced to the facts worth comparing."""

    def __init__(self, text: str, code: int) -> None:
        self.code = code
        self.text = text
        self.answers: dict[str, str] = {}
        self.stages: dict[str, str] = {}
        self.failures: list[str] = []
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            if line.startswith(FAILURE_PREFIXES):
                self.failures.append(line)
                continue
            if not line.startswith(ANSWER_PREFIXES):
                continue
            if line.startswith("RESIDENT_STAGESUM "):
                parts = line.split()
                if len(parts) >= 3:
                    self.stages[parts[1]] = parts[2]
                self.answers[" ".join(parts[:2])] = parts[-1]
            else:
                head, _, tail = line.partition(" ")
                if head == "RESIDENT_CARRIER":
                    self.answers[line.split(" ", 2)[0] + " " + tail.split(" ", 1)[0]] = tail
                else:
                    self.answers[head] = tail

    def differences(self, other: "Run") -> list[str]:
        """What the two runs disagree about, stages named first."""
        out: list[str] = []
        for stage in sorted(set(self.stages) | set(other.stages)):
            mine = self.stages.get(stage, "<absent>")
            theirs = other.stages.get(stage, "<absent>")
            if mine != theirs:
                out.append("stage %s: %s vs %s" % (stage, mine, theirs))
        for key in sorted(set(self.answers) | set(other.answers)):
            if key.startswith("RESIDENT_STAGESUM"):
                continue
            mine = self.answers.get(key, "<absent>")
            theirs = other.answers.get(key, "<absent>")
            if mine != theirs:
                out.append("%s: %s vs %s" % (key, mine, theirs))
        return out


def build(profile: str, out_dir: Path) -> Path:
    """Build the program exactly the way the driver does, varying only -O."""
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)
    done = subprocess.run(
        tc.compile_command(PROGRAM, out_dir, profile),
        capture_output=True,
        text=True,
        cwd=WORK,
    )
    if done.returncode != 0:
        bad = [l.strip() for l in done.stdout.splitlines()
               if "Error" in l or "Fatal" in l]
        raise SystemExit("build failed (%s):\n%s" % (profile, "\n".join(bad[:12])))
    return out_dir / "resident.exe"


def run(exe: Path, carriers: int, laps: int, workers: int, timeout: int) -> Run:
    try:
        done = subprocess.run(
            [str(exe), "--seed", "1", "--carriers", str(carriers),
             "--laps", str(laps), "--workers", str(workers)],
            capture_output=True, text=True, cwd=WORK, timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        got = exc.stdout or ""
        if isinstance(got, bytes):
            got = got.decode(errors="replace")
        return Run(got + "\nRESIDENT_FAILURE timeout", 99)
    return Run(done.stdout, done.returncode)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--carriers", type=int, default=8)
    ap.add_argument("--laps", type=int, default=40)
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--profiles", default=",".join(PROFILES))
    ap.add_argument("--ladder", default="10,60,240",
                    help="lap counts the program must stay green at")
    ap.add_argument("--work", type=Path,
                    default=SUITE / "results" / "devil-resident")
    ap.add_argument("--report", type=Path)
    args = ap.parse_args()

    profiles = [p.strip() for p in args.profiles.split(",") if p.strip()]
    findings: list[str] = []
    results: dict[str, Run] = {}

    root = args.work.resolve()
    root.mkdir(parents=True, exist_ok=True)

    # --- profiles: every optimisation level must give the same answers -------
    for profile in profiles:
        exe = build(profile, root / profile)
        got = run(exe, args.carriers, args.laps, 2, args.timeout)
        results[profile] = got
        print("profile %-8s rc=%d stages=%s root=%s"
              % (profile, got.code, got.answers.get("RESIDENT_STAGES", "?"),
                 got.answers.get("RESIDENT_ROOT", "?")))
        for line in got.failures:
            findings.append("%s: %s" % (profile, line))

    base_name = profiles[0]
    base = results[base_name]
    for profile in profiles[1:]:
        diff = results[profile].differences(base)
        if diff:
            findings.append("profile %s differs from %s:\n    %s"
                            % (profile, base_name, "\n    ".join(diff[:10])))

    # --- schedule: the answer must not depend on how many threads ran --------
    exe = (root / profiles[-1]) / "resident.exe"
    for workers in (1, 4):
        got = run(exe, args.carriers, args.laps, workers, args.timeout)
        for line in got.failures:
            findings.append("workers=%d: %s" % (workers, line))
        diff = got.differences(results[profiles[-1]])
        if diff:
            findings.append("schedule leaks into the answer at workers=%d:\n    %s"
                            % (workers, "\n    ".join(diff[:10])))
        print("workers %-2d rc=%d root=%s" % (workers, got.code,
                                              got.answers.get("RESIDENT_ROOT", "?")))

    # --- determinism: same binary, twice ------------------------------------
    again = run(exe, args.carriers, args.laps, 2, args.timeout)
    diff = again.differences(results[profiles[-1]])
    if diff:
        findings.append("same binary drifts between runs:\n    %s"
                        % "\n    ".join(diff[:10]))
    print("rerun     rc=%d root=%s" % (again.code,
                                       again.answers.get("RESIDENT_ROOT", "?")))

    # --- rebuild: same sources, fresh build ---------------------------------
    rebuilt = build(profiles[-1], root / (profiles[-1] + "-again"))
    got = run(rebuilt, args.carriers, args.laps, 2, args.timeout)
    diff = got.differences(results[profiles[-1]])
    if diff:
        findings.append("rebuild changes behaviour:\n    %s"
                        % "\n    ".join(diff[:10]))
    print("rebuild   rc=%d root=%s" % (got.code,
                                       got.answers.get("RESIDENT_ROOT", "?")))

    # --- ladder: the program must stay green as it ages ---------------------
    for laps in [int(x) for x in args.ladder.split(",") if x.strip()]:
        got = run(exe, args.carriers, laps, 3, args.timeout)
        print("ladder laps=%-5d rc=%d root=%s handled=%s"
              % (laps, got.code, got.answers.get("RESIDENT_ROOT", "?"),
                 got.answers.get("RESIDENT_HANDLED", "?")))
        for line in got.failures:
            findings.append("laps=%d: %s" % (laps, line))
        # The carrier count times laps times stages is an exact number, and the
        # program checks it itself; a non-zero exit with no failure line means
        # it fell over in some way the program did not name.
        if got.code != 0 and not got.failures:
            findings.append("laps=%d: exit %d without naming a failure"
                            % (laps, got.code))

    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps({
            "profiles": {
                name: {
                    "exit_code": got.code,
                    "answers": got.answers,
                    "stages": got.stages,
                    "failures": got.failures,
                }
                for name, got in results.items()
            },
            "settings": {
                "carriers": args.carriers,
                "laps": args.laps,
                "ladder": args.ladder,
            },
            "findings": findings,
        }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print()
    if findings:
        print("RESIDENT_GATE FINDINGS %d" % len(findings))
        for item in findings:
            print("  - %s" % item)
        return 1
    print("RESIDENT_GATE OK profiles=%d stages=%s carriers=%d laps=%d"
          % (len(profiles), base.answers.get("RESIDENT_STAGES", "?"),
             args.carriers, args.laps))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
