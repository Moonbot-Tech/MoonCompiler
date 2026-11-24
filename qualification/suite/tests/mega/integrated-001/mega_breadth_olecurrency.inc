{ OleVariant Currency arithmetic must retain its scaled integer carrier and the cancellation residue. }

function BreadthReadVariantCurrency(const Number: OleVariant): Int64;
var
  Typed: Currency;
begin
  Typed := Currency(Number);
  Move(Typed, Result, SizeOf(Result));
end;

procedure RunBreadthVariantCurrency;
var
  Left, Right: Currency;
  A, B, Saved, Answer: OleVariant;
  Raw, Residue: Int64;
begin
  Raw := OpaqueI(9000000000000000029);
  Move(Raw, Left, SizeOf(Left));
  Raw := OpaqueI(-9000000000000000012);
  Move(Raw, Right, SizeOf(Right));
  A := Left;
  B := Right;
  Saved := A;
  Answer := A + B;
  Residue := BreadthReadVariantCurrency(Answer);
  Check((VarType(A) = varCurrency) and (VarType(B) = varCurrency) and (VarType(Answer) = varCurrency),
    'breadth-ole-currency-arithmetic-keeps-currency-carrier');
  Check(Residue = 17, 'breadth-ole-currency-cancellation-keeps-scaled-residue');
  VarClear(A);
  Check(VarIsEmpty(A) and (BreadthReadVariantCurrency(Saved) = 9000000000000000029),
    'breadth-ole-currency-snapshot-keeps-all-scaled-bits');
  Answer := Saved - Currency(0.0001);
  Raw := BreadthReadVariantCurrency(Answer);
  Check((VarType(Answer) = varCurrency) and (Raw = 9000000000000000028),
    'breadth-ole-currency-subtracts-one-unit-near-high-limit');
  Mix(UInt64(Raw) xor UInt64(Residue));
end;
