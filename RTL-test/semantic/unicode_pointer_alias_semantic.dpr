program unicode_pointer_alias_semantic;
{$IFDEF FPC}{$mode delphi}{$ENDIF}
uses SysUtils;
type
  TProbe = class
    class function ReadChar(P: PChar): Char; static;
  end;
class function TProbe.ReadChar(P: PWideChar): WideChar;
begin
  Result := P^;
end;
var
  A: AnsiString;
  W: UnicodeString;
  P: PChar;
begin
  W := 'x' + WideChar($0430) + 'z';
  P := PChar(W);
  If TProbe.ReadChar(P) <> 'x' then Halt(11);
  If AnsiStrScan(P, WideChar($0430)) <> P + 1 then Halt(12);
  If AnsiStrScan(P, WideChar(0)) <> P + 3 then Halt(13);
  If AnsiStrScan(P, 'q') <> nil then Halt(14);
  A := 'xyz';
  If AnsiStrScan(PAnsiChar(A), AnsiChar('y')) <> PAnsiChar(A) + 1 then Halt(15);
  If AnsiStrScan(PAnsiChar(A), AnsiChar('q')) <> nil then Halt(16);
  WriteLn('UNICODE_POINTER_ALIAS_SEMANTIC_PASS');
end.
