#!/usr/bin/env python3
"""Exercise long options through direct, environment and embedded compiler APIs."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path


def run(
    command: list[str], cwd: Path, timeout: int = 120,
    environment: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command, cwd=cwd, env=environment, capture_output=True, text=True,
        timeout=timeout, check=False,
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_log(path: Path, result: subprocess.CompletedProcess[str]) -> None:
    path.write_text(result.stdout + result.stderr, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("compiler", type=Path)
    parser.add_argument("config", type=Path)
    parser.add_argument("compiler_root", type=Path)
    parser.add_argument("run_id")
    args = parser.parse_args()

    compiler = args.compiler.resolve()
    config = args.config.resolve()
    root = args.compiler_root.resolve()
    target_os = run([str(compiler), "-iTO"], root, 30).stdout.strip().lower()
    if target_os not in {"linux", "win64"}:
        parser.error(f"unsupported host target: {target_os!r}")
    if not config.is_file() or not (root / "compiler" / "compiler.pas").is_file():
        parser.error("config and compiler source tree must exist")

    if target_os == "win64":
        harness_config = (
            root / "toolchain" / "ide" / "bin"
            / "x86_64-win64" / "fpc.cfg"
        )
    else:
        harness_config = root / "toolchain" / "ide" / "etc" / "fpc.cfg"
    if not harness_config.is_file():
        parser.error(f"IDE compiler config does not exist: {harness_config}")

    output = root / "qualification" / "suite" / "results" / "runs" / args.run_id / "argument-transport"
    if output.exists():
        parser.error(f"run already exists: {output}")
    output.mkdir(parents=True)
    executable_suffix = ".exe" if target_os == "win64" else ""
    failures: list[str] = []

    if target_os == "win64":
        msg2inc = (
            root / "toolchain" / "ide" / "bin"
            / "x86_64-win64" / "msg2inc.exe"
        )
    else:
        msg2inc = root / "toolchain" / "ide" / "bin" / "msg2inc"
    message_source = root / "compiler" / "msg" / "errore.msg"
    generated_includes = output / "compiler-includes"
    generated_includes.mkdir()
    if not msg2inc.is_file() or not message_source.is_file():
        parser.error("IDE msg2inc and the English compiler message source must exist")
    message_build = run(
        [str(msg2inc), str(message_source), "msg", "msg"],
        generated_includes, 120,
    )
    write_log(output / "message-includes.log", message_build)
    generated_message_files = [
        generated_includes / "msgtxt.inc",
        generated_includes / "msgidx.inc",
    ]
    if message_build.returncode != 0 or not all(
        path.is_file() for path in generated_message_files
    ):
        failures.append("compiler message include generation failed")

    harness_source = output / "argument_transport_embed.pas"
    harness_source.write_text(
        "program argument_transport_embed;\n\n"
        "{$i fpcdefs.inc}\n\n"
        "uses SysUtils, globals, compiler;\n\n"
        "begin\n"
        "  Halt(compiler.Compile(GetEnvironmentVariable('MOON_EMBED_COMMAND')));\n"
        "end.\n",
        encoding="utf-8",
    )
    harness = output / ("argument_transport_embed" + executable_suffix)
    harness_units = output / "harness-units"
    harness_units.mkdir()
    source_root = root / "compiler"
    harness_command = [
        # Compiler units themselves use the ordinary FPC ABI.  Building this
        # embedded harness with the product Unicode ABI creates a compiler
        # configuration that MoonCompiler never ships and corrupts its option
        # parser before the transport boundary is reached.  The embedded
        # command below still consumes the product config being tested.
        str(compiler), "-n", f"@{harness_config}", "-O2",
        "-dMOONCOMPILER_PRODUCT_RUNTIME", "-dMOONCOMPILER_VANILLA_RUNTIME",
        "-dx86_64", f"-Fu{source_root}", f"-Fu{source_root / 'x86_64'}",
        f"-Fu{source_root / 'systems'}", f"-Fu{source_root / 'x86'}",
        f"-Fi{generated_includes}", f"-Fi{source_root}",
        f"-Fi{source_root / 'x86_64'}",
        f"-Fi{source_root / 'x86'}", f"-FU{harness_units}",
        f"-FE{output}", f"-o{harness}", str(harness_source),
    ]
    harness_build = run(harness_command, root, 600)
    write_log(output / "harness-compile.log", harness_build)
    if harness_build.returncode != 0:
        failures.append(f"embedded harness compile exit {harness_build.returncode}")

    marker = output / "marker"
    marker.mkdir()
    (marker / "argument_marker.inc").write_text("{$define ARGUMENT_MARKER}\n", encoding="utf-8")
    target_source = output / "argument_target.pas"
    target_source.write_text(
        "program argument_target;\n"
        "{$i argument_marker.inc}\n"
        "{$ifndef ARGUMENT_MARKER}{$fatal long include option was lost}{$endif}\n"
        "begin WriteLn('ARGUMENT_OK'); end.\n",
        encoding="utf-8",
    )
    fake_paths = [str(output / "missing" / f"path-{index:02d}") for index in range(12)]
    long_option = "-Fi" + ";".join([*fake_paths, str(marker)])
    if len(long_option) <= 255 or str(marker) in long_option[:255]:
        failures.append("test setup did not place the valid path after byte 255")

    common = [str(compiler), "-n", f"@{config}", "-B", "-O2"]

    def compile_target(name: str, option: str, environment: dict[str, str] | None = None) -> None:
        target_output = output / name
        target_output.mkdir()
        result = run(
            [*common, option, f"-FU{target_output}", f"-FE{target_output}", str(target_source)],
            root, environment=environment,
        )
        write_log(target_output / "compile.log", result)
        executable = target_output / ("argument_target" + executable_suffix)
        executed = None
        if result.returncode == 0 and executable.is_file():
            executed = run([str(executable)], target_output, 30)
            write_log(target_output / "run.log", executed)
        if result.returncode != 0 or executed is None or executed.returncode != 0 or executed.stdout.strip() != "ARGUMENT_OK":
            failures.append(f"{name} did not preserve the long include option")

    compile_target("direct", long_option)
    env = os.environ.copy()
    env["MOON_LONG_OPTION"] = long_option
    compile_target("environment", "!MOON_LONG_OPTION", env)

    if harness_build.returncode == 0:
        quoted_dir = output / "quoted include"
        quoted_dir.mkdir()
        filler = " ".join(f"-dMOON_ARGUMENT_FILL_{index:03d}" for index in range(40))
        quoted_output = output / "embedded-quoted"
        quoted_output.mkdir()
        embedded_command = (
            f"[{config}] -B -O2 \"-Fi{quoted_dir}\" {filler} "
            f"{long_option} -FU{quoted_output} -FE{quoted_output} {target_source}"
        )
        if len(embedded_command.split(f'\"-Fi{quoted_dir}\"', 1)[1]) <= 255:
            failures.append("test setup did not leave a long tail after the quoted option")
        embedded_env = os.environ.copy()
        # The embedded harness lives outside the toolchain; resolve the
        # product config's $FPCBINDIR from the compiler under test.
        embedded_env["PPC_EXEC_PATH"] = str(compiler.parent)
        embedded_env["MOON_EMBED_COMMAND"] = embedded_command
        embedded = run([str(harness)], root, 120, embedded_env)
        write_log(quoted_output / "compile.log", embedded)
        embedded_executable = quoted_output / ("argument_target" + executable_suffix)
        if embedded.returncode != 0 or not embedded_executable.is_file():
            failures.append("embedded quoted option lost the command tail")

        for spaces in range(5):
            trailing_output = output / f"embedded-trailing-{spaces}"
            trailing_output.mkdir()
            embedded_env["MOON_EMBED_COMMAND"] = (
                f"[{config}] -B -O2 {long_option} -FU{trailing_output} "
                f"-FE{trailing_output} {target_source}" + " " * spaces
            )
            trailing = run([str(harness)], root, 120, embedded_env)
            write_log(trailing_output / "compile.log", trailing)
            trailing_executable = trailing_output / ("argument_target" + executable_suffix)
            if trailing.returncode != 0 or not trailing_executable.is_file():
                failures.append(f"embedded command failed with {spaces} trailing spaces")

    report = {
        "compiler": str(compiler),
        "compiler_sha256": sha256(compiler),
        "config": str(config),
        "config_sha256": sha256(config),
        "harness_config": str(harness_config),
        "harness_config_sha256": sha256(harness_config),
        "message_generator": str(msg2inc),
        "message_generator_sha256": sha256(msg2inc),
        "message_source_sha256": sha256(message_source),
        "generated_message_sha256": {
            path.name: sha256(path) for path in generated_message_files
            if path.is_file()
        },
        "target_os": target_os,
        "long_option_length": len(long_option),
        "embedded_harness_compile_exit": harness_build.returncode,
        "failures": failures,
    }
    (output / "manifest.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8",
    )
    if failures:
        print("ARGUMENT_TRANSPORT_FAIL: " + "; ".join(failures))
        return 1
    print(f"ARGUMENT_TRANSPORT_PASS target={target_os} option={len(long_option)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
