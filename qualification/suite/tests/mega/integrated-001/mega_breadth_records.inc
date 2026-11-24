{ Packed ordinal fields at an indirect ABI boundary and advanced record construction. }

{$Z1}
type
  TBreadthSmallEnum = (beMiddle = 7, beLast = 200);
{$Z4}
type
  TBreadthWideEnum = (beLow = 1, beHigh = 300);
{$Z1}
type
  TBreadthPackedEnums = packed record
    Head: Byte;
    Small: TBreadthSmallEnum;
    Wide: TBreadthWideEnum;
    Tail: Word;
  end;
  TBreadthPackedEnumEdit = function(Value: TBreadthPackedEnums; Mask: Word): TBreadthPackedEnums; cdecl;

function BreadthEditPackedEnums(Value: TBreadthPackedEnums; Mask: Word): TBreadthPackedEnums; cdecl;
begin
  Result.Head := Value.Head xor $40;
  If Value.Small = beLast then
    Result.Wide := beLow
  else
    Result.Wide := beHigh;
  If Value.Wide = beHigh then
    Result.Small := beMiddle
  else
    Result.Small := beLast;
  Result.Tail := Value.Tail xor Mask;
end;

procedure RunBreadthPackedEnums;
var
  Source, Edited: TBreadthPackedEnums;
  Edit: TBreadthPackedEnumEdit;
  SourceBits, EditedBits: UInt64;
begin
  Check(SizeOf(TBreadthPackedEnums) = 8, 'breadth-packed-enum-mixed-width-size');
  Source.Head := Byte(OpaqueI($BC));
  Source.Small := TBreadthSmallEnum(OpaqueI(Ord(beLast)));
  Source.Wide := TBreadthWideEnum(OpaqueI(Ord(beHigh)));
  Source.Tail := Word(OpaqueI($F32A));
  Edit := BreadthEditPackedEnums;
  Edited := Edit(Source, Word(OpaqueI($A117)));
  Move(Source, SourceBits, SizeOf(SourceBits));
  Move(Edited, EditedBits, SizeOf(EditedBits));
  Check(SourceBits = UInt64($F32A0000012CC8BC), 'breadth-packed-enum-source-bits');
  Check(EditedBits = UInt64($523D0000000107FC), 'breadth-packed-enum-edited-abi-bits');
  Edited := Edit(Edited, Word(OpaqueI($A117)));
  Move(Edited, EditedBits, SizeOf(EditedBits));
  Check(EditedBits = UInt64($F32A0000012CC8BC), 'breadth-packed-enum-second-dispatch');
  Mix(EditedBits);
end;

type
  TBreadthConstructedPacket = record
    Owner: IInterface;
    Text: AnsiString;
    Number: Int64;
    constructor Create(Value: Int64; Reject: Boolean);
  end;

constructor TBreadthConstructedPacket.Create(Value: Int64; Reject: Boolean);
begin
  Owner := TIntersectionOwner.Create;
  Text := AnsiString(IntToStr(Value));
  Number := Value * 3;
  If Reject then
    raise EAbort.Create('record constructor');
end;

procedure BreadthStagePacket(var Dest: TBreadthConstructedPacket; Value: Int64; Reject: Boolean);
var
  Pending: TBreadthConstructedPacket;
begin
  Pending := TBreadthConstructedPacket.Create(Value, Reject);
  Dest := Pending;
end;

procedure BreadthCheckPacketScope;
var
  Dest: TBreadthConstructedPacket;
  Caught: Boolean;
begin
  BreadthStagePacket(Dest, OpaqueI(19), False);
  Check((Dest.Number = 57) and (Dest.Text = '19') and (Dest.Owner <> nil),
    'breadth-record-constructor-fills-managed-destination');
  Caught := False;
  try
    BreadthStagePacket(Dest, OpaqueI(-107), True);
  except
    on E: EAbort do Caught := E.Message = 'record constructor';
  end;
  Check(Caught and (Dest.Number = 57) and (Dest.Text = '19') and (Dest.Owner <> nil),
    'breadth-record-constructor-failure-keeps-earlier-packet');
  BreadthStagePacket(Dest, OpaqueI(41), False);
  Check((Dest.Number = 123) and (Dest.Text = '41') and (Dest.Owner <> nil),
    'breadth-record-constructor-success-replaces-earlier-packet');
end;

procedure RunBreadthRecordConstructor;
begin
  TIntersectionOwner.Destroyed := 0;
  BreadthCheckPacketScope;
  Check(TIntersectionOwner.Destroyed = 3, 'breadth-record-constructor-scope-releases-three-owners');
  Mix(UInt64(TIntersectionOwner.Destroyed));
end;
