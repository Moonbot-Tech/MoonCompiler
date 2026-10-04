program tstringcowfastpath1;

{$mode delphiunicode}
{$R+}{$Q+}

uses
  SysUtils;

type
  TBox = record
    Text: UnicodeString;
  end;
  PBox = ^TBox;
  TStringArray = array of UnicodeString;

var
  Box: TBox;
  BoxCalls,
  IndexCalls,
  CharCalls: Integer;

procedure Fail(Code: Integer);
begin
  Halt(Code);
end;

function GetBox: PBox;
begin
  Inc(BoxCalls);
  Result:=@Box;
end;

function GetIndex: Integer;
begin
  Inc(IndexCalls);
  Result:=2;
end;

function GetChar: WideChar;
begin
  Inc(CharCalls);
  Result:='X';
end;

procedure PutChar(var C: WideChar);
begin
  C:='Y';
end;

function FillUnicode(Count: Integer): UnicodeString; noinline;
var
  I: Integer;
begin
  SetLength(Result,Count);
  for I:=1 to Count do
    Result[I]:=WideChar(65+(I and 15));
end;

function FillAnsi(Count: Integer): AnsiString; noinline;
var
  I: Integer;
begin
  SetLength(Result,Count);
  for I:=1 to Count do
    Result[I]:=AnsiChar(65+(I and 15));
end;

procedure CheckRepeatedCopies;
var
  U,
  OldU: UnicodeString;
  A,
  OldA: UTF8String;
  I,
  Count: Integer;
begin
  for Count:=0 to 128 do
    begin
      SetLength(U,Count);
      for I:=1 to Count do
        U[I]:=WideChar(1000+(I mod 57));
      for I:=1 to Count do
        begin
          OldU:=U;
          U[I]:=WideChar(2000+(I mod 57));
          if OldU[I]<>WideChar(1000+(I mod 57)) then
            Fail(1);
        end;

      SetLength(A,Count);
      for I:=1 to Count do
        A[I]:=AnsiChar(65+(I mod 20));
      for I:=1 to Count do
        begin
          OldA:=A;
          A[I]:=AnsiChar(97+(I mod 20));
          if OldA[I]<>AnsiChar(65+(I mod 20)) then
            Fail(2);
        end;
      if (Count>0) and (StringCodePage(A)<>65001) then
        Fail(3);
    end;
end;

procedure CheckArraySlots;
var
  Items,
  Alias: TStringArray;
  Snapshot: UnicodeString;
begin
  SetLength(Items,1);
  Items[0]:='abcdef';
  Alias:=Items;
  Snapshot:=Items[0];
  Items[0][2]:='Q';
  if Items[0]<>'aQcdef' then
    Fail(4);
  if Alias[0]<>'aQcdef' then
    Fail(5);
  if Snapshot<>'abcdef' then
    Fail(6);
end;

procedure CheckCaptured;
var
  S,
  Snapshot: UnicodeString;

  procedure Change;
  begin
    S[1]:='C';
  end;

begin
  S:='abcdef';
  Snapshot:=S;
  Change;
  if S<>'Cbcdef' then
    Fail(7);
  if Snapshot<>'abcdef' then
    Fail(8);
end;

procedure CheckComplexLValue;
var
  Snapshot: UnicodeString;
begin
  Box.Text:='abcdef';
  Snapshot:=Box.Text;
  GetBox^.Text[GetIndex]:=GetChar;
  if (BoxCalls<>1) or (IndexCalls<>1) or (CharCalls<>1) then
    Fail(9);
  if (Box.Text<>'aXcdef') or (Snapshot<>'abcdef') then
    Fail(10);
  PutChar(GetBox^.Text[GetIndex]);
  if (BoxCalls<>2) or (IndexCalls<>2) or (Box.Text<>'aYcdef') then
    Fail(11);
end;

procedure CheckExceptionPath;
var
  S,
  Snapshot: UnicodeString;
  Raised: Boolean;
begin
  S:='abc';
  Snapshot:=S;
  Raised:=False;
  try
    S[Length(S)+1]:='X';
  except
    on ERangeError do
      Raised:=True;
  end;
  if not Raised or (S<>'abc') or (Snapshot<>'abc') then
    Fail(12);
end;

procedure CheckLiteralAndPublicHelpers;
var
  U,
  OldU: UnicodeString;
  A,
  OldA: UTF8String;
  W,
  OldW: WideString;
begin
  U:='literal';
  OldU:=U;
  U[1]:='L';
  if (U<>'Literal') or (OldU<>'literal') then
    Fail(13);
  UniqueString(U);
  if U<>'Literal' then
    Fail(14);

  A:='literal';
  OldA:=A;
  A[1]:='L';
  if (A<>'Literal') or (OldA<>'literal') then
    Fail(15);
  UniqueString(A);
  if (A<>'Literal') or (StringCodePage(A)<>65001) then
    Fail(16);

  W:='wide';
  OldW:=W;
  W[1]:='W';
  if (W<>'Wide') or (OldW<>'wide') then
    Fail(17);
end;

var
  U: UnicodeString;
  A: AnsiString;
begin
  U:=FillUnicode(128);
  A:=FillAnsi(128);
  if (Length(U)<>128) or (Length(A)<>128) then
    Fail(18);
  CheckRepeatedCopies;
  CheckArraySlots;
  CheckCaptured;
  CheckComplexLValue;
  CheckExceptionPath;
  CheckLiteralAndPublicHelpers;
  WriteLn('STRING_COW_FASTPATH_OK');
end.
