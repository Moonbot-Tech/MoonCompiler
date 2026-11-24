{$define BREADTH_HAS_EXTENDED_METHODS}
{$ifdef FPC}
  {$if FPC_FULLVERSION < 30301}
    {$undef BREADTH_HAS_EXTENDED_METHODS}
  {$endif}
{$endif}

{$ifdef BREADTH_HAS_EXTENDED_METHODS}
{ The public method table exposes an inter-unit callable entry with a managed result. }

procedure RunBreadthRttiEndpoint;
type
  TPacketCall = function(Left: Int64; Scale: Double; const Text: UnicodeString; Right: Int64): UnicodeString of object; cdecl;
var
  Context: TRttiContext;
  Method: TRttiMethod;
  Endpoint: TBreadthRttiEndpoint;
  Params: TArray<TRttiParameter>;
  Link: TMethod;
  Call: TPacketCall;
  Text: UnicodeString;
begin
  Endpoint := TBreadthRttiEndpoint.Create;
  try
    Context := TRttiContext.Create;
    try
      Method := Context.GetType(TypeInfo(TBreadthRttiEndpoint)).GetMethod('Packet');
      Check((Method <> nil) and (Method.CodeAddress <> nil), 'breadth-rtti-packet-finds-public-method-in-compiled-unit');
      If (Method = nil) or (Method.CodeAddress = nil) then
        Exit;
      Params := Method.GetParameters;
      Check((Length(Params) = 4) and (Params[0].ParamType = Context.GetType(TypeInfo(Int64)))
        and (Params[1].ParamType = Context.GetType(TypeInfo(Double))) and (Params[2].ParamType = Context.GetType(TypeInfo(UnicodeString)))
        and (Params[3].ParamType = Context.GetType(TypeInfo(Int64))) and (Method.ReturnType = Context.GetType(TypeInfo(UnicodeString))),
        'breadth-rtti-packet-reports-scalar-and-managed-argument-types');
      Link.Code := Method.CodeAddress;
      Link.Data := Endpoint;
      Call := TPacketCall(Link);
      Text := Call(OpaqueI(91000000013), OpaqueD(-3.125), 'tag'#0'unit', OpaqueI(-87000000021));
      Check((Endpoint.Mark = 3999999967) and (Text = 'tag'#0'unit!'), 'breadth-rtti-packet-call-keeps-registers-and-hidden-result');
    finally
      Context.Free;
    end;
  finally
    Endpoint.Free;
  end;
end;
{$endif}
