{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A late-bound export row carries an exact id and receives a typed adjustment and a Unicode prefix. }

type
  TBreadthReceiptVariant = class(TInvokeableVariantType)
  public
    procedure Clear(var Value: TVarData); override;
    procedure Copy(var Dest: TVarData; const Source: TVarData; const Indirect: Boolean); override;
    function GetProperty(var Dest: TVarData; const Value: TVarData; const Name: string): Boolean; override;
    function DoFunction(var Dest: TVarData; const Value: TVarData; const Name: string;
      const Arguments: TVarDataArray): Boolean; override;
  end;

procedure TBreadthReceiptVariant.Clear(var Value: TVarData);
begin
  Value.VType := varEmpty;
end;

procedure TBreadthReceiptVariant.Copy(var Dest: TVarData; const Source: TVarData; const Indirect: Boolean);
begin
  Dest := Source;
end;

function TBreadthReceiptVariant.GetProperty(var Dest: TVarData; const Value: TVarData; const Name: string): Boolean;
begin
  Result := SameText(Name, 'OrderId');
  If Result then
    Variant(Dest) := Value.VInt64;
end;

function TBreadthReceiptVariant.DoFunction(var Dest: TVarData; const Value: TVarData; const Name: string;
  const Arguments: TVarDataArray): Boolean;
var
  Prefix: string;
  Offset: Int64;
begin
  Result := SameText(Name, 'AdjustedLabel') and (Length(Arguments) = 2);
  If Result then begin
    Prefix := string(Variant(Arguments[0]));
    Offset := Int64(Variant(Arguments[1]));
    Variant(Dest) := Prefix + ':' + IntToStr(Value.VInt64 + Offset);
  end;
end;

procedure RunBreadthVariantReceipt;
const
  Prefix = 'route' + #$03BB + #0 + #$D83D#$DE80;
var
  ReceiptKind: TBreadthReceiptVariant;
  Original, Retained: Variant;
  LabelText: string;
  Offset: Int64;
begin
  ReceiptKind := TBreadthReceiptVariant.Create;
  try
    TVarData(Original).VType := ReceiptKind.VarType;
    TVarData(Original).VInt64 := OpaqueI(9007199254740993);
    Retained := Original;
    VarClear(Original);
    Check(VarIsEmpty(Original) and (Int64(Retained.OrderId) = 9007199254740993),
      'breadth-late-bound-receipt-copy-retains-64-bit-id-after-original-clears');
    Offset := OpaqueI(-810000000037);
    LabelText := string(Retained.AdjustedLabel(string(Prefix), Offset));
    Check(LabelText = Prefix + ':9006389254740956', 'breadth-late-bound-receipt-marshals-unicode-and-signed-64-bit-offset');
    Check(Int64(Retained.OrderId) = 9007199254740993, 'breadth-late-bound-receipt-calculation-keeps-source-value');
    Mix(UInt64(Length(LabelText)));
  finally
    VarClear(Retained);
    VarClear(Original);
    ReceiptKind.Free;
  end;
end;
{$endif}
