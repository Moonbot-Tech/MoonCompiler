# dvl-0050 — fixed: Delphi-default BOM for TStrings

Found by the resident layer, rtl-persist stage, with Delphi 12.2 as the oracle.

## What happens

The same one-line list containing ab, saved with TEncoding.UTF8:

| | size | first bytes |
|---|---:|---|
| ours | 4 | 61 62 0D 0A |
| Delphi 12.2 | 7 | EF BB BF 61 |

Delphi prefixes the content with EF BB BF; we did not. The remaining bytes
match.

## Why it matters

A file written by us and a file written by Delphi are **not byte-for-byte
identical** for the same content. This has three quiet consequences:

* hash comparison of files built by different compilers fails;
* an external tool that recognizes encoding from a marker reads our file using
  its default interpretation, which depends on the machine.

Our LoadFromStream correctly recognized and discarded the preamble. The earlier
claim that it retained a BOM in the first line was an error in the initial
report and was removed.

There is no error or warning: content appears “the same” while the bytes differ.

## Reproduction

probe/rest.dpr, section --- save with UTF8, prints the size and first four
bytes. It builds through the standard driver; the oracle is Delphi 12.2 dcc64
with -U<lib\win64\release> -NSSystem.

## Cause and repair

SaveToStream(Stream, Encoding) already wrote Encoding.GetPreamble when
WriteBOM=True. The error was in TStrings.Create: the object started with
WriteBOM=False and implicit soPreserveBOM. The default now matches Delphi:
soWriteBOM, soTrailingLineBreak, soUseLocale. soPreserveBOM was not removed and
applications may still enable it explicitly.

The permanent tdelphistringlistbom1 test runs one source against Delphi 12.2
and our RTL: UTF-8/UTF-16, empty and nonempty list, explicit WriteBOM=False,
reading with and without BOM, and explicit soPreserveBOM under FPC. Before the
repair the exact binary exited with code 1; afterwards O-/O2/O3 and the shared
74/74 gate are green.
