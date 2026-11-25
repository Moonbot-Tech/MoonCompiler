program regex_split_boundary_semantic;
{$ifdef FPC}{$mode delphiunicode}{$endif}
{$apptype console}
uses SysUtils, System.RegularExpressions;

procedure Check(const Text, Pattern: UnicodeString; Count, Start: Integer; const Expected: array of UnicodeString; AllowEmpty: Boolean=False);
var R: TRegEx; A: TArray<string>; I: Integer;
begin
  if AllowEmpty then R:=TRegEx.Create(Pattern,[]) else R:=TRegEx.Create(Pattern);
  A:=R.Split(Text,Count,Start);
  if Length(A)<>Length(Expected) then begin WriteLn('FAIL split count ',Start, ' ',Length(A)); Halt(1) end;
  for I:=0 to High(A) do
    if A[I]<>Expected[I] then begin WriteLn('FAIL split field ',I); Halt(2) end;
end;

begin
  Check('|A|B|','\|',0,1,['','A','B','']);
  Check('H|a|b|','\|',0,4,['H|a','b','']);
  Check('||A|','\|',0,1,['','','A','']);
  Check('x|y','(\|)',0,2,['x','|','y']);
  Check('A'+#$03BB+'B'+#$03BB,#$03BB,0,2,['A','B','']);
  Check('|A|B|','\|',1,1,['|A|B|']);
  Check('|A|B|','\|',2,1,['','A|B|']);
  Check('0|1|2|3|4|','\|',2,4,['0|1','2','3','4','']);
  Check('0|1|2|3|4|','\|',3,4,['0|1','2','3|4|']);
  Check('H|A|B|','(\|)',3,2,['H','|','A','|','B|']);
  Check('ABC','^',0,1,['ABC']);
  Check('ABC','(?=B)',0,2,['ABC']);
  Check('ABC','(?=B)',0,1,['A','BC'],True);
{$ifdef FPC}
  { With empty matches enabled, Moon ignores an empty match exactly at StartPos. }
  Check('ABC','(?=B)',0,2,['ABC'],True);
{$endif}
  Check('ABC','\|',0,1,['ABC']);
  WriteLn('REGEX_SPLIT_BOUNDARY_PASS');
end.
