# Linux x86-64 stack contract — 2026-08-28

Focused probe: `RTL-test/semantic/linux_stack_contract_semantic.dpr`.
Platform: Hetzner `77.42.117.2`, Linux x86-64, page size 4096.
One source with strict product oracle passed O-/O2/O3.

Ordinary login/process limit:

```text
rlimit: current=8388608 max=18446744073709551615
main: size=8388608 guard=0
TThread: size=1048576 guard=4096
BeginThread: size=1048576 guard=4096
raw-pthread: size=8388608 guard=4096
LINUX_STACK_CONTRACT_OK
```

Under `ulimit -s 2048`:

```text
rlimit: current=2097152 max=2097152
main: size=2097152 guard=0
TThread: size=1048576 guard=4096
BeginThread: size=1048576 guard=4096
raw-pthread: size=2097152 guard=4096
LINUX_STACK_CONTRACT_OK
```

Under `ulimit -s unlimited`:

```text
rlimit: current=18446744073709551615 max=18446744073709551615
main: size=<kernel grow-down range reported by glibc> guard=0
TThread: size=1048576 guard=4096
BeginThread: size=1048576 guard=4096
raw-pthread: size=2097152 guard=4096
LINUX_STACK_CONTRACT_OK
```

Conclusion: exactly 1 MiB is a property of product `TThread`/default
`BeginThread`, not a global Linux replacement. Main belongs to process
`RLIMIT_STACK`; raw pthread without attributes belongs to glibc's startup
policy. This preserves an explicitly increased `StackSize` for special heavy
threads and does not change third-party libraries.
