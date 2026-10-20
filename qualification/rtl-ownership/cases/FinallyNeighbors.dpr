program FinallyNeighbors;
uses mormot.core.fpcx64mm, System.SysUtils;
{$INLINE OFF}
type
  TError = class(Exception)
    ID: Integer;
    constructor Create(AID: Integer);
    destructor Destroy; override;
  end;
var Destroyed: array[1..4] of Integer; LiveAtCatch, MaxFrames: Integer;
constructor TError.Create(AID: Integer);
begin
  inherited Create('neighbor');
  ID := AID;
end;
destructor TError.Destroy;
begin
  Inc(Destroyed[ID]);
  inherited;
end;
procedure Check(Value: Boolean; Code: Integer);
begin
  If not Value then begin
    Writeln('FAIL=', Code, ' destroyed=', Destroyed[1], '/', Destroyed[2], '/', Destroyed[3]);
    Halt(Code);
  end;
end;
procedure RaiseId(ID: Integer);
begin
  raise TError.Create(ID);
end;
procedure DoAV;
var P: PInteger;
begin
  P := nil;
  P^ := 1;
end;
procedure CheckCatch(ID: Integer);
begin
  Check(ExceptObject is TError, 40);
  Check(TError(ExceptObject).ID = ID, 41);
  Check(Destroyed[ID] = 0, 42);
  If RaiseList^.FrameCount > MaxFrames then MaxFrames := RaiseList^.FrameCount;
  Inc(LiveAtCatch);
end;
procedure Run(const Mode: string);
var Base, Enclosing: PExceptObject; Expected: Integer;
begin
  FillChar(Destroyed, SizeOf(Destroyed), 0);
  Base := RaiseList;
  Expected := 3;
  If Mode = 'nested' then begin
    try
      try
        try RaiseId(1); finally RaiseId(2); end;
      finally RaiseId(3); end;
    except CheckCatch(3); end;
  end else If Mode = 'local-catch' then begin
    try
      try RaiseId(1);
      finally
        Enclosing := RaiseList;
        try RaiseId(2); except CheckCatch(2); end;
        Check(RaiseList = Enclosing, 20);
        RaiseId(3);
      end;
    except CheckCatch(3); end;
  end else If Mode = 'outer-catch' then begin
    try RaiseId(1);
    except
      Enclosing := RaiseList;
      try
        try RaiseId(2); finally RaiseId(3); end;
      except CheckCatch(3); end;
      Check(RaiseList = Enclosing, 21);
      CheckCatch(1);
    end;
  end else If Mode = 'local-handled' then begin
    Expected := 2;
    try
      try RaiseId(1);
      finally
        Enclosing := RaiseList;
        try RaiseId(2); except CheckCatch(2); end;
        Check(RaiseList = Enclosing, 22);
      end;
    except CheckCatch(1); end;
  end else If Mode = 'av-replacement' then begin
    Expected := 1;
    try
      try DoAV; finally RaiseId(1); end;
    except CheckCatch(1); end;
  end else If Mode = 'replacement-av' then begin
    Expected := 1;
    try
      try RaiseId(1); finally DoAV; end;
    except Check(ExceptObject is EAccessViolation, 24); end;
  end else If Mode = 'av-outer-catch' then begin
    Expected := 2;
    try RaiseId(1);
    except
      Enclosing := RaiseList;
      try
        try DoAV; finally RaiseId(2); end;
      except CheckCatch(2); end;
      Check(RaiseList = Enclosing, 25);
      CheckCatch(1);
    end;
  end else Halt(100);
  Check(RaiseList = Base, 28);
  for var I := 1 to Expected do Check(Destroyed[I] = 1, 30 + I);
end;
begin
  for var I := 1 to 8 do Run(ParamStr(1));
  Writeln('PASS ', ParamStr(1), ' caught=', LiveAtCatch, ' maxframes=', MaxFrames);
end.
