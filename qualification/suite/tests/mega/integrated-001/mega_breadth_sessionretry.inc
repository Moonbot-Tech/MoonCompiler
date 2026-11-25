{ A generic session factory must release a failed attempt and leave the current session usable. }

type
  TBreadthSessionLease = class(TInterfacedObject)
  public
    class var Released: Integer;
    destructor Destroy; override;
  end;

  TBreadthImportSession = class
  public
    Lease: IInterface;
    Title: UnicodeString;
    class var FailOpening: Boolean;
    class var Openings: Integer;
    constructor Create;
  end;

  TBreadthSessionFactory<T: class, constructor> = class
    class function Open: T; static;
  end;

destructor TBreadthSessionLease.Destroy;
begin
  Inc(Released);
  inherited Destroy;
end;

constructor TBreadthImportSession.Create;
begin
  inherited Create;
  Inc(Openings);
  Lease := TBreadthSessionLease.Create;
  Title := 'session-' + #$03BB;
  If FailOpening then
    raise EAbort.Create('import path unavailable');
end;

class function TBreadthSessionFactory<T>.Open: T;
begin
  Result := T.Create;
end;

procedure RunBreadthSessionFactoryRetry;
var
  Current, Original, Retry: TBreadthImportSession;
  Reported: Boolean;
begin
  TBreadthSessionLease.Released := 0;
  TBreadthImportSession.Openings := 0;
  TBreadthImportSession.FailOpening := False;
  Current := TBreadthSessionFactory<TBreadthImportSession>.Open;
  Original := Current;
  Retry := nil;
  try
    TBreadthImportSession.FailOpening := True;
    Reported := False;
    try
      Current := TBreadthSessionFactory<TBreadthImportSession>.Open;
    except
      on E: EAbort do Reported := E.Message = 'import path unavailable';
    end;
    Check(Reported and (Current = Original) and (Original.Title = 'session-' + #$03BB),
      'breadth-session-factory-failure-leaves-previous-destination-and-reports-reason');
    Check((TBreadthImportSession.Openings = 2) and (TBreadthSessionLease.Released = 1) and Assigned(Original.Lease),
      'breadth-session-factory-releases-only-failed-constructor-lease');
    TBreadthImportSession.FailOpening := False;
    Retry := TBreadthSessionFactory<TBreadthImportSession>.Open;
    Check((Retry <> Original) and (Retry.Title = Original.Title) and (Retry.Lease <> Original.Lease),
      'breadth-session-factory-retry-publishes-new-fully-initialized-session');
  finally
    Retry.Free;
    If Current <> Original then
      Current.Free;
    Original.Free;
  end;
  Check((TBreadthImportSession.Openings = 3) and (TBreadthSessionLease.Released = 3),
    'breadth-session-factory-each-attempt-releases-one-lease');
  Mix(UInt64(TBreadthSessionLease.Released));
end;
