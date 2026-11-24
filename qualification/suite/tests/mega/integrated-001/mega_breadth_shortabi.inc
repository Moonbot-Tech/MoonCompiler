{ A by-value packed record cannot observe edits through a var alias to its short-string field. }

type
  TBreadthWireName = string[5];
  TBreadthWireFrame = packed record
    Prefix: Byte;
    Name: TBreadthWireName;
    Code: Cardinal;
  end;
  TBreadthWireTransform = function(Frame: TBreadthWireFrame; var ExternalName: TBreadthWireName;
    Salt: Cardinal): TBreadthWireFrame; cdecl;

function BreadthTransformWire(Frame: TBreadthWireFrame; var ExternalName: TBreadthWireName;
  Salt: Cardinal): TBreadthWireFrame; cdecl;
begin
  ExternalName := 'reset';
  Result.Prefix := Frame.Prefix xor Byte(Salt);
  Result.Name := Frame.Name + 'YZ';
  Result.Code := Frame.Code xor Salt;
end;

procedure RunBreadthAliasedShortString;
var
  Source, Reply: TBreadthWireFrame;
  Transform: TBreadthWireTransform;
begin
  Source.Prefix := Byte(OpaqueI($5C));
  Source.Name := 'A'#0'BC';
  Source.Code := Cardinal(OpaqueI($FE876543));
  Transform := BreadthTransformWire;
  Reply := Transform(Source, Source.Name, Cardinal(OpaqueI($8702D137)));
  Check(SizeOf(TBreadthWireFrame) = 11, 'breadth-packed-short-string-frame-size');
  Check((Source.Name = 'reset') and (Source.Prefix = $5C) and (Source.Code = $FE876543),
    'breadth-packed-short-string-field-write-respects-neighbors');
  Check((Length(Reply.Name) = 5) and (Reply.Name = 'A'#0'BCY'),
    'breadth-packed-short-string-by-value-copy-predates-aliased-write');
  Check((Reply.Prefix = $6B) and (Reply.Code = $7985B474), 'breadth-packed-short-string-return-keeps-unaligned-scalar');
  Mix(UInt64(Reply.Code));
end;
