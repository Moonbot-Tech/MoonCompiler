program fpc_41824_narrow_compare;

{$mode objfpc}{$H+}

uses
  SysUtils;

function ReadByte(const Data: TBytes; var Position: Integer): Byte;
begin
  Result := Data[Position];
  Inc(Position);
end;

function ReadSubLength(const Data: TBytes; var Position: Integer): Integer;
var
  First: Integer;
begin
  First := ReadByte(Data, Position);
  if First < 192 then
    Result := First
  else if First < 255 then
    Result := ((First - 192) shl 8) + ReadByte(Data, Position) + 192
  else
    Result := -1;
end;

var
  Data: TBytes;
  Position, R: Integer;
begin
  SetLength(Data, 2);
  Data[0] := 2;
  Data[1] := 99;
  Position := 0;
  R := ReadSubLength(Data, Position);
  if (R <> 2) or (Position <> 1) then
  begin
    WriteLn('FAIL fpc-41824 value=', R, ' position=', Position);
    Halt(1);
  end;
  WriteLn('PASS fpc-41824');
end.
