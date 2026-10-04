"""Hostile checks for effect expectations and explicit installed-RTL overrides."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]


def load(path: str):
    spec = importlib.util.spec_from_file_location("gate", ROOT / path)
    module = importlib.util.module_from_spec(spec)
    with patch.object(sys, "path", [str((ROOT / path).parent), *sys.path]):
        spec.loader.exec_module(module)
    return module


class OptimizerGateContracts(unittest.TestCase):
    def test_explicit_rtl_and_help_do_not_probe_an_implicit_install(self):
        paths = (
            "effect-observe/run_effect_gate.py", "effect-observe/run_effect_identity.py",
            "optimizer-core/f2/run_f2_gate.py", "optimizer-core/f2/run_f2_ppu.py",
            "optimizer-core/f2/run_exact_gate.py", "optimizer-core/setcc-compare/run_gate.py",
            "optimizer-core/f3/run_f3_gate.py", "optimizer-core/f4/run_f4_gate.py",
            "optimizer-core/f5/run_f5_gate.py", "optimizer-core/cse/run_managed_load_gate.py",
            "optimizer-core/loop-base/run_loop_base_gate.py",
            "optimizer-core/placement/run_code_alignment_gate.py",
            "optimizer-core/placement/run_branch_pad_gate.py", "optimizer-core/shl-lea/run_shl_lea_gate.py",
            "compiler-asm-numbers/run_gate.py",
            "optimizer-core/f2/run_f2_perf.py", "optimizer-core/f3/run_f3_scaling.py",
            "optimizer-core/loop-regvar/run_loop_regvar_gate.py",
        )
        for path in paths:
            gate = load("qualification/" + path)
            with self.subTest(path=path), contextlib.redirect_stdout(io.StringIO()), \
                    patch.object(gate, "default_rtl", side_effect=AssertionError("implicit RTL probe")):
                with patch.object(sys, "argv", [path, "--help"]), self.assertRaises(SystemExit) as exit:
                    gate.main()
                self.assertEqual(exit.exception.code, 0)
                # Stop at the first workspace operation after argument parsing.
                # The old eager default raises before reaching either boundary.
                with patch.object(sys, "argv", [path, "--rtl", "explicit-rtl"]), \
                        patch.object(gate.Path, "exists", side_effect=RuntimeError("parsed")), \
                        patch.object(gate.tempfile, "mkdtemp", side_effect=RuntimeError("parsed")), \
                        self.assertRaisesRegex(RuntimeError, "parsed"):
                    gate.main()

    def test_tail_help_and_explicit_toolchain_do_not_probe_an_implicit_install(self):
        gate = load("qualification/optimizer-core/tail-forwarding/run_gate.py")
        with contextlib.redirect_stdout(io.StringIO()), \
                patch.object(sys, "argv", ["tail", "--help"]), \
                patch.object(gate.Path, "resolve", side_effect=AssertionError("implicit install probe")), \
                self.assertRaises(SystemExit) as exit:
            gate.main()
        self.assertEqual(exit.exception.code, 0)
        with tempfile.TemporaryDirectory() as directory:
            install = Path(directory) / "explicit-install"
            config = install / ("bin/x86_64-win64/fpc.cfg" if os.name == "nt" else "etc/fpc.cfg")
            with patch.object(sys, "argv", ["tail", "--toolchain", str(install), "--output", directory]), \
                    patch.object(gate.Path, "read_text", autospec=True, side_effect=RuntimeError("parsed")) as read, \
                    self.assertRaisesRegex(RuntimeError, "parsed"):
                gate.main()
            self.assertEqual(read.call_args.args[0], config.resolve())

    def test_relation_and_source_ir_help_need_no_install(self):
        for path in ("value-relations/run_gate.py", "value-relations/run_ir_gate.py",
                     "value-in-register/run_ir_gate.py"):
            gate = load("qualification/optimizer-core/" + path)
            with self.subTest(path=path), contextlib.redirect_stdout(io.StringIO()), \
                    patch.object(sys, "argv", [path, "--help"]), \
                    patch.object(gate.Path, "resolve", side_effect=AssertionError("implicit install probe")), \
                    self.assertRaises(SystemExit) as exit:
                gate.main()
            self.assertEqual(exit.exception.code, 0)

    def test_effect_contract_rejects_missing_writes_reasons_and_temp_identity(self):
        gate = load("qualification/effect-observe/run_effect_gate.py")
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "f_contract.pas"
            fixture.write_text(
                "// EXPECT: proc=Cow r=EHGTP w_contains=EHGTP ie=smt reason=string_cow\n"
                "// EXPECT: proc=Temp temps=1 rl=- wl=- sc=1 q=ok un=ok reason=compiler_temp\n"
                "// EXPECT-NOT: proc=Pure reason=string_cow\n", encoding="utf-8")
            baseline = {
                "Cow": dict(r="EHGTP", w="L!EHGTP", ie="smt", reasons="string_cow:1",
                            reason_map={"string_cow": 1}),
                "Temp": dict(temps="1", rl="-", wl="-", sc="1", q="ok", un="ok",
                             reasons="compiler_temp:1", reason_map={"compiler_temp": 1}),
                "Pure": dict(reasons="-", reason_map={}),
            }

            def check(rows):
                failures = []
                gate.check_fixture(fixture, rows, "contract", failures)
                return failures

            self.assertEqual(check(baseline), [])
            # Refining the unknown-block fallback can remove unbounded L.
            refined = {name: dict(row) for name, row in baseline.items()}
            refined["Cow"]["w"] = "EHGTP"
            self.assertEqual(check(refined), [])
            for name, field, value in (
                ("Cow", "w", "HGTP"), ("Cow", "w", "EGTP"), ("Cow", "w", "EHTP"),
                ("Cow", "w", "EHGP"), ("Cow", "w", "EHGT"), ("Cow", "w", "L"),
                ("Cow", "reason_map", {}), ("Cow", "reason_map", {"string_cow": 0}), ("Temp", "temps", "0"),
                ("Temp", "wl", "local"), ("Temp", "reason_map", {}),
                ("Pure", "reason_map", {"string_cow": 1}),
            ):
                with self.subTest(name=name, field=field, value=value):
                    mutant = {name: dict(row) for name, row in baseline.items()}
                    mutant[name][field] = value
                    self.assertTrue(check(mutant))

    def test_failed_determinism_repeat_cannot_report_pass(self):
        gate = load("qualification/effect-observe/run_effect_gate.py")
        summary = "effect-observe-summary: proc=Local mid=LOCAL nodes=1 r=L w=L ie=- temps=0 reasons=-\n"
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            (base / "f_repeat.pas").write_text("// EXPECT: proc=Local r=L\n")
            (base / "system.ppu").touch()
            output = io.StringIO()
            with patch.object(gate, "FIXTURES", base), \
                    patch.object(sys, "argv", ["gate", "--compiler", __file__, "--rtl", str(base)]), \
                    patch.object(gate, "compile_fixture", side_effect=[(0, summary), (0, summary),
                                                                       (1, "repeat failed"), (0, "")]), \
                    contextlib.redirect_stdout(output):
                self.assertEqual(gate.main(), 1)
            self.assertIn("[repeat]: compile failed", output.getvalue())

    def test_zeroext_explicit_install_overrides_both_lab_roots_and_propagates_failure(self):
        gate = load("qualification/suite/scripts/run_devil_zeroext_gate.py")
        with tempfile.TemporaryDirectory() as directory, \
                patch.dict(os.environ, MOONBOT_TOOLCHAIN="foreign-backend", DEVIL_TOOLCHAIN_ROOT="foreign-mm"):
            installed = str((Path(directory) / "installed").resolve())
            for explicit in (False, True):
                with self.subTest(explicit=explicit):
                    argv = ["zeroext", "--work", directory]
                    if explicit:
                        argv += ["--toolchain", installed]
                    with patch.object(sys, "argv", argv), \
                            patch.object(gate.subprocess, "run", return_value=subprocess.CompletedProcess([], 7)) as run, \
                            self.assertRaises(SystemExit) as exit:
                        gate.main()
                    self.assertEqual(exit.exception.code, 7)
                    env = run.call_args.kwargs["env"]
                    self.assertEqual(env["MOONBOT_TOOLCHAIN"], installed if explicit else "foreign-backend")
                    self.assertEqual(env["DEVIL_TOOLCHAIN_ROOT"], installed if explicit else "foreign-mm")
                    self.assertEqual(os.environ["MOONBOT_TOOLCHAIN"], "foreign-backend")

    @unittest.skipUnless(os.name == "nt", "native PowerShell failure propagation")
    def test_windows_optimizer_ci_stops_after_each_kind_of_native_failure(self):
        workflow = (ROOT / ".github/workflows/qualification.yml").read_text(encoding="utf-8")
        pattern = (r"      - name: Run optimizer model and transformation contracts\n"
                   r"        shell: powershell\n        run: \|\n((?:          .*\n|\n)+)")
        body = "".join(line[10:] if line.startswith("          ") else line
                       for line in re.search(pattern, workflow).group(1).splitlines(keepends=True))
        stub = """
function Invoke-GateStub {
  $global:GateInvocation++
  Write-Output "INVOKED=$global:GateInvocation"
  $code = If ($global:GateInvocation -eq $global:GateFailure) { 7 } else { 0 }
  & $env:ComSpec /d /c exit $code
  $global:LASTEXITCODE = $LASTEXITCODE
}
function python { Invoke-GateStub }
"""
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            stack = base / "qualification/win-stack-default/run.ps1"
            stack.parent.mkdir(parents=True)
            stack.write_text("Invoke-GateStub\n")
            probe = base / "probe.ps1"
            # First/last foreach iteration and every subsequent command kind.
            for failure in (0, 1, *range(11, 21)):
                with self.subTest(failure=failure):
                    probe.write_text(f"$global:GateInvocation = 0\n$global:GateFailure = {failure}\n"
                                     + stub + body + "\nexit $LASTEXITCODE\n")
                    result = subprocess.run(["powershell", "-NoProfile", "-File", str(probe)],
                                            cwd=base, capture_output=True, text=True, timeout=30)
                    calls = [int(value) for value in re.findall(r"INVOKED=(\d+)", result.stdout)]
                    self.assertEqual(calls, list(range(1, (failure or 20) + 1)), result.stderr)
                    self.assertEqual(result.returncode == 0, failure == 0, result.stderr)

    @unittest.skipIf(os.name == "nt", "native bash failure propagation")
    def test_linux_optimizer_ci_stops_after_each_kind_of_native_failure(self):
        workflow = (ROOT / ".github/workflows/qualification.yml").read_text(encoding="utf-8")
        pattern = (r"      - name: Run optimizer model and transformation contracts\n"
                   r"        run: \|\n((?:          .*\n|\n)+)")
        body = "".join(line[10:] if line.startswith("          ") else line
                       for line in re.search(pattern, workflow).group(1).splitlines(keepends=True))
        stub = """
calls=0
python3() {
  calls=$((calls+1))
  printf 'INVOKED=%s\\n' "$calls"
  if [ "$calls" = "$failure" ]; then return 7; fi
}
"""
        with tempfile.TemporaryDirectory() as directory:
            for failure in (0, 1, *range(11, 20)):
                with self.subTest(failure=failure):
                    result = subprocess.run(["bash", "-e", "-c", f"failure={failure}\n" + stub + body],
                                            cwd=directory, capture_output=True, text=True, timeout=30)
                    calls = [int(value) for value in re.findall(r"INVOKED=(\d+)", result.stdout)]
                    self.assertEqual(calls, list(range(1, (failure or 19) + 1)), result.stderr)
                    self.assertEqual(result.returncode == 0, failure == 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
