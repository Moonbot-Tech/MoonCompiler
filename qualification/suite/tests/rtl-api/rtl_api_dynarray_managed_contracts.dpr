program rtl_api_dynarray_managed_contracts;

{$APPTYPE CONSOLE}

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch inlinevars}
{$endif}

uses
  mormot.core.fpcx64mm,
  SysUtils;

type
  EManagedProbe = class(Exception);

  TOwner = record
    Token: Integer;
    Value: Integer;
    class operator Initialize(out Dest: TOwner);
    class operator Assign(var Dest: TOwner; const [ref] Source: TOwner);
    class operator Finalize(var Dest: TOwner);
  end;

  TOwnerPair = array[0..1] of TOwner;

  TInitCell = record
    Payload: array[0..15] of UInt64;
    class operator Initialize(out Dest: TInitCell);
    class operator Finalize(var Dest: TInitCell);
  end;

var
  NextToken: Integer;
  AssignCalls: Integer;
  OwnerInitializeCalls: Integer;
  FinalizeCalls: Integer;
  ZeroFinalizes: Integer;
  DuplicateFinalizes: Integer;
  RaiseOnAssign: Integer;
  RaiseBeforeAssignWrite: Boolean;
  RaiseOnOwnerInitialize: Boolean;
  LiveTokens: array[0..100000] of Boolean;
  InitCalls: Integer;
  InitFinalizes: Integer;
  RaiseOnInitialize: Integer;

procedure Check(ACondition: Boolean; const AName: string);
begin
  if not ACondition then
    begin
      WriteLn('FAIL ',AName);
      Halt(1);
    end;
end;

function LiveCount: Integer;
var
  I: Integer;
begin
  Result:=0;
  for I:=1 to NextToken do
    if LiveTokens[I] then
      Inc(Result);
end;

procedure ResetOwnerCounters;
begin
  AssignCalls:=0;
  OwnerInitializeCalls:=0;
  FinalizeCalls:=0;
  ZeroFinalizes:=0;
  DuplicateFinalizes:=0;
  RaiseOnAssign:=0;
  RaiseBeforeAssignWrite:=False;
end;

class operator TOwner.Initialize(out Dest: TOwner);
begin
  Inc(OwnerInitializeCalls);
  if RaiseOnOwnerInitialize then
    raise EManagedProbe.Create('unexpected initialize during copy');
  Inc(NextToken);
  Dest.Token:=NextToken;
  Dest.Value:=0;
  LiveTokens[Dest.Token]:=True;
end;

class operator TOwner.Assign(var Dest: TOwner; const [ref] Source: TOwner);
begin
  Inc(AssignCalls);
  if (AssignCalls=RaiseOnAssign) and RaiseBeforeAssignWrite then
    raise EManagedProbe.Create('assign-before-write');
  if (Dest.Token>0) and LiveTokens[Dest.Token] then
    LiveTokens[Dest.Token]:=False;
  Inc(NextToken);
  Dest.Token:=NextToken;
  Dest.Value:=Source.Value;
  LiveTokens[Dest.Token]:=True;
  if (AssignCalls=RaiseOnAssign) and not RaiseBeforeAssignWrite then
    raise EManagedProbe.Create('assign-after-write');
end;

class operator TOwner.Finalize(var Dest: TOwner);
begin
  Inc(FinalizeCalls);
  if Dest.Token=0 then
    Inc(ZeroFinalizes)
  else if (Dest.Token<0) or not LiveTokens[Dest.Token] then
    Inc(DuplicateFinalizes)
  else
    LiveTokens[Dest.Token]:=False;
  Dest.Token:=0;
end;

class operator TInitCell.Initialize(out Dest: TInitCell);
begin
  Inc(InitCalls);
  if InitCalls=RaiseOnInitialize then
    raise EManagedProbe.Create('initialize');
  Dest.Payload[0]:=42;
end;

class operator TInitCell.Finalize(var Dest: TInitCell);
begin
  Inc(InitFinalizes);
  Dest.Payload[0]:=0;
end;

procedure CheckCopyAndSharedSetLength;
var
  A,B: TArray<TOwner>;
  C,D: TArray<TOwnerPair>;
begin
  SetLength(A,2);
  A[0].Value:=11;
  A[1].Value:=22;
  B:=A;
  ResetOwnerCounters;
  SetLength(B,3);
  Check(AssignCalls=2,'setlength-shared-assign-count');
  Check(OwnerInitializeCalls=1,'setlength-only-default-constructs-tail');
  Check((B[0].Value=11) and (B[1].Value=22),'setlength-shared-values');
  Check((A[0].Token<>B[0].Token) and (A[1].Token<>B[1].Token),
    'setlength-shared-independent-owners');
  B:=nil;
  A:=nil;
  Check((LiveCount=0) and (DuplicateFinalizes=0),'setlength-shared-cleanup');

  SetLength(A,3);
  A[0].Value:=31;
  A[1].Value:=32;
  A[2].Value:=33;
  ResetOwnerCounters;
  B:=Copy(A,1,2);
  Check((AssignCalls=2) and (Length(B)=2),'copy-slice-assign-count');
  Check(OwnerInitializeCalls=0,'copy-slice-does-not-initialize');
  Check((B[0].Value=32) and (B[1].Value=33),'copy-slice-values');
  B:=nil;
  A:=nil;
  Check((LiveCount=0) and (DuplicateFinalizes=0),'copy-slice-cleanup');

  SetLength(C,1);
  C[0][0].Value:=41;
  C[0][1].Value:=42;
  ResetOwnerCounters;
  D:=Copy(C);
  Check((AssignCalls=2) and (D[0][0].Value=41) and
    (D[0][1].Value=42),'copy-nested-static-array');
  Check(OwnerInitializeCalls=0,'copy-nested-does-not-initialize');
  D:=nil;
  C:=nil;
  Check((LiveCount=0) and (DuplicateFinalizes=0),'copy-nested-cleanup');
end;

procedure CheckDeleteInsertConcat;
var
  A,B,C: TArray<TOwner>;
  procedure InsertArray;
  begin
    Insert(A,B,0);
  end;
begin
  SetLength(A,2);
  A[0].Value:=51;
  A[1].Value:=52;
  B:=A;
  ResetOwnerCounters;
  Delete(B,0,1);
  Check((AssignCalls=2) and (Length(B)=1) and (B[0].Value=52),
    'delete-shared-detach');
  Check(OwnerInitializeCalls=0,'delete-shared-does-not-initialize-copy');
  B:=nil;
  A:=nil;
  Check((LiveCount=0) and (DuplicateFinalizes=0),'delete-shared-cleanup');

  SetLength(A,2);
  A[0].Value:=61;
  A[1].Value:=62;
  ResetOwnerCounters;
  InsertArray;
  Check((AssignCalls=2) and (Length(B)=2) and (B[1].Value=62),
    'insert-new-array');
  Check(OwnerInitializeCalls=0,'insert-does-not-initialize-copy');
  B:=nil;
  A:=nil;
  Check((LiveCount=0) and (DuplicateFinalizes=0),'insert-new-cleanup');

  SetLength(A,2);
  A[0].Value:=71;
  A[1].Value:=72;
  ResetOwnerCounters;
  B:=A+A;
  Check((AssignCalls=4) and (Length(B)=4) and
    (B[0].Value=71) and (B[3].Value=72),'concat-independent-copies');
  Check(OwnerInitializeCalls=0,'concat-does-not-initialize-copy');
  B:=nil;
  A:=nil;
  Check((LiveCount=0) and (DuplicateFinalizes=0),'concat-cleanup');

  SetLength(A,2);
  SetLength(B,1);
  SetLength(C,1);
  A[0].Value:=81;
  A[1].Value:=82;
  B[0].Value:=83;
  C[0].Value:=84;
  ResetOwnerCounters;
  A:=A+B+C;
  Check((AssignCalls=2) and (Length(A)=4) and
    (A[0].Value=81) and (A[2].Value=83) and (A[3].Value=84),
    'concat-multi-prefix-transfer');
  A:=nil;
  B:=nil;
  C:=nil;
  Check((LiveCount=0) and (DuplicateFinalizes=0),'concat-multi-cleanup');
end;

procedure CheckCopyRollback;
var
  A,B: TArray<TOwner>;
  Original: Pointer;
  Caught: Boolean;
  Failure,Stage: Integer;
begin
  SetLength(A,3);
  A[0].Value:=91;
  A[1].Value:=92;
  A[2].Value:=93;
  for Stage:=0 to 1 do
    for Failure:=1 to 3 do
      begin
        ResetOwnerCounters;
        RaiseOnAssign:=Failure;
        RaiseBeforeAssignWrite:=Stage=0;
        Caught:=False;
        try
          B:=Copy(A);
        except
          on E: EManagedProbe do
            Caught:=True;
        end;
        Check(Caught and (Length(B)=0),'copy-raise-result-unpublished');
        Check(OwnerInitializeCalls=0,'copy-raise-does-not-initialize');
        Check((LiveCount=3) and (DuplicateFinalizes=0),'copy-raise-rollback');
        if Stage=0 then
          Check(ZeroFinalizes=1,'copy-raise-before-write-current-slot')
        else
          Check(ZeroFinalizes=0,'copy-raise-after-write-current-slot');
      end;

  B:=A;
  Original:=Pointer(B);
  ResetOwnerCounters;
  RaiseOnAssign:=2;
  Caught:=False;
  try
    SetLength(B,4);
  except
    on E: EManagedProbe do
      Caught:=True;
  end;
  Check(Caught and (Pointer(B)=Original) and (Length(B)=3),
    'setlength-shared-raise-preserves-array');
  Check((B[0].Value=91) and (B[2].Value=93),'setlength-shared-raise-values');
  Check((LiveCount=3) and (DuplicateFinalizes=0),
    'setlength-shared-raise-rollback');
  B:=nil;
  A:=nil;
  Check((LiveCount=0) and (DuplicateFinalizes=0),'copy-rollback-final-cleanup');
end;

procedure CheckCopyWithInitializeDisabled;
var
  A,B: TArray<TOwner>;
begin
  SetLength(A,2);
  A[0].Value:=101;
  A[1].Value:=102;
  ResetOwnerCounters;
  RaiseOnOwnerInitialize:=True;
  try
    B:=Copy(A);
  finally
    RaiseOnOwnerInitialize:=False;
  end;
  Check((Length(B)=2) and (B[0].Value=101) and (B[1].Value=102),
    'copy-with-initialize-disabled-values');
  Check((OwnerInitializeCalls=0) and (AssignCalls=2),
    'copy-with-initialize-disabled-lifecycle');
  B:=nil;
  A:=nil;
  Check((LiveCount=0) and (DuplicateFinalizes=0),
    'copy-with-initialize-disabled-cleanup');
end;

procedure CheckSelfAliases;
var
  A: TArray<TOwner>;
begin
  SetLength(A,2);
  A[0].Value:=111;
  A[1].Value:=112;
  ResetOwnerCounters;
  A:=Copy(A);
  Check((AssignCalls=2) and (Length(A)=2) and
    (A[0].Value=111) and (A[1].Value=112),'copy-self-alias');

  ResetOwnerCounters;
  A:=A+A;
  Check((AssignCalls=4) and (Length(A)=4) and
    (A[0].Value=111) and (A[2].Value=111) and (A[3].Value=112),
    'concat-self-prefix-transfer');

  ResetOwnerCounters;
  Insert(A,A,1);
  Check((AssignCalls=8) and (Length(A)=8) and
    (A[0].Value=111) and (A[1].Value=111) and
    (A[4].Value=112) and (A[7].Value=112),'insert-self-alias');
  A:=nil;
end;

procedure CheckBuiltInManagedFastPath;
var
  A,B,C: TArray<string>;
begin
  A:=TArray<string>.Create('alpha','bravo');
  B:=A;
  SetLength(B,3);
  B[2]:='charlie';
  Check((A[0]='alpha') and (Length(A)=2),'builtin-setlength-source');
  Check((B[0]='alpha') and (B[2]='charlie'),'builtin-setlength-result');
  C:=Copy(B,1,2);
  Check((Length(C)=2) and (C[0]='bravo') and (C[1]='charlie'),
    'builtin-copy');
  Insert(A,C,1);
  Check((Length(C)=4) and (C[0]='bravo') and (C[1]='alpha') and
    (C[3]='charlie'),'builtin-insert');
  Delete(C,0,1);
  Check((Length(C)=3) and (C[0]='alpha') and (C[2]='charlie'),
    'builtin-delete');
  C:=A+B;
  Check((Length(C)=5) and (C[0]='alpha') and (C[2]='alpha') and
    (C[4]='charlie'),'builtin-concat');
end;

procedure CheckInitializeRollback;
var
  A: TArray<TInitCell>;
  BeforeStatus,AfterStatus: TMMFragmentationStatus;
  I,Failure: Integer;
  Caught: Boolean;
begin
  BeforeStatus:=CurrentHeapFragmentationStatus;
  InitFinalizes:=0;
  for Failure in [1,2,100] do
    for I:=1 to 40 do
      begin
        InitCalls:=0;
        RaiseOnInitialize:=Failure;
        Caught:=False;
        try
          SetLength(A,100);
        except
          on E: EManagedProbe do
            Caught:=True;
        end;
        Check(Caught and (Length(A)=0),'initialize-empty-rollback-state');
      end;
  AfterStatus:=CurrentHeapFragmentationStatus;
  Check(InitFinalizes=4000,'initialize-empty-finalized-prefix');
  Check(BeforeStatus.LiveSmallBytes=AfterStatus.LiveSmallBytes,
    'initialize-empty-no-small-leak');
  Check(BeforeStatus.LiveMediumBytes=AfterStatus.LiveMediumBytes,
    'initialize-empty-no-medium-leak');

  RaiseOnInitialize:=0;
  InitCalls:=0;
  SetLength(A,2);
  A[0].Payload[0]:=101;
  A[1].Payload[0]:=102;
  InitCalls:=0;
  RaiseOnInitialize:=1;
  Caught:=False;
  try
    SetLength(A,10000);
  except
    on E: EManagedProbe do
      Caught:=True;
  end;
  Check(Caught and (Length(A)=2),'initialize-grow-preserves-length');
  Check((A[0].Payload[0]=101) and (A[1].Payload[0]=102),
    'initialize-grow-preserves-values');
  RaiseOnInitialize:=0;
  A:=nil;
end;

begin
  CheckCopyAndSharedSetLength;
  CheckDeleteInsertConcat;
  CheckCopyRollback;
  CheckCopyWithInitializeDisabled;
  DuplicateFinalizes:=0;
  CheckSelfAliases;
  Check((LiveCount=0) and (DuplicateFinalizes=0),'self-alias-cleanup');
  CheckBuiltInManagedFastPath;
  CheckInitializeRollback;
  WriteLn('RTL_API_DYNARRAY_MANAGED_CONTRACTS_OK');
end.
