# Sorted row lookup

`sorted-lookup` prepares 4, 32 or 256 rows in a sorted `TStringList`, then
looks up eight names with mixed hits, misses and ASCII case differences.
The two dictionaries use a shared field-name prefix or different starting
characters. A hit consumes the row object's ID; a miss contributes one.
One operation is one lookup and result consumption. Preparation, independent
per-query identity checks and the full digest oracle are outside timing.

`UseLocale=False` explicitly selects ordinal UTF16 name comparison. The
ordinary `TStringList` default uses locale comparison and retains its virtual
comparer. Derived overrides and case-sensitive/locale paths are separately
covered by the API contract test, including duplicates, insertion positions
and the unsorted-list error.

```text
python qualification/performance/tools/pulse.py run --programs sorted-lookup --systems moon --mode quick
```
