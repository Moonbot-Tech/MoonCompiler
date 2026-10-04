program tgenericrecursivegrowth2;

{$mode delphi}

type
  TNode<T> = class
    Next: TNode<T>;
  end;
  TWrappedNode<T> = class
  end;
  TTreeNode<T> = class
    Children: TWrappedNode<TTreeNode<T>>;
  end;
  TIntNode = TNode<Integer>;
  TDeepNode = TNode<TNode<TNode<Integer>>>;
  TIntegerTree = TTreeNode<Integer>;

var
  Node: TIntNode;
  Deep: TDeepNode;
  Tree: TIntegerTree;
begin
  Node:=nil;
  Deep:=nil;
  Tree:=nil;
  if (Node<>nil) or (Deep<>nil) or (Tree<>nil) then Halt(1);
end.
