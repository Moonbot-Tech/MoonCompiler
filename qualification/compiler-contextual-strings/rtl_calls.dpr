program Oracle;
{$APPTYPE CONSOLE}
uses
{$IFDEF UNIX}cwstring,{$ENDIF}
  System.SysUtils, System.StrUtils;

procedure Check(Value: Boolean; const Name: string);
begin
  If not Value then begin
    Writeln('FAIL: ', Name);
    Halt(1);
  end;
end;

procedure Exercise;
var
  U: UnicodeString;
  WideValues: array[0..1] of UnicodeString;
begin
  U:=#$4E2D#$6587;
  Check(not MatchText(U, ['??', 'ab']), 'MatchText must preserve Unicode');
  Check(not MatchStr(U, ['??', 'ab']), 'MatchStr must preserve Unicode');
  Check(IndexText(U, ['??', 'ab'])=-1, 'IndexText must preserve Unicode');
  Check(IndexStr(U, ['??', 'ab'])=-1, 'IndexStr must preserve Unicode');
  Check(MatchText(U, ['ab', #$4E2D#$6587]), 'Unicode literal');
  Check(IndexStr(U, [#$4E2D#$6587, 'ab'])=0, 'Unicode literal first');
  WideValues[0]:='??';
  WideValues[1]:=U;
  Check(IndexText(U, WideValues)=1, 'typed Unicode array');
  Check(not MatchText(U, []), 'empty list');
  Check(IndexStr('', ['', 'ab'])=0, 'empty string');
  Check(MatchText('AB', ['ab', 'cd']), 'case insensitive ASCII');
  Check(not MatchStr('AB', ['ab', 'cd']), 'case sensitive ASCII');
  U:='instrument_discovered';
  Check(MatchText(U, ['instrument_discovered', 'wallet_discovered']), 'reported call');
  Check(IndexStr(U, ['wallet_discovered', 'instrument_discovered'])=1, 'reported index');
end;

var SavedCodePage: TSystemCodePage;
begin
  SavedCodePage:=DefaultSystemCodePage;
  try
    Exercise;
    DefaultSystemCodePage:=1251;
    Exercise;
    DefaultSystemCodePage:=65001;
    Exercise;
  finally
    DefaultSystemCodePage:=SavedCodePage;
  end;
  Writeln('RTL_STRING_OVERLOADS_PASS');
end.
