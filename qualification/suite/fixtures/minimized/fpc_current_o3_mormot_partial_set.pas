program fpc_current_o3_mormot_partial_set;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
{$ifdef unix}
  cthreads,
{$endif}
  mormot.core.base,
  mormot.core.rtti,
  mormot.core.json;

type
  TMyEnum = (enFirst, enTwo, enThree, enFour, enFive);
  TMyEnumPart = enTwo .. enFour;
  TSetMyEnumPart = set of TMyEnumPart;

var
  Text: RawUtf8;
  P: PUtf8Char;
  EndOfObject: AnsiChar;
  Value: QWord;
begin
  Text := '"five,first,two"';
  P := UniqueRawUtf8(Text);
  Value := GetSetNameValue(TypeInfo(TSetMyEnumPart), P, EndOfObject);
  If Value <> 2 then
  begin
    WriteLn('FAIL value=', Value);
    Halt(1);
  end;
  If P = nil then
  begin
    WriteLn('FAIL pointer=nil');
    Halt(1);
  end;
  If P^ <> #0 then
  begin
    WriteLn('FAIL remaining=', Ord(P^));
    Halt(1);
  end;
  If EndOfObject <> #0 then
  begin
    WriteLn('FAIL end=', Ord(EndOfObject));
    Halt(1);
  end;
  WriteLn('PASS value=', Value, ' end=', Ord(EndOfObject));
end.
