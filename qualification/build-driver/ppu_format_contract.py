#!/usr/bin/env python3
"""Guard the independent header and payload version domains of compiler PPUs."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
PPU = ROOT / "compiler" / "ppu.pas"
AASMTai = ROOT / "compiler" / "aasmtai.pas"
HEADER_VERSION = 208
ALIGN_PAYLOAD_VERSION = 45


def constant(source: str, name: str) -> int:
    match = re.search(rf"\b{re.escape(name)}\s*=\s*(\d+)\s*;", source)
    if match is None:
        raise RuntimeError(f"cannot find {name} in {PPU}")
    return int(match.group(1))


def main() -> int:
    ppu = PPU.read_text(encoding="utf-8")
    short = constant(ppu, "CurrentPPUVersion")
    long = constant(ppu, "CurrentPPULongVersion")
    if short != HEADER_VERSION:
        raise RuntimeError(
            f"PPU header version is {short}, expected {HEADER_VERSION}; "
            "the byte-sized version changes only with tppuheader"
        )
    if long < ALIGN_PAYLOAD_VERSION:
        raise RuntimeError(
            f"PPU payload version is {long}, but serialized placement "
            f"fields require at least {ALIGN_PAYLOAD_VERSION}"
        )

    aasmtai = AASMTai.read_text(encoding="utf-8")
    load = aasmtai.index("constructor tai_align_abstract.ppuload")
    write = aasmtai.index("procedure tai_align_abstract.ppuwrite", load)
    end = aasmtai.index("{****************************************************************************", write)
    payload = aasmtai[load:end]
    for field in ("fixedfill", "padbytes", "purpose"):
        if payload.count(field) < 2:
            raise RuntimeError(
                f"serialized alignment field {field} is missing a read/write side"
            )
    print(
        "PPU_FORMAT_CONTRACT_PASS "
        f"header={short} payload={long} align_fields=fixedfill,padbytes,purpose"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
