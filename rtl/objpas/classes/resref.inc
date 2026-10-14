{%MainUnit classes.pp}
{
    This file is part of the Free Pascal Run Time Library (rtl)
    Copyright (c) 2007 by Michael Van Canneyt,
    member of the Free Pascal development team

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

type
  // Quadruple representing an unresolved component property.

  { TUnresolvedReference }

  TUnresolvedReference = class(TlinkedListItem)
  Private
    FRoot: TComponent;     // Root component when streaming
    FPropInfo: PPropInfo;  // Property to set.
    FGlobal,               // Global component.
    FRelative : string;    // Path relative to global component.
    Function Resolve(var Instance : TPersistent) : Boolean; // Resolve this reference
    Function RootMatches(ARoot : TComponent) : Boolean; {$ifdef CLASSESINLINE} inline; {$endif CLASSESINLINE} // True if Froot matches or ARoot is nil.
    Function NextRef : TUnresolvedReference; {$ifdef CLASSESINLINE} inline; {$endif CLASSESINLINE}
  end;

  TLocalUnResolvedReference = class(TUnresolvedReference)
    Finstance : TPersistent;
  end;

  // Linked list of TPersistent items that have unresolved properties.

  { TUnResolvedInstance }

  TUnResolvedInstance = Class(TLinkedListItem)
    Instance : TPersistent; // Instance we're handling unresolveds for
    FUnresolved : TLinkedList; // The list
    FResolving : Boolean; // Skip this instance during a nested resolver call.
    Destructor Destroy; override;
    Function AddReference(ARoot : TComponent; APropInfo : PPropInfo; AGlobal,ARelative : String) : TUnresolvedReference;
    Function RootUnresolved : TUnresolvedReference; {$ifdef CLASSESINLINE} inline; {$endif CLASSESINLINE} // Return root element in list.
    Function ResolveReferences : Boolean; // Return true if all unresolveds were resolved.
  end;

  // Visitor used to try and resolve instances in the global list
  TResolveReferenceVisitor = Class(TLinkedListVisitor)
    Function Visit(Item : TLinkedListItem) : Boolean; override;
  end;

  // Visitor used to remove all references to a certain component.
  TRemoveReferenceVisitor = Class(TLinkedListVisitor)
    FRef : String;
    FRoot : TComponent;
    Constructor Create(ARoot : TComponent;Const ARef : String);
    Function Visit(Item : TLinkedListItem) : Boolean; override;
  end;

  // Visitor used to collect reference names.
  TReferenceNamesVisitor = Class(TLinkedListVisitor)
    FList : TStrings;
    FRoot : TComponent;
    Function Visit(Item : TLinkedListItem) : Boolean; override;
    Constructor Create(ARoot : TComponent;AList : TStrings);
  end;

  // Visitor used to collect instance names.
  TReferenceInstancesVisitor = Class(TLinkedListVisitor)
    FList : TStrings;
    FRef  : String;
    FRoot : TComponent;
    Function Visit(Item : TLinkedListItem) : Boolean; override;
    Constructor Create(ARoot : TComponent;Const ARef : String; AList : TStrings);
  end;

  // Visitor used to redirect links to another root component.
  TRedirectReferenceVisitor = Class(TLinkedListVisitor)
    FOld,
    FNew : String;
    FRoot : TComponent;
    Function Visit(Item : TLinkedListItem) : Boolean; override;
    Constructor Create(ARoot : TComponent;Const AOld,ANew : String);
  end;

var
  NeedResolving : TLinkedList;
  ResolveSection : TRTLCriticalSection;
  ResolveListDepth : SizeInt;

// Register the instance and its reference atomically with respect to global visitors.
Procedure AddtoResolveList(AInstance: TPersistent; ARoot: TComponent;
  APropInfo: PPropInfo; const AGlobal, ARelative: String);
var
  Item : TUnResolvedInstance;
begin
{$ifdef FPC_HAS_FEATURE_THREADING}
  EnterCriticalSection(ResolveSection);
  try
{$endif}
    If NeedResolving=Nil then
      NeedResolving:=TLinkedList.Create(TUnResolvedInstance);
    Item:=TUnResolvedInstance(NeedResolving.Root);
    While (Item<>Nil) and (Item.Instance<>AInstance) do
      Item:=TUnResolvedInstance(Item.Next);
    If Item=Nil then
      begin
      Item:=TUnResolvedInstance(NeedResolving.Add);
      Item.Instance:=AInstance;
      end;
    Item.AddReference(ARoot,APropInfo,AGlobal,ARelative);
{$ifdef FPC_HAS_FEATURE_THREADING}
  finally
    LeaveCriticalSection(ResolveSection);
  end;
{$endif}
end;

// Reentrant callbacks may destroy receivers. Keep list nodes alive until every visitor returns.
Procedure CleanupResolveList;
var
  Item, Next : TUnResolvedInstance;
  R, RN : TUnresolvedReference;
begin
  Item:=TUnResolvedInstance(NeedResolving.Root);
  While Item<>Nil do
    begin
    Next:=TUnResolvedInstance(Item.Next);
    If (Item.Instance<>Nil) and Assigned(Item.FUnresolved) then
      begin
      R:=TUnresolvedReference(Item.FUnresolved.Root);
      While R<>Nil do
        begin
        RN:=TUnresolvedReference(R.Next);
        If R.FPropInfo=Nil then
          Item.FUnresolved.RemoveItem(R,True);
        R:=RN;
        end;
      end;
    If Item.Instance=Nil then
      NeedResolving.RemoveItem(Item,True);
    Item:=Next;
    end;
end;

// Walk through the global list of instances to be resolved.

Procedure VisitResolveList(V : TLinkedListVisitor);

begin
{$ifdef FPC_HAS_FEATURE_THREADING}
  EnterCriticalSection(ResolveSection);
  Try
{$endif}
    Inc(ResolveListDepth);
    try
      NeedResolving.Foreach(V);
    Finally
      FreeAndNil(V);
      Dec(ResolveListDepth);
      If ResolveListDepth=0 then
        CleanupResolveList;
    end;
{$ifdef FPC_HAS_FEATURE_THREADING}
  Finally
    LeaveCriticalSection(ResolveSection);
  end;
{$endif}
end;

procedure GlobalFixupReferences;

begin
  If (NeedResolving=Nil) then
    Exit;
{$ifdef FPC_HAS_FEATURE_THREADING}
  GlobalNameSpace.BeginWrite;
  try
{$endif}
    VisitResolveList(TResolveReferenceVisitor.Create);
{$ifdef FPC_HAS_FEATURE_THREADING}
  finally
    GlobalNameSpace.EndWrite;
  end;
{$endif}
end;


procedure GetFixupReferenceNames(Root: TComponent; Names: TStrings);

begin
  If (NeedResolving=Nil) then
    Exit;
  VisitResolveList(TReferenceNamesVisitor.Create(Root,Names));
end;

procedure GetFixupInstanceNames(Root: TComponent; const ReferenceRootName: string; Names: TStrings);

begin
  If (NeedResolving=Nil) then
    Exit;
  VisitResolveList(TReferenceInstancesVisitor.Create(Root,ReferenceRootName,Names));
end;

procedure RedirectFixupReferences(Root: TComponent; const OldRootName, NewRootName: string);

begin
  If (NeedResolving=Nil) then
      Exit;
  VisitResolveList(TRedirectReferenceVisitor.Create(Root,OldRootName,NewRootName));
end;

procedure RemoveFixupReferences(Root: TComponent; const RootName: string);

begin
  If (NeedResolving=Nil) then
      Exit;
  VisitResolveList(TRemoveReferenceVisitor.Create(Root,RootName));
end;

procedure RemoveFixups(Instance: TPersistent);
var
  Item, Next : TUnResolvedInstance;
begin
  If (Instance=Nil) or (NeedResolving=Nil) or (NeedResolving.Root=Nil) then
    Exit;
{$ifdef FPC_HAS_FEATURE_THREADING}
  EnterCriticalSection(ResolveSection);
  try
{$endif}
    Item:=TUnResolvedInstance(NeedResolving.Root);
    While Item<>Nil do
      begin
      Next:=TUnResolvedInstance(Item.Next);
      If Item.Instance=Instance then
        begin
        Item.Instance:=Nil;
        If ResolveListDepth=0 then
          NeedResolving.RemoveItem(Item,True);
        end;
      Item:=Next;
      end;
{$ifdef FPC_HAS_FEATURE_THREADING}
  finally
    LeaveCriticalSection(ResolveSection);
  end;
{$endif}
end;

{ TUnresolvedReference }

Function TUnresolvedReference.Resolve(var Instance : TPersistent) : Boolean;

Var
  C : TComponent;

begin
  C:=FindGlobalComponent(FGlobal);
  Result:=(C<>Nil) and (Instance<>Nil) and (FPropInfo<>Nil);
  If Result then
    begin
    C:=FindNestedComponent(C,FRelative);
    Result:=C<>Nil;
    If Result then
      SetObjectProp(Instance, FPropInfo,C);
    end;
end;

Function TUnresolvedReference.RootMatches(ARoot : TComponent) : Boolean; {$ifdef CLASSESINLINE} inline; {$endif CLASSESINLINE}

begin
  Result:=(ARoot=Nil) or (ARoot=FRoot);
end;

Function TUnResolvedReference.NextRef : TUnresolvedReference;

begin
  Result:=TUnresolvedReference(Next);
  While (Result<>Nil) and (Result.FPropInfo=Nil) do
    Result:=TUnresolvedReference(Result.Next);
end;

{ TUnResolvedInstance }

destructor TUnResolvedInstance.Destroy;
begin
  FUnresolved.Free;
  inherited Destroy;
end;

function TUnResolvedInstance.AddReference(ARoot: TComponent;
  APropInfo: PPropInfo; AGlobal, ARelative: String): TUnresolvedReference;
begin
  If (FUnResolved=Nil) then
    FUnResolved:=TLinkedList.Create(TUnresolvedReference);
  Result:=FUnResolved.Add as TUnresolvedReference;
  Result.FGlobal:=AGLobal;
  Result.FRelative:=ARelative;
  Result.FPropInfo:=APropInfo;
  Result.FRoot:=ARoot;
end;

Function TUnResolvedInstance.RootUnresolved : TUnresolvedReference;

begin
  Result:=Nil;
  If (Instance<>Nil) and Assigned(FUnResolved) then
    begin
    Result:=TUnresolvedReference(FUnResolved.Root);
    While (Result<>Nil) and (Result.FPropInfo=Nil) do
      Result:=TUnresolvedReference(Result.Next);
    end;
end;

Function TUnResolvedInstance.ResolveReferences:Boolean;
var
  R : TUnresolvedReference;
begin
  If FResolving then
    Exit(False);
  FResolving:=True;
  try
    R:=RootUnResolved;
    While (R<>Nil) and (Instance<>Nil) do
      begin
      If R.Resolve(Self.Instance) then
        R.FPropInfo:=Nil;
      R:=R.NextRef;
      end;
    Result:=RootUnResolved=Nil;
  finally
    FResolving:=False;
  end;
end;

{ TReferenceNamesVisitor }

Constructor TReferenceNamesVisitor.Create(ARoot : TComponent;AList : TStrings);

begin
  FRoot:=ARoot;
  FList:=AList;
end;

Function TReferenceNamesVisitor.Visit(Item : TLinkedListItem) : Boolean;

Var
  R : TUnresolvedReference;
  UI : TUnResolvedInstance;

begin
  UI:=TUnResolvedInstance(Item);
  R:=UI.RootUnresolved;
  While (R<>Nil) and (UI.Instance<>Nil) do
    begin
    If R.RootMatches(FRoot) then
      If (FList.IndexOf(R.FGlobal)=-1) and (UI.Instance<>Nil) and (R.FPropInfo<>Nil) then
        FList.Add(R.FGlobal);
    R:=R.NextRef;
    end;
  Result:=True;
end;

{ TReferenceInstancesVisitor }

Constructor TReferenceInstancesVisitor.Create(ARoot : TComponent; Const ARef : String;AList : TStrings);

begin
  FRoot:=ARoot;
  FRef:=UpperCase(ARef);
  FList:=AList;
end;

Function TReferenceInstancesVisitor.Visit(Item : TLinkedListItem) : Boolean;

Var
  R : TUnresolvedReference;
  UI : TUnResolvedInstance;

begin
  UI:=TUnResolvedInstance(Item);
  R:=UI.RootUnresolved;
  While (R<>Nil) and (UI.Instance<>Nil) do
    begin
    If (FRoot=R.FRoot) and (FRef=UpperCase(R.FGLobal)) Then
      If (FList.IndexOf(R.FRelative)=-1) and (UI.Instance<>Nil) and (R.FPropInfo<>Nil) then
        Flist.Add(R.FRelative);
    R:=R.NextRef;
    end;
  Result:=True;
end;

{ TRedirectReferenceVisitor }

Constructor TRedirectReferenceVisitor.Create(ARoot : TComponent; Const AOld,ANew  : String);

begin
  FRoot:=ARoot;
  FOld:=UpperCase(AOld);
  FNew:=ANew;
end;

Function TRedirectReferenceVisitor.Visit(Item : TLinkedListItem) : Boolean;

Var
  R : TUnresolvedReference;

begin
  R:=TUnResolvedInstance(Item).RootUnresolved;
  While (R<>Nil) do
    begin
    If R.RootMatches(FRoot) and (FOld=UpperCase(R.FGLobal)) Then
      R.FGlobal:=FNew;
    R:=R.NextRef;
    end;
  Result:=True;
end;

{ TRemoveReferenceVisitor }

Constructor TRemoveReferenceVisitor.Create(ARoot : TComponent; Const ARef  : String);

begin
  FRoot:=ARoot;
  FRef:=UpperCase(ARef);
end;

Function TRemoveReferenceVisitor.Visit(Item : TLinkedListItem) : Boolean;
var
  UI : TUnResolvedInstance;
  R : TUnresolvedReference;
begin
  UI:=TUnResolvedInstance(Item);
  R:=UI.RootUnresolved;
  While R<>Nil do
    begin
    If R.RootMatches(FRoot) and ((FRef='') or (FRef=UpperCase(R.FGlobal))) then
      R.FPropInfo:=Nil;
    R:=R.NextRef;
    end;
  If UI.RootUnresolved=Nil then
    UI.Instance:=Nil;
  Result:=True;
end;

{ TResolveReferenceVisitor }

Function TResolveReferenceVisitor.Visit(Item : TLinkedListItem) : Boolean;

begin
  If TUnResolvedInstance(Item).ResolveReferences then
    TUnResolvedInstance(Item).Instance:=Nil;
  Result:=True;
end;
