program interface_lookup_semantic;

{$mode delphiunicode}{$H+}

uses SysUtils;

type
  IAlpha = interface
    ['{79C1FD02-142D-4E32-9002-010203040506}']
    function Alpha: Integer;
  end;
  IBeta = interface
    ['{79C1FD02-142D-4E32-9002-010203040507}']
    function Beta: Integer;
  end;
  IGamma = interface
    ['{79C1FD02-142D-4E32-9002-010203040508}']
    function Gamma: Integer;
  end;
  TProbe = class(TInterfacedObject, IAlpha, IBeta)
    function Alpha: Integer;
    function Beta: Integer;
  end;
  TChild = class(TProbe, IGamma)
    function Gamma: Integer;
  end;
  TDelegated = class(TInterfacedObject, IBeta)
  private
    FInner: IBeta;
  public
    constructor Create;
    property Inner: IBeta read FInner implements IBeta;
  end;
  TDynamic = class(TProbe, IInterface)
    Queries: Integer;
    function QueryInterface(constref IID: TGUID; out Obj): HRESULT;
      {$ifdef WINDOWS}stdcall{$else}cdecl{$endif}; reintroduce;
  end;
  {$interfaces corba}
  IPlain = interface
    ['plain-interface']
    function Plain: Integer;
  end;
  {$interfaces com}
  TMixed = class(TProbe, IPlain)
    function Plain: Integer;
  end;

procedure Check(Value: Boolean);
begin
  if not Value then Halt(1);
end;

function TProbe.Alpha: Integer;
begin
  Result := 11;
end;

function TProbe.Beta: Integer;
begin
  Result := 22;
end;

function TChild.Gamma: Integer;
begin
  Result := 33;
end;

function TMixed.Plain: Integer;
begin
  Result := 44;
end;

constructor TDelegated.Create;
begin
  inherited;
  FInner := TProbe.Create;
end;

function TDynamic.QueryInterface(constref IID: TGUID; out Obj): HRESULT;
begin
  Inc(Queries);
  Pointer(Obj) := nil;
  Result := E_NOINTERFACE;
end;

var
  Obj: TChild;
  Dynamic: TDynamic;
  Owner: IInterface;
  A: IAlpha;
  B: IBeta;
  C: IGamma;
  G, Changed: TGUID;
  I: Integer;
  Weak: Pointer;
  Mixed: TMixed;
  Plain: IPlain;
  Unaligned: packed record
    Prefix: Byte;
    Guid: TGUID;
  end;
begin
  Obj := TChild.Create;
  Owner := Obj;
  Check(Supports(Obj, IAlpha, A) and (A.Alpha = 11));
  Check(Supports(Obj, IBeta, B) and (B.Beta = 22));
  Check(Supports(Obj, IGamma, C) and (C.Gamma = 33));
  Check(Supports(TChild, IAlpha) and Supports(TChild, IGamma));
  G := IAlpha;
  for I := 0 to 15 do
  begin
    Changed := G;
    PByte(@Changed)[I] := PByte(@Changed)[I] xor $80;
    Check(TChild.GetInterfaceEntry(Changed) = nil);
  end;
  Weak := nil;
  Check(Obj.GetInterfaceWeak(G, Weak) and (Weak = Pointer(A)));
  Check(Obj.RefCount = 4);
  Unaligned.Guid := G;
  Check(TChild.GetInterfaceEntry(Unaligned.Guid) = TChild.GetInterfaceEntry(G));
  A := nil;
  B := nil;
  C := nil;
  Owner := TDelegated.Create;
  Check(Supports(Owner, IBeta, B) and (B.Beta = 22));
  B := nil;
  Owner := nil;
  Dynamic := TDynamic.Create;
  Owner := Dynamic;
  Check(Supports(Dynamic, IBeta, B) and (B.Beta = 22));
  Check(Dynamic.Queries = 1);
  B := nil;
  Check(not Supports(Owner, IBeta, B));
  Check((Dynamic.Queries = 2) and (B = nil));
  Owner := nil;
  Mixed := TMixed.Create;
  Owner := Mixed;
  Check(Mixed.GetInterfaceByStr('plain-interface', Plain) and (Plain.Plain = 44));
  Check(Supports(Mixed, IAlpha, A) and (A.Alpha = 11));
  Check(TMixed.GetInterfaceEntry(Changed) = nil);
  A := nil;
  Owner := nil;
  Check(not Supports(TObject(nil), IAlpha, A));
  WriteLn('INTERFACE_LOOKUP_OK');
end.
