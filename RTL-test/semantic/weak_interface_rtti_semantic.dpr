program weak_interface_rtti_semantic;
{$IFDEF FPC}{$MODE DELPHIUNICODE}{$MODESWITCH PREFIXEDATTRIBUTES}{$ENDIF}
{$APPTYPE CONSOLE}
{$RTTI EXPLICIT FIELDS([vcPublic]) PROPERTIES([vcPublished,vcPublic]) METHODS([])}
uses Classes, SysUtils, TypInfo, Rtti;

type
  IService = interface
    ['{B69ECF91-FB9E-40DB-864B-5AF2BFE93E9A}']
    function ServiceNumber: Integer;
  end;
  TService = class(TInterfacedObject, IService)
    function ServiceNumber: Integer;
  end;
  WeakAttribute = class(TCustomAttribute);
  TRow = record
    Tag: NativeInt;
    [System.Weak] Link: IService;
  end;
  TLinks = class(TPersistent)
  public
    [System.Weak] First, Second: IService;
    [Weak] Held: IService;
    Data: TRow;
    property Nested: IService read Data.Link write Data.Link;
{$IFDEF FPC}
    class var Shared: TRow;
    class property SharedLink: IService read Shared.Link write Shared.Link;
{$ENDIF}
  published
    property Mixed: IService read Held write First;
    property Strong: IService read Second write Held;
  end;

function TService.ServiceNumber: Integer;
begin
  Result:=41;
end;

procedure SetField(F: TRttiField; Instance: TObject; const V: IService);
begin
  F.SetValue(Instance,TValue.From<IService>(V));
end;

procedure SetProperty(P: TRttiProperty; Instance: TObject; const V: IService);
begin
  P.SetValue(Instance,TValue.From<IService>(V));
end;

procedure Check(Mode: Integer);
var
  Links: TLinks;
  Obj: TService;
  Target: IService;
  Context: TRttiContext;
begin
  Context:=TRttiContext.Create;
  Links:=TLinks.Create;
  try
    Obj:=TService.Create;
    Target:=Obj;
    case Mode of
      0: Links.First:=Target;
      1: SetInterfaceProp(Links,'Mixed',Target);
      2: SetField(Context.GetType(TLinks).GetField('First'),Links,Target);
      3: SetProperty(Context.GetType(TLinks).GetProperty('Mixed'),Links,Target);
{$IFDEF FPC}
      4: SetRawInterfaceProp(Links,'Mixed',Pointer(Target));
{$ENDIF}
      7: SetOrdProp(Links,'Mixed',NativeInt(Pointer(Target)));
      5: SetField(Context.GetType(TLinks).GetField('Held'),Links,Target);
      6: SetInterfaceProp(Links,'Strong',Target);
    else
      Halt(10);
    end;
    if not (Mode in [5,6]) then begin
      if (Obj.RefCount<>1) or (Pointer(Links.First)<>Pointer(Target)) then Halt(20+Mode);
      if Links.First.ServiceNumber<>41 then Halt(30+Mode);
      Links.Second:=Target;
      Target:=nil;
      if (PPointer(@Links.First)^<>nil) or (PPointer(@Links.Second)^<>nil) then Halt(40+Mode);
    end else begin
      if (Obj.RefCount<>2) or (Pointer(Links.Held)<>Pointer(Target)) then Halt(50+Mode);
      Links.Second:=Target;
      Target:=nil;
      if Links.Held.ServiceNumber<>41 then Halt(60+Mode);
      Links.Held:=nil;
      if PPointer(@Links.Second)^<>nil then Halt(70+Mode);
    end;
  finally
    Links.Free;
    Context.Free;
  end;
end;

{$IFDEF FPC}
procedure CheckNested;
var
  Instance: TLinks;
  T: TService;
  V: IService;
  C: TRttiContext;
  P: TRttiProperty;
begin
  Instance:=TLinks.Create;
  C:=TRttiContext.Create;
  try
    T:=TService.Create;
    V:=T;
    P:=C.GetType(TLinks).GetProperty('Nested');
    if P=nil then Halt(80);
    SetProperty(P,Instance,V);
    if Pointer(Instance.Data.Link)<>Pointer(V) then Halt(81);
    P:=C.GetType(TLinks).GetProperty('SharedLink');
    if P=nil then Halt(84);
    SetProperty(P,nil,V);
    SetInterfaceProp(nil,PPropInfo(P.Handle),V);
    SetOrdProp(Instance,PPropInfo(P.Handle),NativeInt(Pointer(V)));
    SetRawInterfaceProp(Instance,PPropInfo(P.Handle),Pointer(V));
    if (T.RefCount<>1) or (Pointer(TLinks.Shared.Link)<>Pointer(V)) then Halt(82);
    V:=nil;
    if (PPointer(@TLinks.Shared.Link)^<>nil) or (PPointer(@Instance.Data.Link)^<>nil) then Halt(83);
  finally
    C.Free;
    Instance.Free;
  end;
end;
{$ENDIF}

type
  TAttributeClass = class of TUnimplementedAttribute;
var
  I: Integer;
  Attr: TAttributeClass;
begin
  Attr := System.WeakAttribute;
  if Attr <> System.WeakAttribute then Halt(88);
  for I:=0 to 7 do Check(I);
  {$IFDEF FPC}CheckNested;{$ENDIF}
  WriteLn('WEAK_INTERFACE_RTTI_PASS');
end.
