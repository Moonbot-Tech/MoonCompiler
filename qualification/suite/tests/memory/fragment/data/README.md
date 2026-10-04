# Replay data

The original MoonBot capture contains two 237 MB event streams plus small JSON,
gzip, epoch, and order-book fixtures. Those opaque production-derived captures
are deliberately not stored in Git.

The benchmark source is retained now so that the allocation/lifetime model and
its semantic checks are not lost. Before this workload becomes a registered
qualification gate, the event history must be reduced to a compact,
deterministically generated corpus that preserves the measured size-class,
lifetime, realloc, and cross-thread distributions.
