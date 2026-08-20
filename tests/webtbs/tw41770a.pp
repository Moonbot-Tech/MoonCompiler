{ %fail }

{ A generic parameter forwarded into a specialization whose formal carries
  the `constructor` constraint must carry that constraint itself.
  DCC64 36.0 rejects this program with E2513. }

program tw41770a;

{$mode delphi}

type
  TBase = class
  end;

  TNeedCtor<X: TBase, constructor> = class
  end;

  TOuter<T: TBase> = class
    FInner: TNeedCtor<T>;
  end;

begin
end.
