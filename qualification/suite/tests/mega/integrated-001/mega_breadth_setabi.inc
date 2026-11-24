{ A full-byte set crosses cdecl by value while the original storage is rewritten through var. }

type
  TBreadthSetTransform = function(Snapshot, Filter: TByteSet; var Live: TByteSet;
    Drop, Add: Byte): TByteSet; cdecl;

function BreadthTransformSet(Snapshot, Filter: TByteSet; var Live: TByteSet; Drop, Add: Byte): TByteSet; cdecl;
begin
  Live := [3, 65, 129, 193, 250];
  Result := Snapshot * Filter;
  Exclude(Result, Drop);
  Include(Result, Add);
end;

procedure RunBreadthByValueSet;
var
  Live, Filter, Answer: TByteSet;
  Transform: TBreadthSetTransform;
  Words: array[0..3] of UInt64;
begin
  Live := [0, 7, 8, 63, 64, 127, 128, 191, 192, 249, 255];
  Filter := [0, 8, 64, 128, 192, 248, 255];
  Transform := BreadthTransformSet;
  Answer := Transform(Live, Filter, Live, Byte(OpaqueI(255)), Byte(OpaqueI(250)));
  Check(SizeOf(TByteSet) = SizeOf(Words), 'breadth-full-byte-set-physical-width');
  Check(Answer = [0, 8, 64, 128, 192, 250], 'breadth-full-byte-set-by-value-retains-before-alias-write');
  Check((Live = [3, 65, 129, 193, 250]) and (Filter = [0, 8, 64, 128, 192, 248, 255]),
    'breadth-full-byte-set-only-var-slot-is-overwritten');
  Move(Answer, Words, SizeOf(Words));
  Check((Words[0] = $101) and (Words[1] = 1) and (Words[2] = 1) and (Words[3] = UInt64($0400000000000001)),
    'breadth-full-byte-set-result-preserves-all-four-payload-words');
  Mix(Words[0] xor Words[3]);
end;
