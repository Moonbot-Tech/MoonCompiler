"""Pulse must build the application's Release profile, including its language."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

import pulse


class ReleaseProfileTests(unittest.TestCase):
    def test_current_toolchain_uses_product_config_with_release_selected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config_dir = root / ("bin/x86_64-win64" if pulse.IS_WINDOWS else "etc")
            config_dir.mkdir(parents=True)
            config = config_dir / "fpc.cfg"
            config.write_text("#INCLUDE moon-base.cfg\n#IFDEF RELEASE\n-O3\n#ENDIF\n")
            (config_dir / "moon-base.cfg").write_text("# base\n")
            backend = root / "ppcx64"
            backend.touch()
            with mock.patch.object(pulse, "moon_toolchain_backend", return_value=backend), \
                 mock.patch.object(pulse, "output_dir", return_value=root / "out"), \
                 mock.patch.object(pulse, "run") as run:
                pulse.build_moon("abi", False, toolchain=root)
            command = run.call_args.args[0]
            self.assertIn(f"@{config}", command)
            self.assertIn("-dRELEASE", command)
            self.assertLess(command.index("-dRELEASE"), command.index(f"@{config}"))
            # The product config owns the language; the builder must not
            # substitute its old partial profile after reading that config.
            self.assertNotIn("-Mdelphi", command)

    def test_legacy_toolchain_receives_the_old_drivers_release_profile(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config_dir = root / ("bin/x86_64-win64" if pulse.IS_WINDOWS else "etc")
            config_dir.mkdir(parents=True)
            config = config_dir / "fpc.cfg"
            config.write_text("-O2\n")  # ccaa's template was not its app profile.
            backend = root / "ppcx64"
            backend.touch()
            with mock.patch.object(pulse, "moon_toolchain_backend", return_value=backend), \
                 mock.patch.object(pulse, "output_dir", return_value=root / "out"), \
                 mock.patch.object(pulse, "run") as run:
                pulse.build_moon("abi", False, toolchain=root)
            command = run.call_args.args[0]
            configs = [Path(arg[1:]) for arg in command if arg.startswith("@")]
            self.assertEqual(len(configs), 2)
            self.assertEqual(configs[0], config)
            profile = configs[1].read_text().splitlines()
            for option in ("-Minlinevars", "-Mfunctionreferences", "-Municodestrings",
                           "-FNSystem", "-UaSystem.SysUtils=SysUtils", "-O3", "-Ci",
                           "-Co-", "-Cr-", "-Ct-", "-Sa-", "-gl", "-gw3", "-uDEBUG"):
                self.assertIn(option, profile)

    def test_base_config_remains_part_of_build_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            driver, config = pulse.moon_toolchain_paths(root)
            base = config.with_name("moon-base.cfg")
            backend = root / "ppcx64"
            for path in (driver, config, base, backend):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("first")
            with mock.patch.object(pulse, "moon_toolchain_backend", return_value=backend):
                before = pulse.moon_toolchain_identity(root)
                base.write_text("different pinned MM")
                after = pulse.moon_toolchain_identity(root)
            self.assertNotEqual(before, after)
            self.assertEqual(after["base_config_sha256"], pulse.sha256(base))

    @unittest.skipUnless(os.environ.get("PULSE_TEST_TOOLCHAIN"), "requires a ready product toolchain")
    def test_product_language_and_release_behavior_with_real_compiler(self):
        root = Path(os.environ["PULSE_TEST_TOOLCHAIN"])
        mm = Path(os.environ.get("PULSE_TEST_MM_SOURCE", pulse.MM_SOURCE))
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary)
            source = target / "pulse_profile.dpr"
            source.write_text("""program pulse_profile;
uses mormot.core.fpcx64mm, System.SysUtils;
begin
  {$ifndef RELEASE}{$fatal Release define missing}{$endif}
  {$ifdef DEBUG}{$fatal Debug define present}{$endif}
  {$ifopt I-}{$fatal IO checks disabled}{$endif}
  {$ifopt R+}{$fatal Range checks enabled}{$endif}
  {$ifopt Q+}{$fatal Overflow checks enabled}{$endif}
  Assert(False);
  for var I := 1 to 1 do Writeln(I, ':', SizeOf(Char));
end.
""")
            def run(command, **kwargs):
                result = subprocess.run(command, capture_output=True, text=True,
                                        creationflags=0x08000000 if pulse.IS_WINDOWS else 0)
                if result.returncode:
                    print(result.stdout + result.stderr)
                result.check_returncode()
                return result
            with mock.patch.dict(pulse.PROGRAMS, {"profile": source}), \
                 mock.patch.object(pulse, "output_dir", return_value=target), \
                 mock.patch.object(pulse, "run", side_effect=run):
                exe = pulse.build_moon("profile", False, toolchain=root, mm_source=mm)
                self.assertEqual(run([str(exe)]).stdout.strip(), "1:2")
                for override in ("-uRELEASE", "-dDEBUG", "-Ci-", "-Sa"):
                    with self.subTest(override=override), self.assertRaises(subprocess.CalledProcessError):
                        exe = pulse.build_moon("profile", False, toolchain=root, mm_source=mm,
                                              extra_options=[override])
                        run([str(exe)])


if __name__ == "__main__":
    unittest.main()
