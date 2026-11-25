{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A query can checkpoint its parameter values and rebind named slots without replacing other parameters. }

procedure RunBreadthParamsCheckpoint;
var
  Source, Checkpoint: TParams;
  Ticket, Caption: TParam;
  LabelText: UnicodeString;
begin
  Source := TParams.Create;
  Checkpoint := nil;
  try
    Checkpoint := TParams.Create;
    Ticket := Source.CreateParam(ftLargeInt, 'ticket', ptInput);
    Ticket.AsLargeInt := OpaqueI(9007199254740993);
    Caption := Source.CreateParam(ftWideString, 'caption', ptInput);
    LabelText := 'label' + #0 + #$03BB + #$D83D + #$DE80;
    Caption.AsWideString := LabelText;
    Checkpoint.Assign(Source);

    Ticket.Clear;
    Caption.AsWideString := 'rebound';
    Check((Checkpoint.Count = 2) and (Checkpoint.ParamByName('TICKET').AsLargeInt = 9007199254740993)
      and Checkpoint.ParamByName('ticket').Bound, 'breadth-db-params-snapshot-keeps-exact-bound-id');
    Check((Checkpoint.ParamByName('caption').AsWideString = LabelText)
      and (Checkpoint.ParamByName('caption').DataType = ftWideString),
      'breadth-db-params-snapshot-keeps-typed-unicode-after-source-rebind');
    Mix(UInt64(Checkpoint.ParamByName('ticket').AsLargeInt));

    Checkpoint.CreateParam(ftInteger, 'result', ptOutput).AsInteger := 73;
    Checkpoint.AssignValues(Source);
    Ticket := Checkpoint.ParamByName('ticket');
    Check(Ticket.IsNull and Ticket.Bound and (Ticket.DataType = ftLargeInt) and (Ticket.ParamType = ptInput),
      'breadth-db-params-rebinds-typed-null-without-resetting-direction');
    Check(Checkpoint.ParamByName('caption').AsWideString = 'rebound', 'breadth-db-params-rebinds-text-by-name');
    Check((Checkpoint.Count = 3) and (Checkpoint.ParamByName('result').AsInteger = 73)
      and (Checkpoint.ParamByName('result').ParamType = ptOutput), 'breadth-db-params-rebind-leaves-other-parameters');
  finally
    Checkpoint.Free;
    Source.Free;
  end;
end;

procedure RunBreadthParamsDecimal;
const
  Wire = '9007199254740993.0197';
var
  Params: TParams;
  Price: TParam;
  Settings: TFormatSettings;
begin
  Settings := Default(TFormatSettings);
  Settings.DecimalSeparator := '.';
  Settings.ThousandSeparator := ',';
  Params := TParams.Create;
  try
    Price := Params.CreateParam(ftFMTBcd, 'price', ptInput);
    Price.Precision := 21;
    Price.NumericScale := 4;
    Params.ParamValues['price'] := VarFmtBCDCreate(StrToBcd(Wire, Settings));
    Check(Price.Bound and not Price.IsNull and (Price.DataType = ftFMTBcd)
      and (Price.Precision = 21) and (Price.NumericScale = 4), 'breadth-db-decimal-variant-binds-typed-param-with-scale');
    Check(BcdToStr(Price.AsFMTBCD, Settings) = Wire, 'breadth-db-decimal-variant-preserves-value-beyond-binary64');
  finally
    Params.Free;
  end;
end;
{$endif}
