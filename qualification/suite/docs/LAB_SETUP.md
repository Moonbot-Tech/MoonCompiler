# Additional reference toolchains

Normal qualification uses the compiler from the repository root:

```bash
../../build compiler
```

`runner_manifest.json` already points `moonbot-compiler-beta` to
`../../.moonbot/toolchain` and selects the standard Linux or Win64 driver/config
for the current platform. Product mORMot is bundled in
`qualification/vendor/mormot-product`; the new public mORMot runner fetches
itself from the URL and exact commit in the manifest. `qualification/prepare.sh`
performs the same contract in advance when the lab must be prepared to work
without network access.

## FPC 3.2.4 RC1

This toolchain is required only for historical A/B and the PPU-version gate. It
does not participate in the normal product build. Exact source commit:

```text
d78e2897014a69f56a1cfb53c75335c4cc37ba0e
```

Clone it into `qualification/suite/checkouts/fpc-3.2.4-rc1`, build it with the
normal FPC bootstrap, and install it in
`qualification/suite/toolchains/fpc-3.2.4-rc1`. Both directories are ignored by
Git.

## Historical affected/reference versions

Entries in `runner_manifest.json` contain the exact commit and expected class of
the old result. Prepare them only when re-investigating the defect's origin. A
release does not require downloading every historical compiler.

A reference result cannot be used blindly as an oracle. Accepted behavior still
requires Delphi 12.2 semantics, a specification, or the independent invariant
described in `research/fixture_oracles.json`.
