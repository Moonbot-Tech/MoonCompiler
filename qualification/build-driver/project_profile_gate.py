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
        project / "src" / "BuildProfileFlags.pas",
        """unit BuildProfileFlags;

interface

const
{$ifdef DEBUG}
  ProfileProtection = False;
{$elseif defined(RELEASE)}
  ProfileProtection = True;
{$else}
  {$fatal MOONCOMPILER_BUILD_KIND_IS_MISSING}
{$endif}

implementation

end.
""",
    )
    write(
        project / "driver_profile_smoke.dpr",
        """program driver_profile_smoke;

{$define MOONCOMPILER_EXPECT_ASSERTIONS_ON}
{$define MOONCOMPILER_EXPECT_DEBUG}

{$ifdef MOONCOMPILER_EXPECT_DEBUG}
  {$ifndef DEBUG}
    {$fatal MOONCOMPILER_DEBUG_DEFINE_IS_MISSING}
  {$endif}
  {$ifdef RELEASE}
    {$fatal MOONCOMPILER_DEBUG_AND_RELEASE_ARE_BOTH_DEFINED}
  {$endif}
{$else}
  {$ifndef RELEASE}
    {$fatal MOONCOMPILER_RELEASE_DEFINE_IS_MISSING}
  {$endif}
  {$ifdef DEBUG}
    {$fatal MOONCOMPILER_RELEASE_ALSO_DEFINES_DEBUG}
  {$endif}
{$endif}

{$ifopt I-}
{$fatal MOONCOMPILER_PRODUCT_IO_CHECK_MUST_BE_ON}
{$endif}
{$ifopt Q+}
{$fatal MOONCOMPILER_PRODUCT_OVERFLOW_CHECK_MUST_BE_OFF}
{$endif}
{$ifopt R+}
{$fatal MOONCOMPILER_PRODUCT_RANGE_CHECK_MUST_BE_OFF}
{$endif}
{$ifopt S+}
{$fatal MOONCOMPILER_PRODUCT_STACK_CHECK_MUST_BE_OFF}
{$endif}
{$ifdef MOONCOMPILER_EXPECT_ASSERTIONS_ON}
{$ifopt C-}
{$fatal MOONCOMPILER_DEBUG_ASSERTIONS_MUST_BE_ON}
{$endif}
{$else}
{$ifopt C+}
{$fatal MOONCOMPILER_RELEASE_ASSERTIONS_MUST_BE_OFF}
{$endif}
{$endif}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  System.SysUtils,
  System.Generics.Collections,
  BuildProfileFlags,
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
{$if ProfileProtection}
  Write('MOONCOMPILER_PROJECT_PROFILE_OK profile=release protection=1');
{$else}
  Write('MOONCOMPILER_PROJECT_PROFILE_OK profile=debug protection=0');
{$endif}
{$ifdef FPCX64MM_DIAGNOSTIC}
  Writeln(' diagnostic-mm=1');
{$else}
  Writeln(' diagnostic-mm=0');
{$endif}
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


def build_command(
    project: Path,
    profile: str,
    name: str = "driver_profile_smoke.dpr",
    *,
    diagnostic_mm: bool = False,
) -> list[str]:
    source = project / name
    if os.name == "nt":
        command = [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(ROOT / "build.ps1"),
            str(source),
            profile,
        ]
        if diagnostic_mm:
            command.append("-DiagnosticMM")
        return command
    command = [str(ROOT / "build"), str(source), profile]
    if diagnostic_mm:
        command.append("--diagnostic-mm")
    return command


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
            smoke = project / "driver_profile_smoke.dpr"
            source = smoke.read_text(encoding="utf-8")
            if profile == "release":
                source = source.replace(
                    "{$define MOONCOMPILER_EXPECT_ASSERTIONS_ON}",
                    "{$undef MOONCOMPILER_EXPECT_ASSERTIONS_ON}",
                )
                source = source.replace(
                    "{$define MOONCOMPILER_EXPECT_DEBUG}",
                    "{$undef MOONCOMPILER_EXPECT_DEBUG}",
                )
                write(smoke, source)
            result = run(build_command(project, profile))
            if f"building {project / 'driver_profile_smoke.dpr'}" not in result.stdout:
                raise RuntimeError(f"build driver did not report its logical project path\n{result.stdout}")
            runtime = run([str(executable)], cwd=project)
            protection = 0 if profile == "debug" else 1
            expected = (
                "MOONCOMPILER_PROJECT_PROFILE_OK "
                f"profile={profile} protection={protection} diagnostic-mm=0"
            )
            if runtime.stdout.strip() != expected:
                raise RuntimeError(f"unexpected project output: {runtime.stdout!r}")

            if profile == "debug":
                diagnostic = run(build_command(
                    project, profile, diagnostic_mm=True
                ))
                if "diagnostic-mm" not in diagnostic.stdout:
                    raise RuntimeError(
                        "build driver did not report the diagnostic MM mode\n"
                        + diagnostic.stdout
                    )
                diagnostic_runtime = run([str(executable)], cwd=project)
                diagnostic_expected = (
                    "MOONCOMPILER_PROJECT_PROFILE_OK "
                    "profile=debug protection=0 diagnostic-mm=1"
                )
                if diagnostic_expected not in diagnostic_runtime.stdout:
                    raise RuntimeError(
                        "diagnostic MM define did not reach the application\n"
                        + diagnostic_runtime.stdout
                    )

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

        print("MOONCOMPILER_PROJECT_PROFILE_GATE_PASS profiles=2 diagnostic-mm=1 dependency=clean-pinned string=unicode")
        return 0
    finally:
        shutil.rmtree(cache, ignore_errors=True)
        shutil.rmtree(WORK, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
