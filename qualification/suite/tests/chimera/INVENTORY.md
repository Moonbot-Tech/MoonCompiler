# Arbitrage and MoonBot inventory

> Quidquid latet apparebit, nil inultum remanebit. Festina lente.

The sole canonical list of work Chimera must carry. It is maintained
**manually, by the meaning of the work**. Search and scripts are navigation,
not proof of completeness: a list assembled by traversing syntax answers “what
constructs occur”, whereas the needed answer is “what work is done here, and
how can it break”.

The machine-readable half is `inventory.json`. It is not a separate document,
but the verifiable form of the same responsibility: the gate cross-checks it
with this file and with what actually executed in the program. A discrepancy
in either direction stops the run.

## Row fields

| field | meaning |
|---|---|
| `id` | stable identifier: `CHI-<product>-<domain>-<number>` |
| `product` | `MoonBot`, `Arbitrage`, or `mORMot` |
| `source` | file and symbol in the live project |
| `work` | physical meaning of the work—what is actually done here |
| `risk` | which class of failure would be lost if the row were removed |
| `forms` | required bodies: `whole`, `split`, `inline`, `noinline`, `threaded`, `oracle` |
| `oracle` | what precisely checks it, and why it is independent |
| `branches` | branches that must ACTUALLY execute; each has a program counter |
| `organ` | Chimera unit that carries it |
| `status` | `covered`, `merged-with <ID>`, `excluded <reason>`, or `open` |

`open` is an honest marker for unfinished work. The gate fails by default when
such rows exist: an inventory with a hole is not an inventory. The
`--allow-open` option exists only for intermediate development.

## Current status

Sixty-nine rows, none open: fifty-four carry an executable body, ten are
merged into neighbouring rows with proof that no separate failure class
remains, and five are excluded for a stated reason. By product: forty-two
MoonBot rows, seventeen Arbitrage rows, and ten rows mapping mORMot usage.

“Closed” here does not mean “there is nothing more to transfer”. It means that
everything read from the two projects to date has a body and an oracle, and the
gate verifies that by execution. The next reading of the live code will almost
certainly uncover forms absent from the list; then the list grows and the gate
turns red until they are transferred. That is the intention.

## MoonBot — trading hot path

### CHI-MB-TRADE-001 — tape record, direction in the quantity sign

* **source:** `MoonBot/TradeTypes.pas`, `TTrade`
* **work:** a sixteen-byte trade record; direction is stored in the SIGN of the
  quantity and requested by reading the same field as an unsigned integer
  (`PCardinal(@Qty)^ and $80000000`). The unit is deliberately a leaf: it
  imports nothing of its own because body inlining works only outside a
  dependency cycle.
* **risk:** if the optimizer decides that writing through `Single` and reading
  through `Cardinal` cannot address the same memory, trade direction silently
  shifts and an order goes the wrong way.
* **forms:** `whole`, `oracle`
* **oracle:** two independent ways to ask for direction—sign bit versus
  comparison with zero; they agree across the complete tape inside the `tape`
  organ. Plus record size as a wire contract.
* **branches:** `sign-bit`, `compare`, `size-16`
* **organ:** `chimera_body`, checked in `chimera_tape`
* **status:** `covered`

### CHI-MB-TAPE-001 — folding the tape by windows

* **source:** `MoonBot/MarketsU.pas`, `TMarket.JoinHOrders`
  (the window-fold portion)
* **work:** one reverse traversal of the tape that fills a dozen windows of
  different lengths, tenth-of-a-second buckets, a minute-volume ring with
  index wrap and lazy cell clearing, the moving average `(X*99+Q)/100`, price
  bounds, movement flags, and a time-based early exit. More than forty values
  are simultaneously live in local variables.
* **risk:** register pressure in a large body, spilling values to the stack,
  long live ranges, `double`→`single` narrowing at every addition, product
  truncation in the bucket index, and index wrap through zero. All of these
  produce silently wrong volumes and prices.
* **forms:** `whole`, `split`, `inline`, `noinline`, `oracle`
* **oracle:** five bodies for one operation. Four are identical in actions and
  order and compared BIT FOR BIT; the fifth is written independently (without
  `with`, without an early exit, direction by comparison) and is compared with
  exact quantities to the unit and floating-point quantities with a tolerance.
  The “inlined versus not inlined” pair is separately valuable: the same text,
  included through one file, produces two machine-code outputs.
* **branches:** `whole`, `split`, `inline-leaf`, `noinline-cycle`, `oracle`,
  `scan`, `bucket`, `minute-ring`, `window-5s`, `window-15s`,
  `sparse-second`, `price-up`, `price-down`, `break-early`
* **organ:** `chimera_tape` + `chimera_tape_types`, `chimera_tape_leaf`,
  `chimera_tape_ring_far`, `chimera_tape_v3`, `chimera_tape_v4`,
  `chimera_tape_pure.inc`
* **status:** `covered`

### CHI-MB-RING-001 — trade ring between threads

* **source:** `MoonBot/EngineBase.pas`,
  `TMarketEngine.AddTmpHOrder`; the ring portion and splice from
  `MarketsU.JoinHOrders`
* **work:** transfer trades from the socket thread to the calculation thread
  with no lock at all. A slot is filled BEFORE the write index is published.
  The producer may add quantity to an already occupied slot, deriving the
  right to do so from a read index moved by another thread. The consumer
  snapshots both indexes, unfolds the ring into contiguous memory with one or
  two `Move` operations across the split, splices the batch to history with a
  binary search using a closure comparator, and advances the read index as its
  last line. Beside it is a non-atomic “remember the largest” from another
  thread.
* **risk:** order of the two assignments during publication, modular arithmetic
  with negative values, a ring split across two `Move` operations, a
  non-transitive comparator in binary search, and losing added quantity in a
  race.
* **forms:** `whole`, `oracle`, `threaded`
* **oracle:** a sparse tape (step deliberately greater than the splice
  tolerance) is compared bitwise with an independent implementation without a
  ring at all, using the same drain schedule; a dense tape uses assertions
  independent of the splice point; the threaded run inventories outcomes and
  estimates volume from both sides. The splice point is presented as an
  observation, not an assertion: binary search on a non-transitive comparator
  may return any member of a plateau.
* **branches:** `feed-store`, `feed-merge`, `drain`, `drain-wrap`, `splice-drop`,
  `splice-keep`, `oracle-flat`, `threaded-overlap`, `threaded-ring-full`,
  `threaded-lost-merge`
* **organ:** `chimera_ring` + `chimera_crew`
* **status:** `covered`

### CHI-MB-TRADE-002 — absorbing a trade into one of two preceding trades

* **source:** `TradeTypes.pas`, `TTrade.TryAggregate`
* **work:** a record method with two `var` parameters of its own type; two
  compound predicates of four conditions each; two early `Exit(True)` calls
  from the middle and one normal return.
* **risk:** the caller may pass the same record for both parameters—at the ring
  boundary it does—so they cannot be considered non-overlapping. Also `-0.0`:
  its magnitude is zero, its sign bit is set, and the direction of such a
  trade is a property of its representation.
* **forms:** `whole`, `oracle`
* **oracle:** a table of precomputed conditions makes the decision differently
  (direction by comparison with zero rather than sign bit), with no early exit.
  Both the verdict and the slot receiving the quantity are compared.
* **branches:** `hit-first`, `hit-second`, `miss`, `aliased-slots`,
  `negative-zero`, `repeat-into-first`
* **organ:** `chimera_agg`
* **status:** `covered`

### CHI-MB-SORT-001 — sorting the tape before splicing

* **source:** `MarketsU.pas`, `TMarket.QuickSortOrders`
* **work:** pivot at the segment midpoint, comparison with a tolerance in both
  directions, exchange through an OWNER FIELD, recursion left with a tail loop
  right, depth counter in the owner field, and bailout on exceeding the limit.
* **risk:** the exchange temporary is shared by the entire recursion, so it
  cannot stay in a register across a call; the tolerance means the algorithm
  does not induce a strict order; bailout leaves the work unfinished and exits
  past the matching decrement.
* **forms:** `whole`, `oracle`
* **oracle:** permutation preservation (an order-independent fold plus
  comparison of sorted copies) holds for every outcome, including abandoned
  work; at zero tolerance, the time ordering matches independent insertion
  sort; at live tolerance, there are no inversions greater than the tolerance;
  the depth counter returns to zero.
* **branches:** `swap`, `swap-skipped`, `recurse-left`, `tail-right`, `nested`,
  `exact-order`, `eps-order`, `bailout`, `bailout-permutation`
* **organ:** `chimera_sort`
* **status:** `covered`

### CHI-MB-CODE-001 / CHI-MB-CODE-002 — converting bytes to printable form

* **source:** `Common/nethelpers.pas` — `Encode3to4`, `Decode4to3Ex`,
  `EncodeTriplet`
* **work:** both tables, one-based index work over a byte string, accumulating
  three bytes into four six-bit pieces with shifts and masks, decoding through
  a shifting accumulator while skipping foreign characters, tail padding, and
  triplet encoding by a character set.
* **risk:** an off-by-one in indexes does not fail but silently corrupts the
  tail; the order of shifting and addition inside the expression is part of
  the meaning; three different parser endings; a character set as a separate
  representation.
* **forms:** `whole`, `oracle`
* **oracle:** RFC 4648 standard vectors—external truth; a round trip through
  all lengths TOGETHER WITH canonical-form checks (multiple of four, number and
  position of padding marks); independent bitwise decoding without a table.
* **branches:** `vectors`, `roundtrip`, `canonical-padding`,
  `independent-decode`, `skip-foreign`, `embedded-zero`, `regrow`; for address
  encoding: `plain`, `escaped`, `separators`, `empty`, `high-bytes`, `all-special`
* **organ:** `chimera_code`
* **status:** `covered`

### CHI-ARB-NAME-001 — minimal distinguishing name prefix

* **source:** `ArbServer.pas` — `TaggedName` and the collision-resolution loop
  inside `BuildComboPairs`
* **work:** find the minimal hash-prefix length distinguishing a record from
  all same-name neighbours, and construct a wire name by writing RAW HASH
  BYTES directly into the body of a managed string.
* **risk:** `Move` places number bytes inside the string, and the string must
  remain a string with a known length rather than terminate at a zero byte;
  `repeat` has two exits, the second meaning “the name did not diverge”;
  `CompareMem` is a byte-level view of an integer.
* **forms:** `whole`, `oracle`
* **oracle:** the result property is checked by direct enumeration (the chosen
  length is unique, the preceding one is not), independently of how it was
  found; plus naïve bytewise enumeration of the same length; plus parsing the
  constructed name back; plus a standard CRC32C vector.
* **branches:** `crc-vector`, `crc-empty`, `single-byte-tag`, `grown-tag`,
  `unresolved`, `wire-roundtrip`, `zero-bytes`, `empty-name`
* **organ:** `chimera_name`
* **status:** `covered`

## Arbitrage — wire

### Wire: CHI-ARB-WIRE-001, CHI-ARB-WIRE-002, CHI-ARB-WIRE-003, CHI-ARB-WIRE-004, CHI-ARB-CRYPT-001, CHI-ARB-CRYPT-002

Six rows of one organ: wire records and wrappers (WIRE-001), block padding
(WIRE-002), in-place encryption and a growing buffer (WIRE-003), self-delimiting
stream parsing (WIRE-004), the cipher itself and its rejection paths
(CRYPT-001), vector and counter (CRYPT-002).

* **source:** `Arb/ArbProto.pas` (the same unit on the Arbitrage server side)
* **work:** encrypted frame `[vector 12][tag 16][body]`; block padding
  `((L shr 4)+1) shl 4`, which ALWAYS adds at least a byte; padding is written
  straight into the output buffer and encrypted IN PLACE (source and receiver
  are one address); a growing buffer; untyped `const`/`var` parameters with a
  separate length; parsing a self-delimiting stream
  `[length][name][count]×[exchange][price]` to the end of the body.
* **risk:** in-place encryption where the optimizer may decide source and
  receiver do not overlap; padding arithmetic at block boundaries; buffer
  reuse where length comes from a counter rather than capacity; pointer parsing
  with a boundary check.
* **forms:** `whole`, `oracle`
* **oracle:** AES-GCM standard vector (external truth); canonical frame—exact
  lengths and offsets, rather than merely “it decrypted back”; independent
  array-slice parser versus pointer parser; rejection paths: body corruption,
  tag corruption, foreign key, truncated input, record-length mismatch.
* **branches:** `record-sizes`, `untyped-wrapper`, `length-mismatch`, `edges`,
  `full-block-adds-block`, `encrypt-in-place`, `grow-only-buffer`,
  `no-stale-bytes`, `roundtrip`, `two-parsers`, `reject-overrun`, `empty`,
  `nist-vector`, `reject-tampered`, `reject-bad-tag`, `reject-wrong-key`,
  `reject-truncated`, `aad`, `iv-tail-ignored`, `counter-monotonic`
* **organ:** `chimera_wire`
* **status:** `covered`

Two facts obtained by measurement during transfer and recorded so they never
have to be rediscovered:

1. `TAesGcm` uses exactly the first twelve vector bytes; the remaining four
   affect neither ciphertext nor tag. The live code therefore legitimately
   puts twelve of sixteen bytes on the wire, and garbage in the parsing tail is
   harmless. This is checked by an assertion, not accepted on faith.
2. The way the live code supplies additional data does **not affect** the tag:
   the first `Encrypt` resets state and mixes in only what was supplied earlier
   through `MacSetNonce`. In both projects, every call uses empty additional
   data, so there is no harm now, but the parameter silently does not work. A
   product note, not a compiler note.

## Arbitrage — pairs and containers

### CHI-ARB-PAIR-001, CHI-ARB-PAIR-002 — pair construction and identity filter

* **source:** `ArbServer.pas` — `RebuildPairsIndex`, `BuildComboPairs`
* **work:** pointer-by-token through a temporary dictionary of lists with
  named cleanup in `finally`; a market-list snapshot taken once; filter
  `((own or foreign) = 0) or (own = foreign)`; price multiplier `(a*b)/(c*d)`;
  nested loops with `Continue`, a growing neighbour buffer, and final `Move`;
  a branch for the family of related engines.
* **risk:** an engine still loading mutates the list beneath a reader—skipping
  it entirely is part of the algorithm; ordering of floating-point operations
  in the multiplier; `Move` of records into an array of exactly the required
  length.
* **forms:** `whole`, `oracle`
* **oracle:** naïve enumeration of all combinations with no pointer, snapshots,
  or growing buffer; the filter rule is presented as a table of every
  combination of zero and two different identities; the multiplier is compared
  bitwise with the same expression evaluated separately.
* **branches:** `single-engine`, `engine-family`, `skipped`, `loading-skipped`,
  `nobody-wanted`, `price-scale`, `denomination`, `table`
* **organ:** `chimera_pairs`
* **status:** `covered`

### CHI-ARB-DICT-001 — generic dictionary under a lock

* **source:** `Common/SafeDict.pas`
* **work:** a generic wrapper around a dictionary; access to the raw dictionary
  only through a closure and only under a read-write lock; release in `finally`.
* **risk:** an exception from a closure invoked under the lock—if `finally`
  does not run, the dictionary deadlocks rather than fails; generics with
  managed keys and values.
* **forms:** `whole`, `threaded`, `oracle`
* **oracle:** comparison with a regular dictionary filled with the same keys;
  sum of a traversal under the read lock versus a separately calculated sum;
  after a closure throws, the next call must return and the changes made before
  the throw must remain.
* **branches:** `add-get`, `remove`, `keys`, `for-read`, `for-write`,
  `exception-releases-lock`, `threaded-readers`
* **organ:** `chimera_hands`
* **status:** `covered`

## MoonBot — closures

### CHI-MB-CLOS-001, CHI-MB-CLOS-002, CHI-MB-CLOS-003, CHI-MB-CLOS-004

Four rows of one organ: capture through two frames and moving a closure into a
thread (CLOS-001), capture of managed residents and parameters of different
kinds (CLOS-002), loop variable versus a per-iteration copy (CLOS-003), and a
closure surviving the exit of its procedure (CLOS-004).

* **source:** `AssetTransferU.pas` — an anonymous thread receives a closure;
  the closure captures a local of an outer procedure and creates a second one
  inside itself for delayed invocation.
* **risk:** a captured value must move into the closure frame; reference counts
  of managed residents must balance; a shared loop variable and a per-iteration
  copy produce DIFFERENT answers, and both cases are live.
* **forms:** `whole`, `threaded`, `oracle`
* **oracle:** both answers are known in advance (sum of the final values versus
  sum of the sequence); counts of live objects and interfaces must return to
  their initial values.
* **branches:** `nested-capture`, `thread-capture`, `managed-capture`,
  `lifetime-balanced`, `params`, `shared-variable`, `per-iteration-copy`,
  `escaped`
* **organ:** `chimera_hands`
* **status:** `covered`

A note that cost debugging time: a delayed closure cannot be placed into a
local RECORD—the nested closure writes into the captured copy, and the caller
receives an empty field. In the live code it is placed into an object field (a
queue of delayed calls), which avoids this trap.

## MoonBot — buffers, signatures, strings

### CHI-MB-BUF-001, CHI-MB-BUF-002 — reusable stream and packet cache

* **source:** `MoonProto/MoonProtoTradesStream.pas` — `TReusableMemStream`,
  `TPacketCache`
* **work:** reallocation that never returns memory downward (growth with
  double spare capacity; shrinking and clearing retain the previous capacity
  and address), explicit trimming under a flag that the method itself reads;
  linear cache that restarts at the beginning on overflow and evicts by range
  overlap; pointer array growing in hundreds with zero-fill through `FillChar`.
* **risk:** the reallocation method is called by the library internally and
  changes capacity BY REFERENCE—the returned pointer and written capacity are
  different answers; after a large packet, a small one is written into the
  same memory and the former tail must not enter the new one; offset eviction
  fails silently by returning foreign data under the requested number.
* **forms:** `whole`, `oracle`
* **oracle:** independent cache model as a regular dictionary of copies—it
  knows neither offsets nor eviction; everything the live cache returns must
  agree with the model, though the live cache may forget; capacity and memory
  address are compared directly.
* **branches:** `grow`, `clear-keeps`, `smaller-keeps`, `no-stale`,
  `trim-closes-period`, `trim`, `regrow-after-trim`; for the cache: `wrap`,
  `evict`, `grow-indices`, `hit`, `miss`, `too-big`, `empty`
* **organ:** `chimera_buf`
* **status:** `covered`

Note: it does not trim “everything extra”, only capacity inflated BEYOND the
period's greatest need. The first trim merely closes the period; the next one
returns memory.

### CHI-MB-SIGN-001 — exchange-request signature string

* **source:** `ByBitEngine.pas` and `BitGetEngine.pas`, `BuildHMAC` methods
* **work:** two different construction forms. The first is a flat concatenation
  of timestamp, key, window, and parameters with a hexadecimal digest. The
  second is a path where the question mark appears only for non-empty
  parameters, the body is appended only when present, and the digest is
  returned in printable form.
* **risk:** an empty part changes not the length but the separator composition;
  folding a condition makes the compiler silently produce a different string,
  and the exchange rejects the signature.
* **forms:** `whole`, `oracle`
* **oracle:** RFC 4231 digest vectors and a separate printable-form vector;
  signature strings are presented IN FULL for every combination of empty and
  non-empty parts; independent construction by concatenating a list of pieces.
* **branches:** `rfc-vectors`, `base64-vector`, `flat`, `flat-empty`,
  `path-combinations`, `exact-strings`, `all-verbs`, `long-params`, `long-key`
* **organ:** `chimera_sign`
* **status:** `covered`

### CHI-MB-STR-001 — byte strings on the path to the exchange

* **source:** engine string paths and `nethelpers`
* **work:** embedded zero, all two hundred and fifty-six byte values,
  conversion between narrow and wide form, empty string, one-character growth
  a thousand times, copy on write.
* **risk:** length must remain length rather than be counted to zero; high bytes
  must not turn into question marks; modifying a copy must not affect the
  original.
* **forms:** `whole`, `oracle`
* **oracle:** round trip through encoding for every byte value; bytewise
  conversion to wide form and back; direct checks of length and contents after
  growth.
* **branches:** `embedded-zero`, `all-bytes`, `narrow-wide`, `empty`,
  `regrow-by-one`, `copy-on-write`
* **organ:** `chimera_code`
* **status:** `covered`

### CHI-ARB-BUF-001 — single-writer ring and copy-on-write list

* **source:** `Common/HelpClasses.pas` — `TThreadSafeBuffer<T>`,
  `TSlowSafeList<T>`, `TDelayedTrash`
* **work:** a generic ring where position advances before the write, count
  grows only to capacity, reading proceeds backwards with wrap, and an index
  beyond capacity is SILENTLY clamped; a list where a “slow” add creates a new
  list, swaps the reference, and puts the old one into deferred collection.
* **risk:** slot write precedes position publication—the same order of two
  assignments as in the trade ring, but on a generic type and returning a slot
  pointer; replacing a reference under a reader is legal precisely because the
  old body remains alive, and early collection causes not a failure but silent
  corruption.
* **forms:** `whole`, `oracle`
* **oracle:** independent ring model using a regular array with an explicit
  index; snapshot taken before replacement must remain unchanged, and the new
  one must differ by exactly the added element; count of live objects.
* **branches:** `empty-refuses`, `wrap`, `read-back`, `clamped-index`, `clear`,
  `managed-content`, `direct-add`, `copy-on-write`, `old-body-alive`,
  `delayed-trash`, `object-content`
* **organ:** `chimera_hold`
* **status:** `covered`

### CHI-MB-PROTO-001, CHI-MB-PROTO-002, CHI-MB-PROTO-003, CHI-MB-PROTO-004 — message framing

* **source:** `Vars.pas` — string framing; `MoonProto/*` — stream primitives
  and market-message field order
* **work:** a string is stored with length IN BYTES after conversion to an
  eight-bit encoding; in the short form length is a byte and overflow is not
  checked; writing is mandatory while reading primitives is best-effort; fields
  are adjacent with no delimiters.
* **risk:** character length instead of byte length shifts the ENTIRE following
  stream; best-effort reading does not throw, but silently leaves the old value;
  buffer reuse must not mix in the former tail.
* **forms:** `whole`, `oracle`
* **oracle:** canonical size calculated by the rules, not measurement; a
  field-by-field round trip; cutting the stream at EVERY point while checking
  that the complete message cannot be read; a cut inside a multibyte character.
* **branches:** `roundtrip`, `canonical-size`, `utf8-length`, `empty-string`,
  `short-length`, `short-overflow`, `every-cut`, `cut-inside-char`,
  `big-then-small`, `throw-midway`
* **organ:** `chimera_proto`
* **status:** `covered`

Note: requiring that “values differ” for a truncated stream is wrong—best-effort
reading stores as many bytes as it finds, and if a number's high bytes are zero
already, the truncated value equals the complete one. The one precise property
here is that it is impossible to read as many bytes as the complete message
occupies from a truncated stream.

### CHI-MB-BOOK-001, CHI-MB-BOOK-002 — order book: extending and folding walls

* **source:** `MarketsU.pas` — `TMarket.HandleGlass`; `BitGetEngine.pas` —
  `HandleBookChain`
* **work:** complete snapshot through `SetLength` plus `Move` on both sides and
  again from a service copy into the working one; wall folding with nested
  loops where ONE level reaches several buckets at once and the threshold is
  calculated by division by a percentage; extending distant levels from a
  second source by growing with spare capacity and subtracting accounted volume
  calculated by a reverse traversal with an early exit.
* **risk:** the array is not a ring here but a sorted list, and work moves
  ranges within it; one value enters several accumulators and traversal order
  determines which; beyond the actual end after spare-capacity growth are old
  records, which must not enter the answer.
* **forms:** `whole`, `oracle`
* **oracle:** walls recalculated by direct enumeration—one traversal per bucket,
  without nesting; extension checked by result properties (price order,
  unchanged original levels, length at the actual end, volume no greater than
  provided); snapshot compared bitwise.
* **branches:** `snapshot`, `fold`, `nested-buckets`, `empty-snapshot`,
  `extend`, `first-level-trimmed`, `originals-intact`, `order-kept`,
  `trimmed-length`, `volume-bounded`, `too-short`
* **organ:** `chimera_book`
* **status:** `covered`

Note: the branch subtracting already accounted volume lives only when a distant
level is LARGER than the sum of the nearer levels it covers. With equal volumes
it never executes, and all reverse-traversal arithmetic runs idle.

### CHI-MB-TASK-001 — order state as a wire record

* **source:** `MoonProto/MoonProtoOrderState.pas`, `TaskWorkers.pas`
* **work:** packed record of nested packed sections with exact sizes (33, 63,
  20); changing one section while neighbouring ones remain unchanged; task
  number from an atomic counter; long assignment list on creation; phase
  transitions by a table of legal ones.
* **risk:** field offset is calculated as the sum of preceding section sizes,
  and one extra alignment shifts the entire record tail; an eight-byte field
  sits at an unaligned address and must be read whole.
* **forms:** `whole`, `threaded`, `oracle`
* **oracle:** sizes and offsets are written out by packing rules rather than
  measured; bytewise immutability of neighbouring sections; table of legal
  transitions separate from the code that transitions; unique numbers from
  many threads.
* **branches:** `sizes`, `offsets`, `unaligned-field`, `patch-exec`,
  `patch-place`, `fill-complete`, `transitions`, `full-path`,
  `cancel-anywhere`, `atomic-numbers`, `byte-copy`
* **organ:** `chimera_task`
* **status:** `covered`

### CHI-MB-JSON-001, CHI-MOR-MAP-001 — parsing an exchange response

* **source:** `Common/JsonHelpers.pas` and engine parsers
* **work:** complete production chain: raw body → document → named fields →
  object with unknown keys → path descent → array of objects → own structure →
  string → search within it. A value arrives as either a number OR a string,
  and both forms are taken.
* **risk:** an absent field must leave a variable untouched; filters differ by
  a kind field rather than order; a broken body must be rejected completely,
  not half parsed.
* **forms:** `whole`, `oracle`
* **oracle:** known values of every field are written out in advance; canonical
  body reconstruction and repeat parsing; independent number scanner by
  substring search without a parser.
* **branches:** `price-as-string`, `price-as-number`, `independent-scan`,
  `case-insensitive-default`, `case-sensitive`, `missing-field`,
  `unknown-keys`, `nested-array`, `filter-by-kind`, `rebuild-roundtrip`,
  `to-string-search`, `reject-broken`, `empty-object`
* **organ:** `chimera_json`
* **status:** `covered`

Fact obtained during transfer: the default parsing set looks up a field
**case-insensitively**—`q` is found for query `Q`. On the exchange wire, where
`p` and `P` can be different fields, this is unsafe; sensitivity is enabled by
a separate set flag. Both behaviours are presented as assertions.

### CHI-ARB-STREAM-001 — block transfer of trades

* **source:** `StreamServer/StreamProto.pas`
* **work:** packed header whose checksum is first and calculated over the whole
  block with itself zeroed; the checksum itself is a port of an assembler form
  based on carries, shifts, and rotations, where each byte enters state twice
  with two masks; self-delimiting payload by market; byte block number with
  wrap; compression marker in a flag bit.
* **risk:** the checksum is built from bit carries and rotations—exactly what
  the optimizer most readily touches—and the client compares it byte for byte;
  blocks arrive with repeats and out of order.
* **forms:** `whole`, `oracle`
* **oracle:** a second checksum implementation over an array of state bytes
  rather than an integer—no line shared with the first; canonical block size
  from the format rules; exact reconstruction under shuffled delivery with
  repeats.
* **branches:** `header-layout`, `checksum-two-ways`, `roundtrip`,
  `canonical-size`, `reject-tampered`, `checksum-collision`,
  `reject-truncated`, `out-of-order`, `repeats`, `empty-block`, `flags`,
  `blocknum-wrap`
* **organ:** `chimera_stream`
* **status:** `covered`

Fact obtained during transfer: this protocol's checksum has COLLISIONS for a
single-bit change—and so does its complete eight-byte form, not only its
four-byte reduction. Requiring that “every corruption is caught” would be
false, so the missed fraction is measured and presented as a number. A property
of the live protocol, not a transfer defect.

### CHI-ARB-GROUP-001, CHI-ARB-CANON-001 — observation series and registry

* **source:** `Common/GroupManager.pas`, `Common/CanonMapper.pas`
* **work:** a series counts only with matching verdict, sufficient interval,
  fit within the maximum gap, and NEW revisions on both sides; on failure the
  timestamp does not advance; all time comparisons are modulo their
  difference. Registry: compound key of chain and address, normalization of
  chain spelling, replacement of an absent address with a special value,
  several distinct records under one name.
* **risk:** five consecutive conditions, each excluding its own way to be
  fooled—fold any one and a series arises from nothing; the counter lives in a
  record inside a dictionary, so a change requires fetch-modify-store; a
  compound key is concatenated, and bad concatenation merges distinct records.
* **forms:** `whole`, `oracle`
* **oracle:** properties rather than samples: a series cannot grow faster than
  one count per input, on a verdict change it equals one, and on a dead
  snapshot it cannot rise above one regardless of how many inputs arrive;
  different records under one name must remain distinct, and key lookup must
  find exactly its own record.
* **branches:** `steady-growth`, `too-soon`, `stale-revision`, `one-side-only`,
  `verdict-flip`, `gap-breaks`, `clock-back`, `dead-data-breaks`,
  `same-name-two-assets`, `chain-aliases`, `native-address`, `address-case`,
  `lookup`, `per-record-lists`
* **organ:** `chimera_group`
* **status:** `covered`

Note: after breaking a series, a gap RESTARTS it and updates its timestamp.
Therefore “the next live observation after a dead period starts at one” is
wrong: it legitimately continues the already restarted series. The one precise
property here is that a series cannot rise above one on a dead snapshot.

### CHI-MB-HL-001 — action schema and field order

* **source:** `HyperL/HLSigs.pas`
* **work:** a schema is described by a field set received through an OPEN array
  and copied element by element; there are three schema kinds (flat, nested in
  an object, nested in an array), and their common part is built by one
  builder; construction immediately precomputes flags and indexes of special
  fields by case-insensitive name lookup; the body is assembled strictly in
  description order.
* **risk:** an open array is a distinct passing mechanism with its own
  boundary; a precomputed index survives a schema copy and must remain valid;
  field order is part of the meaning—reordering produces a different digest and
  exchange rejection.
* **forms:** `whole`, `oracle`
* **oracle:** bodies presented as FULL strings; independent construction by
  reverse description traversal and reversal; standard digest vector and its
  sensitivity to field reordering.
* **branches:** `digest-vector`, `flat-body`, `backwards-build`,
  `precomputed-index`, `no-special-fields`, `copy-keeps-index`,
  `container-object`, `container-array`, `order-matters`, `empty-schema`,
  `long-schema`
* **organ:** `chimera_hl`
* **status:** `covered`

Boundary qualification: the elliptic signature itself is replaced here by a
digest with a known vector. This row concerns the schema and field order; the
curve mathematics is checked by a separate suite layer, and there is nothing
with which to duplicate it here.

### CHI-MB-STRAT-001 — detection calculation by buckets

* **source:** `MarketsU.pas`, `TMarket.CalculateMoonHookDetectionL`
* **work:** a window from triple clamping, which configuration may widen; the
  first pass searches for the lowest price but remembers its index only from
  the SECOND match; volume is recalculated by two different paths with their
  own thresholds; the second pass operates on PAIRS of adjacent buckets, and
  when there are no pairs, on singles; if those are empty too, it uses a
  fallback value. Five early exits.
* **risk:** a long chain in which every condition depends on the preceding
  pass; one condition carries TWO meanings—“there is no minimum” and “the
  minimum is in the first bucket”; clamps with product truncation.
* **forms:** `whole`, `oracle`
* **oracle:** independent direct enumeration of volume, minimum, and index,
  without early exits or pairs; each exit must be reached with its own data
  set; properties of the found result (lower price no greater than any bucket
  in the window, upper price greater than lower).
* **branches:** `exit-no-minimum`, `detected`, `flat-or-no-minimum`,
  `exit-low-volume`, `exit-low-reduced`, `reduce-off`, `window-widened`,
  `singles-path`, `pairs-path`, `fallback-high`
* **organ:** `chimera_strat`
* **status:** `covered`

### CHI-MB-SIGN-002, CHI-MB-SIGN-003, CHI-MB-SIGN-004 — three further signature forms

One exchange, one form; they differ in structure rather than details.

**CHI-MB-SIGN-002** (`GateEngine.pas`): signature-string parts are separated
by a LINE BREAK, and the body's separate digest, rather than the body itself,
is placed in the string—including when the body is empty. The result uses a
longer digest than the others. Oracle: SHA-512 and HMAC-SHA512 vectors, the
complete string is presented, and different bodies must produce different
strings.

**CHI-MB-SIGN-003** (`HuobiEngine.pas`): parameters are parsed into a list,
SORTED by their own comparator, each piece is address-encoded, and only then is
a string concatenated from method, host, path, and parameters through line
breaks. Here the parameter list is both input AND output: it is rebuilt by the
end of the call. Oracle: the order is presented as a complete string, unsafe
character encoding is checked separately, and the digest is compared with one
calculated from that same string.

A comparator detail worth knowing: the case of the FIRST character is
significant (the step compares codes), while case of the rest is not (the
case-insensitive comparison is reached only after an exact match of the first
characters). The resulting order is non-obvious, and it enters the signature.

**CHI-MB-SIGN-004** (`OKXEngine.pas`): `merged-with CHI-MB-SIGN-001`.
Proof: the signature string uses the same rule as the BitGet path form—
`timestamp + method + version + path`, a question mark for non-empty
parameters, body for non-empty body, printable digest. The only difference is
the window value: it is `45000` for BitGet and empty for OKX with speed mode
disabled. But the window enters neither exchange's signature string; it travels
in a separate header, so its value does not create a separate failure class.
Everything that could break—the separator composition for empty parts—is
already presented by `path-combinations` and `exact-strings` branches.

* **risk:** each exchange has its own signature string, and a string-construction
  error is not a failure but a SILENT exchange refusal to accept an order. There
  are three different string structures here: line break as separator and body
  digest within it; ordering by a custom comparator with each piece encoded;
  path form with brackets of empty parts. Remove any one and its own class is
  lost: long digest, order from a non-obvious comparison, or separator
  composition for empty parts.
* **organs:** `chimera_sign`
* **branches:** `sha512-vector`, `hmac512-vector`, `line-joined`,
  `empty-body-still-hashed`, `body-affects-signature`, `comparer`,
  `params-in-out`, `sorted-order`, `encoded-unsafe`, `signature`,
  `empty-params`

### CHI-ARB-USERS-001 — legacy cipher and signature composition

* **source:** `Users/MoonBotUsers.pas` — user-list request. The path is live:
  the list is created in the application core and used by the Arbitrage server.
* **work:** salt from three numbers in hexadecimal form; cipher vector is a
  SLICE FROM THE MIDDLE of the salt; block padding with ZEROS in a loop;
  two-stage signature (salt digest inside the encrypted data, ciphertext digest
  outside); legacy sixteen-byte digest as part of the server contract;
  address encoding of pieces.
* **risk and why this is not a wire duplicate:** there padding stores its
  length and is checked while parsing; here it is zeros and a trailing DATA
  zero is indistinguishable from padding; there a block-aligned message gets an
  extra block, here it gets nothing; there the vector comes from a counter,
  here it is sliced from a string and depends on sufficiently long salt; there
  is one digest, here two on different secrets.
* **forms:** `whole`, `oracle`
* **oracle:** MD5 and HMAC-MD5 vectors (RFC 2202)—the library has no keyed
  digest, so it is constructed by definition and confirmed by a vector; cipher
  round trip; padding properties; foreign vector corrupts exactly the first
  block; address masking by a table at length boundaries.
* **branches:** `md5-vector`, `hmac-md5-vector`, `zero-padding`,
  `aligned-gets-nothing`, `zero-tail-ambiguous`, `cbc-roundtrip`,
  `iv-affects-first-block`, `salt-long-enough`, `request-body`,
  `two-stage-signature`, `url-encoded`, `mask-edges`
* **organ:** `chimera_users`
* **status:** `covered`

### CHI-MB-PACK-001 — candle package: two compressions and a shadow buffer

* **source:** `MarketsU.pas` — candle-package construction, publication, and
  receipt.
* **work:** header with a zero count first (so a version-one reader stops); the
  real market count is written by returning to the position; time-zone shift
  travels as a minute count and is subtracted from itself; candle bodies are
  fixed-size records, DIFFERENT by version (packed singles versus regular
  doubles); an unknown market is skipped by candle count times record size for
  THAT version; completed stream is compressed with fast compression into a
  SHADOW buffer, and only then is the current buffer swapped under the lock;
  reader, by marker, decompresses the fast compression and recompresses it
  slowly.
* **risk:** decompressed length lives INSIDE the compressed block, not beside
  it; buffer switch must not show a reader a half-constructed buffer; element
  size is determined by the version field, not a type declaration.
* **live-path detail transferred verbatim:** the “recompress” marker is cleared
  BEFORE recompression succeeds. A silent refusal therefore does not repeat,
  while an exception restores the marker and repeats. Both paths are presented.
* **oracle:** independent builder and parser of the same stream without the
  compression library—a byte-for-byte reference; compression properties;
  recompression counter.
* **organ:** `chimera_pack` · **status:** `covered`

### CHI-ARB-TEXT-001 — rendering a report with a writer

* **source:** `ArbServer.pas :: DumpFilterAnalysis` (the same form in
  `GroupManager.pas`, `AIClient.pas`).
* **work:** writer over a buffer IN THE CALLING FUNCTION FRAME (eight kilobytes
  on the stack, stream beyond); brackets and commas by hand, three flags at
  three levels remember “is this first?”; a nested procedure writes into the
  outer function's writer; values are placed differently by type; the “would
  send” decision comes from eight conditions, some calculated from time and
  price differences.
* **risk:** stack-buffer boundary lies INSIDE the report; an extra or missing
  comma at any of the three levels breaks the entire document.
* **oracle:** the same rendering by ordinary string concatenation and a second
  set of expressions; character-by-character comparison, and floating-point
  values by value (the writer has its own number formatting, so comparing its
  text would compare the library with itself).
* **organ:** `chimera_text` · **status:** `covered`

### CHI-MB-REUSE-001 — string buffer with a forged length

* **source:** `WebSocket.Thread.pas :: TWSThread.EmitText`; second form is the
  trade-parsing scratch buffer in Arbitrage `BinanceEngine.pas`.
* **work:** writing directly into a string body, with length forged outside the
  RTL; capacity is remembered in a separate field; before writing, reference
  count is checked—the buffer held externally is released in full.
* **risk:** manually managed string: the former write's tail must not stick
  out, and a string held externally must not be corrupted.
* **why the second form is beside it:** it measures capacity by length, and
  shrink loses the remembered capacity—returning to the former length allocates
  again. The difference is presented by an allocation counter, not argument.
* **oracle:** contents against a reference copy, length, allocation and release
  counters.
* **organ:** `chimera_text` · **status:** `covered`

### CHI-MB-SCAN-001 — character-by-character trade-stream parsing

* **source:** `ByBitParser.pas :: FastParseTradesWS` — called for EVERY
  trade-stream message, hence it is written without the parser.
* **work:** body is recognized by letters at fixed positions; market name is
  cut out up to a quote; then a character state machine with a nesting counter;
  a field is recognized by looking three or four characters back, and one
  branch looks ahead too; numbers are taken directly from the body middle by
  pointer.
* **risk:** an object nested within a trade must not create a new trade;
  look-behind at the array boundary; parsing a number without cutting a
  substring.
* **oracle:** the same body through the parser. It required case sensitivity:
  fields `s` (market) and `S` (side) coexist, and case-insensitive lookup
  returns the market name instead of the side.
* **organ:** `chimera_json` · **status:** `covered`

### CHI-MB-SHAKE-001 — connection handshake

* **source:** `WebSocket.Thread.pas :: DoHandshake`, `HttpHeaderIs`,
  `HttpHeaderContains` (the same form in Arbitrage).
* **work:** request by string concatenation, path normalized to a leading slash
  by three paths; printable connection key, response must be a key digest with
  a concatenated constant string; end of headers found by comparing FOUR BYTES
  as one word in the receive ring; headers read case-insensitively, extensions
  by substring search; unsolicited subprotocol is rejected.
* **risk:** data arrives in pieces, and the four-byte boundary can fall between
  them.
* **oracle:** widely used digest and printable-form examples plus own table
  encoder; text-encoding correctness by a table of valid and corrupt sequences
  versus the rule written here; piecemeal arrival is run through ALL split
  locations.
* **organ:** `chimera_shake` · **status:** `covered`

### CHI-ARB-NAMEHASH-001 — wire name and its checksum

* **source:** `Arb/ArbClientU.pas` (name split, byte-to-string conversion,
  checksum), `GroupManager.pas` (name normalization), engine parsers
  (case-insensitive trade side).
* **risk:** checksum is calculated over BYTES, while string length is in
  characters; lowercasing must not affect non-Latin bytes.
* **oracle:** widely used checksum example; comparison of the converted-name
  checksum with the checksum of the original wire slice.
* **organ:** `chimera_shake` · **status:** `covered`

---

## mORMot usage map

The map was built by enumeration: names declared in the interface sections of
units from the pinned library copy were taken and found in both products; names
declared by the products themselves or supplied by the language were removed as
coincidences. What remains is what the products actually use. The decision for
each composition follows.

| row | composition | where it lives in the products | decision |
|---|---|---|---|
| `CHI-MOR-JSON-001` | document and its fields (`_Safe`, `_Json`, `GetAsArray`, `GetAsDocVariant`, `GetDocVariantByPath`, `JSON_FAST_FLOAT` set, number parsing from pointer) | engine parsers in both products, `JsonHelpers.pas` | `merged-with CHI-MB-JSON-001` |
| `CHI-MOR-CRYPT-001` | cipher and digests (`TAesGcm`, `TAesCbc`, `TSha1/3/256/512`, keyed digest, `Keccak256Full`, random source) | Arbitrage wire, exchange signatures, HyperLiquid, user list | `merged-with CHI-ARB-WIRE-001` |
| `CHI-MOR-PACK-001` | fast compression (`AlgoSynLZ`) combined with slow compression supplied by the language | `MarketsU.pas` candle package | `merged-with CHI-MB-PACK-001` |
| `CHI-MOR-TEXT-001` | writer over a frame buffer (`TTextWriter`, `AddDirect/AddU/AddSingle/AddNoJsonEscapeUtf8`) | Arbitrage report rendering | `merged-with CHI-ARB-TEXT-001` |
| `CHI-MOR-STR-001` | manually managed string (`FastSetString`, `FakeLength`, `MoveFast`, reference count) | socket-message receipt, trade parsing | `merged-with CHI-MB-REUSE-001` |
| `CHI-MOR-UNICODE-001` | string conversion and search (`StringToUtf8`, `Utf8DecodeToString`, `LowerCaseU`, `SameTextU`, `IdemPChar`, `PosExI`, text-encoding validation, header lookup by name, printable form, checksum) | socket handshake, market names, side comparison | `merged-with CHI-MB-SHAKE-001` |
| `CHI-MOR-OS-001` | file helpers (`FileFromString`, `StringFromFile`) and time constants | report and settings persistence | `excluded`: the product creates no composition from them—one call, one answer |
| `CHI-MOR-UNUSED-001` | big-number arithmetic, set wrappers, unzipper, second compressor, key store, external-crypto-library wrapper | — | `excluded`: no reachable calls in either product (checked by name enumeration) |
| `CHI-MOR-SOCK-001` | network transport | connections | `excluded`: the subject under test is computation and memory, not a system call |

### CHI-MB-STATE-001 — order-state canon

* **source:** `MoonProto/MoonProtoOrderState.pas`.
* **work:** state is one dense record of strictly specified size made from
  nested dense records; over it sits a table of thirteen sections (offsets and
  sizes in arrays), and a section travels only whole; what changed is a bit
  mask from memory comparison at section boundaries; lengths and counts travel
  as variable-length numbers (seven bits per byte, high bit marks continuation),
  and reading proceeds directly in buffer memory and stops at the tenth byte;
  proof is a checksum of three consecutive pieces; wire times are integer UTC,
  and everything before the epoch is not a fact but emptiness.
* **risk:** one extra alignment shifts the entire record tail; seven-bit shift
  with accumulation; mask determines which bytes arrived and which retained
  their own values.
* **oracle:** variable-length number is written and read by a SECOND method—
  division and multiplication instead of shifts; boundary table is checked for
  consistency by itself (offset = sum of preceding sizes, sum of all = record
  size); partial transfer is compared both ways; proof is calculated by manual
  concatenation of the same pieces and must change on a modification in ANY
  section.
* **organ:** `chimera_state` · **status:** `covered`

### CHI-MB-FIELD-001, CHI-MB-PROTO-005 — two opposite field forms

**CHI-MB-FIELD-001** (`MoonProto/StrategySerializer.pas`): a field travels
self-describing—type-code byte, then value; a zero value raises the code's
high bit and carries no value at all; a floating-point value with magnitude
below a threshold counts as zero, and a very small nonzero travels as zero;
unknown field is skipped by the size from its code, while an unknown code skips
eight bytes blindly; names travel as dictionary numbers.

**CHI-MB-PROTO-005** (`MoonProto/MoonProtoSerialization.pas`): the opposite
form—more than forty adjacent fields without codes, held together only because
the reader repeats write order. The reader parses them into more than forty
local variables and only then puts them in place; an unwanted market is still
read fully, otherwise the next one shifts.

* **risk:** first form: masking the zero marker and skipping by guesswork;
  second form: silent shift of the entire stream at the slightest ordering
  mismatch.
* **oracle:** table of type codes (value is read identically, length is the
  promised one); stream with an unknown field in the middle parses identically
  to one without it; flat-record length is calculated by the rules rather than
  measured; consuming an unwanted market is checked by the next market reading
  correctly.
* **organ:** `chimera_field` · **status:** `covered`

### CHI-MB-BOOK-003, CHI-MB-BOOK-004 — two further order-book forms

**CHI-MB-BOOK-003** (`EngineBase.pas :: ApplyOrderBookDiffKeepZero`): merge
two sorted lists in one traversal; comparison direction depends on side; a
level with zero volume does not enter the new list—that is deletion; old level
at the same price is skipped regardless of whether a new one entered; then the
head is trimmed at the price from the second delta list by moving a range within
the same array, and length is corrected at the very end.

**CHI-MB-BOOK-004** (`MoonProto/MoonProtoOrderBook.pas`): packet numbers are
sixteen-bit and wrap—comparison is by signed cast of the difference, so “zero
follows the maximum” works by itself; delta is cut into packets by alternating
sides with packet count estimated in advance; cache of out-of-order packets is
kept sorted by binary-insertion with the same wrapped comparison; cache expiry
and request throttling use modulo time differences.

* **risk:** merge: loss or duplication of a level when prices match within the
  tolerance, and moving overlapping ranges within one array; numbers: wrap of
  a sixteen-bit counter, where naïve comparison reverses the queue; cache:
  binary insertion using the same wrapped comparison and time moving backwards.
* **oracle:** merge: same answer from a price map with replacement and ordering
  (no merging or shifting); slicing: completeness and order of all levels plus
  per-packet limit; cache: number order, including around wrap, and a clock
  moving backward does not cancel expiry.
* **organ:** `chimera_book` · **status:** `covered`

---

## MoonProto catalogue: decision for every unit

The specification requires traversing the catalogue in full. Twenty-four
units, a decision for each:

| unit | contents | decision |
|---|---|---|
| `MoonProtoOrderState` | state canon, variable-length number, proof, times | `CHI-MB-STATE-001` |
| `MoonProtoTradesStream` | reusable stream and linear packet cache | `CHI-MB-BUF-001`, `CHI-MB-BUF-002` |
| `MoonProtoCommon` | stream-write and stream-read primitives | `CHI-MB-PROTO-001`…`004` |
| `MoonProtoSerialization` | flat market record | `CHI-MB-PROTO-005` |
| `StrategySerializer` | self-describing settings stream | `CHI-MB-FIELD-001` |
| `MoonProtoOrderBook` | delta slicing, wrapped numbers, cache | `CHI-MB-BOOK-004` |
| `MoonProtoOrderNode` | `CHI-MB-MPNODE-001` — server order node | `merged-with CHI-MB-STATE-001`: node work is ownership and state publication; the state form itself has already been transferred, and it contains nothing beyond a lock and reference |
| `MoonProtoIntStruct`, `MoonProtoTradeStruct`, `MoonProtoUIStruct`, `MoonProtoBalanceStruct`, `MoonProtoEngineStruct`, `MoonProtoStratStruct`, `MoonProtoBaseStruct`, `MoonProtoDataStruct` | `CHI-MB-MPSTRUCT-001` — message descriptions | `merged-with CHI-MB-PROTO-005`: all are the same flat field order over the same primitives, differing only in their field list. A field list creates no separate failure class: it creates ONE class—write/read order mismatch—and that is presented |
| `MoonProtoEngine`, `MoonProtoServer`, `MoonProtoClient`, `MoonProtoUDPServer`, `MoonProtoUDPClient`, `MoonProtoEngineServer`, `IndyUDPHelper` | `CHI-MB-MPTRANS-001` — transport | `excluded`: subject under test is computation and memory, not a system call. Everything transport does itself—packet slicing, number-indexed cache, repeat requests—is extracted and transferred to `CHI-MB-BOOK-004`; the rest is socket work |
| `StrategySchemaBuilder` | `CHI-MB-MPSCHEMA-001` — building strategy descriptions | `excluded`: it is built by traversing live type descriptions, so it checks language machinery rather than a computation form. Blob format uses the same type codes as `CHI-MB-FIELD-001` |
| `MoonProtoFunc` | `CHI-MB-MPFUNC-001` — packet checksum and fixed datagram sizes | `merged-with CHI-ARB-NAMEHASH-001`: same checksum of a memory slice; fixed datagram sizes are not computation |

## CHI-MB-LIFE-001 — lifetime: the compiler's invisible code

All other Chimera work checks VALUES. This checks **side effects absent from
the source**: assignment of a reference-counted variable expands into a pair of
accounting calls; exiting a procedure with a managed value expands into hidden
protection; exception in the body expands into frame unwinding, where every
level must release its own value.

An error here does not produce a wrong number. It produces a leak—or releases
what is still in use: access to memory already returned to the allocator, not
where it happened, and not immediately.

* **source:** `MyListHelper.pas` — modified list helper supplied by the
  language: element exchange SAVES the former value (the former moves aside,
  the new one takes its place, notifications receive both, and only then is the
  former released). Plus `Bworks.pas`—one hundred and sixteen protections and
  ninety-nine handlers in one unit.
* **oracle:** **explicit accounting versus implicit**. One path lives on the
  reference count maintained by the language; the second performs the same
  work on the same items but writes capture and release manually. Both record
  an event tape—who was born, who died, and in which order—and the tapes must
  match character for character. Beyond the tapes: live count returns to zero
  after all work, and a deeper level is released before a shallower one.
* **what is presented:** unwinding at each of six depths; replacement in a
  store; assigning a slot to itself; protection while exiting from the middle;
  exception INSIDE protection (displaces the original but leaves no live
  values); rethrow; managed record made of a string, reference count, and array
  at once—copying, clearing copies, growing and shrinking an array of such
  records; exception in another thread.
* **organ:** `chimera_life` · **status:** `covered`

---

## Inventory state

The current inventory contains 70 reviewed rows: 55 are covered directly, five
are excluded with a written boundary, and ten are merged into an equivalent
covered composition. No reviewed row remains open. The machine-readable source
of this state is [`inventory.json`](inventory.json); its contract gate rejects
an unknown status or an unaccounted row.
