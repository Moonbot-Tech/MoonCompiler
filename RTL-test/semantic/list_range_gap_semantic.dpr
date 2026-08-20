program list_range_gap_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{ Semantic pin for the DeleteRange/InsertRange dead-clear removal: list
  contents after every range operation must match a hand-built oracle for
  unmanaged and managed elements, the notification path must still see
  every element, and managed elements must survive delete/insert cycles
  without corruption. }

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  SysUtils, Classes, Generics.Collections;

procedure Fail(const Msg: string);
begin
  WriteLn('FAIL ', Msg);
  Halt(1);
end;

type
  TNotifyList = class(TList<Integer>)
  public
    NotifyCount: Integer;
  protected
    procedure Notify(const Item: Integer; Action: TCollectionNotification); override;
  end;

procedure TNotifyList.Notify(const Item: Integer; Action: TCollectionNotification);
begin
  inherited Notify(Item, Action);
  Inc(NotifyCount);
end;

var
  Ints: TList<Integer>;
  Strs: TList<UnicodeString>;
  NotifyList: TNotifyList;
  Middle: array of Integer;
  StrsMiddle: array of UnicodeString;
  Expected: array of Integer;
  I, J: Integer;
  S: UnicodeString;
begin
  { unmanaged: delete/insert ranges at head, middle and tail }
  Ints := TList<Integer>.Create;
  try
    for I := 0 to 63 do
      Ints.Add(I);
    SetLength(Middle, 16);
    for I := 0 to 15 do
      Middle[I] := 1000 + I;

    Ints.DeleteRange(16, 16);          { removes 16..31 }
    Ints.InsertRange(16, Middle);      { inserts 1000..1015 }
    Ints.DeleteRange(0, 4);            { removes 0..3 }
    Ints.DeleteRange(Ints.Count - 4, 4); { removes tail 60..63 }
    Ints.InsertRange(0, [-1, -2]);
    Ints.InsertRange(Ints.Count, [777]);

    SetLength(Expected, 0);
    Expected := [-1, -2];
    for I := 4 to 15 do
      Expected := Expected + [I];
    for I := 0 to 15 do
      Expected := Expected + [1000 + I];
    for I := 32 to 59 do
      Expected := Expected + [I];
    Expected := Expected + [777];

    If Ints.Count <> Length(Expected) then
      Fail(Format('int count %d <> %d', [Ints.Count, Length(Expected)]));
    for I := 0 to Ints.Count - 1 do
      If Ints[I] <> Expected[I] then
        Fail(Format('int mismatch at %d: %d <> %d', [I, Ints[I], Expected[I]]));

    { delete everything }
    Ints.DeleteRange(0, Ints.Count);
    If Ints.Count <> 0 then
      Fail('delete-all count');
    Ints.InsertRange(0, [5, 6, 7]);
    If (Ints.Count <> 3) or (Ints[0] <> 5) or (Ints[2] <> 7) then
      Fail('insert into emptied list');
  finally
    FreeAndNil(Ints);
  end;

  { managed elements: values and lifetimes across delete/insert cycles }
  Strs := TList<UnicodeString>.Create;
  try
    for I := 0 to 31 do
      Strs.Add('item-' + IntToStr(I));
    SetLength(StrsMiddle, 8);
    for I := 0 to 7 do
      StrsMiddle[I] := 'mid-' + IntToStr(I);

    for J := 1 to 50 do
    begin
      Strs.DeleteRange(8, 8);
      Strs.InsertRange(8, StrsMiddle);
    end;

    If Strs.Count <> 32 then
      Fail('string count');
    for I := 0 to 7 do
      If Strs[I] <> 'item-' + IntToStr(I) then
        Fail('string head at ' + IntToStr(I));
    for I := 0 to 7 do
      If Strs[8 + I] <> 'mid-' + IntToStr(I) then
        Fail('string middle at ' + IntToStr(I));
    for I := 16 to 31 do
      If Strs[I] <> 'item-' + IntToStr(I) then
        Fail('string tail at ' + IntToStr(I));
    { force each string to prove its heap block is alive }
    for I := 0 to Strs.Count - 1 do
    begin
      S := Strs[I] + '';
      If Length(S) < 5 then
        Fail('string content');
    end;
  finally
    FreeAndNil(Strs);
  end;

  { descendant with Notify override must still see every removed and
    added element (the fast path is only for exact TList<T>) }
  NotifyList := TNotifyList.Create;
  try
    NotifyList.NotifyCount := 0;
    for I := 0 to 15 do
      NotifyList.Add(I);       { 16 adds }
    NotifyList.DeleteRange(4, 8);  { 8 removes }
    NotifyList.InsertRange(4, [70, 71]); { 2 adds }
    If NotifyList.NotifyCount <> 16 + 8 + 2 then
      Fail(Format('notify count %d', [NotifyList.NotifyCount]));
    If (NotifyList.Count <> 10) or (NotifyList[4] <> 70) or
       (NotifyList[5] <> 71) or (NotifyList[6] <> 12) then
      Fail('notify list contents');
  finally
    FreeAndNil(NotifyList);
  end;

  WriteLn('LIST_RANGE_GAP_OK');
end.
