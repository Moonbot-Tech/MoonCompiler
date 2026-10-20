program RttiLifetimeAudit;
{$mode delphiunicode}
uses mormot.core.fpcx64mm, {$ifdef Unix}ffi.manager,{$endif} System.SysUtils, System.Rtti, System.TypInfo;

{$RTTI EXPLICIT FIELDS([vcPublic]) PROPERTIES([vcPublic]) METHODS([vcPublic])}
{$M+}
type
  ITracked = interface ['{037805C6-BC84-45C0-87AD-10A4DD1B12DE}'] end;
  TTracked = class(TInterfacedObject, ITracked)
    constructor Create;
    destructor Destroy; override;
  end;
  TData = record Ref: ITracked; Text: string; end;
  PData = ^TData;
  TCustom = record
    Ref: ITracked;
    Magic: Integer;
    class operator Initialize(var Dest: TCustom);
    class operator Copy(constref Source: TCustom; var Dest: TCustom);
  end;
  TRow = class
  public
    Ref: ITracked;
    Data: TData;
    Custom: TCustom;
    Number: Int64;
    class var StaticData: TData;
    property DataProp: TData read Data write Data;
    class property StaticProp: TData read StaticData write StaticData;
  end;
  TRecordRow = record
    Data: TData;
    property DataProp: TData read Data write Data;
  end;
  TRefProc = procedure(var Value: ITracked; out Other: ITracked);
  TRefFunc = function(var Value: ITracked): ITracked;
  ICallback = interface ['{9FFB371C-80DB-4E76-99BE-BCA33C7A32CD}']
    procedure Replace(var Value: ITracked; out Other: ITracked);
    function ReplaceAndReturn(var Value: ITracked): ITracked;
  end;
  THost = class
    procedure Invoke(Method: TRttiMethod; const Args: TValueArray; out Ret: TValue);
  end;
  PValue = ^TValue;
  PTracked = ^ITracked;
var Created, Destroyed, Checks, Copies, Calls: Integer;
    NewRef, OtherRef: ITracked;

procedure Check(Value: Boolean; const Name: string);
begin
  Inc(Checks);
  If not Value then begin Writeln('FAIL ', Name); Halt(1); end;
end;
constructor TTracked.Create;
begin inherited Create; Inc(Created); end;
destructor TTracked.Destroy;
begin Inc(Destroyed); inherited Destroy; end;
class operator TCustom.Initialize(var Dest: TCustom);
begin Dest.Magic := 12345; end;
class operator TCustom.Copy(constref Source: TCustom; var Dest: TCustom);
begin
  Check(Dest.Magic = 12345, 'custom initialized destination');
  Dest.Ref := Source.Ref;
  Dest.Magic := Source.Magic;
  Inc(Copies);
end;
procedure Callback(UserData: Pointer; const Args: TValueArray; out Ret: TValue);
begin
  Inc(Calls);
  PValue(@Args[0])^ := TValue.From<ITracked>(NewRef);
  If Length(Args) > 1 then PValue(@Args[1])^ := TValue.From<ITracked>(OtherRef)
  else Ret := TValue.From<ITracked>(OtherRef);
end;
procedure THost.Invoke(Method: TRttiMethod; const Args: TValueArray; out Ret: TValue);
begin
  Inc(Calls);
  PValue(@Args[1])^ := TValue.From<ITracked>(NewRef);
  If Length(Args) > 2 then PValue(@Args[2])^ := TValue.From<ITracked>(OtherRef)
  else Ret := TValue.From<ITracked>(OtherRef);
end;
procedure RunField(const Mode: string);
var C: TRttiContext; R: TRow; F: TRttiField; V: TValue; D: TData;
    U: TCustom; I, Before: Integer; Failed: Boolean;
begin
  C := TRttiContext.Create; R := TRow.Create;
  try
    If Mode = 'custom' then F := C.GetType(TRow).GetField('Custom')
    else If Mode = 'record' then F := C.GetType(TRow).GetField('Data')
    else F := C.GetType(TRow).GetField('Ref');
    Check(F <> nil, 'field RTTI');
    for I := 1 to 32 do begin
      If Mode = 'custom' then begin
        R.Custom.Ref := TTracked.Create; U.Ref := TTracked.Create;
        V := TValue.From<TCustom>(U); Before := Copies; F.SetValue(R, V);
        Check(Copies = Before + 1, 'one custom assignment');
        Check(R.Custom.Ref = U.Ref, 'custom value');
        U.Ref := nil; V := TValue.Empty; R.Custom.Ref := nil;
      end else If Mode = 'record' then begin
        R.Data.Ref := TTracked.Create; D.Ref := TTracked.Create;
        D.Text := StringOfChar('X', I + 100); V := TValue.From<TData>(D);
        F.SetValue(R, V); Check(R.Data.Ref = D.Ref, 'record value');
        D := Default(TData); V := TValue.Empty; R.Data := Default(TData);
      end else begin
        R.Ref := TTracked.Create; NewRef := TTracked.Create;
        V := TValue.From<ITracked>(NewRef); F.SetValue(R, V);
        Check(R.Ref = NewRef, 'field value');
        V := F.GetValue(R); F.SetValue(R, V); Check(R.Ref = NewRef, 'self value');
        Failed := False;
        try F.SetValue(R, TValue.From<Integer>(12)); except on EInvalidCast do Failed := True; end;
        Check(Failed and (R.Ref = NewRef), 'failed cast preserves');
        NewRef := nil; V := TValue.Empty; F.SetValue(R, V);
        Check(R.Ref = nil, 'empty clears');
      end;
      Check(Created = Destroyed, 'field owners reclaimed');
    end;
  finally R.Free; C.Free; end;
end;
procedure RunProperty(const Mode: string);
var C: TRttiContext; R: TRow; RR: TRecordRow; P: TRttiProperty;
    D: TData; V: TValue; I: Integer;
begin
  C := TRttiContext.Create; R := TRow.Create;
  try
    If Mode = 'recordprop' then P := C.GetType(TypeInfo(TRecordRow)).GetProperty('DataProp')
    else If Mode = 'staticprop' then P := C.GetType(TRow).GetProperty('StaticProp')
    else P := C.GetType(TRow).GetProperty('DataProp');
    Check(P <> nil, 'property RTTI');
    If Mode = 'staticprop' then
      Writeln('STATIC expected=', HexStr(@TRow.StaticData), ' setproc=', HexStr(PPropInfo(P.Handle)^.SetProc));
    for I := 1 to 32 do begin
      D.Ref := TTracked.Create; D.Text := StringOfChar('Y', 100+I);
      If Mode = 'staticprop' then TRow.StaticData.Ref := TTracked.Create
      else If Mode = 'recordprop' then RR.Data.Ref := TTracked.Create
      else R.Data.Ref := TTracked.Create;
      V := TValue.From<TData>(D);
      If Mode = 'staticprop' then P.SetValue(nil, V)
      else If Mode = 'recordprop' then P.SetValue(@RR, V)
      else P.SetValue(R, V);
      If Mode = 'staticprop' then Check(TRow.StaticData.Ref = D.Ref, 'static result')
      else If Mode = 'recordprop' then Check(RR.Data.Ref = D.Ref, 'record property result')
      else Check(R.Data.Ref = D.Ref, 'property result');
      If Mode = 'staticprop' then begin
        V := P.GetValue(nil);
        Check(PData(V.GetReferenceToRawData)^.Ref = D.Ref, 'static getter owns reference');
        P.SetValue(nil, V);
        Check(TRow.StaticData.Ref = D.Ref, 'static self assignment');
      end;
      D := Default(TData); V := TValue.Empty;
      If Mode = 'staticprop' then P.SetValue(nil, V)
      else If Mode = 'recordprop' then P.SetValue(@RR, V)
      else P.SetValue(R, V);
      Check(Created = Destroyed, 'property owners reclaimed');
    end;
  finally TRow.StaticData := Default(TData); R.Free; C.Free; end;
end;
procedure RunCallback(const Mode: string);
var C: TRttiContext; Impl: TMethodImplementation; Proc: TRefProc; Func: TRefFunc;
    Ref, Other: ITracked; Intf: ICallback; I: Integer; Host: THost;
begin
  C := TRttiContext.Create; Impl := nil; Host := THost.Create;
  try
    If Mode = 'virtual' then Intf := TVirtualInterface.Create(TypeInfo(ICallback), Host.Invoke) as ICallback
    else If Mode = 'callbackresult' then begin
      Impl := (C.GetType(TypeInfo(TRefFunc)) as TRttiInvokableType).CreateImplementation(nil, Callback);
      Func := TRefFunc(Impl.CodeAddress);
    end else begin
      Impl := (C.GetType(TypeInfo(TRefProc)) as TRttiInvokableType).CreateImplementation(nil, Callback);
      Proc := TRefProc(Impl.CodeAddress);
    end;
    for I := 1 to 32 do begin
      Ref := TTracked.Create; Other := TTracked.Create;
      NewRef := TTracked.Create; OtherRef := TTracked.Create;
      If Mode = 'virtual' then Intf.Replace(Ref, Other)
      else If Mode = 'callbackresult' then Other := Func(Ref)
      else Proc(Ref, Other);
      Check((Ref = NewRef) and (Other = OtherRef), 'callback values');
      Ref := nil; Other := nil; NewRef := nil; OtherRef := nil;
      Check(Created = Destroyed, 'callback owners reclaimed');
    end;
    If Mode = 'virtual' then begin
      Ref := TTracked.Create; NewRef := TTracked.Create; OtherRef := TTracked.Create;
      Other := Intf.ReplaceAndReturn(Ref);
      Check((Ref = NewRef) and (Other = OtherRef), 'virtual result');
      Ref := nil; Other := nil; NewRef := nil; OtherRef := nil;
      Check(Created = Destroyed, 'virtual return owners reclaimed');
    end;
    Check(Calls >= 32, 'callback executed');
  finally Intf := nil; Impl.Free; Host.Free; C.Free; end;
end;
procedure RunFresh;
var Ref: ITracked; V, Z: TValue; P: Pointer; I: Integer; D: TData;
begin
  for I := 1 to 32 do begin
    Ref := TTracked.Create; TValue.Make(@Ref, TypeInfo(ITracked), V);
    GetMem(P, SizeOf(ITracked)); FillChar(P^, SizeOf(ITracked), $A5);
    V.ExtractRawData(P); Ref := nil; V := TValue.Empty;
    Check(Created = Destroyed + 1, 'fresh extraction owns reference');
    PTracked(P)^ := nil; FreeMem(P);
    Z := TValue.Empty.Cast(TypeInfo(TData)); D := Z.AsType<TData>;
    Check((D.Ref = nil) and (D.Text = ''), 'empty record cast'); Z := TValue.Empty;
    Check(Created = Destroyed, 'fresh owners reclaimed');
  end;
end;
begin
  If (ParamStr(1) = 'callback') or (ParamStr(1) = 'callbackresult') or (ParamStr(1) = 'virtual') then RunCallback(ParamStr(1))
  else If (ParamStr(1) = 'property') or (ParamStr(1) = 'staticprop') or (ParamStr(1) = 'recordprop') then RunProperty(ParamStr(1))
  else If ParamStr(1) = 'fresh' then RunFresh
  else RunField(ParamStr(1));
  Check(Created = Destroyed, 'all tracked owners reclaimed');
  Writeln('AUDIT_PASS checks=', Checks, ' created=', Created, ' destroyed=', Destroyed, ' mode=', ParamStr(1));
end.
