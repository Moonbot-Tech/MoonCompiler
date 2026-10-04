"""zlib_delphi_gate.py: a verdict only when every process pair is on one side of the line."""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import zlib_delphi_gate as gate


def row(minimum: float, maximum: float, oracle: str = "MATCH") -> dict[str, object]:
    return {"oracle_status": oracle,
            "paired_candidate_over_baseline": {"minimum": minimum, "maximum": maximum}}


def result(folder: Path, rows: dict[str, dict[str, object]]) -> Path:
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "summary.json").write_text(json.dumps({f"zlib/{name}": value for name, value in rows.items()}),
                                         encoding="utf-8")
    return folder


class ZlibDelphiGateTests(unittest.TestCase):
    def test_a_verdict_needs_every_pair_on_one_side(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            folder = result(Path(temporary), {
                "websocket-inflate-256": row(1.234, 1.276),         # byte-copying zlib of 28.09 morning
                "stream-deflate-trades-4k": row(0.846, 0.881),
                "stream-inflate-trades-4k": row(0.463, 0.574),      # Pulse DRIFT, plainly not slower
                "stream-deflate-candles-1m": row(0.98, 1.09),       # straddles 1.05: no verdict
                "stream-inflate-candles-1m": row(0.9, 1.0, "DIFF"),
            })
            verdicts = gate.verdicts(folder, list(gate.PRODUCT_ROWS))
        self.assertTrue(verdicts["websocket-inflate-256"].startswith("SLOWER"))
        self.assertTrue(verdicts["stream-deflate-trades-4k"].startswith("PASS"))
        self.assertTrue(verdicts["stream-inflate-trades-4k"].startswith("PASS"))
        self.assertTrue(verdicts["stream-deflate-candles-1m"].startswith("UNRESOLVED"))
        self.assertEqual(verdicts["stream-inflate-candles-1m"], "SEMANTIC_MISMATCH")
        self.assertEqual(verdicts["stream-deflate-history-fastest"], "MISSING")
        with tempfile.TemporaryDirectory() as temporary:
            folder = result(Path(temporary), {"websocket-inflate-256": row(1.0, gate.LIMIT)})
            self.assertTrue(gate.verdicts(folder, ["websocket-inflate-256"])["websocket-inflate-256"]
                            .startswith("PASS"))

    def test_an_undecided_row_is_measured_again_and_fails_when_it_stays_undecided(self) -> None:
        def run(outcomes: list[dict[str, dict[str, object]]]) -> tuple[int, list[list[str]]]:
            asked: list[list[str]] = []
            with tempfile.TemporaryDirectory() as temporary:
                def measure(output, rows, toolchain, attempt):
                    asked.append(list(rows))
                    return result(Path(temporary) / str(attempt), outcomes[attempt - 1])
                with mock.patch.object(gate, "measure", measure), \
                     mock.patch("sys.argv", ["zlib_delphi_gate.py", "--output", temporary]), \
                     mock.patch("builtins.print"):
                    return gate.main(), asked
        passing = {name: row(0.85, 0.95) for name in gate.PRODUCT_ROWS}
        undecided = dict(passing, **{"websocket-inflate-256": row(1.0, 1.1)})
        code, asked = run([undecided, {"websocket-inflate-256": row(0.9, 0.95)}])
        self.assertEqual((code, asked[1]), (0, ["websocket-inflate-256"]))
        code, asked = run([undecided, {"websocket-inflate-256": row(1.0, 1.1)},
                           {"websocket-inflate-256": row(1.01, 1.2)}])
        self.assertEqual((code, len(asked)), (1, gate.ATTEMPTS))
        slower = dict(passing, **{"stream-deflate-trades-4k": row(1.2, 1.3)})
        code, asked = run([slower])
        self.assertEqual((code, len(asked)), (1, 1))


if __name__ == "__main__":
    unittest.main()
