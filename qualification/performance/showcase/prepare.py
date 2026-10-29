"""Freeze public Binance inputs and deterministic synthetic trades; no benchmark runs."""

import argparse
import datetime
import hashlib
import json
import pathlib
import random
import urllib.request
from decimal import Decimal


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("directory", type=pathlib.Path)
    ap.add_argument("--per-symbol", type=int, default=64)
    a = ap.parse_args()
    a.directory.mkdir(parents=True, exist_ok=True)
    response = a.directory / "exchangeInfo.json"
    if not response.exists():
        req = urllib.request.Request(
            "https://api.binance.com/api/v3/exchangeInfo",
            headers={"User-Agent": "MoonCompiler-benchmark/1.0"},
        )
        response.write_bytes(urllib.request.urlopen(req, timeout=60).read())
    info = json.loads(response.read_bytes())
    symbols = sorted(x["symbol"] for x in info["symbols"])
    assert len(symbols) == len(set(symbols)) and len(symbols) > 1000
    (a.directory / "symbols.txt").write_text(
        "\n".join(symbols) + "\n", encoding="utf-8"
    )
    expected = {
        s: {"count": 0, "volume": Decimal(0), "price": Decimal(0)} for s in symbols
    }
    rng = random.Random(20261029)
    order = list(range(len(symbols)))
    with (a.directory / "trades.jsonl").open(
        "w", encoding="utf-8", newline="\n"
    ) as out:
        tid = 100000000
        for round_no in range(a.per_symbol):
            rng.shuffle(order)
            for idx in order:
                symbol = symbols[idx]
                # Synthetic, positive decimal values; every status/symbol is deliberately covered.
                price = Decimal(
                    (idx * 7919 + round_no * 173) % 100000000 + 1
                ) / Decimal(10000)
                qty = Decimal((idx * 37 + round_no * 97) % 100000 + 1) / Decimal(100000)
                timestamp = 1793232000000 + tid - 100000000
                trade = {
                    "e": "aggTrade",
                    "E": timestamp + 2,
                    "s": symbol,
                    "a": tid,
                    "p": f"{price:.8f}",
                    "q": f"{qty:.8f}",
                    "f": tid * 2,
                    "l": tid * 2 + 1,
                    "T": timestamp,
                    "m": bool(tid & 1),
                    "M": True,
                }
                packet = {"stream": symbol.lower() + "@aggTrade", "data": trade}
                out.write(
                    json.dumps(packet, separators=(",", ":"), ensure_ascii=False) + "\n"
                )
                e = expected[symbol]
                e["count"] += 1
                e["price"] = price
                e["volume"] += price * qty
                tid += 1
    oracle = {
        s: {"count": v["count"], "price": str(v["price"]), "volume": str(v["volume"])}
        for s, v in expected.items()
    }
    (a.directory / "oracle.json").write_text(
        json.dumps(oracle, ensure_ascii=False), encoding="utf-8"
    )
    manifest = {
        "captured_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "endpoint": "https://api.binance.com/api/v3/exchangeInfo",
        "symbols": len(symbols),
        "trades": len(symbols) * a.per_symbol,
        "per_symbol": a.per_symbol,
        "seed": 20261029,
        "synthetic": True,
        "schema": "Binance Spot combined aggTrade stream; all returned symbols including inactive",
        "files": {
            p.name: {
                "bytes": p.stat().st_size,
                "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
            }
            for p in a.directory.iterdir()
            if p.is_file() and p.name != "manifest.json"
        },
    }
    (a.directory / "manifest.json").write_text(
        json.dumps(manifest, indent=2), encoding="utf-8"
    )
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
