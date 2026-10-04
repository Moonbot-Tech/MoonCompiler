# A unit of a cycle compiled by name after its implementation changed

`cycrel` uses `cyctypes` in its interface (the result type of an `inline`
function), `cyctypes` uses `cycrel` in its implementation and inlines that
function.  Both are built once; then the body of a routine of `cycrel`
changes (`-dCYCREL_CHANGED`) and `cycrel.pas` is compiled by name next to the
existing `cyctypes.ppu` - what a makefile, an IDE "compile unit" command or
the RTL build of one unit does.

`cyctypes.ppu` recorded the implementation crc of `cycrel`, so `cyctypes` is
compiled again from its sources, and its old definitions are freed.  By then
`cycrel` has parsed its implementation and waits for the crcs of the units
it uses.  The scheduler "reloaded" it, which re-resolves only what has deref
data - for a unit compiled from its sources in the same run that is the
interface; the node trees kept for inlining and the implementation's
definitions get theirs when the ppu is written.  The tree of `Relation`
went on naming the freed `TRelation`, `cyctypes` inlined it, and the compiler
died: an access violation in a release build, internal error 200306031 in a
debug build, nothing at all under some verbosity settings - and the program
linked afterwards ran with the old routine body.

Found with the RTL: `math.pp` compiled by name next to `types.ppu` after a
change in an assembler routine of Math (`Math.CompareValue` inlined into
`TRectF.IsEmpty`).

Such a unit is now compiled again instead of reloaded
(`tppumodule.reload_needs_recompile`).  The gate
(`run_service_regressions_gate`) builds, changes the body, compiles the unit
by name, builds again and expects the new body's result, at `-O-`, `-O2` and
`-O3`; before the fix `-O3` crashed.
