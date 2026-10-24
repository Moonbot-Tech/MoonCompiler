program unwind_traps;
uses System.SysUtils;
{$L unwind_traps_helper.o}
{$LINKLIB c}
{$LINKLIB dl}
function audit_setup(Lo, Hi: PtrUInt; Negative: Integer): Integer; cdecl; external;
function audit_arm(Address: PtrUInt): Integer; cdecl; external;
function audit_finish: Integer; cdecl; external;
procedure audit_observe(Value:Pointer); cdecl; external;

var
  Sum: Int64;
  Cleanups: Integer;

function AuditLeaf(X: Int64): Int64; cdecl; public name 'AuditLeaf';
var A, B, C, Stored: Int64;
begin
  A := X * 3;
  B := X xor $12345;
  C := A + B;
  Stored := C xor (X shl 2);
  audit_observe(@Stored);
  Result := Stored;
end;

function AuditEH(X: Int64): Int64; cdecl; public name 'AuditEH';
var S: UnicodeString; P0,P1,P2,P3,P4,P5,P6: Int64;
begin
  S := 'managed-' + IntToStr(X);
  try
    P0 := AuditLeaf(X+0);
    P1 := AuditLeaf(X+1);
    P2 := AuditLeaf(X+2);
    P3 := AuditLeaf(X+3);
    P4 := AuditLeaf(X+4);
    P5 := AuditLeaf(X+5);
    P6 := AuditLeaf(X+6);
    Result := AuditLeaf(X) + Length(S);
    If (X=1) and (P0+P1+P2+P3+P4+P5+P6<>522011) then Halt(96);
    If (X=2) and (P0+P1+P2+P3+P4+P5+P6<>522013) then Halt(96);
    If (X=3) and (P0+P1+P2+P3+P4+P5+P6<>522011) then Halt(96);
  finally
    Inc(Cleanups);
    Sum := Sum + Length(S);
  end;
end;

procedure AuditMiddle; cdecl; public name 'AuditMiddle';
begin
  for var I := 1 to 3 do
    Sum := Sum + AuditEH(I);
end;

procedure AuditAnchor; cdecl; public name 'AuditAnchor';
begin
  AuditMiddle;
  Sum := Sum xor $345;
end;

begin
  If audit_setup(StrToQWord(ParamStr(2)), StrToQWord(ParamStr(3)), StrToInt(ParamStr(4))) <> 0 then Halt(92);
  If audit_arm(StrToQWord(ParamStr(1))) <> 0 then Halt(93);
  AuditAnchor;
  If Cleanups <> 3 then Halt(94);
  If Sum <> 223556 then begin
    Writeln('SUM=', Sum);
    Halt(95);
  end;
  Halt(audit_finish);
end.
