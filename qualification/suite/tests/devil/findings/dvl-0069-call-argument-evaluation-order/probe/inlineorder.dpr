program inlineorder;
{$APPTYPE CONSOLE}
{$ifdef FPC}{$mode delphiunicode}{$H+}{$modeswitch advancedrecords}{$modeswitch INLINEVARS}{$endif}
{$Q-}{$R-}
uses SysUtils;

type
  TSrc = record
    State: UInt64;
    function NextWord: UInt64; inline;
    function NextBelow(ALimit: Integer): Integer; inline;
  end;

function TSrc.NextWord: UInt64;
begin
  State := State xor (State shl 13);
  State := State xor (State shr 7);
  State := State xor (State shl 17);
  Result := State;
end;

function TSrc.NextBelow(ALimit: Integer): Integer;
begin
  Result := Integer((NextWord shr 33) mod UInt64(ALimit));
end;

var
  S: TSrc;
  V, W: UInt64;
  Raw: UInt64;
  Sh: Integer;
begin
  { дорога первая: два вызова в ОДНОМ выражении }
  S.State := 20260830;
  V := S.NextWord shr S.NextBelow(40);
  WriteLn('в одном выражении: ', V, '  состояние после: ', S.State);

  { дорога вторая: те же два вызова РАЗНЫМИ операторами, слева направо }
  S.State := 20260830;
  Raw := S.NextWord;
  Sh := S.NextBelow(40);
  W := Raw shr Sh;
  WriteLn('раздельно:         ', W, '  состояние после: ', S.State);

  if V = W then WriteLn('СОВПАЛО (порядок слева направо)')
           else WriteLn('РАЗОШЛОСЬ (правый операнд вычислен первым)');
end.
