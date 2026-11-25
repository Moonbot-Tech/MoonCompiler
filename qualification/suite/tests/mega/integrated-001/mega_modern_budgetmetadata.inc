{$ifdef BREADTH_HAS_PRODUCT_IO}
{ A settings inspector boxes a decimal limit and preserves the full-scale backing field. }

type
  {$RTTI EXPLICIT FIELDS([vcPrivate]) PROPERTIES([vcPublished])}
  TBreadthBudgetLimits = class(TPersistent)
  private
    FQuota: Currency;
    FArchiveBalance: Currency;
  published
    property Quota: Currency read FQuota write FQuota;
  end;
  {$RTTI INHERIT}

function BreadthCurrencyFromScale(Scaled: Int64): Currency;
begin
  Move(Scaled, Result, SizeOf(Result));
end;

function BreadthCurrencyScale(Value: Currency): Int64;
begin
  Move(Value, Result, SizeOf(Result));
end;

procedure RunBreadthBudgetMetadata;
var
  Context: TRttiContext;
  Target: TBreadthBudgetLimits;
  Info: TRttiType;
  Quota: TRttiProperty;
  Archive: TRttiField;
  Saved: TValue;
begin
  Context := TRttiContext.Create;
  try
    Info := Context.GetType(TBreadthBudgetLimits);
    If Info = nil then begin
      Check(False, 'breadth-budget-rtti-type-is-present');
      Exit;
    end;
    Quota := Info.GetProperty('Quota');
    Archive := Info.GetField('FArchiveBalance');
    Check((Quota <> nil) and (Archive <> nil) and (Quota.PropertyType.Handle = TypeInfo(Currency))
      and (Archive.FieldType.Handle = TypeInfo(Currency)), 'breadth-budget-rtti-distinguishes-exact-currency-type');
    If (Quota = nil) or (Archive = nil) then
      Exit;
    Target := TBreadthBudgetLimits.Create;
    try
      Quota.SetValue(Target, TValue.From<Currency>(BreadthCurrencyFromScale(OpaqueI(-570314159))));
      Check(BreadthCurrencyScale(Target.Quota) = -570314159, 'breadth-budget-rtti-property-stores-signed-decimal-limit');
      Check(BreadthCurrencyScale(Quota.GetValue(Target).AsType<Currency>) = -570314159,
        'breadth-budget-rtti-property-reads-signed-decimal-limit');
      Archive.SetValue(Target, TValue.From<Currency>(BreadthCurrencyFromScale(OpaqueI(9007199254740993))));
      Saved := Archive.GetValue(Target);
      Check(BreadthCurrencyScale(Target.FArchiveBalance) = 9007199254740993,
        'breadth-budget-rtti-field-write-keeps-full-fixed-point-scale');
    finally
      Target.Free;
    end;
    Check(BreadthCurrencyScale(Saved.AsType<Currency>) = 9007199254740993,
      'breadth-budget-rtti-boxed-field-keeps-exact-balance-after-source-free');
    Mix(UInt64(BreadthCurrencyScale(Saved.AsType<Currency>)));
  finally
    Context.Free;
  end;
end;
{$endif}
