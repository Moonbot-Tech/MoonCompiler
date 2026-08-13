unit ScopeX.Collections;

interface

type
  TPair<T, U> = record
    Key: T;
    Value: U;
  end;

  TEnumerator<T> = class abstract
  protected
    function DoGetCurrent: T; virtual; abstract;
  end;

  TEnumerable<T> = class abstract
  protected
    function DoGetEnumerator: TEnumerator<T>; virtual; abstract;
  end;

implementation

end.
