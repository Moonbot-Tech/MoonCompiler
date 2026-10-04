{ %OPT=-O3 -OoAUTOINLINE }
program tmoongroupedcase1;
{$mode delphiunicode}
{$Q+}{$R+}
uses SysUtils;
var Reads, Hits: Integer;
function ReadValue(V: Integer): Integer;
begin
  Inc(Reads);
  Result := V;
end;
function Classify(V: Integer): Integer;
begin
  case ReadValue(V) of
    0, 3, 7, 31, 44, 58, 91, 93, 123, 125, 255: Result := 1;
    10..12, 17, 34, 65: Result := 2;
    14, 19, 63, 127, 254: Result := 3;
  else
    Result := 4;
  end;
end;
function Expected(V: Integer): Integer;
begin
  Result := 4;
  if (V=0) or (V=3) or (V=7) or (V=31) or (V=44) or (V=58) or
     (V=91) or (V=93) or (V=123) or (V=125) or (V=255) then Result:=1;
  if ((V>=10) and (V<=12)) or (V=17) or (V=34) or (V=65) then Result:=2;
  if (V=14) or (V=19) or (V=63) or (V=127) or (V=254) then Result:=3;
end;
function WideClassify(V: WideChar): Integer;
begin
  Result := 0;
  case V of
    WideChar(0), WideChar(7), WideChar(44), WideChar(58), WideChar(91),
    WideChar(93), WideChar(123), WideChar(125), WideChar(255): Result := 1;
  end;
end;
procedure Escapes;
var I: Integer;
begin
  for I:=0 to 255 do
    case I of
      3,7,44,58,91,93,123,125,255: Continue;
      34: Exit;
    else
      Inc(Hits);
    end;
end;
var I, E: Integer;
begin
  for I:=-1024 to 65536 do
    if Classify(I)<>Expected(I) then Halt(1);
  if (Classify(Low(Integer))<>4) or (Classify(High(Integer))<>4) then Halt(2);
  if Reads<>66563 then Halt(3);
  for I:=0 to 65535 do
  begin
    E:=0;
    if (I=0) or (I=7) or (I=44) or (I=58) or (I=91) or (I=93) or
       (I=123) or (I=125) or (I=255) then E:=1;
    if WideClassify(WideChar(I))<>E then Halt(4);
  end;
  Escapes;
  if Hits<>32 then Halt(5);
  WriteLn('grouped case ok');
end.
