{ %OPT=-O3 }
program tcheckedincdec1;

{$mode delphi}
{$Q+}
{$R-}

uses
  SysUtils;

var
  RuntimeZero: Int64 = 0;

function IncIntegerRaises: Boolean;
var
  Value: Integer;
begin
  Value := High(Integer) - RuntimeZero;
  try
    Inc(Value);
    Result := False;
  except
    on EIntOverflow do
      Result := True;
  end;
end;

function DecIntegerRaises: Boolean;
var
  Value: Integer;
begin
  Value := Low(Integer) + RuntimeZero;
  try
    Dec(Value);
    Result := False;
  except
    on EIntOverflow do
      Result := True;
  end;
end;

function IncInt64Raises: Boolean;
var
  Value: Int64;
begin
  Value := High(Int64) - RuntimeZero;
  try
    Inc(Value);
    Result := False;
  except
    on EIntOverflow do
      Result := True;
  end;
end;

function IncUInt64Raises: Boolean;
var
  Value: UInt64;
begin
  Value := High(UInt64) - UInt64(RuntimeZero);
  try
    Inc(Value);
    Result := False;
  except
    on EIntOverflow do
      Result := True;
  end;
end;

begin
  If not IncIntegerRaises then Halt(1);
  If not DecIntegerRaises then Halt(2);
  If not IncInt64Raises then Halt(3);
  If not IncUInt64Raises then Halt(4);
end.
