# Timestamp event processing

`timestamp-events` converts 64 prepared `TDateTime` values to Unix seconds,
consumes their hour buckets and compares successive timestamps. One operation
is one timestamp conversion and consumption. Input preparation and the complete
digest oracle are outside timing.

The three separate traces contain modern dates, negative `TDateTime` values
(dates before 30 December 1899), and one such date per four inputs.
Dates before the Unix epoch but after 30 December 1899 still use the positive
`TDateTime` path. These traces expose the normal positive conversion,
the retained calendar fallback and their composition, without assigning weights
to an application. This model does not call `Now` or measure OS clock access.

The independent DateTimeToUnix contract test also covers millisecond rounding,
neighbouring binary64 values, date limits, local-time conversion, invalid values
and all four floating-point rounding modes.

```text
python qualification/performance/tools/pulse.py run --programs timestamp-events --systems moon --mode quick
```
