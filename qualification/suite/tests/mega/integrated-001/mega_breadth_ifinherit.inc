{ An extended interface keeps its inherited prefix callable after an upcast and a query back. }

type
  IBreadthExtendedTag = interface(IBreadthTaggedOwner)
    ['{5B959516-B4A5-4A27-A48E-39565DE20E79}']
    function Annotate(const Prefix: AnsiString; Key: Int64; Factor: Double): TCrossEntry;
  end;

  TBreadthExtendedTag = class(TBreadthTaggedOwner, IBreadthExtendedTag)
    function Annotate(const Prefix: AnsiString; Key: Int64; Factor: Double): TCrossEntry;
  end;

function TBreadthExtendedTag.Annotate(const Prefix: AnsiString; Key: Int64; Factor: Double): TCrossEntry;
begin
  Result.Code := Tag + Key + Trunc(Factor * 32.0);
  Result.Text := Prefix + '-extended';
end;

procedure BreadthHoldInheritedInterface;
var
  Extended, Recovered: IBreadthExtendedTag;
  Base: IBreadthTaggedOwner;
  Value: TCrossEntry;
begin
  Extended := TBreadthExtendedTag.Create;
  Base := Extended;
  Check((Base.Tag = 74000000051) and (Extended.Tag = 74000000051), 'breadth-interface-inheritance-preserves-prefix-slot');
  Check(Supports(Base, IBreadthExtendedTag, Recovered), 'breadth-interface-inheritance-queries-derived-view-from-prefix');
  If Recovered = nil then
    Exit;
  Check((Base as IInterface) = (Recovered as IInterface), 'breadth-interface-inheritance-preserves-canonical-identity');
  Extended := nil;
  Base := nil;
  Value := Recovered.Annotate(AnsiString('route'), OpaqueI(-38000000071), OpaqueD(-1.375));
  Check((TBreadthTaggedOwner.Destroyed = 0) and (Value.Code = 35999999936) and (Value.Text = 'route-extended'),
    'breadth-interface-inheritance-tail-slot-retains-owner-and-managed-result');
  Mix(UInt64(Value.Code));
end;

procedure RunBreadthInheritedInterface;
begin
  TBreadthTaggedOwner.Destroyed := 0;
  BreadthHoldInheritedInterface;
  Check(TBreadthTaggedOwner.Destroyed = 1, 'breadth-interface-inheritance-releases-the-shared-owner');
end;
