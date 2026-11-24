{ Managed operator results assigned back through an operand alias. }

type
  PBreadthTextJoin = ^TBreadthTextJoin;
  TBreadthTextJoin = record
    Text: AnsiString;
    Owner: IInterface;
    Score: Int64;
    class operator Add(const Left, Right: TBreadthTextJoin): TBreadthTextJoin;
  end;

class operator TBreadthTextJoin.Add(const Left, Right: TBreadthTextJoin): TBreadthTextJoin;
begin
  Result.Text := '[';
  Result.Owner := nil;
  Result.Score := 31;
  Result.Text := Result.Text + Left.Text + '/' + Right.Text + ']';
  Result.Score := Result.Score + 5 * Left.Score - 3 * Right.Score;
  Result.Owner := Left.Owner;
end;

procedure BreadthJoinWithAliases;
var
  Left, Right: TBreadthTextJoin;
  LeftAlias: PBreadthTextJoin;
  LeftOwner, RightOwner: Pointer;
begin
  Left.Text := AnsiString('L' + IntToStr(OpaqueI(15)));
  Left.Score := OpaqueI(-58);
  Left.Owner := TIntersectionOwner.Create;
  Right.Text := AnsiString('R' + IntToStr(OpaqueI(42)));
  Right.Score := OpaqueI(97);
  Right.Owner := TIntersectionOwner.Create;
  RightOwner := Pointer(Right.Owner);
  LeftOwner := Pointer(Left.Owner);
  LeftAlias := @Left;
  LeftAlias^ := LeftAlias^ + Right;
  Check((Left.Text = '[L15/R42]') and (Left.Score = -550) and (Pointer(Left.Owner) = LeftOwner),
    'breadth-managed-operator-result-can-overlap-left-operand');
  Check((Right.Text = 'R42') and (Right.Score = 97) and (Pointer(Right.Owner) = RightOwner),
    'breadth-managed-operator-overlap-leaves-right-operand-unchanged');
  Right := LeftAlias^ + Right;
  Check((Right.Text = '[[L15/R42]/R42]') and (Right.Score = -3010) and (Pointer(Right.Owner) = LeftOwner),
    'breadth-managed-operator-result-can-overlap-right-operand');
  Mix(UInt64(Right.Score));
end;

procedure RunBreadthManagedOperator;
begin
  TIntersectionOwner.Destroyed := 0;
  BreadthJoinWithAliases;
  Check(TIntersectionOwner.Destroyed = 2, 'breadth-managed-operator-releases-both-operand-owners');
end;
