{ TStringList.Add/AddObject reach InsertItem through the overload of the RTL
  string ABI: the FPC ABI (IDE profile) inserts through InsertItem(Index,S),
  which Lazarus descendants override alone, and sets the object afterwards;
  the Unicode product RTL follows Delphi with one InsertItem(Index,S,O). }
program tstringlistinsertitem;

{$mode objfpc}{$H+}

uses
  Classes;

type
  TProbeList = class(TStringList)
  protected
    Calls: string;
    procedure InsertItem(Index: Integer; const S: string); override;
    procedure InsertItem(Index: Integer; const S: string; O: TObject); override;
  end;

procedure TProbeList.InsertItem(Index: Integer; const S: string);
begin
  Calls := Calls + '2';
  inherited InsertItem(Index, S);
end;

procedure TProbeList.InsertItem(Index: Integer; const S: string; O: TObject);
begin
  Calls := Calls + '3';
  inherited InsertItem(Index, S, O);
end;

procedure Check(Ok: Boolean; Code: Integer);
begin
  if not Ok then
  begin
    Writeln('failed ', Code);
    Halt(Code);
  end;
end;

var
  List: TProbeList;
  Item: TObject;
  Expected: string;
begin
  if SizeOf(List.Strings[0][1]) = 1 then
    Expected := '23'
  else
    Expected := '3';
  Item := TObject.Create;
  List := TProbeList.Create;
  try
    List.Add('plain');
    Check(List.Calls = Expected, 1);
    List.Calls := '';
    List.AddObject('object', Item);
    Check(List.Calls = Expected, 2);
    Check(List.Objects[1] = Item, 3);
    List.Sorted := True;
    List.Calls := '';
    List.AddObject('middle', Item);
    Check(List.Calls = Expected, 4);
    Check((List[1] = 'object') and (List.Objects[1] = Item), 5);
  finally
    List.Free;
    Item.Free;
  end;
  Writeln('ok');
end.
