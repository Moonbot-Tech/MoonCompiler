from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import qualify_measurement_method as method


class MeasurementOutputTests(unittest.TestCase):
    def test_pascal_program_names_and_the_patched_control_are_accepted(self):
        for program, emitted in (("hot-rtl", "pulse_hot-rtl"), ("mormot-json", "pulse_mormot_json"),
                                 ("local-pressure", "pulse_local_pressure"), ("repairs-control", "pulse_repairs")):
            output = (f"PULSE_CASE program={emitted} case=a oracle=1\n"
                      f"PULSE_SAMPLE program={emitted} case=a sample=1 iterations=5 operations=5\n"
                      f"PULSE_END program={emitted} status=PASS\n")
            with self.subTest(program=program):
                definitions, samples = method.parse_measurement_output(output, program, ["a"], 1, Path("log"))
                self.assertEqual(definitions["a"]["oracle"], "1")
                self.assertEqual(samples["a"][0]["iterations"], 5)

    def test_both_launch_paths_bind_output_to_the_requested_work(self):
        valid = (
            "PULSE_CASE program=p case=a oracle=1\n"
            "PULSE_SAMPLE program=p case=a sample=1 iterations=5 operations=5\n"
            "PULSE_END program=p status=PASS\n"
        )
        invalid = {
            "other case": valid.replace("case=a", "case=b"),
            "other program": valid.replace("program=p", "program=q"),
            "missing definition": valid.split("\n", 1)[1],
            "duplicate definition": valid.split("\n", 1)[0] + "\n" + valid,
            "missing end": valid.replace("PULSE_END program=p status=PASS", "error=PULSE_END"),
            "failed end": valid.replace("status=PASS", "status=FAIL"),
            "duplicate end": valid + "PULSE_END program=p status=PASS\n",
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "p.exe"
            executable.write_bytes(b"image")
            launchers = (
                lambda: method.run_one(executable, "p", "a", "v", 0, 6, "single-cpu", (0,), root,
                                       samples_per_process=1),
                lambda: method.run_many(executable, "p", ["a"], "v", 0, 6, "single-cpu", (0,), root, 1, 1),
            )
            for index, launch in enumerate(launchers):
                with self.subTest(path=index, output="valid"), mock.patch.object(
                    method, "launch", return_value=(valid, 0, 7, 0.1, {})
                ):
                    self.assertTrue(launch())
                for name, output in invalid.items():
                    with self.subTest(path=index, output=name), mock.patch.object(
                        method, "launch", return_value=(output, 0, 7, 0.1, {})
                    ):
                        with self.assertRaises(RuntimeError):
                            launch()


if __name__ == "__main__":
    unittest.main()
