program widechar_set_membership_semantic;

{$ifdef FPC}
  {$mode delphiunicode}
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
  Calls: Integer;

function CountedWide(Value: Word): WideChar;
begin
  Inc(Calls);
  Result:=WideChar(Value);
end;

var
  I: Integer;
  W: WideChar;
  FourHits: Integer;
  FiveHits: Integer;
  MixedHits: Integer;
  ByteHits: Integer;
  VariableHits: Integer;
  ByteSet: set of AnsiChar;
begin
  FourHits:=0;
  FiveHits:=0;
  MixedHits:=0;
  ByteHits:=0;
  for I:=0 to 1000 do
  begin
    W:=WideChar(I);
    If W in ['a','e','i','o'] then
      Inc(FourHits);
    If W in ['a','e','i','o','u'] then
      Inc(FiveHits);
    If W in ['0'..'9','A'..'F','a'..'f','_','$',#$80..#$ff] then
      Inc(MixedHits);
    If W in [#$80..#$ff] then
      Inc(ByteHits);
  end;
  If (FourHits<>4) or (FiveHits<>5) or (MixedHits<>152) or
     (ByteHits<>128) then
    Fail('constant set matrix');

  Calls:=0;
  If CountedWide($410) in ['a','e','i','o','u'] then
    Fail('wide value falsely mapped through ANSI');
  If Calls<>1 then
    Fail('left operand evaluated more than once');

  ByteSet:=[AnsiChar(#$80)..AnsiChar(#$ff)];
  VariableHits:=0;
  for I:=0 to 1000 do
    If WideChar(I) in ByteSet then
      Inc(VariableHits);
  If VariableHits<>128 then
    Fail('variable byte set');

  WriteLn('WIDECHAR_SET_MEMBERSHIP_OK');
end.
