program reader_typed_component_reference_semantic;
{$ifdef FPC}{$mode delphi}{$endif}
{$apptype console}
uses Classes, SysUtils;

type
  ISentinel = interface ['{FC02A40C-F4D3-4C25-B675-F1F44241A301}']
    function Sentinel: Integer;
  end;
  IToken = interface ['{07C6897B-7C0C-42AF-A36A-515AD2A7E4FF}']
    function Token: Int64;
  end;
{$ifdef FPC}
  {$interfaces corba}
  IPlain = interface ['reader-plain']
    function PlainValue: Integer;
  end;
  {$interfaces com}
{$endif}
  TProvider = class(TComponent, ISentinel, IToken{$ifdef FPC}, IPlain{$endif})
    function QueryInterface({$ifdef FPC}constref{$else}const{$endif} IID: TGUID; out Obj): HResult; override;
      {$if defined(FPC) and not defined(WINDOWS)}cdecl{$else}stdcall{$ifend};
{$ifdef FPC}
    function PlainValue: Integer;
{$endif}
    function Sentinel: Integer;
    function Token: Int64;
  end;
  TWatched = class(TInterfacedObject, IToken)
    destructor Destroy; override;
    function Token: Int64;
  end;
  TClient = class(TComponent)
  private
    FLink, FViaSetter: IToken;
{$ifdef FPC}
    [Weak] FObserved: IToken;
    FPlain: IPlain;
{$endif}
    FPeer: TComponent;
    FCalls: Integer;
    procedure SetToken(const Value: IToken);
  published
    property Link: IToken read FLink write FLink;
    property ViaSetter: IToken read FViaSetter write SetToken;
{$ifdef FPC}
    property Plain: IPlain read FPlain write FPlain;
    property Observed: IToken read FObserved write FObserved;
{$endif}
    property Peer: TComponent read FPeer write FPeer;
  end;
var
  ForeignRoot: TComponent;
  Destroyed, Queries: Integer;

procedure Check(Ok: Boolean; const Detail: string);
begin
  if not Ok then begin
    WriteLn('FAIL ', Detail);
    Halt(1);
  end;
end;

function TProvider.QueryInterface({$ifdef FPC}constref{$else}const{$endif} IID: TGUID; out Obj): HResult;
  {$if defined(FPC) and not defined(WINDOWS)}cdecl{$else}stdcall{$ifend};
begin
  if IsEqualGUID(IID,IToken) then Inc(Queries);
  Result:=inherited QueryInterface(IID,Obj);
end;

{$ifdef FPC}
function TProvider.PlainValue: Integer;
begin Result:=41 end;
{$endif}

function TProvider.Sentinel: Integer;
begin Result := -11 end;

function TProvider.Token: Int64;
begin Result := 83000000013 end;

function TWatched.Token: Int64;
begin Result := 2 end;

destructor TWatched.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

procedure TClient.SetToken(const Value: IToken);
begin
  Inc(FCalls);
  FViaSetter := Value;
end;

function Lookup(const Name: string): TComponent;
begin
  if SameText(Name, 'Foreign') then Result := ForeignRoot else Result := nil;
end;

procedure ReadProperties(Client: TClient; const Lines: AnsiString);
var
  Text, Binary: TMemoryStream;
  Resource: AnsiString;
begin
  Resource := 'object Client: TClient'#10 + Lines + #10'end'#10;
  Text := TMemoryStream.Create;
  Binary := TMemoryStream.Create;
  try
    Text.WriteBuffer(Resource[1], Length(Resource));
    Text.Position := 0;
    ObjectTextToBinary(Text, Binary);
    Binary.Position := 0;
    Binary.ReadComponent(Client);
  finally
    Binary.Free;
    Text.Free;
  end;
end;

var
  Client: TClient;
  A, B: TProvider;
  Want: IToken;
begin
  Client := TClient.Create(nil);
  ForeignRoot := TComponent.Create(nil);
  RegisterFindGlobalComponentProc(Lookup);
  try
    A := TProvider.Create(Client);
    A.Name := 'First';
    ForeignRoot.Name := 'Foreign';
    B := TProvider.Create(ForeignRoot);
    B.Name := 'Second';
    TComponent.Create(Client).Name := 'Plain';

    ReadProperties(Client, '  Link = First'#10'  ViaSetter = Foreign.Second'#10'  Peer = First');
    GlobalFixupReferences;
    Check(Queries>=2,'both streaming paths query the provider');
    Want := A;
    Check(Pointer(Client.Link) = Pointer(Want), 'local typed view');
    Check(Client.Link.Token = 83000000013, 'local dispatch');
    Want := B;
    Check(Pointer(Client.ViaSetter) = Pointer(Want), 'cross-root typed view');
    Check((Client.ViaSetter.Token = 83000000013) and (Client.FCalls = 1), 'setter dispatch');
    Check(Client.Peer = A, 'object property');
    Want := nil;


    Client.Link := TWatched.Create;
    ReadProperties(Client, '  Link = nil');
    Check((Client.Link = nil) and (Destroyed = 1), 'nil releases previous field owner');
    Client.Link := TWatched.Create;
    ReadProperties(Client, '  Link = Plain');
    Check((Client.Link = nil) and (Destroyed = 2), 'unsupported interface releases previous owner');
    ReadProperties(Client, '  ViaSetter = nil');
    Check((Client.ViaSetter = nil) and (Client.FCalls = 2), 'nil setter called once');
{$ifdef FPC}
    ReadProperties(Client, '  Plain = First');
    Check(Client.Plain.PlainValue=41,'raw interface view');
    ReadProperties(Client, '  Plain = nil');
    Check(Client.Plain=nil,'raw interface cleared');
    ReadProperties(Client, '  Observed = Foreign.Second');
    GlobalFixupReferences;
    Check((Client.Observed<>nil) and (Client.Observed.Token=83000000013), 'weak typed view');
    B.Free;
    Check(Client.Observed=nil, 'typed weak property cleared when provider is destroyed');
{$endif}
  finally
    UnregisterFindGlobalComponentProc(Lookup);
    Client.Free;
    ForeignRoot.Free;
  end;
  WriteLn('READER_TYPED_COMPONENT_REFERENCE_PASS');
end.
