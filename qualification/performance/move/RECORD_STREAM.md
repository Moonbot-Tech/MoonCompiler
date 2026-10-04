# Record stream model

`pulse_record_stream.dpr` prepares eight deterministic payloads, then produces
records containing an ID, length and content digest. A queue holds up to four
pending records. FIFO appends; priority mode inserts every fourth record at the
front, requiring a backward overlapping move. Removing a processed record
compacts the window with a forward overlapping move. The receiver retains 8 or
64 independent copies and reads every payload before replacing or releasing it.

Shape 0 uses 12–96 byte payloads; shape 1 uses 129–16384 byte payloads. Two heap
phases shift input/window and output pointers by different small offsets. These
are independent program modes, not weights assigned to a particular consumer.
One reported operation is one complete record, including packing, queue changes,
retention and consumption. Allocating storage and preparing payloads happen
outside the measured case.

Before timing, 128 records check every ID exactly once and compare every payload
byte. Timed runs check payload digests and the expected sum of IDs and content,
including the final retained records. Cases also handle the harness's short
calibration runs correctly. The test calls the linked `System.Move`; it contains
no copied machine code, feature-flag changes or address relocation helpers.

The ordinary Pulse runner registers this program as `record-stream`. For example:
`python qualification/performance/tools/pulse.py --help` shows the local build
and run commands. A selected case is named
`shape1-priority1-retain64-phase1`; `list` exposes all 16 modes.
