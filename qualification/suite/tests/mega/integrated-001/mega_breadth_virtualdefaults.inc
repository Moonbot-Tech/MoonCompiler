{ Call-site defaults belong to the static view, while the receiving method is virtual. }

type
  TBreadthCheckpointBase = class
    function Render(Ticket: Int64; const Mark: UnicodeString = 'root'): UnicodeString; virtual;
  end;

  TBreadthCheckpointLive = class(TBreadthCheckpointBase)
    function Render(Ticket: Int64; const Mark: UnicodeString = 'live'): UnicodeString; override;
  end;

function TBreadthCheckpointBase.Render(Ticket: Int64; const Mark: UnicodeString): UnicodeString;
begin
  Result := Mark + #0 + IntToStr(Ticket);
end;

function TBreadthCheckpointLive.Render(Ticket: Int64; const Mark: UnicodeString): UnicodeString;
begin
  Result := inherited Render(Ticket - 31) + '/' + Mark;
end;

procedure RunBreadthVirtualDefaults;
var
  Handler: TBreadthCheckpointLive;
  BaseView: TBreadthCheckpointBase;
  ResultText: UnicodeString;
  Ticket: Int64;
begin
  Handler := TBreadthCheckpointLive.Create;
  try
    BaseView := Handler;
    Ticket := OpaqueI(830000000012);
    Check(BaseView.Render(Ticket) = 'root' + #0 + '829999999981/root',
      'breadth-virtual-default-through-base-view-uses-base-default-and-derived-code');
    Check(Handler.Render(Ticket) = 'root' + #0 + '829999999981/live',
      'breadth-virtual-default-through-derived-view-uses-derived-default');
    ResultText := BaseView.Render(-Ticket, 'tag-' + #$03BB);
    Check(ResultText = 'root' + #0 + '-830000000043/tag-' + #$03BB,
      'breadth-virtual-explicit-mark-keeps-managed-text-while-inherited-call-uses-base-default');
    Mix(UInt64(Length(ResultText)));
  finally
    FreeAndNil(Handler);
  end;
end;
