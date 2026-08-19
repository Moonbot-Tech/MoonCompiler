program string_helper_facades_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{ Semantic pin for the TStringHelper facade repairs (syshelps.inc):
  Split takes a two-pass exact-allocation path for unquoted character
  separators, IndexOf routes full-tail searches through Pos, and the
  IgnoreCase facades of StartsWith/EndsWith/Contains compare in place
  with the ASCII fold instead of building temporaries.  Pins the edge
  behaviour of all rewritten paths: an empty source, empty fields,
  leading/trailing and doubled separators, ExcludeEmpty, ACount limits, the quoted path,
  fold class limited to ASCII, and IndexOf window clamping. }

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$endif}
  SysUtils;

procedure Fail(const AWhere: string);
begin
  WriteLn('FAIL: ', AWhere);
  Halt(1);
end;

procedure CheckSplit;
var
  S: UnicodeString;
  P: TArray<UnicodeString>;
begin
  S := 'a,b,c';
  P := S.Split([WideChar(',')]);
  If (Length(P) <> 3) or (P[0] <> 'a') or (P[1] <> 'b') or (P[2] <> 'c') then
    Fail('split plain');

  S := ',a,,b,';
  P := S.Split([WideChar(',')]);
  If (Length(P) <> 5) or (P[0] <> '') or (P[1] <> 'a') or (P[2] <> '') or
     (P[3] <> 'b') or (P[4] <> '') then
    Fail('split empties kept');

  P := S.Split([WideChar(',')], TStringSplitOptions.ExcludeEmpty);
  If (Length(P) <> 2) or (P[0] <> 'a') or (P[1] <> 'b') then
    Fail('split ExcludeEmpty');

  S := 'x;y,z';
  P := S.Split([WideChar(','), WideChar(';')]);
  If (Length(P) <> 3) or (P[0] <> 'x') or (P[1] <> 'y') or (P[2] <> 'z') then
    Fail('split two separators');

  S := 'a,b,c,d';
  P := S.Split([WideChar(',')], 2);
  If (Length(P) <> 2) or (P[0] <> 'a') or (P[1] <> 'b') then
    Fail('split ACount limit');

  S := '';
  P := S.Split([WideChar(',')]);
  If Length(P) <> 0 then
    Fail('split empty source');

  S := 'no-separators';
  P := S.Split([WideChar(',')]);
  If (Length(P) <> 1) or (P[0] <> 'no-separators') then
    Fail('split no hit');

  { quoted path keeps the old engine }
  S := 'a,"b,c",d';
  P := S.Split([WideChar(',')], WideChar('"'));
  If (Length(P) <> 3) or (P[0] <> 'a') or (P[1] <> '"b,c"') or (P[2] <> 'd') then
    Fail('split quoted');
end;

procedure CheckIndexOf;
var
  S: UnicodeString;
begin
  S := 'market-needle-market';
  If S.IndexOf(UnicodeString('needle')) <> 7 then
    Fail('indexof basic');
  If S.IndexOf(UnicodeString('absent')) <> -1 then
    Fail('indexof missing');
  If S.IndexOf(UnicodeString('market'), 1) <> 14 then
    Fail('indexof from start');
  If S.IndexOf(UnicodeString('market'), 14) <> 14 then
    Fail('indexof at limit');
  If S.IndexOf(UnicodeString('market'), 15) <> -1 then
    Fail('indexof past');
  If S.IndexOf(UnicodeString('')) <> -1 then
    Fail('indexof empty needle');
  If S.IndexOf(UnicodeString('needle'), -5) <> 7 then
    Fail('indexof negative start');
  { windowed search keeps the generic engine }
  If S.IndexOf(UnicodeString('needle'), 0, 12) <> -1 then
    Fail('indexof window too small');
  If S.IndexOf(UnicodeString('needle'), 0, 13) <> 7 then
    Fail('indexof window exact');
end;

procedure CheckNoCase;
var
  S: UnicodeString;
begin
  S := 'Key-10042';
  If not S.StartsWith(UnicodeString('KEY-'), True) then
    Fail('startswith nocase hit');
  If S.StartsWith(UnicodeString('KEZ-'), True) then
    Fail('startswith nocase miss');
  If not S.StartsWith(UnicodeString(''), True) then
    Fail('startswith empty');
  If S.StartsWith(UnicodeString('Key-10042-longer'), True) then
    Fail('startswith longer than self');
  If not S.EndsWith(UnicodeString('0042'), True) then
    Fail('endswith nocase hit');
  If S.EndsWith(UnicodeString('0043'), True) then
    Fail('endswith nocase miss');
  If not S.Contains(UnicodeString('EY-1'), True) then
    Fail('contains nocase hit');
  If S.Contains(UnicodeString('EY+1'), True) then
    Fail('contains nocase miss');
  If S.Contains(UnicodeString(''), True) then
    Fail('contains empty needle');
  { the fold class is ASCII only - non-ASCII case pairs stay distinct,
    exactly like the Pos(LowerCase,LowerCase) engine before }
  S := UnicodeString('caf') + WideChar($00C9); { CAFE with U+00C9 }
  If S.Contains(UnicodeString('caf') + WideChar($00E9), True) then
    Fail('contains non-ascii fold');
  If not S.EndsWith(UnicodeString('af') + WideChar($00C9), True) then
    Fail('endswith non-ascii exact');
end;

begin
  CheckSplit;
  CheckIndexOf;
  CheckNoCase;
  WriteLn('STRING_HELPER_FACADES_PASS');
end.
