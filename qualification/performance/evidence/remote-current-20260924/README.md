# Remote → Current, 2026-09-24

Remote `ccaa5fba` versus Current `1aa1e824`, Windows and Linux/HEL1.
[Release gains, practical TODO and trade-offs](REPORT.md); [supporting numerical excerpt](CASES.md);
[machine-readable evidence and identities](EVIDENCE.json).

The full screen measured 981 Windows and 973 Linux cases with 12 valid paired
processes each. The difference is eight Windows-only ASM controls. All measured
work counts and digests matched. The screen took 583.1 s / 546.6 s; independent
shortlist confirmation added 48.2 s / 33.9 s. Both A/A controls passed on each host.
Full coverage and confirmation were executed as successive validation stages
while developing the method; the committed runner performs both automatically
in one invocation. No compiler/RTL product change was made by this method update.

Useful gains include Variant dictionary lookup, case-insensitive string APIs,
TStringList lookup and ordinary RoundTo. For example RoundTo(-2) CPU cost fell
16.7% / 73.6% in the screen and 24.5% / 73.6% in confirmation (Windows / Linux).

Before choosing release preparation, investigate IntToStr(Int64) on Windows
(typical cost +60.5%, confirmation +35.6%) and the composed binary-session
pipeline on Linux (+36.3%, confirmation +35.9%). Both directions reproduced;
the IntToStr magnitude varies. Dictionary capacity reservation on Windows
(+47.7%, confirmation +48.6%) is real but is a one-time setup operation, so its
priority differs from hot lookup. List range editing and linked-list sorting
on Linux are additional practical optimization candidates in the report.
These are TODO candidates, not a declaration that every application got worse.

The accepted Move self-copy trade-off remains accepted. Ordinary copying has
measured wins (512 bytes with source offset 2048: Linux -22.5%, repeated -21.9%;
forward overlap of 64 bytes at distance 16: Windows -12.4%, repeated -12.5%).
Ordinary overlap losses are separate TODO. The screen's +67.9% 15-byte Move
result did not establish the same direction in independent confirmation and
is therefore excluded from the release regression top. Do not quote it as a
stable 68% regression.

On Windows, the 128-byte alloc/free fixture also shows a resource trade-off:
CPU cost -14.3% (repeat -13.3%), retained private memory -62%, but peak resident
memory 9.75 → 11.30 MiB (+15.9%). Those memory values describe the whole benchmark
process. This observation does not itself approve the trade-off for a product.

The report is a performance comparison of these inputs and hosts. It does not
replace correctness, archive/consumer, or full release qualification. Open
numerical risks remain visible; no case-count vote or global speedup is claimed.
