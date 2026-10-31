# JSON helpers used by Moonbot

These three units are copied without code changes from Moonbot Common commit
`33209f5f846f09964f8f74c71f33d9d1e5667f69`:

- `JsonReader.pas`: typed projection of selected fields from a message.
- `JsonReaderScan.pas`: scanner and numeric decoding used by that projection.
- `JsonHelpers.pas`: compact indexed document and typed access to all fields.

Their dependency is the public MoonORMot library. `reproduce.sh build` downloads
its matching revision and the published MoonCompiler SDK. No private repository
or precompiled Common units are needed.

Published by Moonbot-Tech for downloading, building and running these examples.
