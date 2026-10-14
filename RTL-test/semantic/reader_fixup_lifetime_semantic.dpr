program reader_fixup_lifetime_semantic;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$mode delphiunicode}{$ENDIF}
uses
{$IFDEF UNIX}cthreads,{$ENDIF}
  System.Classes, System.SysUtils;

type
  TCancelNames = class(TStringList)
  public
    CancelInAdd: Boolean;
    function IndexOf(const S: string): Integer; override;
    function Add(const S: string): Integer; override;
  end;
  TSlot = class(TPersistent)
  private
    FRef: TComponent;
  published
    property Ref: TComponent read FRef write FRef;
  end;

  TReceiver = class(TComponent)
  private
    FRef, FSecond: TComponent;
    FSlot: TSlot;
    FDead: Boolean;
    procedure SetRef(Value: TComponent);
  public
    KeepStorage, FreeSelf: Boolean;
    constructor Create(Owner: TComponent); override;
    destructor Destroy; override;
    procedure FreeInstance; override;
  published
    property Ref: TComponent read FRef write SetRef;
    property Second: TComponent read FSecond write FSecond;
    property Third: TComponent read FSecond write SetRef;
    property Slot: TSlot read FSlot;
  end;

var
  A, B, C, KillOnLookup, KillOnSet: TReceiver;
  Later: TComponent;
  Held: TList;
  Writes, DeadWrites: Integer;
  RaiseOnLookup, RaiseOnSet, QueryOnLookup, QueryOnSet: Boolean;
  KillAfterFirstWrite: TReceiver;
  ReenterMode: Integer;
  Reentered: Boolean;

procedure Check(Condition: Boolean; const MessageText: string);
begin
  If not Condition then
    raise Exception.Create(MessageText);
end;

function TCancelNames.IndexOf(const S: string): Integer;
begin
  Result := inherited IndexOf(S);
  If not CancelInAdd then
    FreeAndNil(A);
end;

function TCancelNames.Add(const S: string): Integer;
begin
  Result := inherited Add(S);
  If CancelInAdd then
    FreeAndNil(A);
end;

procedure Reenter(Mode: Integer);
begin
  If Reentered then
    Exit;
  Reentered := True;
  If Mode in [1, 3] then
    RemoveFixupReferences(nil, 'Later')
  else
    GlobalFixupReferences;
end;

procedure ExpectNoReferences;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    GetFixupReferenceNames(nil, List);
    Check(List.Count = 0, 'nested reference query saw a dead receiver');
    GetFixupInstanceNames(nil, 'Later', List);
    Check(List.Count = 0, 'nested instance query saw a dead receiver');
  finally
    List.Free;
  end;
end;

constructor TReceiver.Create(Owner: TComponent);
begin
  inherited;
  FSlot := TSlot.Create;
end;

destructor TReceiver.Destroy;
begin
  FDead := True;
  FreeAndNil(FSlot);
  inherited;
end;

procedure TReceiver.FreeInstance;
begin
  // Retain the allocation to detect a stale setter deterministically, without relying on heap reuse.
  If KeepStorage then begin
    CleanupInstance;
    Held.Add(Self);
  end else
    inherited;
end;

procedure TReceiver.SetRef(Value: TComponent);
begin
  Inc(Writes);
  If FDead then
    Inc(DeadWrites);
  FRef := Value;
  If ReenterMode in [3, 4] then
    Reenter(ReenterMode);
  If (Writes = 2) and (KillAfterFirstWrite <> nil) then begin
    KillOnSet := KillAfterFirstWrite;
    KillAfterFirstWrite := nil;
  end;
  If KillOnSet <> nil then begin
    If KillOnSet = A then A := nil;
    If KillOnSet = B then B := nil;
    If KillOnSet = C then C := nil;
    FreeAndNil(KillOnSet);
  end;
  If FreeSelf then begin
    If A = Self then A := nil;
    If B = Self then B := nil;
    If C = Self then C := nil;
    Free;
  end;
  If QueryOnSet then
    ExpectNoReferences;
  If RaiseOnSet then begin
    RaiseOnSet := False;
    raise Exception.Create('setter sentinel');
  end;
end;

function FindLater(const Name: string): TComponent;
begin
  Result := nil;
  If not SameText(Name, 'Later') then
    Exit;
  If ReenterMode in [1, 2] then
    Reenter(ReenterMode);
  If KillOnLookup <> nil then begin
    If KillOnLookup = A then A := nil;
    If KillOnLookup = B then B := nil;
    If KillOnLookup = C then C := nil;
    FreeAndNil(KillOnLookup);
  end;
  If QueryOnLookup then
    ExpectNoReferences;
  If RaiseOnLookup then begin
    RaiseOnLookup := False;
    raise Exception.Create('lookup sentinel');
  end;
  Result := Later;
end;

procedure Load(Receiver: TReceiver; const Properties: string);
var
  Text: TStringStream;
  Binary: TMemoryStream;
  Reader: TReader;
begin
  Text := TStringStream.Create('object Receiver: TReceiver' + sLineBreak + Properties + sLineBreak + 'end');
  Binary := TMemoryStream.Create;
  try
    ObjectTextToBinary(Text, Binary);
    Binary.Position := 0;
    Reader := TReader.Create(Binary, 4096);
    try
      Reader.ReadRootComponent(Receiver);
    finally
      Reader.Free;
    end;
  finally
    Binary.Free;
    Text.Free;
  end;
end;

function Names(Root: TComponent = nil): string;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    GetFixupReferenceNames(Root, List);
    Result := List.CommaText;
  finally
    List.Free;
  end;
end;

procedure MakeTarget;
var
  Child: TComponent;
begin
  Later := TComponent.Create(nil);
  Later.Name := 'Later';
  Child := TComponent.Create(Later);
  Child.Name := 'Child';
end;

procedure Reset;
var
  I: Integer;
begin
  KillOnLookup := nil;
  KillOnSet := nil;
  KillAfterFirstWrite := nil;
  ReenterMode := 0;
  Reentered := False;
  QueryOnLookup := False;
  QueryOnSet := False;
  RaiseOnLookup := False;
  RaiseOnSet := False;
  FreeAndNil(A);
  FreeAndNil(B);
  FreeAndNil(C);
  FreeAndNil(Later);
  Check(Names = '', 'destruction left an unresolved receiver');
  For I := 0 to Held.Count - 1 do
    FreeMem(Held[I]);
  Held.Clear;
  Writes := 0;
  DeadWrites := 0;
end;

procedure OrdinaryCases;
var
  List: TStringList;
begin
  RemoveFixups(nil);
  A := TReceiver.Create(nil);
  Load(A, 'Ref = Later.Child');
  Check(Names = 'Later', 'missing initial reference');
  FreeAndNil(A);
  Check(Names = '', 'freed root remains registered');

  A := TReceiver.Create(nil);
  B := TReceiver.Create(nil);
  C := TReceiver.Create(nil);
  Load(A, 'Ref = Later.Child' + sLineBreak + 'Second = Later.Child');
  Load(B, 'Slot.Ref = Later.Child');
  Load(C, 'Ref = Later.Child');
  FreeAndNil(A);
  Check(Names(B) = 'Later', 'unrelated persistent reference was removed');
  Check(Names(C) = 'Later', 'unrelated component reference was removed');
  FreeAndNil(B.FSlot);
  Check(Names(B) = '', 'freed persistent property remains registered');
  MakeTarget;
  GlobalFixupReferences;
  Check(C.Ref = Later.FindComponent('Child'), 'surviving receiver did not resolve');
  Check(Names = '', 'resolved entry remains');
  Reset;

  A := TReceiver.Create(nil);
  Load(A, 'Ref = Later.Child');
  RemoveFixups(A);
  RemoveFixups(A);
  MakeTarget;
  GlobalFixupReferences;
  Check(A.Ref = nil, 'explicit removal still assigned property');
  Reset;

  A := TReceiver.Create(nil);
  B := TReceiver.Create(nil);
  Load(A, 'Ref = Later.Child' + sLineBreak + 'Second = Other.Child');
  Load(B, 'Ref = Later.Child');
  RemoveFixupReferences(A, 'Later');
  Check((Names(A) = 'Other') and (Names(B) = 'Later'), 'root-filtered cancellation removed live references');
  RedirectFixupReferences(A, 'Other', 'Later');
  List := TStringList.Create;
  try
    GetFixupInstanceNames(A, 'Later', List);
    Check(List.CommaText = 'Child', 'redirect lost the remaining relative path');
  finally
    List.Free;
  end;
  MakeTarget;
  GlobalFixupReferences;
  Check((A.Ref = nil) and (A.Second = Later.FindComponent('Child')) and (B.Ref = A.Second),
    'partial cancellation or redirection corrupted live resolution');
  Reset;
end;

procedure CallbackCases;
begin
  A := TReceiver.Create(nil);
  A.KeepStorage := True;
  Load(A, 'Ref = Later.Child');
  MakeTarget;
  KillOnLookup := A;
  GlobalFixupReferences;
  Check((Writes = 0) and (DeadWrites = 0), 'lookup callback destroyed receiver before assignment');
  Reset;

  A := TReceiver.Create(nil);
  A.KeepStorage := True;
  Load(A, 'Ref = Later.Child');
  A.FreeSelf := True;
  MakeTarget;
  GlobalFixupReferences;
  Check((Writes = 1) and (DeadWrites = 0), 'setter self-destruction corrupted resolution');
  Reset;

  A := TReceiver.Create(nil);
  B := TReceiver.Create(nil);
  Load(A, 'Ref = Later.Child');
  Load(B, 'Ref = Later.Child');
  KillOnSet := A;
  MakeTarget;
  GlobalFixupReferences;
  Check((A = nil) and (B.Ref = Later.FindComponent('Child')) and (Writes = 1),
    'setter did not cancel another pending receiver');
  Reset;
end;

procedure ExpectResolveException(const MessageText: string);
var
  Caught: Boolean;
begin
  Caught := False;
  try
    GlobalFixupReferences;
  except
    on E: Exception do begin
      Check(E.Message = MessageText, 'unexpected exception: ' + E.Message);
      Caught := True;
    end;
  end;
  Check(Caught, 'missing expected exception');
end;

procedure ExtraCases;
begin
  A := TReceiver.Create(nil);
  B := TReceiver.Create(nil);
  Load(A, 'Ref = Later.Child');
  Load(B, 'Ref = Later.Child');
  KillOnLookup := A;
  MakeTarget;
  GlobalFixupReferences;
  Check((A = nil) and (B.Ref = Later.FindComponent('Child')) and (Writes = 1),
    'lookup did not cancel another pending receiver');
  Reset;

  A := TReceiver.Create(nil);
  B := TReceiver.Create(nil);
  Load(A, 'Ref = Later.Child');
  Load(B, 'Ref = Later.Child');
  KillAfterFirstWrite := B;
  MakeTarget;
  GlobalFixupReferences;
  Check((B = nil) and (A.Ref = Later.FindComponent('Child')) and (Writes = 2),
    'destruction of previously resolved receiver corrupted traversal');
  Reset;

  A := TReceiver.Create(nil);
  A.KeepStorage := True;
  Load(A, 'Ref = Later.Child' + sLineBreak + 'Third = Later.Child');
  A.FreeSelf := True;
  QueryOnSet := True;
  MakeTarget;
  GlobalFixupReferences;
  Check((Writes = 1) and (DeadWrites = 0), 'second reference called a destroyed receiver');
  Reset;

  A := TReceiver.Create(nil);
  A.KeepStorage := True;
  Load(A, 'Ref = Later.Child');
  MakeTarget;
  KillOnLookup := A;
  QueryOnLookup := True;
  RaiseOnLookup := True;
  ExpectResolveException('lookup sentinel');
  Check((Writes = 0) and (DeadWrites = 0), 'lookup exception assigned a dead receiver');
  Reset;

  A := TReceiver.Create(nil);
  A.KeepStorage := True;
  Load(A, 'Ref = Later.Child' + sLineBreak + 'Third = Later.Child');
  A.FreeSelf := True;
  MakeTarget;
  QueryOnSet := True;
  RaiseOnSet := True;
  ExpectResolveException('setter sentinel');
  Check((Writes = 1) and (DeadWrites = 0), 'setter exception corrupted receiver lifetime');
  Reset;

  A := TReceiver.Create(nil);
  Load(A, 'Ref = Later.Child');
  MakeTarget;
  RaiseOnSet := True;
  ExpectResolveException('setter sentinel');
  Check(Names = 'Later', 'setter exception lost a live unresolved receiver');
  GlobalFixupReferences;
  Check((Writes = 2) and (A.Ref = Later.FindComponent('Child')) and (Names = ''),
    'live receiver did not recover after setter exception');
  Reset;
end;

procedure ReentrantCases;
var
  Mode: Integer;
  List: TCancelNames;
begin
  For Mode := 1 to 4 do begin
    A := TReceiver.Create(nil);
    Load(A, 'Ref = Later.Child');
    MakeTarget;
    ReenterMode := Mode;
    GlobalFixupReferences;
    Check(Names = '', 'nested operation left a reference');
    If Mode = 1 then
      Check(Writes = 0, 'lookup cancellation still called setter')
    else
      Check(Writes = 1, 'nested operation duplicated setter');
    Reset;
  end;

  A := TReceiver.Create(nil);
  Load(A, 'Ref = Later.Child' + sLineBreak + 'Second = Other.Child');
  List := TCancelNames.Create;
  try
    GetFixupReferenceNames(nil, List);
    Check((A = nil) and (List.Count = 0), 'name lookup continued after receiver destruction');
  finally
    List.Free;
  end;
  Reset;

  A := TReceiver.Create(nil);
  Load(A, 'Ref = Later.Child');
  List := TCancelNames.Create;
  try
    GetFixupInstanceNames(A, 'Later', List);
    Check((A = nil) and (List.Count = 0), 'instance lookup continued after receiver destruction');
  finally
    List.Free;
  end;
  Reset;

  For Mode := 1 to 2 do begin
    A := TReceiver.Create(nil);
    If Mode = 1 then
      Load(A, 'Ref = Later.Child' + sLineBreak + 'Second = Other.Child')
    else
      Load(A, 'Ref = Later.Child' + sLineBreak + 'Second = Later.Other');
    List := TCancelNames.Create;
    List.CancelInAdd := True;
    try
      If Mode = 1 then
        GetFixupReferenceNames(nil, List)
      else
        GetFixupInstanceNames(A, 'Later', List);
      Check((A = nil) and (List.Count = 1), 'name collection continued after receiver destruction');
    finally
      List.Free;
    end;
    Reset;
  end;
end;

begin
  Held := TList.Create;
  RegisterFindGlobalComponentProc(FindLater);
  try
    try
      OrdinaryCases;
      If (ParamCount = 0) or (ParamStr(1) <> 'ordinary') then begin
        CallbackCases;
        ExtraCases;
        ReentrantCases;
      end;
      WriteLn('READER_FIXUP_LIFETIME_PASS');
    except
      on E: Exception do begin
        WriteLn('FAIL ', E.ClassName, ': ', E.Message);
        Halt(1);
      end;
    end;
  finally
    UnregisterFindGlobalComponentProc(FindLater);
    Held.Free;
  end;
end.
