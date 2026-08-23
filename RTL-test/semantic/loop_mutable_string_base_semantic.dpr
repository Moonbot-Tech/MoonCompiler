program loop_mutable_string_base_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  SysUtils;

procedure Fail(const Msg: string);
begin
  WriteLn('FAIL ',Msg);
  Halt(1);
end;

var
  U: UnicodeString;
  A: AnsiString;
  D: array of Byte;
  I: Integer;
  Sum: Integer;
begin
  U:='abcdefgh';
  Sum:=0;
  for I:=1 to 8 do
  begin
    Inc(Sum,Ord(U[I]));
    If I=3 then
      U:='ABCDEFGH';
  end;
  If Sum<>644 then
    Fail('UnicodeString reassignment');

  A:='abcdefgh';
  Sum:=0;
  for I:=1 to 8 do
  begin
    Inc(Sum,Ord(A[I]));
    If I=3 then
      A:='ABCDEFGH';
  end;
  If Sum<>644 then
    Fail('AnsiString reassignment');

  SetLength(D,8);
  for I:=0 to High(D) do
    D[I]:=Byte(I+1);
  Sum:=0;
  for I:=0 to High(D) do
  begin
    Inc(Sum,D[I]);
    If I=2 then
    begin
      SetLength(D,12);
      D[3]:=40;
    end;
  end;
  If Sum<>72 then
    Fail('dynamic array reassignment');

  WriteLn('LOOP_MUTABLE_STRING_BASE_OK');
end.
