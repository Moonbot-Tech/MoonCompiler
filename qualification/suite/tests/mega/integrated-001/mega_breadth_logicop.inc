{ An overloaded and consumes both operand factories even when its mask cannot match. }

type
  TBreadthLogicalValue = record
    Mask: Cardinal;
    Text: UnicodeString;
    class operator BitwiseAnd(const Left, Right: TBreadthLogicalValue): TBreadthLogicalValue;
    class operator Implicit(const Value: TBreadthLogicalValue): Boolean;
  end;

var
  BreadthOperandCalls: Integer;

class operator TBreadthLogicalValue.BitwiseAnd(const Left, Right: TBreadthLogicalValue): TBreadthLogicalValue;
begin
  Result.Mask := Left.Mask and Right.Mask;
  Result.Text := Left.Text + #0 + Right.Text;
end;

class operator TBreadthLogicalValue.Implicit(const Value: TBreadthLogicalValue): Boolean;
begin
  Result := Value.Mask <> 0;
end;

function BreadthLogicalOperand(Mask: Cardinal; const Text: UnicodeString): TBreadthLogicalValue;
begin
  Inc(BreadthOperandCalls);
  Result.Mask := Cardinal(OpaqueI(Mask));
  Result.Text := Text;
end;

procedure RunBreadthLogicalOverload;
var
  Combined: TBreadthLogicalValue;
  Branch: Boolean;
begin
  BreadthOperandCalls := 0;
  Combined := BreadthLogicalOperand(0, 'left') and BreadthLogicalOperand(1, 'right');
  Branch := Combined;
  Check(not Branch and (Combined.Text = 'left'#0'right') and (BreadthOperandCalls = 2),
    'breadth-overloaded-and-evaluates-both-operands-and-preserves-managed-result');
  BreadthOperandCalls := 0;
  Combined := BreadthLogicalOperand($80000001, 'upper') and BreadthLogicalOperand($80000000, 'mask');
  Branch := Combined;
  Check(Branch and (Combined.Mask = $80000000) and (Combined.Text = 'upper'#0'mask') and (BreadthOperandCalls = 2),
    'breadth-overloaded-and-converts-high-bit-mask-through-implicit-boolean');
end;
