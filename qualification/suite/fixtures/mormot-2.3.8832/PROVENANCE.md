# Provenance of the mORMot 2.3.8832 test suite

The `test/` directory is based on the upstream test tree from commit
`38874e16c03373a5275b959fdb1cc38d5597f67f` (`mORMot 2.3-stable release!`).
Original Git tree ID: `632a414230ee6056511ec3a6a30d7f83e5fe7696`.

The product source does not come from this fixture. The runner places the test
tree next to `qualification/vendor/mormot-product/src`, so compilation and
execution use exactly the established MoonBot product snapshot. The documented
local Keccak-256 patch is already part of the snapshot. Its memory manager is
not copied: the compiler pins `runtime/mm/mormot.core.fpcx64mm.pas`.

MoonBot deliberately preserves fractional JSON numbers as text unless double
parsing is explicitly requested. Therefore, the local suite changes only the
affected oracles: default parsing must preserve decimal text, while BSON tests
of numeric encoding explicitly enable `dvoAllowDoubleValue`.
The JSON decimal-serializer check passes `Double(1.12345)`, not a bare decimal
literal: when assigned to a Variant, its Delphi-compatible carrier is
`Currency`, whereas FPC uses `Double`; this distinction is fixed by a separate
Delphi oracle and does not test the serializer itself.
`fixtures/minimized/mormot_variant_bson_probe.pas` independently fixes both
contracts: default text and the explicit numeric path through `IDocDict`.
