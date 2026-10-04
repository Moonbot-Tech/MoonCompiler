# Message lifetime model

`pulse_mm_lifetime.dpr` allocates a 32-byte message header and a separate payload,
copies prepared input into the payload, retains the message and consumes every
payload byte before releasing both allocations. The header's pointer, length,
ID and digest are used; it contains no padding added to reach a chosen MM class.
The digest accumulator is local to the payload reader.

Each mode replaces messages in a live window of 8, 64 or 256 entries. It allocates
the next message before consuming the previous one, so both lifetimes coexist.
Independent roots retain either zero or 64 messages in several classes. The
roots survive all replacements and are consumed at the end. Kind 0 uses 32-byte
replacement payloads; kind 1 cycles through other small/medium sizes; kind 2
uses a deterministic permutation of that mix. Payload sizes are
24, 32, 48, 96, 128, 193, 512, 2048 and 8192 bytes.

Input generation happens outside the measured case. Window/root creation,
replacements, consumption and final release are measured together. Each harness
iteration runs a complete trace of exactly 8192 replacements. One reported
operation is one replacement; creating and releasing the window and roots always
has the same amortization over 8192 replacements. Calibration may repeat whole
traces, but cannot change their lifetime mix or startup cost per replacement.
No mode is assigned a universal weight.

Before timing, 512 replacements compare every retained payload byte. Timed
consumption still checks each message's content digest. The ordinary Pulse
runner registers all 18 cases as `mm-lifetime`, for example
`kind2-live256-roots64`. This test uses the selected program's allocator and
contains no metadata relocation, private accessors or feature-flag changes.
