program stringlist_object_contract;
{$mode objfpc}{$H+}

uses Classes, SysUtils;

type
  TObservedList = class(TStringList)
  public
    ExpectedObject: TObject;
    UnicodeProfile: Boolean;
    Changes, Inserts: Integer;
    procedure InsertItem(Index: Integer; const S: string; O: TObject); override;
    procedure ObserveChange(Sender: TObject);
  end;

procedure Check(Condition: Boolean; const Message: string);
begin
  if not Condition then
    raise Exception.Create(Message);
end;

procedure TObservedList.InsertItem(Index: Integer; const S: string; O: TObject);
begin
  Inc(Inserts);
  if UnicodeProfile then
    Check(O = ExpectedObject, 'Delphi override must receive the object during insertion')
  else
    Check(O = nil, 'FPC inserts the string before assigning the object');
  inherited InsertItem(Index, S, O);
end;

procedure TObservedList.ObserveChange(Sender: TObject);
begin
  Inc(Changes);
  Check(Objects[IndexOf('entry')] = ExpectedObject, 'OnChange observed an incomplete insertion');
end;

var
  List: TObservedList;
  Item: TObject;
  SortedCase: Boolean;
begin
  Item := TObject.Create;
  try
    for SortedCase := False to True do begin
      List := TObservedList.Create;
      try
        List.UnicodeProfile := SizeOf(List.Strings[0][1]) = 2;
        {$ifdef TEST_IDE_PROFILE}
        Check(not List.UnicodeProfile, 'IDE gate selected the Unicode RTL');
        {$else}
        Check(List.UnicodeProfile, 'Product gate selected the FPC RTL');
        {$endif}
        List.ExpectedObject := Item;
        List.Sorted := SortedCase;
        List.Duplicates := dupIgnore;
        List.OnChange := @List.ObserveChange;
        List.AddObject('entry', Item);
        Check((List.Changes = 1) and (List.Inserts = 1), 'Insertion must notify exactly once');
        Check((List.Count = 1) and (List.Objects[0] = Item), 'Object association lost');
        if SortedCase then begin
          List.AddObject('entry', nil);
          Check((List.Count = 1) and (List.Objects[0] = Item), 'Ignored duplicate changed the object');
          Check((List.Changes = 1) and (List.Inserts = 1), 'Ignored duplicate invoked insertion');
        end;
      finally
        List.Free;
      end;
    end;
  finally
    Item.Free;
  end;
  WriteLn('STRINGLIST_OBJECT_CONTRACT_PASS');
end.
