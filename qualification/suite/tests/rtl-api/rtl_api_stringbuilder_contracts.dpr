program rtl_api_stringbuilder_contracts;

{$APPTYPE CONSOLE}

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch inlinevars}
{$endif}

uses
  SysUtils;

procedure Check(ACondition: Boolean; const AName: string);
begin
  if not ACondition then
    begin
      WriteLn('FAIL ',AName);
      Halt(1);
    end;
end;

function ReferenceReplace(const S,OldValue,NewValue: string;
  StartIndex,Count: Integer): string;
var
  Cursor,Finish: Integer;
begin
  Result:=Copy(S,1,StartIndex);
  Cursor:=StartIndex+1;
  Finish:=StartIndex+Count;
  while Cursor<=Finish do
    if (Cursor+Length(OldValue)-1<=Finish) and
       (Copy(S,Cursor,Length(OldValue))=OldValue) then
      begin
        Result:=Result+NewValue;
        Inc(Cursor,Length(OldValue));
      end
    else
      begin
        Result:=Result+S[Cursor];
        Inc(Cursor);
      end;
  Result:=Result+Copy(S,Finish+1,Length(S)-Finish);
end;

procedure CheckReplace(const Name,S,OldValue,NewValue: string;
  StartIndex,Count: Integer);
var
  Builder: TStringBuilder;
  Expected: string;
begin
  Expected:=ReferenceReplace(S,OldValue,NewValue,StartIndex,Count);
  Builder:=TStringBuilder.Create(S);
  try
    Builder.Replace(OldValue,NewValue,StartIndex,Count);
    Check(Builder.ToString=Expected,'unicode-replace-'+Name);
  finally
    Builder.Free;
  end;
end;

procedure CheckUnicodeReplace;
begin
  CheckReplace('match-crosses-right','aabb','bb','X',2,1);
  CheckReplace('match-longer-than-slice','abcd','ab','X',0,1);
  CheckReplace('same-size','aaaa','aa','XX',1,2);
  CheckReplace('grow','aaaa','aa','XYZ',1,2);
  CheckReplace('shrink','zaaaaaz','aa','a',1,3);
  CheckReplace('delete','zaaaaaz','aa','',1,4);
  CheckReplace('repeat-grow','zzbczzedeafzz','e','qqqq',6,3);
  CheckReplace('empty-slice','zaaaaaz','aa','X',1,0);
  CheckReplace('old-longer-than-text','abc','abcd','X',0,3);
  CheckReplace('embedded-nul-mismatch','a'+#0+'b','a'+#0+'x','Q',0,3);
  CheckReplace('embedded-nul-match','a'+#0+'b','a'+#0+'b','Q',0,3);
end;

procedure CheckUnicodeEnumerator;
var
  Builder: TStringBuilder;
  Enumerated: string;
begin
  Builder:=TStringBuilder.Create('abc');
  try
    var Enumerator:=Builder.GetEnumerator;
    Check(Enumerator.MoveNext,'unicode-enumerator-first');
    Check(Enumerator.Current='a','unicode-enumerator-current');
    Check(Enumerator.Current='a','unicode-enumerator-current-repeat');
    Check(Enumerator.MoveNext,'unicode-enumerator-second');
    Check(Enumerator.Current='b','unicode-enumerator-second-current');
    Check(Enumerator.MoveNext,'unicode-enumerator-third');
    Check(Enumerator.Current='c','unicode-enumerator-third-current');
    Check(not Enumerator.MoveNext,'unicode-enumerator-end');
    Check(not Enumerator.MoveNext,'unicode-enumerator-end-repeat');

    var Skipped:=Builder.GetEnumerator;
    Check(Skipped.MoveNext,'unicode-enumerator-skipped-first');
    Check(Skipped.MoveNext,'unicode-enumerator-skipped-second');
    Check(Skipped.Current='b','unicode-enumerator-skipped-current');

    Enumerated:='';
    for var C in Builder do
      Enumerated:=Enumerated+C;
    Check(Enumerated='abc','unicode-enumerator-for-in');

    Builder.Clear;
    var Empty:=Builder.GetEnumerator;
    Check(not Empty.MoveNext,'unicode-enumerator-empty');
  finally
    Builder.Free;
  end;
end;

{$ifdef FPC}
function ReferenceAnsiReplace(const S,OldValue,NewValue: AnsiString;
  StartIndex,Count: Integer): AnsiString;
var
  Cursor,Finish: Integer;
begin
  Result:=Copy(S,1,StartIndex);
  Cursor:=StartIndex+1;
  Finish:=StartIndex+Count;
  while Cursor<=Finish do
    if (Cursor+Length(OldValue)-1<=Finish) and
       (Copy(S,Cursor,Length(OldValue))=OldValue) then
      begin
        Result:=Result+NewValue;
        Inc(Cursor,Length(OldValue));
      end
    else
      begin
        Result:=Result+S[Cursor];
        Inc(Cursor);
      end;
  Result:=Result+Copy(S,Finish+1,Length(S)-Finish);
end;

procedure CheckAnsiReplace;
var
  Actual,Expected,S,Enumerated: AnsiString;
  Builder: TAnsiStringBuilder;
  procedure CheckCase(const Name,Source,OldValue,NewValue: AnsiString;
    StartIndex,Count: Integer);
  begin
    Expected:=ReferenceAnsiReplace(Source,OldValue,NewValue,StartIndex,Count);
    Builder:=TAnsiStringBuilder.Create(Source);
    try
      Builder.Replace(OldValue,NewValue,StartIndex,Count);
      Check(Builder.ToString=Expected,'ansi-replace-'+Name);
    finally
      Builder.Free;
    end;
  end;
begin
  S:='a'+#0+'b';
  Expected:=ReferenceAnsiReplace(S,'a'+#0+'x','Q',0,3);
  Builder:=TAnsiStringBuilder.Create(S);
  try
    Builder.Replace('a'+#0+'x','Q',0,3);
    Actual:=Builder.ToString;
    Check(Actual=Expected,'ansi-replace-embedded-nul-mismatch');
  finally
    Builder.Free;
  end;

  CheckCase('same-size','aaaa','aa','XX',1,2);
  CheckCase('grow','aaaa','aa','XYZ',1,2);
  CheckCase('shrink','zaaaaaz','aa','a',1,3);
  CheckCase('delete','zaaaaaz','aa','',1,4);
  CheckCase('old-longer-than-slice','abcd','ab','X',0,1);

  Builder:=TAnsiStringBuilder.Create('aabb');
  try
    Builder.Replace('bb','X',2,1);
    Check(Builder.ToString='aabb','ansi-replace-slice');

    var Enumerator:=Builder.GetEnumerator;
    Check(Enumerator.MoveNext,'ansi-enumerator-first');
    Check(Enumerator.Current='a','ansi-enumerator-current');
    Check(Enumerator.Current='a','ansi-enumerator-current-repeat');
    Check(Enumerator.MoveNext,'ansi-enumerator-second');
    Check(Enumerator.Current='a','ansi-enumerator-second-current');

    var Skipped:=Builder.GetEnumerator;
    Check(Skipped.MoveNext,'ansi-enumerator-skipped-first');
    Check(Skipped.MoveNext,'ansi-enumerator-skipped-second');
    Check(Skipped.Current='a','ansi-enumerator-skipped-current');

    Enumerated:='';
    for var C in Builder do
      Enumerated:=Enumerated+C;
    Check(Enumerated='aabb','ansi-enumerator-for-in');
  finally
    Builder.Free;
  end;
end;
{$endif}

begin
  CheckUnicodeReplace;
  CheckUnicodeEnumerator;
  {$ifdef FPC}
  CheckAnsiReplace;
  {$endif}
  WriteLn('RTL_API_STRINGBUILDER_CONTRACTS_OK');
end.
