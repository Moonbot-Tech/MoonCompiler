program message_manager_shutdown_contract;

{$mode delphiunicode}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

uses
  SysUtils,
  System.Messaging;

type
  TTestMessage = class(TMessageBase);

  IShutdownProbe = interface
    ['{D6D60148-7BB0-41D6-A91F-5B22AD8B4375}']
    procedure Touch;
  end;

  TShutdownProbe = class(TInterfacedObject,IShutdownProbe)
  private
    FManager: TMessageManager;
    FDestructions: PInteger;
    FFailures: PInteger;
    FRejectedSubscriptions: PInteger;
  public
    constructor Create(AManager: TMessageManager; ADestructions,AFailures,
      ARejectedSubscriptions: PInteger);
    destructor Destroy; override;
    procedure Touch;
  end;

var
  Destructions: Integer;
  Failures: Integer;
  RejectedSubscriptions: Integer;
  ShutdownSubscription: TMessageSubscriptionId;

procedure Fail(const Name: string);
begin
  WriteLn('FAIL ',Name);
  Halt(1);
end;

procedure Require(Condition: Boolean; const Name: string);
begin
  if not Condition then
    Fail(Name);
end;

constructor TShutdownProbe.Create(AManager: TMessageManager; ADestructions,AFailures,
  ARejectedSubscriptions: PInteger);
begin
  inherited Create;
  FManager:=AManager;
  FDestructions:=ADestructions;
  FFailures:=AFailures;
  FRejectedSubscriptions:=ARejectedSubscriptions;
end;

destructor TShutdownProbe.Destroy;
var
  NewSubscription: TMessageSubscriptionId;
begin
  Inc(FDestructions^);
  try
    FManager.Unsubscribe(TTestMessage,ShutdownSubscription);
    NewSubscription:=FManager.SubscribeToMessage(TTestMessage,
      procedure(const Sender: TObject; const Message: TMessageBase)
      begin
      end);
    if NewSubscription=0 then
      Inc(FRejectedSubscriptions^);
  except
    Inc(FFailures^);
  end;
  inherited Destroy;
end;

procedure TShutdownProbe.Touch;
begin
end;

function MakeShutdownListener(Manager: TMessageManager): TMessageListener;
var
  Probe: IShutdownProbe;
begin
  Probe:=TShutdownProbe.Create(Manager,@Destructions,@Failures,
    @RejectedSubscriptions);
  Result:=procedure(const Sender: TObject; const Message: TMessageBase)
    begin
      Probe.Touch;
    end;
end;

procedure CheckNormalUse;
var
  Calls: Integer;
  Manager: TMessageManager;
  Subscription: TMessageSubscriptionId;
begin
  Calls:=0;
  Manager:=TMessageManager.Create;
  try
    Subscription:=Manager.SubscribeToMessage(TTestMessage,
      procedure(const Sender: TObject; const Message: TMessageBase)
      begin
        Inc(Calls);
      end);
    Require(Subscription<>0,'normal-subscribe');
    Manager.SendMessage(nil,TTestMessage.Create,True);
    Require(Calls=1,'normal-send');
    Manager.Unsubscribe(TTestMessage,Subscription);
    Manager.SendMessage(nil,TTestMessage.Create,True);
    Require(Calls=1,'normal-unsubscribe');
  finally
    Manager.Free;
  end;
end;

procedure CheckShutdownReentry;
var
  Listener: TMessageListener;
  Manager: TMessageManager;
begin
  Manager:=TMessageManager.Create;
  Listener:=MakeShutdownListener(Manager);
  ShutdownSubscription:=Manager.SubscribeToMessage(TTestMessage,Listener);
  Require(ShutdownSubscription<>0,'shutdown-subscribe');
  Listener:=nil;
  Manager.Free;
  Require(Destructions=1,'shutdown-capture-destruction');
  Require(Failures=0,'shutdown-reentry-failure');
  Require(RejectedSubscriptions=1,'shutdown-reject-subscribe');
end;

begin
  CheckNormalUse;
  CheckShutdownReentry;
  WriteLn('MESSAGE_MANAGER_SHUTDOWN_OK');
end.
