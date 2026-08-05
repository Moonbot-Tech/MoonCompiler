{ %CPU=x86_64 }
{ %OPT=-O3 }
program tcheckednegauto1;

{$mode delphi}
{$Q+}

uses
  SysUtils;

function NegateUInt64(Value: UInt64): UInt64;
begin
  Result := -Value;
end;

var
  Seen: Boolean;

begin
  Seen := False;
  try
    NegateUInt64(High(UInt64));
  except
    on EIntOverflow do
      Seen := True;
  end;
  If not Seen then
    Halt(1);
end.
