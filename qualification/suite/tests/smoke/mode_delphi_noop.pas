program mode_delphi_noop;

{ Built with the driver's mode switches (-Mdelphi -Municodestrings
  -Minlinevars ...): the unit's own $MODE Delphi is a no-op, so its String is
  the same UnicodeString as ours and its inline variable compiled. }

uses
  mode_delphi_noop_unit;

var
  S: string;
  Bad: Integer;

procedure Check(Cond: Boolean; const What: string);
begin
  If not Cond then begin
    WriteLn('FAIL ', What);
    Inc(Bad);
  end;
end;

begin
  Bad := 0;
  S := 'abc';
  Check(SizeOf(S[1]) = 2, 'program String is UnicodeString');
  Check(CharSize = 2, 'unit String is UnicodeString');
  Check(PCharIsWide(PChar(S)), 'unit PChar is PWideChar');
  Check(InlineVarSum(2, 3) = 5, 'inline variable in the unit');
  Check(Defines = ' FPC_UNICODESTRINGS UNICODE', 'unit defines:' + Defines);
  Check(Passthrough(S) = S, 'string passes without conversion');
  Check(Length(Passthrough('abc' + #$0416)) = 4, 'unit string length');
  If Bad <> 0 then Halt(1);
  WriteLn('MODE_DELPHI_NOOP_OK');
end.
