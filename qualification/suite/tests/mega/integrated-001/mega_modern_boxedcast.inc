{$define BREADTH_HAS_TVALUE_CAST}
{$ifdef FPC}
  {$if FPC_FULLVERSION < 30301}
    {$undef BREADTH_HAS_TVALUE_CAST}
  {$endif}
{$endif}

{$ifdef BREADTH_HAS_TVALUE_CAST}
{ A TValue declared as a base class can be downcast by the dynamic class of its stored object. }

type
  TBreadthBoxedBase = class
    Stamp: Int64;
  end;
  TBreadthBoxedChild = class(TBreadthBoxedBase);
  TBreadthBoxedSibling = class(TBreadthBoxedBase);

procedure RunBreadthBoxedClassCast;
var
  Item: TBreadthBoxedChild;
  Found: TBreadthBoxedChild;
  Unrelated: TBreadthBoxedSibling;
  Text: UnicodeString;
  Box: TValue;
begin
  Item := TBreadthBoxedChild.Create;
  try
    Item.Stamp := OpaqueI(73000000017);
    Box := TValue.From<TBreadthBoxedBase>(Item);
    Check((Box.Kind = tkClass) and (Box.AsObject = Item),
      'breadth-tvalue-class-boxes-existing-object-with-class-kind');
    Check(Box.TryAsType<TBreadthBoxedChild>(Found) and (Found = Item) and (Found.Stamp = 73000000017),
      'breadth-tvalue-class-cast-uses-dynamic-type-and-preserves-identity');
    Check(not Box.TryAsType<TBreadthBoxedSibling>(Unrelated), 'breadth-tvalue-class-cast-rejects-sibling-type');
  finally
    Item.Free;
  end;
  Box := TValue.Empty;
  Text := 'prior-' + IntToStr(OpaqueI(91));
  Check(Box.TryAsType<UnicodeString>(Text) and (Text = ''), 'breadth-tvalue-empty-fills-default-managed-result');
end;
{$endif}
