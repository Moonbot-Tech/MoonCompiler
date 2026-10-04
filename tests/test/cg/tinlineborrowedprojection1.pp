{ %OPT=-O3 -OoAUTOINLINE }
program tinlineborrowedprojection1;

{$ifdef FPC}{$mode delphiunicode}{$endif}
{$inline on}

type
  TStrings = array of UnicodeString;
  TItem = record
    Text: UnicodeString;
  end;
  TBox = class
    Text: UnicodeString;
    Items: TStrings;
    Item: TItem;
  end;
  PText = ^UnicodeString;

var
  Total: NativeInt;

{ These procedures only borrow a descriptor. Their callers have no managed
  local or result and must not need a cleanup frame to inline the read. }
procedure BorrowField(Box: TBox); inline;
begin
  Inc(Total, Length(Box.Text));
end;

procedure BorrowElement(Box: TBox; Index: NativeInt); inline;
begin
  Inc(Total, Length(Box.Items[Index]));
end;

procedure BorrowPointer(Text: PText); inline;
begin
  Inc(Total, Length(Text^));
end;

procedure BorrowRecord(Box: TBox); inline;
begin
  Inc(Total, Length(Box.Item.Text));
end;

procedure BorrowPlain(const Text: UnicodeString); inline;
begin
  Inc(Total, Length(Text));
end;

procedure FieldShape(Box: TBox); {$ifdef FPC}noinline;{$endif}
begin
  BorrowField(Box);
end;

procedure ElementShape(Box: TBox; Index: NativeInt); {$ifdef FPC}noinline;{$endif}
begin
  BorrowElement(Box, Index);
end;

procedure PointerShape(Text: PText); {$ifdef FPC}noinline;{$endif}
begin
  BorrowPointer(Text);
end;

procedure RecordShape(Box: TBox); {$ifdef FPC}noinline;{$endif}
begin
  BorrowRecord(Box);
end;

procedure PlainShape(const Text: UnicodeString); {$ifdef FPC}noinline;{$endif}
begin
  BorrowPlain(Text);
end;

{ A field/element can instead have an owning expression beneath it. Walking
  through projections must still discover that producer. }
function MakeRecord: TItem; {$ifdef FPC}noinline;{$endif}
begin
  SetLength(Result.Text, 19);
end;

function MakeArray: TStrings; {$ifdef FPC}noinline;{$endif}
begin
  SetLength(Result, 1);
  SetLength(Result[0], 23);
end;

procedure OwnRecord; inline;
begin
  Inc(Total, Length(MakeRecord.Text));
end;

procedure OwnArray; inline;
begin
  Inc(Total, Length(MakeArray[0]));
end;

procedure OwnedShape; {$ifdef FPC}noinline;{$endif}
begin
  OwnRecord;
  OwnArray;
end;

var
  Box: TBox;
begin
  Box := TBox.Create;
  try
    SetLength(Box.Text, 7);
    SetLength(Box.Items, 2);
    SetLength(Box.Items[1], 11);
    SetLength(Box.Item.Text, 13);
    FieldShape(Box);
    ElementShape(Box, 1);
    PointerShape(@Box.Text);
    RecordShape(Box);
    PlainShape(Box.Text);
    If Total <> 45 then
      Halt(1);
    OwnedShape;
    If Total <> 87 then
      Halt(2);
  finally
    Box.Free;
  end;
  WriteLn('INLINE_BORROWED_PROJECTION_OK');
end.
