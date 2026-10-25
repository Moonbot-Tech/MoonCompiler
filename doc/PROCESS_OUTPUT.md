# Capturing child-process output

`Process` provides `RunCommand`, `RunCommandInDir` and `TProcess.RunCommandLoop`
on Windows and Linux; the Windows SDK also supplies `ProcessUnicode`. Their output
strings contain decoded text. The child process still writes bytes: UTF-8 characters
may span several pipe reads, and decoding occurs after collection rather than separately per read.

## Text and encoding

`TProcess.OutputCodePage` selects the source encoding for both stdout and stderr.
Its initial value is `DefaultSystemCodePage` when the process object is created:
normally the locale encoding on Linux and the Windows ANSI code page on Windows.
There is no encoding detection, BOM removal or newline normalization. Select the
encoding the child actually produces; console OEM output and UTF-8 output are not
interchangeable. `CP_UTF8` selects UTF-8 explicitly.

```pascal
var P := TProcess.Create(nil);
try
  P.Executable := ProgramName;
  P.Parameters.Add(Argument);
  P.OutputCodePage := CP_UTF8;
  var Text, Errors: string;
  var ChildStatus: Integer;
  If P.RunCommandLoop(Text, Errors, ChildStatus) <> 0 then
    raise Exception.Create('Could not capture command output');
  // ChildStatus is separate from capture success. Inspect it before using Text.
finally
  P.Free;
end;
```

The convenience `RunCommand` functions use `DefaultTProcess`, normally `TProcess`,
and therefore its default encoding. For a different encoding use a configured
`TProcess`, as above. Boolean wrappers return False for an unsuccessful command;
captured output remains available. `RunCommandLoop` returns 0 after successful
capture, with the child's platform exit status in its separate output argument.
A launch/capture failure returns 1; before a child status is obtained that argument
is -1. Existing exception-event callbacks remain available.

## Exact bytes and incremental reads

For binary output use `TProcess.Output` / `Stderr` directly, or
`ReadInputStream(Pipe, DestinationStream, MaxLoops)`. These APIs preserve bytes,
including NUL and invalid text sequences. The stream overload reads the supplied
pipe, so passing `Stderr` does not consume stdout. Partial destination writes are
completed through `WriteBuffer`; if the destination stops accepting bytes, it
raises `EWriteError`. Destination exceptions propagate to the caller. Drain both
channels while the child runs, or use `poStderrToOutput`, to avoid a full pipe blocking the child.

The older `ReadInputStream(Pipe, BytesRead, DataLength, Data, MaxLoops)` overload is
a **byte-buffer API**, even though `Data` has type `string`. In the Unicode SDK,
each element stores one byte value (0..255), not a decoded character. `BytesRead`
counts captured bytes and `DataLength` is the capacity in such elements. The unused
tail is unspecified; `SetLength(Data, BytesRead)` trims it. This representation
preserves byte indexing and existing virtual overrides. It is not a packed byte
array: do not reinterpret its UTF-16 storage as the original byte stream.

`RunCommandLoop` still calls this virtual overload, then decodes the collected
bytes once before its completion/error event. Overrides must preserve the byte
buffer contract. Exact binary consumers should prefer the stream APIs.

The API does not impose a command timeout or output-size policy. Applications that
need bounded execution should use `TProcess` with their own wait/cancellation
policy. This repair does not change process scheduling or termination semantics.
