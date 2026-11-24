{ Textual RTTI writes to an indexed published set property. }

type
  TBreadthAccess = (baRead, baWrite, baAudit, baCache, baRetain);
  TBreadthAccesses = set of TBreadthAccess;

  TBreadthPolicy = class(TPersistent)
  private
    FSlots: array[0..2] of TBreadthAccesses;
    FVisits: Integer;
    function ReadAccess(Index: Integer): TBreadthAccesses;
    procedure WriteAccess(Index: Integer; Value: TBreadthAccesses);
  public
    property Visits: Integer read FVisits;
  published
    property Local: TBreadthAccesses index 0 read ReadAccess write WriteAccess;
    property Remote: TBreadthAccesses index 2 read ReadAccess write WriteAccess;
  end;

function TBreadthPolicy.ReadAccess(Index: Integer): TBreadthAccesses;
begin
  Result := FSlots[Index];
end;

procedure TBreadthPolicy.WriteAccess(Index: Integer; Value: TBreadthAccesses);
begin
  FSlots[Index] := Value;
  FVisits := FVisits * 10 + Index + 1;
end;

procedure RunBreadthPublishedSet;
var
  Target: TBreadthPolicy;
  LocalInfo, RemoteInfo: PPropInfo;
  Rejected: Boolean;
begin
  Target := TBreadthPolicy.Create;
  try
    LocalInfo := GetPropInfo(Target, 'Local');
    RemoteInfo := GetPropInfo(Target, 'Remote');
    Check((LocalInfo <> nil) and (RemoteInfo <> nil) and (LocalInfo <> RemoteInfo), 'breadth-published-set-two-indexed-properties');
    SetSetProp(Target, RemoteInfo, '[baRetain,baRead,baAudit]');
    SetSetProp(Target, LocalInfo, '[baCache,baWrite]');
    Check((Target.Local = [baWrite, baCache]) and (Target.Remote = [baRead, baAudit, baRetain]),
      'breadth-published-set-text-write-passes-property-index');
    Check(Target.Visits = 31, 'breadth-published-set-write-calls-indexed-setter');
    Check(GetSetProp(Target, RemoteInfo, True) = '[baRead,baAudit,baRetain]', 'breadth-published-set-text-read-in-ordinal-order');
    Rejected := False;
    try
      SetSetProp(Target, RemoteInfo, '[baWrite,baMissing]');
    except
      on EPropertyError do Rejected := True;
      on EPropertyConvertError do Rejected := True;
    end;
    Check(Rejected and (Target.Remote = [baRead, baAudit, baRetain]) and (Target.Visits = 31),
      'breadth-published-set-invalid-text-never-enters-setter');
    SetSetProp(Target, RemoteInfo, '[]');
    Check((Target.Remote = []) and (Target.Local = [baWrite, baCache]) and (Target.Visits = 313),
      'breadth-published-set-empty-write-only-changes-target-slot');
    Mix(UInt64(Target.Visits));
  finally
    Target.Free;
  end;
end;
