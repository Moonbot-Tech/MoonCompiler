#!/usr/bin/env python3
"""End-to-end contract for the one-command application build drivers."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / ".qualification" / "build-driver" / f"project-profile-{os.getpid()}"


def run(command: list[str], *, cwd: Path = ROOT, expect: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        encoding="utf-8",
        errors="replace",
        timeout=300,
    )
    if result.returncode != expect:
        raise RuntimeError(
            f"command returned {result.returncode}, expected {expect}: {command}\n{result.stdout}"
        )
    return result


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")


def create_dependency() -> tuple[Path, str]:
    dependency = WORK / "dependency"
    write(
        dependency / "src" / "PinnedDep.pas",
        """unit PinnedDep;

interface

function PinnedDependencyValue: Integer;

implementation

function PinnedDependencyValue: Integer;
begin
  Result := 17;
end;

end.
""",
    )
    run(["git", "init", "-q"], cwd=dependency)
    run(["git", "config", "user.email", "qualification@example.invalid"], cwd=dependency)
    run(["git", "config", "user.name", "Qualification"], cwd=dependency)
    run(["git", "add", "."], cwd=dependency)
    run(["git", "commit", "-q", "-m", "fixture"], cwd=dependency)
    commit = run(["git", "rev-parse", "HEAD"], cwd=dependency).stdout.strip()
    return dependency, commit


def create_project(dependency: Path, commit: str) -> Path:
    project = WORK / "project"
    write(
        project / "src" / "BuildAliasUnit.pas",
        """unit BuildAliasUnit;

interface

function AliasValue: Integer;

implementation

function AliasValue: Integer;
begin
  Result := 25;
end;

end.
""",
    )
    write(
        project / "driver_profile_smoke.dpr",
        """program driver_profile_smoke;

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  System.SysUtils,
  System.Generics.Collections,
  CustomAlias,
  PinnedDep;

var
  Values: TList<Integer>;
  Text: String;

function Kind(const Value: AnsiString): Integer; overload;
begin
  Result := 1;
end;

function Kind(const Value: UnicodeString): Integer; overload;
begin
  Result := 2;
end;

begin
  Text := 'Unicode';
  If Kind(Text) <> 2 then
    Halt(1);
  If AliasValue + PinnedDependencyValue <> 42 then
    Halt(2);
  Values := TList<Integer>.Create;
  try
    Values.Add(42);
    If Values[0] <> 42 then
      Halt(3);
  finally
    Values.Free;
  end;
  Writeln('MOONCOMPILER_PROJECT_PROFILE_OK');
end.
""",
    )
    write(
        project / "driver_profile_missing_threads.dpr",
        """program driver_profile_missing_threads;

uses
  mormot.core.fpcx64mm,
  System.SysUtils;

begin
end.
""",
    )
    dependency_url = dependency.resolve().as_uri()
    write(
        project / "driver_profile_smoke.mooncompiler",
        "\n".join(
            [
                "# MoonCompiler project manifest v1",
                "source=src",
                "alias=CustomAlias=BuildAliasUnit",
                f"dependency=profile-gate-{os.getpid()}|{dependency_url}|{commit}|src",
                "",
            ]
        ),
    )
    return project


def create_invocation_view(project: Path) -> Path:
    if os.name == "nt":
        return project
    view = WORK / "logical-view"
    view.mkdir()
    (view / "driver_profile_smoke.dpr").symlink_to(
        project / "driver_profile_smoke.dpr"
    )
    (view / "driver_profile_missing_threads.dpr").symlink_to(
        project / "driver_profile_missing_threads.dpr"
    )
    (view / "src").symlink_to(project / "src", target_is_directory=True)
    (project / "driver_profile_smoke.mooncompiler").replace(
        view / "driver_profile_smoke.mooncompiler"
    )
    return view


def build_command(project: Path, profile: str, name: str = "driver_profile_smoke.dpr") -> list[str]:
    source = project / name
    if os.name == "nt":
        return [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "build.ps1"),
            str(source),
            profile,
        ]
    return [str(ROOT / "build"), str(source), profile]


def main() -> int:
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    dependency_name = f"profile-gate-{os.getpid()}"
    cache = ROOT / ".moonbot" / "dependencies" / dependency_name
    try:
        dependency, commit = create_dependency()
        project = create_invocation_view(create_project(dependency, commit))
        executable = project / (
            "driver_profile_smoke.exe" if os.name == "nt" else "driver_profile_smoke"
        )
        for profile in ("debug", "release"):
            result = run(build_command(project, profile))
            if f"building {project / 'driver_profile_smoke.dpr'}" not in result.stdout:
                raise RuntimeError(f"build driver did not report its logical project path\n{result.stdout}")
            runtime = run([str(executable)], cwd=project)
            if runtime.stdout.strip() != "MOONCOMPILER_PROJECT_PROFILE_OK":
                raise RuntimeError(f"unexpected project output: {runtime.stdout!r}")

        if os.name != "nt":
            missing_threads = run(
                build_command(project, "debug", "driver_profile_missing_threads.dpr"),
                expect=1,
            )
            if (
                "--required-first-unit=MORMOT.CORE.FPCX64MM,CTHREADS" not in missing_threads.stdout
                or "explicit unit 2 is" not in missing_threads.stdout
            ):
                raise RuntimeError(
                    "missing Linux cthreads was rejected for the wrong reason\n"
                    + missing_threads.stdout
                )

        cached_source = cache / commit.lower() / "src" / "PinnedDep.pas"
        cached_source.write_text(cached_source.read_text(encoding="utf-8") + "\n", encoding="utf-8")
        rejected = run(build_command(project, "debug"), expect=1)
        if "cached dependency is not clean" not in rejected.stdout:
            raise RuntimeError(f"dirty dependency was rejected for the wrong reason\n{rejected.stdout}")

        print("MOONCOMPILER_PROJECT_PROFILE_GATE_PASS profiles=2 dependency=clean-pinned string=unicode")
        return 0
    finally:
        shutil.rmtree(cache, ignore_errors=True)
        shutil.rmtree(WORK, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
