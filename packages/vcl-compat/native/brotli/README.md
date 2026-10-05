# Private Brotli decoder

`Moon.Brotli` links Google's Brotli **1.2.0** decoder, under the MIT license.
The unmodified source is [google/brotli v1.2.0](https://github.com/google/brotli/releases/tag/v1.2.0).
`brotli-1.2.0.tar.gz` SHA-256:
`816c96e8e8f193b40151dad7e8ff37b1221d019dbcb9c35cd3fadbfe6477dfec`.
Keep `LICENSE-brotli.txt` with distributions. No Embarcadero implementation is used.

The unit consumes a bounded input stream and checks complete termination; corrupt,
truncated and trailing input raises an error. The decoder is incremental and uses
the application's memory manager. HTTP applications opt in by adding
`Moon.HttpClient.Brotli` to their `uses` clause; `System.Net.HttpClient` alone
does not link the decoder or advertise `br` automatically. `Moon.Brotli` can
also be used directly for stream decompression without the HTTP client.
An application needs neither a Brotli DLL nor a C compiler. The target objects are
installed beside `moon.brotli.ppu`, like the private objects of `System.ZLib`.

`build.py` verifies the source hash, builds the common/decoder C sources with unwind
tables, prefixes external C definitions with
`moon_brotli_` before compilation, and rejects unexpected dependencies. This also
namespaces compiler-generated COFF `.refptr` symbols and COMDAT sections.
Allocation/copy/clear symbols
bind to the Pascal unit. No encoder or system Brotli library is linked.

```sh
python3 build.py --target x86_64-linux
python3 build.py --target x86_64-win64 --cc x86_64-w64-mingw32-gcc --nm x86_64-w64-mingw32-nm
```
