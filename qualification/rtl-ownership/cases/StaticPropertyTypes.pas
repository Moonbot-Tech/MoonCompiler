unit StaticPropertyTypes;
{$mode delphiunicode}
{$M+}
interface
{$RTTI EXPLICIT FIELDS([vcPublic]) PROPERTIES([vcPublic])}
type
  TStaticHolder<T> = class
  public
    class var Data: T;
    class property Value: T read Data write Data;
  end;
  TRefHolder = TStaticHolder<IInterface>;
  TStringHolder = TStaticHolder<UnicodeString>;
  TIntHolder = TStaticHolder<Int64>;
  TOuter = class
  public type
    TNested = class
    public
      class var Data: IInterface;
      class property Value: IInterface read Data write Data;
    end;
  end;
  TBase = class
  public
    class var Data: IInterface;
    class property Value: IInterface read Data write Data;
  end;
  TDerived = class(TBase);
  TStaticOnly = class
  public
    class var Data: IInterface;
    class property Value: IInterface read Data write Data;
  end;
  TPair = record Ref: IInterface; end;
  TSubfieldHolder = class
  public
    class var Data: TPair;
    class property Value: IInterface read Data.Ref write Data.Ref;
  end;
  TArrayHolder = class
  public
    class var Data: array[0..1] of IInterface;
    class property Value: IInterface read Data[1] write Data[1];
  end;
  TRecordHolder = record
    class var Data: IInterface;
    class property Value: IInterface read Data write Data;
  end;
implementation
end.
