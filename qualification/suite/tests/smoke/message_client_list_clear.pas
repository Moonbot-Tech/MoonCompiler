program message_client_list_clear;

{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

uses
  SysUtils,
  System.Messaging;

type
  TTestMessage = class(TMessageBase);

  TDestroyCapture = class(TInterfacedObject)
  private
    FClients: TMessageClientList;
    FDestructions: PInteger;
  public
    constructor Create(AClients: TMessageClientList; ADestructions: PInteger);
    destructor Destroy; override;
  end;

  TProbe = class
  private
    FClients: TMessageClientList;
    FFirstCalls: Integer;
    FSecondCalls: Integer;
    FAddedCalls: Integer;
    FReentrantCalls: Integer;
    FDestructions: Integer;
    function MakeReentrantListener: TMessageListener;
    procedure InstallReentrantListener;
    procedure ClearAndAdd(const Sender: TObject; const M: TMessageBase);
    procedure CountSecond(const Sender: TObject; const M: TMessageBase);
    procedure CountAdded(const Sender: TObject; const M: TMessageBase);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Check;
  end;

procedure Fail(const Name: string);
begin
  WriteLn('FAIL ', Name);
  Halt(1);
end;

procedure Require(ACondition: Boolean; const Name: string);
begin
  If not ACondition then
    Fail(Name);
end;

constructor TDestroyCapture.Create(AClients: TMessageClientList;
  ADestructions: PInteger);
begin
  inherited Create;
  FClients := AClients;
  FDestructions := ADestructions;
end;

destructor TDestroyCapture.Destroy;
begin
  Inc(FDestructions^);
  FClients.Clear;
  inherited Destroy;
end;

constructor TProbe.Create;
begin
  inherited Create;
  FClients := TMessageClientList.Create(TMessageClient);
end;

destructor TProbe.Destroy;
begin
  FClients.Free;
  inherited Destroy;
end;

function TProbe.MakeReentrantListener: TMessageListener;
var
  KeepAlive: IInterface;
begin
  KeepAlive := TDestroyCapture.Create(FClients, @FDestructions);
  Result := procedure(const Sender: TObject; const M: TMessageBase)
    begin
      If KeepAlive <> nil then
        Inc(FReentrantCalls);
      FClients.Clear;
    end;
end;

procedure TProbe.InstallReentrantListener;
var
  Listener: TMessageListener;
begin
  Listener := MakeReentrantListener;
  FClients.Add(4, Listener);
end;

procedure TProbe.ClearAndAdd(const Sender: TObject; const M: TMessageBase);
begin
  Inc(FFirstCalls);
  FClients.Clear;
  FClients.Add(3, CountAdded);
end;

procedure TProbe.CountSecond(const Sender: TObject; const M: TMessageBase);
begin
  Inc(FSecondCalls);
end;

procedure TProbe.CountAdded(const Sender: TObject; const M: TMessageBase);
begin
  Inc(FAddedCalls);
end;

procedure TProbe.Check;
var
  MessageValue: TTestMessage;
begin
  FClients.Add(1, CountSecond);
  FClients.Add(2, CountAdded);
  FClients.Clear;
  Require(FClients.Count = 0, 'ordinary-clear-count');

  FClients.Add(1, CountSecond);
  MessageValue := TTestMessage.Create;
  try
    FClients.NotifyClients(Self, MessageValue);
  finally
    MessageValue.Free;
  end;
  Require(FSecondCalls = 1, 'ordinary-clear-reuse');

  FClients.Clear;
  FSecondCalls := 0;
  FAddedCalls := 0;
  FClients.Add(1, ClearAndAdd);
  FClients.Add(2, CountSecond);
  MessageValue := TTestMessage.Create;
  try
    FClients.NotifyClients(Self, MessageValue);
    Require(FFirstCalls = 1, 'dispatch-first-called');
    Require(FSecondCalls = 0, 'dispatch-remaining-skipped');
    Require(FAddedCalls = 0, 'dispatch-added-deferred');
    Require(FClients.Count = 1, 'dispatch-clear-compacted');
    FClients.NotifyClients(Self, MessageValue);
  finally
    MessageValue.Free;
  end;
  Require(FFirstCalls = 1, 'dispatch-cleared-not-recalled');
  Require(FAddedCalls = 1, 'dispatch-added-next-notify');

  FClients.Clear;
  InstallReentrantListener;
  MessageValue := TTestMessage.Create;
  try
    FClients.NotifyClients(Self, MessageValue);
  finally
    MessageValue.Free;
  end;
  Require(FReentrantCalls = 1, 'destructor-reentry-listener-called');
  Require(FDestructions = 1, 'destructor-reentry-capture-destroyed');
  Require(FClients.Count = 0, 'destructor-reentry-count');

  FClients.Add(5, CountSecond);
  MessageValue := TTestMessage.Create;
  try
    FClients.NotifyClients(Self, MessageValue);
  finally
    MessageValue.Free;
  end;
  Require(FClients.Count = 1, 'destructor-reentry-reuse-count');
end;

var
  Probe: TProbe;
begin
  Probe := TProbe.Create;
  try
    Probe.Check;
  finally
    Probe.Free;
  end;
  WriteLn('MESSAGE_CLIENT_LIST_CLEAR_OK');
end.
