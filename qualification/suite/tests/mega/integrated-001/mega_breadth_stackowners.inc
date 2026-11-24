{ A stack moves managed values out in LIFO order while Peek retains a view. }

type
  TBreadthStackFrame = record
    Ticket: Int64;
    Text: UnicodeString;
    Owner: IBreadthTaggedOwner;
  end;

procedure BreadthPopStackFrames;
var
  Stack: TStack<TBreadthStackFrame>;
  Frame, View, Taken: TBreadthStackFrame;
  TopIdentity: Pointer;
begin
  Stack := TStack<TBreadthStackFrame>.Create;
  try
    Frame.Ticket := OpaqueI(77000000007);
    Frame.Text := 'base';
    Frame.Owner := TBreadthTaggedOwner.Create;
    Stack.Push(Frame);
    Frame.Ticket := OpaqueI(-81000000013);
    Frame.Text[1] := 'c';
    Frame.Owner := TBreadthTaggedOwner.Create;
    TopIdentity := Pointer(Frame.Owner);
    Stack.Push(Frame);
    Frame.Owner := nil;
    View := Stack.Peek;
    Check((Stack.Count = 2) and (View.Ticket = -81000000013) and (View.Text = 'case')
      and (Pointer(View.Owner) = TopIdentity), 'breadth-stack-peek-retains-typed-top-without-removal');
    Taken := Stack.Pop;
    Stack.TrimExcess;
    Check((Stack.Count = 1) and (Taken.Ticket = View.Ticket) and (Taken.Text = View.Text)
      and (Taken.Owner = View.Owner), 'breadth-stack-pop-moves-managed-value-before-capacity-shrink');
    Frame := Stack.Pop;
    Check((Stack.Count = 0) and (Frame.Ticket = 77000000007) and (Frame.Text = 'base')
      and (Frame.Owner <> nil) and (Pointer(Frame.Owner) <> TopIdentity),
      'breadth-stack-lifo-isolates-older-managed-frame-from-top-mutation');
  finally
    Stack.Free;
  end;
  Check((TBreadthTaggedOwner.Destroyed = 0) and (Taken.Owner.Tag = 74000000051)
    and (Frame.Owner.Tag = 74000000051), 'breadth-stack-popped-owners-survive-container-lifetime');
  Mix(UInt64(Frame.Ticket) xor UInt64(Taken.Ticket));
end;

procedure RunBreadthStackOwners;
begin
  TBreadthTaggedOwner.Destroyed := 0;
  BreadthPopStackFrames;
  Check(TBreadthTaggedOwner.Destroyed = 2, 'breadth-stack-finalizes-each-moved-owner-once');
end;
