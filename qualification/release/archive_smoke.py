#!/usr/bin/env python3
"""Exercise a release archive outside the source tree and through build toolchain."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile


ROOT = Path(__file__).resolve().parents[2]
MM = Path("runtime/mm/mormot.core.fpcx64mm.pas")


def run(label: str, command: list[str], cwd: Path, output: Path, steps: list[dict],
        marker: str | None = None) -> None:
    print(f"ARCHIVE_START {label}", flush=True)
    started = time.monotonic()
    step = {"name": label, "log": str(output / f"{label}.log")}
    try:
        result = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                                errors="replace", timeout=900)
        log = (result.stdout or "") + (result.stderr or "")
        (output / f"{label}.log").write_text(log, encoding="utf-8")
        if result.returncode or (marker is not None and marker not in log):
            raise RuntimeError(f"{label}: exit={result.returncode}; see {label}.log\n"
                               + "\n".join(log.splitlines()[-12:]))
    except Exception as error:
        step.update(status="fail", error=str(error))
        raise
    else:
        step["status"] = "pass"
        print(f"ARCHIVE_PASS {label} {time.monotonic() - started:.0f}s", flush=True)
    finally:
        step["seconds"] = round(time.monotonic() - started, 1)
        steps.append(step)


def stage(label: str, action, steps: list[dict]) -> None:
    started = time.monotonic()
    step = {"name": label}
    try:
        action()
    except Exception as error:
        step.update(status="fail", error=str(error))
        raise
    else:
        step["status"] = "pass"
    finally:
        step["seconds"] = round(time.monotonic() - started, 1)
        steps.append(step)


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def pack(toolchain: Path, asset: Path) -> None:
    if os.name == "nt":
        with zipfile.ZipFile(asset, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(toolchain.rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(toolchain))
    else:
        with tarfile.open(asset, "w:gz") as archive:
            archive.add(toolchain, arcname=".")


def unpack(asset: Path, target: Path) -> None:
    target.mkdir(parents=True)
    if os.name == "nt":
        with zipfile.ZipFile(asset) as archive:
            archive.extractall(target)
    else:
        with tarfile.open(asset, "r:gz") as archive:
            archive.extractall(target, filter="data")


def consumer_smoke(asset: Path, pin: str, output: Path, steps: list[dict]) -> None:
    with tempfile.TemporaryDirectory(prefix="mooncompiler-consumer-") as temp:
        consumer = Path(temp).resolve()
        if consumer.is_relative_to(ROOT):
            raise RuntimeError("consumer directory must be outside the source tree")
        toolchain = consumer / "toolchain"
        app = consumer / "app"
        stage("unpack", lambda: unpack(asset, toolchain), steps)
        app.mkdir()
        if (consumer / ".git").exists() or (app / ".git").exists():
            raise RuntimeError("consumer smoke unexpectedly contains a checkout")
        run("clone_moonormot", ["git", "clone", "--quiet", "--depth", "1",
                              "https://github.com/Moonbot-Tech/MoonORMot.git",
                              str(consumer / "mormot")], consumer, output, steps)
        actual = subprocess.check_output(
            ["git", "-C", str(consumer / "mormot"), "rev-parse", "HEAD"],
            text=True).strip()
        if actual != pin:
            raise RuntimeError(f"MoonORMot moved: archive pin {pin}, main {actual}")
        for source in (ROOT / "examples/hello.dpr", ROOT / "examples/zip.dpr",
                       ROOT / "RTL-test/semantic/file_resource_semantic.dpr",
                       ROOT / "tests/test/units/system/tres4.res"):
            shutil.copy2(source, app / source.name)
        resource = app / "file_resource_semantic.dpr"
        source = resource.read_text(encoding="utf-8")
        old = "{$R ../../tests/test/units/system/tres4.res}"
        if source.count(old) != 1:
            raise RuntimeError("resource smoke source changed")
        resource.write_text(source.replace(old, "{$R tres4.res}"), encoding="utf-8")
        target = "x86_64-win64" if os.name == "nt" else "x86_64-linux"
        fpc = toolchain / ("bin/x86_64-win64/fpc.exe" if os.name == "nt"
                           else "bin/fpc")
        suffix = ".exe" if os.name == "nt" else ""
        for profile, options in (("debug", []), ("release", ["-dRELEASE"])):
            for name, marker in (("hello", "3 prices, sum = "),
                                 ("zip", "ZIP_EXAMPLE_OK"),
                                 ("file_resource_semantic", "FILE_RESOURCE_PASS")):
                run(f"{profile}_{name}_build", [str(fpc), *options, name + ".dpr"],
                    app, output, steps)
                run(f"{profile}_{name}_run", [str(app / (name + suffix))],
                    app, output, steps, marker)
        for profile in ("debug", "release"):
            if not (app / "units" / target / profile).is_dir():
                raise RuntimeError(f"missing {profile} unit directory")


def driver_install(asset: Path, head: str, output: Path, steps: list[dict]) -> None:
    with tempfile.TemporaryDirectory(prefix="mooncompiler-install-") as temp:
        checkout = Path(temp) / "source"
        run("install_worktree", ["git", "worktree", "add", "--detach", str(checkout),
                                 head], ROOT, output, steps)
        try:
            driver = (["powershell", "-NoProfile", "-File", str(checkout / "build.ps1")]
                      if os.name == "nt" else ["bash", str(checkout / "build")])
            run("driver_install", [*driver, "toolchain", str(asset)], checkout, output, steps)
            installed = checkout / "toolchain"
            config = (installed / "bin/x86_64-win64/moon-base.cfg" if os.name == "nt"
                      else installed / "etc/moon-base.cfg")
            ide_config = (installed / "bin/x86_64-win64/fpc.cfg" if os.name == "nt"
                          else installed / "etc/fpc.cfg")
            for path in (config, ide_config):
                if "toolchain.new." in path.read_text(encoding="utf-8"):
                    raise RuntimeError(f"installed configuration retains staging path: {path}")
            for path in ((installed / "bin/x86_64-win64/fpcres.exe",
                          installed / "ide/bin/x86_64-win64/fpcres.exe") if os.name == "nt"
                         else (installed / "bin/fpcres", installed / "ide/bin/fpcres")):
                if not path.is_file():
                    raise RuntimeError(f"installed archive lacks resource compiler: {path}")
            if os.name == "nt":
                units = Path("units/x86_64-win64")
            else:
                matches = list((ROOT / "toolchain/lib/fpc").glob(
                    "*/units/x86_64-linux/rtl/system.ppu"))
                if len(matches) != 1:
                    raise RuntimeError(f"expected one Linux RTL profile, found {len(matches)}")
                units = matches[0].parent.parent.relative_to(ROOT / "toolchain")
            binaries = (["bin/x86_64-win64/fpc.exe", "bin/x86_64-win64/ppcx64.exe"]
                        if os.name == "nt" else ["bin/fpc", "bin/ppcx64"])
            witnesses = ["profile.txt", "runtime/mm/mormot.core.fpcx64mm.pas",
                         *binaries, str(units / "rtl/system.ppu"),
                         str(units / "rtl/sysutils.o"),
                         str(units / "rtl-generics/generics.hashes.o")]
            for name in witnesses:
                if sha256(installed / name) != sha256(ROOT / "toolchain" / name):
                    raise RuntimeError(f"installed archive changed witness {name}")
            failures = []
            for name in ("config_contract_gate", "product_config_gate", "unit_scope_gate",
                         "version_contract"):
                try:
                    run("installed_" + name,
                        [sys.executable, str(checkout / "qualification/build-driver" / (name + ".py"))],
                        checkout, output, steps)
                except (RuntimeError, subprocess.SubprocessError) as error:
                    failures.append(str(error))
            if failures:
                raise RuntimeError("\n".join(failures))
        finally:
            subprocess.run(["git", "worktree", "remove", "--force", str(checkout)],
                           cwd=ROOT, capture_output=True, text=True, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    steps: list[dict] = []
    failures = []
    report = {"platform": sys.platform, "steps": steps}
    try:
        head = git("rev-parse", "HEAD")
        report["head"] = head
        if git("status", "--porcelain", "--untracked-files=no"):
            raise RuntimeError("tracked source is dirty")
        manifest = json.loads((ROOT / "qualification/suite/runner_manifest.json").read_text(
            encoding="utf-8"))
        pin = manifest["mormot"]["sources"]["current"]["commit"]
        report["moonormot"] = pin
        toolchain = ROOT / "toolchain"
        if toolchain.is_symlink() or (hasattr(os.path, "isjunction")
                                      and os.path.isjunction(toolchain)):
            raise RuntimeError("release archive needs a freshly built real toolchain directory")
        bundled = toolchain / MM
        if not bundled.is_file() or bundled.read_bytes().replace(b"\r\n", b"\n") != (
                ROOT / MM).read_bytes().replace(b"\r\n", b"\n"):
            raise RuntimeError("installed toolchain MM differs from this source HEAD")
        asset = output / ("mooncompiler-toolchain-" + head[:12]
                          + ("-win64.zip" if os.name == "nt" else "-linux-x86-64.tar.gz"))
        report["asset"] = str(asset)
        print(f"ARCHIVE_START pack {head}", flush=True)
        stage("pack", lambda: pack(toolchain, asset), steps)
        print(f"ARCHIVE_PASS pack {asset.stat().st_size} bytes", flush=True)
        report["asset_sha256"] = sha256(asset)
        try:
            run("source_rtl_profile_gate",
                [sys.executable, str(ROOT / "qualification/build-driver/rtl_profile_gate.py")],
                ROOT, output, steps)
        except (RuntimeError, subprocess.SubprocessError) as error:
            failures.append(str(error))
        for label, action in (("consumer", lambda: consumer_smoke(asset, pin, output, steps)),
                              ("driver", lambda: driver_install(asset, head, output, steps))):
            try:
                stage(label, action, steps)
            except (RuntimeError, subprocess.SubprocessError) as error:
                failures.append(f"{label}: {error}")
        if failures:
            raise RuntimeError("\n".join(failures))
        report["status"] = "pass"
        print(f"ARCHIVE_SMOKE_PASS {head} {asset}", flush=True)
        return 0
    except Exception as error:
        report["status"] = "fail"
        if not failures:
            failures.append(str(error))
        raise
    finally:
        report["failures"] = failures
        (output / "report.json").write_text(json.dumps(report, indent=2) + "\n",
                                            encoding="utf-8")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"ARCHIVE_SMOKE_FAIL {error}", file=sys.stderr)
        raise SystemExit(1)
