program aggregate_sizes;
{$mode delphi}{$inline on}
uses SysUtils, Generics.Collections;

type
  R1 = packed record V: array[0..0] of Byte; end;
  R2 = packed record V: array[0..1] of Byte; end;
  R4 = packed record V: array[0..3] of Byte; end;
  R8 = packed record V: array[0..7] of Byte; end;
  R16 = packed record V: array[0..15] of Byte; end;
  R32 = packed record V: array[0..31] of Byte; end;
  R64 = packed record V: array[0..63] of Byte; end;
  A1 = array[0..0] of Byte;
  A2 = array[0..1] of Byte;
  A4 = array[0..3] of Byte;
  A8 = array[0..7] of Byte;
  A16 = array[0..15] of Byte;
  A32 = array[0..31] of Byte;
  A64 = array[0..63] of Byte;

  TProbe<T> = class
    class function Receiver(L: TList<T>): TList<T>; static;
    class function Fetch(L: TList<T>; K: Integer): T; static; inline;
    class procedure Run; static;
  end;

var Calls, Scenarios: Integer;

function Indexer(K: Integer): Integer;
begin
  Inc(Calls);
  Result := K;
end;

class function TProbe<T>.Receiver(L: TList<T>): TList<T>;
begin
  Inc(Calls);
  Result := L;
end;

class function TProbe<T>.Fetch(L: TList<T>; K: Integer): T;
begin
  Result := Receiver(L).Items[Indexer(K)];
end;

class procedure TProbe<T>.Run;
var
  L: TList<T>;
  R, F: T;
  I, J, K, Before: Integer;
label Again;
begin
  L := TList<T>.Create;
  try
    for I := 0 to 3 do
    begin
      for J := 0 to SizeOf(T) - 1 do
        PByte(@R)[J] := I * SizeOf(T) + J;
      L.Add(R);
    end;
    I := 0;
    Before := Calls;
Again:
    K := I mod 4;
    F := Fetch(L, K);
    for J := 0 to SizeOf(T) - 1 do
      if PByte(@F)[J] <> K * SizeOf(T) + J then Halt(1);
    Inc(I);
    if I < 10000 then goto Again;
    if Calls - Before <> 20000 then Halt(2);
    Inc(Scenarios);
  finally
    L.Free;
  end;
end;

begin
  TProbe<R1>.Run;
  TProbe<R2>.Run;
  TProbe<R4>.Run;
  TProbe<R8>.Run;
  TProbe<R16>.Run;
  TProbe<R32>.Run;
  TProbe<R64>.Run;
  TProbe<A1>.Run;
  TProbe<A2>.Run;
  TProbe<A4>.Run;
  TProbe<A8>.Run;
  TProbe<A16>.Run;
  TProbe<A32>.Run;
  TProbe<A64>.Run;
  Writeln('AGGREGATE_SIZES_PASS ', Scenarios);
end.
