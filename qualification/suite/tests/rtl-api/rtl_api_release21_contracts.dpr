program rtl_api_release21_contracts;

{$mode delphiunicode}

uses
  {$ifdef unix}cwstring,{$endif}
  SysUtils, Classes, DateUtils, Variants, Generics.Collections;

procedure Check(Condition: Boolean; const Name: string);
begin
  If not Condition then
    raise Exception.Create(Name);
end;

var
  GrowthCalls: Integer;
  RequestedCount: NativeInt;

function CustomGrowth(OldCapacity, NewCount: NativeInt): NativeInt;
begin
  Inc(GrowthCalls);
  RequestedCount := NewCount;
  Result := NewCount + 3;
end;

function BadGrowth(OldCapacity, NewCount: NativeInt): NativeInt;
begin
  Result := NewCount - 1;
end;

procedure Collections;
var
  Old: TGrowCollectionFunc;
  List: Classes.TList;
  Strings: TStringList;
  Values: TList<Integer>;
  Stack: TStack<Integer>;
begin
  List := Classes.TList.Create;
  Strings := TStringList.Create;
  Values := TList<Integer>.Create;
  Stack := TStack<Integer>.Create;
  Old := SetGrowCollectionFunc(CustomGrowth);
  try
    GrowthCalls := 0;
    List.Add(Pointer(1));
    Check((GrowthCalls > 0) and (List.Capacity = 4), 'TList growth hook');
    GrowthCalls := 0;
    Strings.Add('one');
    Check((GrowthCalls > 0) and (Strings.Capacity = 4), 'TStringList growth hook');
    GrowthCalls := 0;
    Values.AddRange([1, 2, 3, 4, 5, 6]);
    Check((GrowthCalls = 1) and (RequestedCount = 6) and (Values.Capacity = 9), 'range growth request');
    GrowthCalls := 0;
    Stack.Push(42);
    Check((GrowthCalls > 0) and (Stack.Pop = 42), 'TStack growth hook');
    Check(GrowCollection(20, 10) = 20, 'growth does not shrink');
    SetGrowCollectionFunc(BadGrowth);
    try
      GrowCollection(0, 10);
      Check(False, 'invalid callback accepted');
    except
      on EArgumentOutOfRangeException do ;
    end;
  finally
    SetGrowCollectionFunc(Old);
    Stack.Free;
    Values.Free;
    Strings.Free;
    List.Free;
  end;
end;

type
  TNumber = record
    Value: Integer;
    function Implicit: Integer;
    function Shadowed: Integer;
  end;
  TNumberHelper = record helper for TNumber
    function Twice: Integer;
    function GetAnswer: Integer;
    property Answer: Integer read GetAnswer;
  end;

function TNumberHelper.Twice: Integer;
begin
  Result := Value * 2;
end;

function TNumberHelper.GetAnswer: Integer;
begin
  Result := Twice + 1;
end;

function TNumber.Implicit: Integer;
begin
  Result := Answer + Twice;
end;

function TNumber.Shadowed: Integer;
var
  Answer: Integer;
begin
  Answer := 99;
  Result := Answer + Self.Answer;
end;

procedure Helpers;
var
  N: TNumber;
begin
  N.Value := 5;
  Check(N.Implicit = 21, 'implicit Self helper');
  Check(N.Shadowed = 110, 'local shadows helper');
  with N do
    Check(Answer = 11, 'with helper scope');
end;

type
  TUnicodeHandler = class(TInvokeableVariantType)
  public
    LastName: string;
    procedure Clear(var V: TVarData); override;
    procedure Copy(var Dest: TVarData; const Source: TVarData; const Indirect: Boolean); override;
    function GetProperty(var Dest: TVarData; const V: TVarData; const Name: string): Boolean; override;
    function SetProperty(const V: TVarData; const Name: string; const Value: TVarData): Boolean; override;
    function DoFunction(var Dest: TVarData; const V: TVarData; const Name: string;
      const Arguments: TVarDataArray): Boolean; override;
    function DoProcedure(const V: TVarData; const Name: string; const Arguments: TVarDataArray): Boolean; override;
  end;
  TCaseHandler = class(TUnicodeHandler)
  protected
    function FixupIdent(const AText: string): string; override;
  end;

procedure TUnicodeHandler.Clear(var V: TVarData);
begin
  V.VType := varEmpty;
end;

procedure TUnicodeHandler.Copy(var Dest: TVarData; const Source: TVarData; const Indirect: Boolean);
begin
  Dest := Source;
end;

function TUnicodeHandler.GetProperty(var Dest: TVarData; const V: TVarData; const Name: string): Boolean;
begin
  LastName := Name;
  Variant(Dest) := Name;
  Result := True;
end;

function TUnicodeHandler.SetProperty(const V: TVarData; const Name: string; const Value: TVarData): Boolean;
begin
  LastName := Name;
  Result := True;
end;

function TUnicodeHandler.DoFunction(var Dest: TVarData; const V: TVarData; const Name: string;
  const Arguments: TVarDataArray): Boolean;
begin
  Result := GetProperty(Dest, V, Name);
end;

function TUnicodeHandler.DoProcedure(const V: TVarData; const Name: string; const Arguments: TVarDataArray): Boolean;
begin
  LastName := Name;
  Result := True;
end;

function TCaseHandler.FixupIdent(const AText: string): string;
begin
  Result := AText;
end;

procedure VariantNames;
var
  Handler: TUnicodeHandler;
  CaseHandler: TCaseHandler;
  Invoke: IVarInvokeable;
  V, R: Variant;
  Name: string;
begin
  Handler := TUnicodeHandler.Create;
  CaseHandler := TCaseHandler.Create;
  try
    TVarData(V).VType := Handler.VarType;
    R := V.MiXeD;
    Check(string(R) = 'MIXED', 'default FixupIdent');
    Check(Supports(Handler, IVarInvokeable, Invoke), 'IVarInvokeable identity');
    Name := #$041A#$043B#$044E#$0447#$D83D#$DE80;
    Check(Invoke.GetProperty(TVarData(R), TVarData(V), Name), 'Unicode property call');
    Check(string(R) = Name, 'Unicode property name');
    Check(Invoke.SetProperty(TVarData(V), Name, TVarData(R)), 'Unicode setter call');
    Check(Handler.LastName = Name, 'Unicode setter name');
    Check(Invoke.DoFunction(TVarData(R), TVarData(V), Name, nil), 'Unicode function call');
    Check(Invoke.DoProcedure(TVarData(V), Name, nil), 'Unicode procedure call');
    Check(Handler.LastName = Name, 'Unicode procedure name');
    VarClear(V);
    TVarData(V).VType := CaseHandler.VarType;
    R := V.MiXeD;
    Check(string(R) = 'MiXeD', 'overridden FixupIdent');
  finally
    Invoke := nil;
    VarClear(R);
    VarClear(V);
    CaseHandler.Free;
    Handler.Free;
  end;
end;

type
  TSyntheticZone = class(TTimeZone)
  protected
    function DoGetID: string; override;
    function DoGetDisplayName(const Value: TDateTime; const ForceDaylight: Boolean): string; override;
    procedure DoGetOffsetsAndType(const Value: TDateTime; out Offset, Save: Int64;
      out Kind: TLocalTimeType); override;
  end;

function TSyntheticZone.DoGetID: string;
begin
  Result := 'Test/HalfHour';
end;

function TSyntheticZone.DoGetDisplayName(const Value: TDateTime; const ForceDaylight: Boolean): string;
begin
  If IsDaylightTime(Value, ForceDaylight) then
    Result := 'Summer'
  else
    Result := 'Winter';
end;

procedure TSyntheticZone.DoGetOffsetsAndType(const Value: TDateTime; out Offset, Save: Int64;
  out Kind: TLocalTimeType);
var
  Start, Finish: TDateTime;
begin
  Offset := 10 * 3600 + 1800;
  Save := 1800;
  Start := EncodeDateTime(YearOf(Value), 4, 1, 2, 0, 0, 0);
  Finish := EncodeDateTime(YearOf(Value), 10, 1, 2, 0, 0, 0);
  If (Value >= Start) and (Value < IncSecond(Start, Save)) then
    Kind := lttInvalid
  else If (Value >= IncSecond(Finish, -Save)) and (Value < Finish) then
    Kind := lttAmbiguous
  else If (Value >= Start) and (Value < Finish) then
    Kind := lttDaylight
  else
    Kind := lttStandard;
end;

procedure DerivedTimeZone;
var
  Zone: TSyntheticZone;
  Local, UTC: TDateTime;
begin
  Zone := TSyntheticZone.Create;
  try
    Check(Zone.HasDST(EncodeDate(2026, 1, 1)), 'HasDST queried in winter');
    Local := EncodeDateTime(2026, 10, 1, 1, 45, 0, 0);
    Check(Zone.IsAmbiguousTime(Local), 'half-hour fold');
    UTC := Zone.ToUniversalTime(Local);
    Check(SecondsBetween(UTC, Zone.ToUniversalTime(Local, True)) = 1800, 'fold selection');
    Check(Abs(Zone.ToLocalTime(UTC) - Local) < 0.1 / SecsPerDay, 'fold UTC standard round trip');
    Check(Abs(Zone.ToLocalTime(Zone.ToUniversalTime(Local, True)) - Local) < 0.1 / SecsPerDay,
      'fold UTC daylight round trip');
    Local := EncodeDateTime(2026, 4, 1, 2, 15, 0, 0);
    Check(Zone.IsInvalidTime(Local), 'half-hour gap');
    try
      Zone.ToUniversalTime(Local);
      Check(False, 'invalid local accepted');
    except
      on ELocalTimeInvalid do ;
    end;
    Check(Zone.GetDisplayName(EncodeDate(2026, 7, 1)) = 'Summer', 'derived display hook');
    Check(Zone.GetAbbreviation(EncodeDate(2026, 1, 1)) = 'GMT+10:30', 'half-hour abbreviation');
  finally
    Zone.Free;
  end;
end;

begin
  Collections;
  Helpers;
  VariantNames;
  DerivedTimeZone;
  WriteLn('RTL_API_RELEASE21_CONTRACTS_OK');
end.
