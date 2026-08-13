program Fpc41456NestedCheckerInternalMin;

{$mode objfpc}
{$inline on}
{$optimization autoinline}
{$optimization removeemptyprocs}
{$optimization dfa}
{$optimization deadstore}
{$optimization deadvalues}
{$optimization constprop}
{$optimization cse}

type
  TChecker = object
    generic class function CheckInsert<T>(const AList: T;
      var Index: Integer; var ResultPointer: Pointer): Boolean; static;
  end;

  TConfig = class
  public type
    TIndexChecker = TChecker;
  end;

  generic TBase<C: TConfig> = object
  protected type
    TIndexChecker = C.TIndexChecker;
  end;

  generic TList<P; C: TConfig> = object(specialize TBase<C>)
  private
    FChecker: TIndexChecker;
  public
    function Insert(Index: Integer): P;
  end;

generic class function TChecker.CheckInsert<T>(const AList: T;
  var Index: Integer; var ResultPointer: Pointer): Boolean;
begin
  Result := True;
end;

function TList.Insert(Index: Integer): P;
begin
  Result := nil;
  if not FChecker.specialize CheckInsert<TList>(Self, Index, Result) then
    Exit;
end;

type
  TConcrete = specialize TList<Pointer, TConfig>;

begin
end.
