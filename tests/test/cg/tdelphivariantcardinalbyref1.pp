program tdelphivariantcardinalbyref1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
{$ifdef FPC}
  SysUtils,
  Variants;
{$else}
  System.SysUtils,
  System.Variants;
{$endif}

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

procedure SetVariantCardinalByRef(var Dest: Variant; var Source: Cardinal);
begin
  VarClear(Dest);
  TVarData(Dest).VType := varLongWord or varByRef;
  TVarData(Dest).VPointer := @Source;
end;

procedure SetOleCardinalByRef(var Dest: OleVariant; var Source: Cardinal);
begin
  VarClear(Dest);
  TVarData(Dest).VType := varLongWord or varByRef;
  TVarData(Dest).VPointer := @Source;
end;

var
  Raw, Value: Cardinal;
  V, A: Variant;
  O: OleVariant;
  Rejected: Boolean;
begin
  Raw := $F1234567;
  SetVariantCardinalByRef(V, Raw);
  Value := V;
  Check(Value = Raw, 1);

  Raw := $89ABCDEF;
  Value := V;
  Check(Value = Raw, 2);

  SetOleCardinalByRef(O, Raw);
  Value := O;
  Check(Value = Raw, 3);

  Raw := $FEDCBA98;
  Value := O;
  Check(Value = Raw, 4);
  TVarData(O).VType := varEmpty;

  A := VarArrayCreate([0, 0], varLongWord);
  A[0] := Cardinal(7);
  Rejected := False;
  try
    Value := A;
  except
    on EVariantError do
      Rejected := True;
  end;
  Check(Rejected, 5);

  O := A;
  Rejected := False;
  try
    Value := O;
  except
    on EVariantError do
      Rejected := True;
  end;
  Check(Rejected, 6);

  VarClear(O);
  VarClear(A);
  TVarData(V).VType := varEmpty;
end.
