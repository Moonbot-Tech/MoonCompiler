program unicode_equality_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('UNICODE_EQUALITY_FAIL: '+AMessage);
end;

function ReferenceEqual(const Left, Right: UnicodeString): Boolean;
var
  I: Integer;
begin
  if Length(Left)<>Length(Right) then
    Exit(False);
  for I:=1 to Length(Left) do
    if Left[I]<>Right[I] then
      Exit(False);
  Result:=True;
end;

function Operand(const Value: UnicodeString; var Calls: Integer): UnicodeString;
  noinline;
begin
  Inc(Calls);
  Result:=Value;
end;

procedure CheckPair(const Left, Right: UnicodeString; CaseNo: Integer);
var
  Expected: Boolean;
begin
  Expected:=ReferenceEqual(Left,Right);
  Check((Left=Right)=Expected,'equal case '+IntToStr(CaseNo));
  Check((Left<>Right)=not Expected,'unequal case '+IntToStr(CaseNo));
end;

var
  Left, Right: UnicodeString;
  L, Cases, LeftCalls, RightCalls: Integer;
begin
  Cases:=0;
  Left:='';
  Right:='';
  CheckPair(Left,Right,Cases);
  for L:=1 to 512 do
    begin
    Left:=StringOfChar(WideChar(32+(L mod 90)),L);
    Right:=Left;
    Inc(Cases);
    CheckPair(Left,Right,Cases);

    Right:=Copy(Left,1,Length(Left));
    UniqueString(Right);
    Inc(Cases);
    CheckPair(Left,Right,Cases);

    Right[L]:=WideChar(33+(L mod 89));
    Inc(Cases);
    CheckPair(Left,Right,Cases);

    Right:=Right+#0;
    Inc(Cases);
    CheckPair(Left,Right,Cases);
    end;

  CheckPair('A'+#0+'B','A'+#0+'B',Cases+1);
  CheckPair('A'+#0+'B','A'+#0+'C',Cases+2);

  LeftCalls:=0;
  RightCalls:=0;
  Check(Operand('side',LeftCalls)=Operand('side',RightCalls),
    'side-effect equality');
  Check((LeftCalls=1) and (RightCalls=1),'operand evaluation count');
  WriteLn('UNICODE_EQUALITY_SEMANTIC_PASS');
end.
