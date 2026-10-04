{ %OPT=-O3 -OoAUTOINLINE }
program tmoonimplicitopenarray1;
{$mode delphiunicode}
uses SysUtils;
type
  TValue = class(TInterfacedObject)
    destructor Destroy; override;
  end;
var
  Objects: array[0..2] of TValue;
  Destroyed, Caught: Integer;
destructor TValue.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;
procedure Take(A,B,C,D: NativeInt; Values: array of IInterface;
  Text: array of UnicodeString; Fail: Boolean);
var I: Integer;
begin
  if (A+B+C+D<>10) or (Length(Values)<>3) or (Length(Text)<>3) then Halt(1);
  for I:=0 to 2 do
    if Objects[I].RefCount<>2 then Halt(2);
  Values[0]:=nil;
  Text[0]:='changed';
  if Fail then raise Exception.Create('body');
end;
procedure Run;
var
  Values: array[0..2] of IInterface;
  Text: array[0..2] of UnicodeString;
  I: Integer;
begin
  for I:=0 to 2 do
  begin
    Objects[I]:=TValue.Create;
    Values[I]:=Objects[I];
    Text[I]:=IntToStr(I);
  end;
  Take(1,2,3,4,Values,Text,False);
  try
    Take(1,2,3,4,Values,Text,True);
    Halt(3);
  except
    on E: Exception do
      if E.Message='body' then Inc(Caught) else raise;
  end;
  for I:=0 to 2 do
    if (Objects[I].RefCount<>1) or (Text[I]<>IntToStr(I)) then Halt(4);
end;
begin
  Run;
  if (Destroyed<>3) or (Caught<>1) then Halt(5);
  WriteLn('implicit openarray ok');
end.
