{ %OPT=-O2 }
program tsetconstbase1;

{$ifdef FPC}
  {$mode delphi}
{$endif}

type
  TSetBase216 = set of 216..255;
  TSetBase208 = set of 208..255;
  TSetBase200 = set of 200..255;
  TSetBase8 = set of 8..63;

const
  SetBase216: TSetBase216 = [216, 223, 224, 239, 247, 255];
  SetBase208: TSetBase208 = [208, 215, 216, 231, 239, 247, 255];
  SetBase200: TSetBase200 = [205, 208, 214, 239, 250];
  SetBase8: TSetBase8 = [8, 15, 16, 31, 47, 63];

procedure CheckBytes(Data: Pointer; const Expected: array of Byte; ExitCode: Integer);
var
  I: Integer;
begin
  for I := 0 to High(Expected) do
    If PByte(Data)[I] <> Expected[I] then
      Halt(ExitCode + I);
end;

begin
  If SizeOf(TSetBase216) <> 8 then
    Halt(1);
  If SizeOf(TSetBase208) <> 8 then
    Halt(2);
  If SizeOf(TSetBase200) <> 8 then
    Halt(3);
  If SizeOf(TSetBase8) <> 8 then
    Halt(4);
  CheckBytes(@SetBase216, [$81, $01, $80, $80, $80, $00, $00, $00], 10);
  CheckBytes(@SetBase208, [$81, $01, $80, $80, $80, $80, $00, $00], 30);
  CheckBytes(@SetBase200, [$20, $41, $00, $00, $80, $00, $04, $00], 50);
  CheckBytes(@SetBase8, [$81, $01, $80, $00, $80, $00, $80, $00], 70);
end.
