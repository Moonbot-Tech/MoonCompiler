program tdelphiolevariantint641;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
{$ifdef FPC}
  SysUtils,
  Variants;
{$else}
  System.SysUtils,
  System.Variants;
{$endif}

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

var
  O: OleVariant;
  U: UInt64;
  I: Int64;
begin
  O := '18446744073709551615';
  U := O;
  Check(U = High(UInt64), 1);

  O := '-9223372036854775808';
  I := O;
  Check(I = Low(Int64), 2);

  O := '42';
  U := O;
  Check(U = 42, 3);

  O := '-42';
  I := O;
  Check(I = -42, 4);
end.
