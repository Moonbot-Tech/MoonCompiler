{ %OPT=-Mdelphi -O2 -dMOONCOMPILER_UNICODE_DEFAULT }
program tmoonunicodestringlist1;

uses
  SysUtils,
  Classes;

type
  TFirstCharStringList = class(TStringList)
  protected
    function DoCompareText(const S1, S2: String): PtrInt; override;
  end;

  TObservedStringList = class(TStringList)
  public
    ChangingCount: Integer;
    ChangedCount: Integer;
  protected
    procedure Changing; override;
    procedure Changed; override;
  end;

function TFirstCharStringList.DoCompareText(const S1, S2: String): PtrInt;
begin
  If (S1 <> '') and (S2 <> '') then
    Result := Ord(S1[1]) - Ord(S2[1])
  else
    Result := Length(S1) - Length(S2);
end;

procedure TObservedStringList.Changing;
begin
  Inc(ChangingCount);
  inherited Changing;
end;

procedure TObservedStringList.Changed;
begin
  Inc(ChangedCount);
  inherited Changed;
end;

procedure Check(Condition: Boolean; Code: Byte);
begin
  If not Condition then
    Halt(Code);
end;

procedure CheckPlainList;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.Add('alpha');
    List.Add(UnicodeString(#$0411#$0435#$0442#$0430));
    List.Add('omega');
    Check(List.IndexOf(UnicodeString(#$0411#$0435#$0442#$0430)) = 1, 1);
    Check(List.IndexOf('missing') = -1, 2);
    List.CaseSensitive := False;
    Check(List.IndexOf('ALPHA') = 0, 3);
    List.CaseSensitive := True;
    Check(List.IndexOf('ALPHA') = -1, 4);
  finally
    List.Free;
  end;
end;

procedure CheckSortedList;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.Sorted := True;
    List.Add('gamma');
    List.Add('alpha');
    List.Add('beta');
    Check(List.IndexOf('alpha') = 0, 5);
    Check(List.IndexOf('beta') = 1, 6);
    Check(List.IndexOf('delta') = -1, 7);
  finally
    List.Free;
  end;
end;

procedure CheckOverriddenComparison;
var
  List: TFirstCharStringList;
begin
  List := TFirstCharStringList.Create;
  try
    List.Add('a');
    List.Add('b-long');
    Check(List.IndexOf('another-length') = 0, 8);
    Check(List.IndexOf('b') = 1, 9);
  finally
    List.Free;
  end;
end;

procedure CheckAddNotifications;
var
  Item: TObject;
  List: TObservedStringList;
begin
  List := TObservedStringList.Create;
  try
    List.Add('plain');
    Check((List.ChangingCount = 1) and (List.ChangedCount = 1), 10);

    Item := TObject.Create;
    List.AddObject('object', Item);
    Check(List.Objects[1] = Item, 11);
    Check((List.ChangingCount = 2) and (List.ChangedCount = 2), 12);
  finally
    List.Objects[1].Free;
    List.Free;
  end;
end;

begin
  CheckPlainList;
  CheckSortedList;
  CheckOverriddenComparison;
  CheckAddNotifications;
end.
