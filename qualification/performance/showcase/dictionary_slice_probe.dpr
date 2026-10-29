program dictionary_slice_probe;
{$mode delphiunicode}
{$codepage utf8}
uses {$ifdef UNIX}cthreads,{$endif} SysUtils, Generics.Collections, System.Diagnostics;
const
  KeyCount = 4096;
  Passes = 512;
  ExpectedChecksum: UInt64 = 4296015872;
type
  TQuery = record
    Buffer: UTF8String;
    Text: PAnsiChar;
    Size: SizeInt;
  end;
  TMap = TDictionary<UTF8String, Integer>;
var
  D: TMap;
  Queries: array of TQuery;

function RunCopied: UInt64;
var Pass, I, Value: Integer; Key: UTF8String;
begin
  Result := 0;
  for Pass := 1 to Passes do
    for I := 0 to High(Queries) do begin
      SetString(Key, Queries[I].Text, Queries[I].Size);
      If not D.TryGetValue(Key, Value) then Halt(10);
      Inc(Result, Value);
    end;
end;

function RunSlice: UInt64;
var Pass, I, Value: Integer;
begin
  Result := 0;
  for Pass := 1 to Passes do
    for I := 0 to High(Queries) do begin
      If not D.TryGetValueUtf8(Queries[I].Text, Queries[I].Size, Value) then Halt(11);
      Inc(Result, Value);
    end;
end;

var Key: UTF8String; I, Round, Mode, N: Integer; Started, Elapsed, Checksum: UInt64;
begin
  D := TMap.Create(KeyCount);
  SetLength(Queries, KeyCount);
  for I := 0 to KeyCount - 1 do begin
    Key := UTF8String('ticker-') + UTF8String(IntToStr(I)) + '-USDT';
    D.Add(Key, I + 1);
    Queries[I].Buffer := 'prefix' + Key + 'suffix';
    Queries[I].Text := PAnsiChar(Queries[I].Buffer) + 6;
    Queries[I].Size := Length(Key);
  end;
  for Round := 0 to 5 do
    for N := 0 to 1 do begin
      Mode := (Round + N) and 1;
      Started := TStopwatch.GetTimeStamp;
      If Mode = 0 then Checksum := RunCopied else Checksum := RunSlice;
      Elapsed := System.Round((TStopwatch.GetTimeStamp - Started) * (1000000000.0 / TStopwatch.Frequency));
      If Checksum <> ExpectedChecksum then Halt(12);
      Writeln('round=', Round, ' mode=', Mode, ' nanoseconds=', Elapsed, ' checksum=', Checksum);
    end;
  D.Free;
end.
