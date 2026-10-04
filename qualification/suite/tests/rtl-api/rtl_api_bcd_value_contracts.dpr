program rtl_api_bcd_value_contracts;

{$IFDEF FPC}{$mode delphiunicode}{$ELSE}{$APPTYPE CONSOLE}{$ENDIF}

uses
  SysUtils, Variants, FmtBcd, Generics.Defaults, Generics.Collections;

function Digit(const B: TBCD; I: Integer): Byte;
begin
  If Odd(I) then Result:=B.Fraction[I div 2] and $f else Result:=B.Fraction[I div 2] shr 4;
end;

function Pad(const B: TBCD; Leading,Trailing: Integer): TBCD;
var
  I,N: Integer;
begin
  FillChar(Result,SizeOf(Result),0);
  Result.Precision:=B.Precision+Leading+Trailing;
  Result.SignSpecialPlaces:=(B.SignSpecialPlaces and $c0) or (BCDScale(B)+Trailing);
  for I:=0 to B.Precision-1 do begin
    N:=I+Leading;
    If Odd(N) then Result.Fraction[N div 2]:=Result.Fraction[N div 2] or Digit(B,I)
    else Result.Fraction[N div 2]:=Digit(B,I) shl 4;
  end;
end;

const
  Texts: array[0..12] of string = ('-1.25','-1.23456789','-1.21','-0.001','0','0.001',
    '1.00000000000000001','1.00000000000000002','1.2','1.21','1.23456789','1.25','2');
var
  Values: array[0..51] of TBCD;
  I,J,K,N,Actual,Expected: Integer;
  A,B: Variant;
  C: IEqualityComparer<Variant>;
  D: TDictionary<Variant,Integer>;
  Roundtrip: TBCD;
  {$IFDEF FPC}
  Handler: TCustomVariantType;
  KC: IVarKeyComparer;
  {$ENDIF}

procedure Check(Value: Boolean; const Name: string);
begin
  If not Value then begin
    Writeln('FAIL ',Name);
    Halt(1);
  end;
end;

begin
  C:=TEqualityComparer<Variant>.Default;
  {$IFDEF FPC}
  Check(FindCustomVariantType(VarFMTBCD,Handler) and Supports(Handler,IVarKeyComparer,KC),
    'explicit content hash interface');
  {$ENDIF}
  Values[0]:=StrToBCD('1.25');
  CurrToBCD(Currency(1.25),Values[1]);
  Check(BCDCompare(Values[0],Values[1])=0,'public CurrToBCD native equality');
  A:=VarFMTBCDCreate(Values[0]);
  B:=VarFMTBCDCreate(Values[1]);
  Check(VarCompareValue(A,B)=vrEqual,'public CurrToBCD Variant equality');
  Check(C.Equals(A,B),'public CurrToBCD key equality');
  Check(C.GetHashCode(A)=C.GetHashCode(B),'public CurrToBCD hash');
  D:=TDictionary<Variant,Integer>.Create;
  try
    D.Add(A,73);
    Check(D.TryGetValue(B,N) and (N=73),'public CurrToBCD lookup');
    D.AddOrSetValue(B,91);
    Check((D.Count=1) and (D[A]=91),'public CurrToBCD update');
    D.Remove(B);
    Check(D.Count=0,'public CurrToBCD remove');
  finally
    D.Free;
  end;
  for I:=0 to High(Texts) do begin
    Values[I*4]:=StrToBCD(Texts[I]);
    Values[I*4+1]:=Pad(Values[I*4],0,1);
    Values[I*4+2]:=Pad(Values[I*4],1,2);
    Values[I*4+3]:=Pad(Values[I*4],8,4);
  end;
  for I:=0 to High(Values) do begin
    A:=VarFMTBCDCreate(Values[I]);
    Roundtrip:=VarToBCD(A);
    Check(CompareMem(@Roundtrip,@Values[I],SizeOf(Roundtrip)),'producer roundtrip');
    for J:=0 to High(Values) do begin
      Expected:=0;
      If I div 4<J div 4 then Expected:=-1 else If I div 4>J div 4 then Expected:=1;
      Actual:=BCDCompare(Values[I],Values[J]);
      Check(Actual=Expected,'native compare '+IntToStr(I)+'/'+IntToStr(J));
      B:=VarFMTBCDCreate(Values[J]);
      Check((VarCompareValue(A,B)=vrEqual)=(Expected=0),'Variant equality');
      Check(C.Equals(A,B)=(Expected=0),'key equality');
      If Expected=0 then begin
        {$IFDEF FPC}
        Check(KC.GetKeyHashCode(TVarData(A))=KC.GetKeyHashCode(TVarData(B)),'content hash');
        {$ENDIF}
        Check(C.GetHashCode(A)=C.GetHashCode(B),'hash');
        D:=TDictionary<Variant,Integer>.Create;
        try
          D.Add(A,73);
          Check(D.TryGetValue(B,N) and (N=73),'lookup');
          D.AddOrSetValue(B,91);
          Check((D.Count=1) and (D[A]=91),'update');
          D.Remove(B);
          Check(D.Count=0,'remove');
        finally
          D.Free;
        end;
      end;
    end;
  end;
  for I:=0 to High(Values) do for J:=0 to High(Values) do for K:=0 to High(Values) do
    If (BCDCompare(Values[I],Values[J])=0) and (BCDCompare(Values[J],Values[K])=0) then
      Check(BCDCompare(Values[I],Values[K])=0,'native transitivity');
  Writeln('RTL_API_BCD_VALUE_CONTRACTS_OK');
end.
