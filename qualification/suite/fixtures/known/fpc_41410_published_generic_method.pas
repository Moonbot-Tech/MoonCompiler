program Fpc41410PublishedGenericMethod;

{$mode delphi}

type
  {$M+}
  TContainer = class
  published
    procedure Test<T>;
  end;
  {$M-}

procedure TContainer.Test<T>;
begin
end;

begin
end.
