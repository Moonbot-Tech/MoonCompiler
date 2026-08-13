program Fpc41788GenericVirtualLink;

{$mode delphi}

type
  TEnumerator<T> = class
    procedure DoMoveNext; virtual;
  end;

  TEnumerable = class
    class function List<T>: TEnumerator<T>;
  end;

  TConsumer<T> = class
    procedure Run;
  end;

procedure TEnumerator<T>.DoMoveNext;
begin
end;

class function TEnumerable.List<T>: TEnumerator<T>;
begin
  Result := nil;
end;

procedure TConsumer<T>.Run;
begin
  TEnumerable.List<T>();
end;

begin
end.
