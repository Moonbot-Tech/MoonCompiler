{ %OPT=-O2 }
program tmoonkeynames1;

{$mode delphi}

uses
  Classes;

var
  Values: TStringList;
begin
  Values := TStringList.Create;
  try
    Values.Add('plain');
    Values.Add('key=value');
    if Values.KeyNames[0] <> 'plain' then
      Halt(1);
    if Values.KeyNames[1] <> 'key' then
      Halt(2);
  finally
    Values.Free;
  end;
end.
