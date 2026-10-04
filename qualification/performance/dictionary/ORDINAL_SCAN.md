# Ordinal value lookup model

`pulse_ordinal_scan.dpr` prepares a dictionary outside the measured interval
and queries its Integer values through the public `ContainsValue` method.
Every result contributes to an observable hit count checked against the
prepared queries. Setup also checks every inserted value and a missing value.

The keys are fully initialized 8-byte or 192-byte records. Their insertion
order is a deterministic permutation of 64 or 256 IDs. Reserving the count or
eight times the count separates dense and sparse tables without changing the
stored data. Queries are all misses, alternating hits and misses, or a zero
whose entry has been deleted. The last mode checks that unused and deleted
buckets do not match the default Integer value.

One operation is one lookup. Allocation, population, removal, validation and
destruction occur outside the timed callback. The callback never mutates the
dictionary, so independent calibration batches perform the same work per
lookup. The program calls the actual linked implementation and keeps no
private copied scan loop.

Pulse registers the program as `ordinal-scan`; `list` exposes 24 modes, for
example `key1-count256-reserve8-mode2`. This is a set of meaningful alternatives,
not a distribution assigning weights to key sizes or occupancies.
