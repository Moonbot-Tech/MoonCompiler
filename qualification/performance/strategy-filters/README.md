# Filter and EMA benchmarks

Both programs use deterministic, synthetic station readings. Each operation is one classification or one band-group evaluation. Each harness iteration performs 64 operations. Select the pair with `--programs strategy-filters,ema-filters`.

| Program | Work measured |
| --- | --- |
| `strategy-filters` | A threshold check with a calibration dictionary. Separate cases reject low-quality inputs early, search a station list, recompute limits using floating-point powers, read the clock, or construct a diagnostic string for a rejection. |
| `ema-filters` | A 2,048-row circular history of four exponential moving averages. Evaluation reads 64-byte rule records through a generic list, selects channels and checks weighted bands. Cases exercise one rule, eight rules, delayed history, a recent peak, alternative groups and missing channels. |

Moving averages are prepared before timing. Decisions vary across the fixture. Startup checks each scenario against an expected weighted sum over every input. The diagnostic case includes the formatted message length in that sum. The clock case performs one real clock read per calibrated station. Wall time does not select fixture outcomes on supported systems.

Use these workloads to compare code generation and RTL costs across compilers. Their results apply to the synthetic cases. Historical values obtained with other fixtures are separate measurement series.
