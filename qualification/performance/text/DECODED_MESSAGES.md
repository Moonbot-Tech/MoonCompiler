# UTF8 message decoding

`decoded-messages` converts eight prepared UTF8 messages to UnicodeString and
consumes every UTF16 unit. One operation is one decoded and consumed message.
Preparation and the value oracle run outside timing. A 256-message oracle
checks the complete digest and the retained string contents.

The three input structures are explicit controls, with no assigned mixture
weights: 32 Cyrillic units, an ASCII envelope containing a Cyrillic greeting,
and an ASCII message. Each has immediate consumption and a 64-result retention
window. The retained result outlives a subsequent conversion, exposing normal
managed-string lifetimes without adding unrelated byte-by-byte field updates.

The Cyrillic form exercises consecutive two-byte UTF8 sequences. The mixed
form exposes the cost of entering and leaving that run, while ASCII controls
the existing fast path. This is separate from the independent UTF8 bounds,
malformed-input and guard-page qualification test.

Build through the usual Pulse program selection:

```text
python qualification/performance/tools/pulse.py run --programs decoded-messages --systems moon --mode quick
```
