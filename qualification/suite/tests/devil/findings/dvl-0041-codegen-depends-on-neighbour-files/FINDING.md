# dvl-0041 — fixed: uninitialized padding in a set constant

Found by the **determinism mirror** (`--determinism`): the same source built
twice in succession by the same compiler with the same profile produced
different `devil.o` and `devil.exe`. Its owner called this the number-one
finding to repair: MoonBot algorithms depend on reproducible machine code.

## Current state

Fixed in the compiler; it is not listed in Known Issues. The compiler's internal
set always occupies 32 bytes and stores elements `0..255`. For a type with a
nonzero base, the old loop incorrectly used the rounded ABI size of the result:
`set of 200..255` occupies eight bytes even though only seven are significant.
The last iteration read byte 32 past the internal buffer and wrote it into the
result padding.

The repair calculates the number of logical bytes from `setmax-setbase`,
copies only those bytes, and explicitly zeroes ABI padding. The focused
regression covers logical sizes of 5, 6, and 7 bytes, each stored by Delphi in
eight bytes, plus an adjacent low set base. After the self-host rebuild, the
environment gate produced 16/16: code and data were identical when adjacent
files, output path, cwd, environment, and search path changed. The Debug path
from a different cwd is checked separately after removing debug metadata and is
not presented as a code-generation difference.

## What occurred before the repair

The compiler receives the same source. Change **only what lies beside it in the
directory**—files that the compiler neither opens nor uses.

| Source directory | `devil.o` |
|---|---|
| clean | `d93aa7eaa85487c2` |
| same, repeated | `d93aa7eaa85487c2` |
| + empty subdirectory | `d93aa7eaa85487c2` |
| + one unrelated `.txt` | `d93aa7eaa85487c2` |
| **+ two unrelated `.txt` files** | **`fcfe68c44ba8992c`** |
| + three, four files | `d93aa7eaa85487c2` |
| **+ one file with a long name** | **`030dcfcfcaad9735`** |
| same file, but 100 KB of content | `d93aa7eaa85487c2` |
| remove everything again | `d93aa7eaa85487c2` |

The result reads as follows: **the names and number** of neighboring files
affect the output. The dependency is deterministic: the same environment always
produces the same result, which is why it appeared in “series”—everything was
stable until the directory changed.

## How broad it was (environment gate)

The table above was captured before the repair on a small program. The finding
led to `run_devil_env_gate.py`, which perturbs the environment systematically
and requires artifacts not to move. On a normally sized program (four layers,
60 cases) the issue was much broader: **nine of ten perturbations changed
machine code**, including those that were harmless on the small bench:

| Perturbation | Result |
|---|---|
| Change nothing (control) | Baseline |
| One unrelated file | Code changed |
| File with a long name | Code changed |
| Two, three, four files | Code changed |
| File with another extension | Code changed |
| Same files in reverse creation order | Code changed |
| **Empty subdirectory** | Code changed |
| 100 KB file | Code changed |

All nine differences had one root cause: the volume and ordering of names
changed the byte accidentally read beyond the set buffer. After the repair, the
gate remains a permanent trap for the whole class, but its 16 perturbations show
no new differences.

## What exactly differed

The difference was **exactly one byte**, and it occurred identically in both
`.o` and `.exe`, so it reached the final image; the linker did not eliminate it
(`evidence-A.o` and `evidence-B.o` are the retained pair, 14,309,753 bytes
each):

```
A: 01 00 00 e3 04 01 00 ff ff ff ff 13 ... "dvl-set-00021-…"
B: 01 00 c0 e3 04 01 00 ff ff ff ff 13 ... "dvl-set-00021-…"
```

The byte lies in the set-constant block for case `dvl-set-00021`, whose type is
`set of 200..255`. Values `00` and `C0` are two high bits outside the used set
domain. Program behavior therefore did not change: every check and digest
matched.

This exposes the mechanism: the set constant was laid out in the image such that
its tail beyond the domain was not given a defined value—whatever remained in
the compiler's internal buffer landed there. What remained in that buffer
depended on how many names, and names of what length, the compiler had processed
beforehand—that is, on the contents of the search directory.

## Why this is a red flag

Program behavior is identical, but bytes are not. That silently breaks
everything that relies on reproducible machine code:

- reproducible builds: two runs on one machine produce different artifacts;
- binary comparison of builds as proof that a change affected nothing;
- any artifact signature or hash;
- before/after comparison during optimization—the difference may be noise.

Tests do not reveal it: they are green because the garbage resides in bits no
one reads. So far no one reads them; elsewhere the same mechanism could land in
significant bits.

## Historical reproduction and permanent control

`repro-stand.py` is a self-contained bench: it generates one layer in a
separate directory, builds it, adds one unrelated subdirectory, `.txt`, or
`.pas` file at a time, and prints the `devil.o` hash after each step. Before
the repair, hashes differed; now all must match. `repro-stand-detail.py`
retains a more detailed matrix of the earlier trigger.

Through the suite:

```
run_devil_gate.py --seeds 23 --cases 40 --profiles release --determinism --dcc ...
```

The mirror retains both complete builds in the run work directory under
`results/runs/` and maintains `determinism-baseline.json`, a source-fingerprint
baseline that detects a mode change **between** runs as well as within one run.

## What was checked and rejected

- lack of memory: peak compiler usage on the large program was **1.40 GB** with
  14 GB free; the build took 28 seconds;
- generator nondeterminism: two generations of one seed produced 56 files
  without a single difference;
- program execution between builds: the `.o` before and after matched
  byte-for-byte;
- Delphi running between builds: it adds nothing to the source directory;
- recreating the output directory: ten builds into the same recreated directory
  produced zero differences;
- a small program with the same `set of 200..255`: ten builds and one hash—the
  issue needs volume; on a small input the buffer is clean.

## Boundaries

Checked with the `release` profile. An empty subdirectory does not affect the
result, nor do the contents or size of a neighboring file. The finding was in
the `set` layer, and the differing byte always fell in set constants; other
constant types on this bench did not differ.
