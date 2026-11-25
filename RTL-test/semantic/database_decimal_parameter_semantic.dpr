program database_decimal_parameter_semantic;
{$mode delphiunicode}{$apptype console}
uses SysUtils, DB, FmtBcd, BufDataset;

procedure Check(Condition: Boolean; const Detail: string);
begin
  if not Condition then begin WriteLn('FAIL ',Detail); Halt(1) end;
end;

var
  Master: TBufDataset;
  Params: TParams;
  P: TParam;
  Settings: TFormatSettings;
  Price: TBcd;
begin
  Settings:=Default(TFormatSettings);
  Settings.DecimalSeparator:='.';
  Price:=StrToBcd('9007199254740993.0197',Settings);
  Master:=TBufDataset.Create(nil);
  Params:=TParams.Create;
  try
    Master.FieldDefs.Add('price',ftInteger);
    Master.CreateDataset;
    Master.Append;
    Master.FieldByName('price').AsInteger:=7;
    Master.Post;
    P:=Params.CreateParam(ftFMTBcd,'price',ptInput);
    P.Precision:=21;
    P.NumericScale:=4;
    P.AsFMTBCD:=Price;
    Check(P.Bound and not P.IsNull,'explicit decimal binds parameter');
    Params.CopyParamValuesFromDataset(Master,False);
    Check((P.DataType=ftFMTBcd) and (P.Precision=21) and (P.NumericScale=4) and
      (BcdToStr(P.AsFMTBCD,Settings)='9007199254740993.0197'),'master preserves explicit decimal');
    P.Bound:=False;
    Params.CopyParamValuesFromDataset(Master,False);
    Check(P.AsInteger=7,'unbound parameter still follows master');
  finally
    Params.Free;
    Master.Free;
  end;
  WriteLn('DATABASE_DECIMAL_PARAMETER_PASS');
end.
