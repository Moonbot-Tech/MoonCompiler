# System.Move x86-64 evidence — 2026-08-24

Exact code: `75190e41` on top of test matrix `dce51dba`.

Verification contract:

- Win64, Delphi 12.2 `dcc64 -O+ --inline:auto` against MoonCompiler `-O3`;
- 297 identical cases, each run by seven paired processes in palindromic
  Delphi/Moon order;
- the primary Move metric is TSC ticks/op inside the tight loop;
- half-sample mode rejects outliers; adjacent mirrored processes yield the
  central paired ratio;
- any differing digest is a semantic failure, not a performance result.

Result: 297/297 oracle MATCH, geomean Moon/Delphi `0.936`, 124 clear wins,
144 at parity, 29 losses. The complete table is in `REPORT.md`, exact samples
and paired ratios are in `summary.json`.

A separate exact old/new A/B confirmed the cache-policy boundary. At the same
1 MiB size, the new temporal path costs `0.425x` of the old one in hot/reuse
form, but `1.522x` in one-pass streaming form. Starting at 16 MiB, the new code
enables NT stores and returns to parity with the old one. The size and addresses
of one call contain no information about future reuse, so one size-only
threshold cannot win both forms at once. The production policy retains data in
cache while source+dest fit in the largest deterministic cache; a separate
hinted streaming API is permissible only with a proven product consumer.

Additional gates:

- clean `build.ps1 compiler` completed;
- `system_move_semantic.dpr`: debug/O2/O3 — 3/3;
- full Win64 `RTL-test`: 240/240;
- clean Linux x86-64 `./build compiler` completed on Intel Xeon W-2295;
- Linux `system_move_semantic.dpr`: debug/O2/O3 — 3/3;
- full Linux `RTL-test`: 237/237;
- Linux medium: 297/297 oracle MATCH for bundled/default-MM binaries.

The Linux performance ratio in `LINUX_REPORT.md` is not a comparison of two
`Move` implementations: both executables contain the same RTL but differ in
MM, link layout, and process placement. It is therefore used only as a
cross-CPU/runtime control without a failure; Win64 A/B provides the
Delphi-relative verdict.

SHA-256:

- `summary.json`: `033E8C12363FC90AFECB89E269B1F094B95EDCBFC47F7514848FEC197CCB2084`;
- `REPORT.md`: `61189FCC1D56232AFA3EA76C23DEC4AE3FA9A710D68E00C07E52D8FC5A79EBBD`;
- `linux-summary.json`: `6EBF9111CEFDE92ED5E8804915FECD8BD96E2419C6C6B4A935581DF33EFD4787`;
- `LINUX_REPORT.md`: `34501E4F995519F815890AFA7DCEB6742E7FB248D2B1B221A76456F07C49F784`;
- `OLD_VS_NEW_QUICK_REPORT.md`: `4690BB24465F0CE06AD2CA1DEFB1B38032D4F81B13BE15C743F0CBC3E960A5EB`;
- `old-vs-new-quick-summary.json`: `0C90A494DBCE5895994A49D745DEEE65B60167C101B37F8107F1284EF2D06B4C`;
- `OLD_VS_NEW_REPORT.md`: `0597CBDCCE47822A530F8D2281C97C4C9749E5932213AEB06C6381EBE733EC4E`;
- `old-vs-new-summary.json`: `BEEB5CAE1A3C29B1D91F081BBF5301807A0C205C4C6CF69DF817E4C4564578FC`.
