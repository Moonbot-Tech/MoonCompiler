{$ifdef BREADTH_HAS_PRODUCT_IO}
{ Closing one view during notification removes its callback and keeps delivery to the other view. }

type
  TBreadthPanelNotice = class(TMessage<string>)
  public
    class var Released: Integer;
    destructor Destroy; override;
  end;

  TBreadthNoticeView = class
    Manager: TMessageManager;
    Subscription: TMessageSubscriptionId;
    Calls: Integer;
    LastSender: TObject;
    Caption: string;
    DetachOnNotice: Boolean;
    procedure Notice(const Sender: TObject; const Message: TMessageBase);
  end;

destructor TBreadthPanelNotice.Destroy;
begin
  Inc(Released);
  inherited Destroy;
end;

procedure TBreadthNoticeView.Notice(const Sender: TObject; const Message: TMessageBase);
begin
  Inc(Calls);
  LastSender := Sender;
  Caption := TBreadthPanelNotice(Message).Value;
  If DetachOnNotice then
    Manager.Unsubscribe(TBreadthPanelNotice, Subscription, True);
end;

procedure RunBreadthDetachPanelNotification;
const
  ClosingText: UnicodeString = 'close' + #$03BB + #0 + ' confirmed';
  RefreshText: UnicodeString = 'refresh' + #$D83D#$DE80;
var
  Dispatcher: TMessageManager;
  ClosingView, ActiveView: TBreadthNoticeView;
  Borrowed: TBreadthPanelNotice;
begin
  Dispatcher := TMessageManager.Create;
  ClosingView := nil;
  ActiveView := nil;
  TBreadthPanelNotice.Released := 0;
  try
    ClosingView := TBreadthNoticeView.Create;
    ActiveView := TBreadthNoticeView.Create;
    ClosingView.Manager := Dispatcher;
    ClosingView.DetachOnNotice := True;
    ClosingView.Subscription := Dispatcher.SubscribeToMessage(TBreadthPanelNotice, ClosingView.Notice);
    Dispatcher.SubscribeToMessage(TBreadthPanelNotice, ActiveView.Notice);

    Borrowed := TBreadthPanelNotice.Create(ClosingText);
    try
      Dispatcher.SendMessage(ActiveView, Borrowed, False);
      Check(TBreadthPanelNotice.Released = 0, 'breadth-panel-notification-keeps-caller-owned-message');
    finally
      If TBreadthPanelNotice.Released = 0 then
        Borrowed.Free;
    end;
    Check((ClosingView.Calls = 1) and (ActiveView.Calls = 1) and (ActiveView.Caption = ClosingText)
      and (ActiveView.LastSender = ActiveView), 'breadth-panel-notification-finishes-peer-delivery-after-self-unsubscribe');

    Dispatcher.SendMessage(ActiveView, TBreadthPanelNotice.Create(RefreshText), True);
    Check((ClosingView.Calls = 1) and (ClosingView.Caption = ClosingText), 'breadth-panel-notification-closed-view-is-no-longer-called');
    Check((ActiveView.Calls = 2) and (ActiveView.Caption = RefreshText), 'breadth-panel-notification-remaining-view-keeps-transferred-text');
    Check(TBreadthPanelNotice.Released = 2, 'breadth-panel-notification-messages-released-once-by-their-owners');
    Mix(UInt64(ActiveView.Calls * 100 + Length(ActiveView.Caption)));
  finally
    Dispatcher.Free;
    ActiveView.Free;
    ClosingView.Free;
  end;
end;
{$endif}
