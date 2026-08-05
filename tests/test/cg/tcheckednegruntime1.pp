{ %CPU=x86_64 }
program tcheckednegruntime1;

{$mode delphi}
{$Q+}

uses
  SysUtils;

function NegateUInt64(Value: UInt64): Int64; noinline;
begin
  Result := -Value;
end;

function NegateInt64(Value: Int64): Int64; noinline;
begin
  Result := -Value;
end;

function NegateUInt128(Value: UInt128): Int128; noinline;
begin
  Result := -Value;
end;

function NegateInt128(Value: Int128): Int128; noinline;
begin
  Result := -Value;
end;

function AboveSignedUInt128: UInt128; noinline;
begin
  Result := UInt128(1) shl 127;
  Inc(Result);
end;

var
  Seen: Integer;

begin
  if NegateUInt64(0) <> 0 then
    Halt(1);

  Seen := 0;
  try
    NegateUInt64(1);
  except
    on EIntOverflow do
      Inc(Seen);
  end;
  try
    NegateUInt64(High(Int64));
  except
    on EIntOverflow do
      Inc(Seen);
  end;
  try
    NegateUInt64(UInt64($8000000000000000));
  except
    on EIntOverflow do
      Inc(Seen);
  end;
  try
    NegateUInt64(UInt64($8000000000000001));
  except
    on EIntOverflow do
      Inc(Seen);
  end;
  try
    NegateUInt64(High(UInt64));
  except
    on EIntOverflow do
      Inc(Seen);
  end;
  try
    NegateInt64(Low(Int64));
  except
    on EIntOverflow do
      Inc(Seen);
  end;
  if Seen <> 6 then
    Halt(2);

  if NegateUInt128(UInt128(1) shl 127) <> Low(Int128) then
    Halt(3);
  if NegateUInt128(UInt128(High(Int128))) <> NegateInt128(High(Int128)) then
    Halt(4);
  if NegateUInt128(0) <> 0 then
    Halt(5);

  Seen := 0;
  try
    NegateUInt128(AboveSignedUInt128);
  except
    on EIntOverflow do
      Inc(Seen);
  end;
  try
    NegateUInt128(High(UInt128));
  except
    on EIntOverflow do
      Inc(Seen);
  end;
  try
    NegateInt128(Low(Int128));
  except
    on EIntOverflow do
      Inc(Seen);
  end;
  if Seen <> 3 then
    Halt(6);
end.
