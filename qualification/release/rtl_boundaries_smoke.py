#!/usr/bin/env python3
"""Run public RTL consumers outside the source tree with an installed toolchain."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "RTL-test" / "semantic"
CASES = (
    "base64_size_boundaries",
    "encoding_boundaries", "file_boundaries", "hash_regex_iso_boundaries",
    "json_lifetime_boundaries", "json_numeric_boundaries", "lightweight_boundaries", "loader_boundaries",
    "uri_boundaries",
    "anonymous_cleanup_external_owner", "asm_delphi_operands", "forcequeue_first_thread",
    "numeric_overload_precision", "typed_const_character_pointers",
    "reader_value_transfer", "reader_fixup_lifetime", "reader_fixup_registration",
    "thread_destruction",
)


def run(command, directory, env=None):
    result = subprocess.run(command, cwd=directory, capture_output=True, text=True,
                            errors="replace", timeout=60, env=env)
    if result.returncode:
        raise RuntimeError(f"Command failed: {command}\n{result.stdout}\n{result.stderr}")
    return result.stdout


SDK_CASES = (
    ("sdk2410_resources", "RESOURCE_PASS"),
    ("sdk2410_ini", "INI_PASS"),
    ("sdk2410_fields", "FIELDS_PASS"),
    ("sdk2410_sqlite", "SQLITE_PASS"),
    ("backtrace_contract", "BACKTRACE_CONTRACT_PASS"),
)


def sdk_boundaries(compiler, directory, options):
    source = ROOT / "qualification/suite/tests/sdk-boundaries"
    cases = SDK_CASES + ((("current_thread_handle_contract", "CURRENT_THREAD_HANDLE_CONTRACT_PASS"),)
                        if os.name == "nt" else ())
    suffix = ".exe" if os.name == "nt" else ""
    shutil.copy2(source / "make_resources.py", directory)
    run([sys.executable, "make_resources.py"], directory)
    count = 0
    for name, marker in cases:
        shutil.copy2(source / (name + ".dpr"), directory)
        run([str(compiler), *options, name + ".dpr"], directory)
        result = run([str(directory / (name + suffix))], directory)
        if not any(line == marker or line.startswith(marker + " ") for line in result.splitlines()):
            raise RuntimeError(f"Missing SDK result {name}: {result}")
        count += 1
        print(f"PASS {name} {directory.name}", flush=True)
    shutil.copy2(ROOT / "qualification/compiler-contextual-strings/rtl_calls.dpr", directory / "contextual_strings.dpr")
    run([str(compiler), *options, "contextual_strings.dpr"], directory)
    result = run([str(directory / ("contextual_strings" + suffix))], directory)
    if result.strip() != "RTL_STRING_OVERLOADS_PASS":
        raise RuntimeError(f"Contextual string overloads failed: {result}")
    count += 1
    print(f"PASS contextual string overloads {directory.name}", flush=True)
    if os.name != "nt":
        for name in ("foreign_bridge.c", "backtrace_extra_contract.dpr", "module_fixture.dpr", "module_path_contract.dpr"):
            shutil.copy2(source / name, directory)
        run(["cc", "-shared", "-fPIC", "-O2", "-g", "-fomit-frame-pointer",
             "-fasynchronous-unwind-tables", "foreign_bridge.c", "-o", "libforeign_bridge.so"], directory)
        run([str(compiler), *options, "backtrace_extra_contract.dpr"], directory)
        result = run([str(directory / "backtrace_extra_contract")], directory)
        if result.strip() != "BACKTRACE_RECURSION_FOREIGN_PASS":
            raise RuntimeError(f"Recursion/foreign backtrace failed: {result}")
        count += 1
        mapped = directory / "module path \u041a\u0438\u0440\u0438\u043b\u043b\u0438\u0446\u0430"
        mapped.mkdir()
        run([str(compiler), *options, "-dMOONCOMPILER_VANILLA_RUNTIME", "-FE" + str(mapped),
             "module_fixture.dpr"], directory)
        run([str(compiler), *options, "-FE" + str(mapped), "module_path_contract.dpr"], directory)
        for executable, library in (("./module_path_contract", "./libmodule_fixture.so"),
                                    (str(mapped / "module_path_contract"), str(mapped / "libmodule_fixture.so"))):
            result = run([executable, library], mapped)
            if result.strip() != "MODULE_PATH_CONTRACT_PASS":
                raise RuntimeError(f"Loaded image identity failed: {result}")
            count += 1
        print(f"PASS Linux frame and module contracts {directory.name}", flush=True)
        utf_source = ROOT / "qualification/suite/tests/rtl-api"
        for name in ("cwstring_utf8_contracts.dpr", "cwstring_iconv_counter.c"):
            shutil.copy2(utf_source / name, directory)
        run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
             "cwstring_iconv_counter.c", "-ldl", "-o", "cwstring-iconv-counter.so"], directory)
        run([str(compiler), *options, "cwstring_utf8_contracts.dpr"], directory)
        utf_env = dict(os.environ, LC_ALL="C.UTF-8", LD_PRELOAD=str(directory / "cwstring-iconv-counter.so"))
        for arguments in ([], ["--threads"]):
            result = run([str(directory / "cwstring_utf8_contracts"), *arguments], directory, utf_env)
            if "CWSTRING_UTF8_CONTRACTS_OK" not in result.splitlines():
                raise RuntimeError(f"UTF manager contract failed: {result}")
            if arguments and "CWSTRING_UTF8_THREAD_ICONV_OPENS=0" not in result.splitlines():
                raise RuntimeError(f"UTF converters returned: {result}")
            count += 1
        print(f"PASS Linux UTF manager contracts {directory.name}", flush=True)
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--sdk-only", action="store_true", help="run only the SDK boundary additions")
    args = parser.parse_args()
    if os.name == "nt":
        import ctypes
        ctypes.windll.kernel32.SetErrorMode(3)
    compiler = args.compiler.resolve(strict=True)
    output = args.out.resolve()
    cases = CASES + (("windows_boundaries", "win64_classes_callbacks") if os.name == "nt" else ())
    suffix = ".exe" if os.name == "nt" else ""
    wait_sources = ROOT / "qualification" / "suite" / "tests" / "rtl-api"
    wait_env = os.environ.copy()
    if os.name != "nt" and not args.sdk_only:
        output.mkdir(parents=True, exist_ok=True)
        shutil.copy2(wait_sources / "thread_wait_tls.c", output)
        helper = output / "thread-wait-tls.so"
        run(["cc", "-shared", "-fPIC", "-pthread", "thread_wait_tls.c", "-o", str(helper)], output)
        wait_env["MOON_WAIT_TLS_HELPER"] = str(helper)
    count = 0
    for profile, options in (("debug", []), ("release", ["-dRELEASE"])):
        directory = output / profile
        directory.mkdir(parents=True, exist_ok=False)
        count += sdk_boundaries(compiler, directory, options)
        if args.sdk_only:
            continue
        # Only consumer sources are staged: there is no -Fu back into the clone.
        for case in cases:
            name = case + "_semantic.dpr"
            shutil.copy2(SOURCES / name, directory / name)
        fixture = "loader_boundary_fixture.pas"
        shutil.copy2(SOURCES / "support" / fixture, directory / fixture)
        run([str(compiler), *options, fixture], directory)
        for case in cases:
            name = case + "_semantic"
            run([str(compiler), *options, name + ".dpr"], directory)
            result = run([str(directory / (name + suffix))], directory)
            if case.upper() + "_PASS" not in result.splitlines():
                raise RuntimeError(f"Missing result for {name} {profile}: {result}")
            count += 1
            print(f"PASS {name} {profile}", flush=True)
        shutil.copy2(wait_sources / "thread_wait_contracts.dpr", directory)
        run([str(compiler), *options, "thread_wait_contracts.dpr"], directory)
        result = run([str(directory / ("thread_wait_contracts" + suffix))], directory, wait_env)
        if result.strip() != "THREAD_WAIT_CONTRACTS_OK":
            raise RuntimeError(f"Thread wait contract {profile}: {result}")
        count += 1
        print(f"PASS thread_wait_contracts {profile}", flush=True)
    print(f"RTL_BOUNDARIES_ARCHIVE_PASS rows={count}")


if __name__ == "__main__":
    main()
