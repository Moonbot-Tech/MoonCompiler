# SDK boundary contracts

These tests cover component resources, INI defaults, Unicode database fields,
SQLite byte boundaries, thread handles, CPU accounting, connection failures and
optimized stack/module lookup. They use explicit values, OS calls and native
SQLite queries as oracles; a successful compilation alone is not a pass.

Run the installed-SDK consumers outside the source tree:

```text
python qualification/release/rtl_boundaries_smoke.py --compiler TOOLCHAIN_FPC --sdk-only --out NEW_DIRECTORY
```

The release archive gate includes these same consumers. It compiles against the
installed units without source overlays. Linux needs a C compiler for the foreign
stack frame and the system `libsqlite3.so.0`; Windows uses `winsqlite3.dll`.

The Linux `native_blob` release job writes and reads BLOBs with embedded
Firebird 3 and a private MySQL 8 server on a Unix socket. Run it as an ordinary
user with `bash qualification/suite/tests/sdk-boundaries/run_native_blob.sh TOOLCHAIN_FPC`.
On Ubuntu 24.04 it uses `firebird3.0-server-core`, `firebird3.0-utils`,
`mysql-server-core-8.0`, `mysql-client-core-8.0` and `libmysqlclient21`.
Both databases and the server data directory are temporary.

Run the source-controlled CPU/connect fixtures and real loopback network tests:

```text
python qualification/suite/tests/sdk-boundaries/run_contracts.py --compiler TOOLCHAIN_FPC --source . --mormot MORMOT_CHECKOUT --out NEW_DIRECTORY --modes debug release
```

`--exhaustion` additionally requires Linux `sudo -n`, `unshare` and `ip`. It creates
a separate network namespace before reducing its ephemeral-port range. The
fixture refuses the host network namespace. Other tests require no root access,
external service or Internet connection.

CPU and connect fixtures extract the current implementation bodies; only their
OS inputs are controlled. They check omitted counters, malformed/truncated reads,
rollback, immediate native errors, pending connections and interruption. The
native connection test independently proves that `SO_ERROR` cannot recover the
selected immediate failure. HTTP tests then check the public exception reason,
native code, request outcome, asynchronous transfer and recovery of the same client.

The stack tests require frame symbols and lines, exact skip/count behavior,
buffer canaries, worker threads, recursion and a C frame built without a frame
pointer. Module tests change the working directory before their first lookup.
Resources include inherited components, absent/empty delta candidates and both
integer and string resource types. Database tests include mixed code pages and
Variant comparisons, OEM bytes, NULL/empty values, embedded zeroes and odd blobs.
