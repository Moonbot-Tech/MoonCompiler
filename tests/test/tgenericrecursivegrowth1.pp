{ %FAIL }
program tgenericrecursivegrowth1;

{$mode delphi}

type
  TNode<T> = class
    Prev: TNode<TNode<T>>;
  end;
  TIntNode = TNode<Integer>;

begin
end.
