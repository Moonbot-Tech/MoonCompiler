# Delphi surface over mORMot: System.Zip, System.Net.Mime, System.Net.HttpClient

The three units here are the Delphi surface that MoonBot and Arbitrage call
and that is built on mORMot - `TZipFile`/`TZipHeader`/`EZip*`,
`TMultipartFormData`, `THTTPClient`/`IHTTPResponse`/`IAsyncResult`/
`TCookieManager`/`ENetHTTP*` - written for MoonCompiler from the behavioural
contracts in the planning document `DELPHI_SURFACE_ADDITIONS_20260920`
(sections 3.1 and 3.2), PKWARE APPNOTE 6.3.10, RFC 9110/9111, RFC 7578,
RFC 1866/3986 and the MoonBot compatibility units they replace, without
Embarcadero's source. They were then audited against Delphi 12.2 (21.09.2026):
the contract programs were also built by Delphi and run against the same
servers and fixtures, every difference was classified (fixed here, or kept on
purpose and listed below), and a line-level resemblance check against the
Delphi units found no shared code. `System.Net.URLClient`, which needs no
mORMot, is an ordinary precompiled unit of the `vcl-compat` package.

## How they are built

The units live here, not in a package, because they are compiled **into each
project against the mORMot the project sees**: `mormot.core.zip`,
`mormot.lib.z`, `mormot.net.client`, `mormot.net.sock`, `mormot.core.*` and
(on POSIX) `mormot.lib.openssl11` come from the project's own trees if it
carries a mORMot, otherwise from the `mormot` directory next to the toolchain
(a clone of `Moonbot-Tech/MoonORMot`), exactly as for `Moon.Diagnostics`.
The toolchain's `fpc.cfg` keeps `runtime/mormot` on the unit path at all
times, so `uses System.Zip;` or `uses System.Net.HttpClient;` is all an
application needs. A project with no mORMot on its path cannot use them.

The units are qualified with MoonORMot and use only the stable public API of
mORMot 2.x. Each of them names `MoonORMot.Need` (this directory) in its uses:
that unit compares `MOONORMOT_VERSION` of the mORMot found with the number in
`runtime/moonormot.need.inc` and stops the build with `MoonORMot is older
than this toolchain requires: run git pull in the mormot directory next to
the toolchain` when it is lower; an equal or newer MoonORMot, or a mORMot
without the constant (upstream, a fork), is accepted as it is. The number is
kept on the tip of MoonORMot `main` by `scripts/sync-moonormot.py` together
with the qualification pin and the bundled memory manager ("MoonORMot
records" in `doc/TESTING.md`). Deflate is mORMot's `mormot.lib.z`, which
under this compiler compresses through `System.ZLib` - the one zlib of the
program (the compiler defines `MOONCOMPILER_SYSTEM_ZLIB`, MoonORMot takes its
`ZLIBRTL` choice; on Linux libdeflate keeps mORMot's whole-buffer calls and
checksums); TLS is SChannel on Windows and OpenSSL (loaded at run time by
`mormot.lib.openssl11`) on Linux, as in mORMot itself.

## System.Zip

The container - central directory, ZIP64, names (UTF-8 by bit 11, the
0x7075 extra field, CP437 otherwise), local headers, writing - is
`mormot.core.zip`'s `TZipRead`/`TZipWrite`; the unit adds the Delphi shape.

- `Open(file, zmRead)` maps the file; `Open(stream, zmRead)` works on a
  memory stream's memory from its `Position` and copies any other stream
  once. `zmWrite` creates; `zmReadWrite` on a file keeps the entries and
  appends (not available on a stream). A damaged or empty archive raises
  `EZipException`; `FileCount`/`FileNames` on a closed archive too.
- `Read(name|index, Stream, LocalHeader, CheckCrc)` gives a stream **owned by
  the caller** that inflates the entry on demand from the archive, no copy of
  the entry; `CopyFrom(Stream, LocalHeader.UncompressedSize64)` reads exactly
  the entry, a seek back restarts the inflater. With `CheckCrc` the last byte
  raises `EZipCRCException` on a mismatch. `Read(name|index, Bytes)` is the
  whole entry with the CRC checked. An unknown name raises
  `EZipFileNotFoundException` with `FileName`, an index out of range
  `EZipException`, an encrypted entry `EZipException`. A stored entry whose
  compressed size is not its uncompressed size, or whose bytes run out before
  that size, raises `EZipException` instead of returning a short success.
  Deflate must reach its end marker at exactly the declared output size;
  truncated streams and extra output are refused, including empty entries.
  `OnProgress` also reports entry reads after each successful chunk and after
  the final CRC check. Keep the archive open while an entry stream is alive.
- `TZipHeader` is the central directory record per APPNOTE, field for field,
  with `UncompressedSize64`/`CompressedSize64`/`LocalHeaderOffset64` (ZIP64
  resolved), `ModifiedTime`, `UTF8Support`, `UseDataDescriptor`, `IsEncrypted`.
- `Add(Data, name, zcDeflate|zcStored)` writes from `Data.Position` to its end
  (`nil` for an empty entry or a `dir/` entry), the local header patched
  with CRC and sizes (no data descriptor), ZIP64 extra fields when needed,
  `ModifiedTime = Now`, a UTF-8 name flagged with bit 11 when it is not
  ASCII. `OnProgress` fires after the entry with its size; other methods
  raise `EZipException`. The central directory is written at `Close`.
- `ExtractAll(Path)` checks every name first - an absolute path, a drive or
  stream colon on Windows, a `..` component raise `EZipException` and
  nothing is written. On Windows a trailing dot or space (CreateFile would
  drop it and overwrite another entry) and DOS device names (`NUL`, `CON`,
  `AUX`, `PRN`, `COM1`/`LPT1` and their numbered variants, with or without an
  extension) are refused the same way. Then it extracts with
  directories created, the CRC checked, the file date set; a CRC or
  truncation error deletes the partial file it had started. A symbolic link
  entry (UNIX host, `S_IFLNK`) is created as a link on POSIX, `OnProgress`
  after each file. The link text is checked the same way before anything is
  written: an absolute target or a `..` component raises and the archive
  extracts nothing.
- `IndexOf` ignores case; `UTF8Support`/`Encoding` of Delphi's `TZipFile`
  are not here: the encoding of names is decided by mORMot as above.

## System.Net.Mime

`TMultipartFormData` is `THttpMultiPartStream` with the Delphi shape:
`AddField(name, value[, type])`, `AddFile(name, path[, type])` (the file is
opened there, a missing file fails there, its bytes are streamed when the
body is read; the type comes from the extension when not given),
`AddBytes(name, bytes[, filename, type])` and `AddStream(name, stream[,
owns][, filename, type])` (the stream from its initial `Position` to its end,
freed with the multipart body when owned), then
`Client.ContentType := MimeTypeHeader; Stream.Position := 0;
Client.Post(URL, Stream)`. The body is a flat RFC 7578 multipart in insertion
order, closed once with the final boundary, so
it can be read more than once; an `Add*` after the body was read raises
`EMultipartFormData`. `Boundary` is the boundary of `MimeTypeHeader`.
`Create(False)` leaves the stream to the caller.
All part methods accept optional `TStrings` headers. CR/LF injection and
overriding Content-Type/Content-Disposition through those headers are refused.
Borrowed streams must stay alive until the body is freed; their initial byte
window is retained for replay. The HTTP multipart overloads rewind the complete
body before each request without changing the client's default ContentType.

## System.Net.HttpClient: what the contract fixes

- One instance, one request at a time; instances are independent. HTTP/1.1
  with keep-alive: a series of requests to one origin rides one connection.
- Request headers are the client's `CustomHeaders` (`CustHeaders` is the
  same collection; `UserAgent`, `Accept`, `AcceptEncoding`, `AcceptLanguage`,
  `ContentType` are its named entries) with the call's `AHeaders` replacing by
  name. `UserAgent := ''` sends no `User-Agent` at all; the default is the
  unit's own, not Embarcadero's.
- `Post/Put/Patch(ASource)` send the source from its `Position` to its end
  with that `Content-Length`; afterwards `ASource.Position` is its end. A
  body up to 1 MB is read once and sent as bytes, a small one in the same
  packet as the headers; a bigger one is streamed from the source.
  `Post/Put(TStrings)` build `application/x-www-form-urlencoded` in `AEncoding`
  (UTF-8 by default) and sets `Content-Type` with the charset for that call.
  Post/Put also accept a filename or `TMultipartFormData` directly. Upload
  `OnSendData` reports zero, then bytes sent; requesting abort raises a client
  exception and closes the connection.
- Any status comes back as a response (4xx/5xx are not exceptions). The body
  goes to `AResponseContent` from its position (position restored) or to an
  internal stream. `Headers` lists what the server sent; `Content-Type`,
  `Content-Length`, `Transfer-Encoding` and `Connection`, which mORMot keeps
  apart from the header text, are appended from its fields (a JSON
  `Content-Type` is reported as `application/json` without its parameters,
  the form mORMot keeps).
- The internal stream is a `TReceivedBody` (a `TMemoryStream`): the body
  exactly as received, in the one block the socket filled, `Memory`/`Size`
  the body, `Position` 0 - no copy between the socket and the caller. This
  is the form MoonBot reads (`EngineBase.ReadHttpBody`,
  `nethelpers.ResultUtf8`: `TMemoryStream(ContentStream).Memory` into a
  `RawUtf8`), and `System.Zip.Open(ContentStream)` and a
  `TDecompressionStream` over it read from the same block. Reading never
  copies; the first write, resize or `Clear` moves the bytes to the
  stream's own storage, after which it behaves as any memory stream.
  `ContentAsString` decodes the received span `[start, end)` — bytes the
  caller left in the stream past that end are not part of the body — and a
  body held in memory is decoded where it lies (the `TEncoding` decoder on
  the block, no byte copy). A `gzip` or `deflate` body that is not one
  complete member raises `ENetHTTPResponseException` (a short read is not a
  successful partial inflate), from `ContentAsString` and from
  `AutomaticDecompression` alike.
- On a kept connection, an empty answer may mean either an idle timeout or
  a server that processed the request and disconnected before replying.
  `GET`/`HEAD`/`PUT`/`DELETE` may retry once on a fresh connection;
  `POST`/`PATCH` raise `ENetHTTPClientException` without a replay. The caller
  must resolve an uncertain operation through the application's own status
  or idempotency mechanism before retrying. No request is repeated after any
  part of an answer, or when sent on a connection opened for that request.
- `Content-Length` is taken as the body's length and checked against what
  arrives. Too long with the server gone quiet: `ENetHTTPResponseException`
  after `ResponseTimeout`, no partial body; too long with the server
  closing: the exception at once. Too short: the body is the announced
  bytes, and the excess, which sits in front of the next answer on that
  connection, makes that next request fail as "not an HTTP response" and
  drops the connection; the request after it rides a new one. Absurdly
  large (above mORMot's `MaxHttpInMemSize`, 1 GB): refused at once, before
  anything is allocated or waited for - with the previous MoonORMot a
  `Content-Length` of 2 GB overflowed the socket read length and came back
  as a "successful" body of 2 GB of garbage. A body without
  `Content-Length` and without chunking (delimited by the connection's
  close, RFC 7230 3.3.3) arrives byte for byte - the MoonORMot backport of
  upstream's raw read replaced a line reader that turned a bare LF into
  CR LF.
- Redirects (`HandleRedirects`, default on): 300/301/302/303/307/308 with a
  `Location`, resolved against the current URL per RFC 3986 (dot segments
  removed, including an absolute path, an absolute URL and a
  protocol-relative URL), up to `MaxRedirects` (default 5), one more raises
  `ENetHTTPRequestException`. `POST` on 301/302/303 and any method but `HEAD`
  on 303 become `GET` without body, `Content-Length` and `Content-Type`;
  307/308 keep method and body. Cookies are updated on every hop. A redirect
  to another scheme, host or port does not send the caller's `Authorization`,
  `Proxy-Authorization` or `Cookie`; cookies stored for the new host still go.
- `AutomaticDecompression = []` (the MoonBot setting) leaves the body as
  received with `Content-Encoding` intact, and `ContentAsString` inflates a
  body whose encoding is exactly `gzip` or `deflate` (zlib-wrapped or raw)
  through `System.ZLib`, always from the start of the body, however the
  caller moved `ContentStream`. With `GZip`/`Deflate`/`Any` set,
  `Accept-Encoding` is added when the caller set none, the body in
  `ContentStream` is already inflated, `ContentAsString` does not inflate
  again, and the `Content-Encoding` and `Content-Length` headers of the coded
  body are dropped (`ContentEncoding = ''`), so nothing describes a body that
  is no longer there.
- Brotli is optional: add `Moon.HttpClient.Brotli` to the application's `uses`
  clause to link its decoder. With that unit, `Any` includes `br`, and `Brotli`
  selects it explicitly. Without the unit, `Any` includes only gzip/deflate;
  an explicit `Brotli` selection raises `ENetHTTPClientException` before any
  connection is opened. An unsolicited `br` response remains available as raw
  bytes through `ContentStream`; `ContentAsString` requires the optional unit
  and raises `ENetHTTPResponseException` with its name when it is absent.
  With the unit, `ContentAsString` also decodes `br` when automatic decompression
  is off. The bundled MIT-licensed decoder is static: no Brotli DLL is required.
  Merely using `System.Net.HttpClient` does not link its code or dictionary.
- `ContentAsString(nil)` decodes with the `charset=` of `Content-Type`
  (quotes removed, case ignored), UTF-8 when absent; a BOM is kept, an
  invalid UTF-8 sequence becomes U+FFFD (what `TEncoding.UTF8` gives).
- Cookies enforce host-only/domain scope, path boundaries, Secure, Expires,
  Max-Age and deletion. Same-name cookies on different paths coexist, with
  more specific paths sent first. Redirects and async requests share the jar.
  `AddServerCookie(Data, URL)` uses the same rules. This is an HTTP-client jar:
  it does not include a browser public-suffix database or browser navigation
  context for SameSite enforcement.
- HTTP Basic authentication supports per-request server credentials and a
  single challenge retry through `CredentialsStorage`, `AuthEvent` or
  `AuthCallback`; client-persistent credentials are shared with async clones.
  Digest/NTLM/Negotiate challenges remain ordinary responses: their enum values
  do not install protocol implementations. HTTP proxy credentials are sent to
  the proxy, including CONNECT, and never as origin Authorization. Proxy
  credentials on a request require configured ProxySettings.
- `OnReceiveData` fires for 200/206 only: first with `AReadCount = 0` and
  the `Content-Length` (or -1 when chunked), then after every received piece.
  `AAbort := True` stops the body without an exception: the response keeps
  the status, the headers and the truncated body, and the connection is
  closed.
- TLS verifies the chain and the host name. On a certificate failure with
  `OnValidateServerCertificate` assigned, the handler is called once with
  `Accepted = False` and the certificate's subject, issuer and CN;
  `Accepted := True` lets the request proceed
  on a connection that ignores the verification, and that connection is
  reused without asking again. Without a handler or when it refuses,
  `ENetHTTPCertificateException`. A trusted certificate never calls the
  handler.
- Errors: a URL without a scheme or a host (`''`, `foo`,
  `localhost:8080/x`, `http://`) raises `ENetURIException` at once, before
  any connection is tried; an unsupported scheme, connection, DNS, handshake
  and timeout failures before the response line raise
  `ENetHTTPClientException`; a failure while the body is being received raises
  `ENetHTTPResponseException`. `ConnectionTimeout`, `SendTimeout` and
  `ResponseTimeout` default to 60000 ms; the response timeout governs the wait
  for the response line and each read of the body.
- Generated HTTP exception messages identify the failure without including
  request URLs, credentials, raw socket/TLS messages or malformed response text.
  Socket result names, exception categories, timeout durations and redirect
  counts remain available. This applies to synchronous and asynchronous calls.
  Application-owned callback exceptions and explicit logging of request/response
  URLs remain the application's responsibility. URI fragments (`#...`) are kept
  in URI APIs but never sent in the HTTP request target; escaped `%23` is preserved.
- `BeginExecute` and the standard `BeginGet/Head/Post/Put/Patch/Delete/Options/Trace`
  methods run the request in a thread on a copy of the client's
  settings; `IsCompleted` is set when it finished (with a response or an
  exception), `Cancel` returns `True` and aborts a running request (`False`
  once completed), `EndAsyncHTTP` waits and returns the response or raises
  the request's exception (`ENetHTTPClientException` for a cancelled one).
  Callback/event overloads and `AsyncWaitEvent` use the shared `System.Types`
  interface. Callbacks run on the worker thread. Releasing the last external
  async result cancels unfinished work and waits for its callback to finish.
  Caller-owned streams, event receivers and explicitly assigned credential
  storage must remain alive until then. DNS providers may continue independently
  after cancellation, bounded to eight resolver workers; they hold no caller
  streams/client objects and cannot open a connection after cancellation.
  ConnectionTimeout includes DNS, TCP and TLS setup. Cancellation shuts down
  the active socket; its I/O owner closes the descriptor, preventing handle reuse
  from redirecting cancellation to another connection.

## Differences from Delphi 12.2 kept on purpose

Found by running `httpclient_contract` built by Delphi (`--http-executable`)
against the gate's servers; each one is the contract's explicit choice.

- Delphi's `ContentAsString` reads the caller's response stream from its
  start (so a stream that held data before the request gives that data too)
  and inflates a compressed body from the stream's current position (a peek
  at the stream before `ContentAsString`, or a second `ContentAsString`,
  fails with a zlib data error). Ours reads the body it received, from its
  start, every time.
- Delphi (WinHTTP) inflates `deflate` only as raw deflate under
  `AutomaticDecompression` and only as zlib in `ContentAsString`; ours takes
  both forms in both places. Delphi's `ContentAsString` does not inflate at
  all when `AutomaticDecompression` covers some other method; ours does.
- A `Cookie` header given with the call is dropped by Delphi in favour of
  the jar; ours joins the two.
- Delphi (WinHTTP) did not enforce `ResponseTimeout = 400` against a 1.5 s
  delay of the response line or of the body on the loopback; ours raises
  after the timeout.
- `Cancel` of a completed request answers `True` in Delphi (its own comment
  says it cannot cancel a completed operation); ours answers `False`.
  `EndAsyncHTTP` after `Cancel` returns a half-filled response in Delphi;
  ours raises `ENetHTTPClientException`, so a cancelled request cannot pass
  for a finished one.
- On Windows Delphi calls `OnValidateServerCertificate` for every HTTPS
  request, before the system has judged the certificate, with
  `Accepted = True`; ours (like Delphi's non-Windows platforms) calls it only
  when the verification failed, with `Accepted = False`, and an accepted
  connection is reused without asking again.
- The default `User-Agent` is the unit's own, not Embarcadero's.

## Qualification

`qualification/suite/scripts/run_runtime_mormot_gate.py` compiles
`qualification/suite/tests/smoke/zip_contract.pas`, `mime_contract.pas` and
`httpclient_contract.pas` in `-O-` and `-O3` against the installed toolchain
and mORMot, with `runtime/mormot` ahead of the installed units;
`--http-executable PATH` runs a foreign build of the HTTP contract (Delphi's,
for the audit above) against the same servers instead. The Zip
contract reads an archive written by Python's `zipfile` (embedded bytes,
known sizes/CRCs/times/names), including data descriptors and repeated append,
writes archives that are read back, checked
against APPNOTE's layout and then read by `zipfile` in the gate, and covers
damaged and empty-entry CRCs, incomplete or oversized deflate, nonzero stream
write positions, trailing stream data, encrypted entries, escaping names, a hand-made
ZIP64 central directory and `ExtractAll`. The Mime contract splits the body
at the announced boundary and checks every part. For the HTTP contract the
gate starts a loopback HTTP server, a
TLS server with a self-signed certificate for `localhost` and one with a
certificate for another host name, and runs the contract: methods and
statuses, header merging and deletion, the redirect table, gzip/deflate/raw
deflate through `ContentAsString`, through `AutomaticDecompression` and
through a caller's `TDecompressionStream` over `ContentStream`, charsets and
invalid UTF-8, form posts in UTF-8 and Windows-1251, the body in memory
(`TReceivedBody`: `Memory`/`Size` are the received block itself, writes and
resizes after it, 1 MB and chunked bodies), request bodies of 10 B, 1 MB and
1.5 MB checked by digest, cookies per host, progress and abort, keep-alive,
a connection dropped by the server while idle (GET retried, POST refused),
a POST/PATCH processed before the server disconnects without replying
(no duplicate), a `Content-Length` too long with the server idle or closing and one
too short (no partial body, no repeat, the out-of-step connection dropped;
the server side asserts that a partly answered request is never seen
twice), timeouts of every kind, async completion/cancel/error, TLS
refusal/handler/acceptance and a multipart upload that the server parses with
Python's `email` package. The server records every request, so the Python
side checks what the client sent (form bodies, the absence of `User-Agent`,
the upload, one connection for the keep-alive series). On Linux the run is
repeated with `SSL_CERT_FILE` pointing at the fixture certificate: the
trusted case passes without the handler and the certificate for another host
is refused. See `doc/TESTING.md` for the command lines.
