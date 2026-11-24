{ Static call-site defaults and explicit exception-location metadata. }

type
  TBreadthDefaultBase = class
    function Produce(Key: Int64; Tags: Integer = 17): TCrossEntry; overload; virtual;
    function Produce(const Key: AnsiString): TCrossEntry; overload;
  end;

  TBreadthDefaultChild = class(TBreadthDefaultBase)
    function Produce(Key: Int64; Tags: Integer = 29): TCrossEntry; overload; override;
  end;

function TBreadthDefaultBase.Produce(Key: Int64; Tags: Integer): TCrossEntry;
begin
  Result.Code := Key + Tags;
  Result.Text := 'base';
end;

function TBreadthDefaultBase.Produce(const Key: AnsiString): TCrossEntry;
begin
  Result.Code := Length(Key) * 107;
  Result.Text := Key + '-named';
end;

function TBreadthDefaultChild.Produce(Key: Int64; Tags: Integer): TCrossEntry;
begin
  Result := inherited Produce(Key, Tags);
  Inc(Result.Code, Int64(Tags) * 1000000007);
  Result.Text := 'child';
end;

procedure RunBreadthVirtualDefaultArguments;
var
  Child: TBreadthDefaultChild;
  Base: TBreadthDefaultBase;
  Answer: TCrossEntry;
begin
  Child := TBreadthDefaultChild.Create;
  try
    Base := Child;
    Answer := Base.Produce(OpaqueI(80000000013));
    Check((Answer.Code = 97000000149) and (Answer.Text = AnsiString('child')), 'breadth-virtual-default-from-static-base');
    Answer := Child.Produce(OpaqueI(80000000013));
    Check((Answer.Code = 109000000245) and (Answer.Text = AnsiString('child')), 'breadth-virtual-default-from-static-child');
    Answer := Child.Produce(AnsiString('word'));
    Check((Answer.Code = 428) and (Answer.Text = AnsiString('word-named')), 'breadth-virtual-overload-still-resolves-inherited-text');
    Mix(UInt64(Answer.Code));
  finally
    Child.Free;
  end;
end;

function BreadthOuterOrigin: Integer;
begin
  Result := 17;
end;

function BreadthInnerOrigin: Integer;
begin
  Result := -43;
end;

procedure BreadthExplicitRaise(Outer: Boolean);
begin
  If Outer then
    raise EConvertError.Create('outer location') at @BreadthOuterOrigin;
  raise EAbort.Create('inner location') at @BreadthInnerOrigin;
end;

procedure RunBreadthExplicitExceptionOrigins;
var
  Seen: Integer;
begin
  Seen := 0;
  try
    try
      BreadthExplicitRaise(True);
    except
      on EConvertError do begin
        Check(ExceptAddr = @BreadthOuterOrigin, 'breadth-exception-explicit-origin');
        Inc(Seen);
        try
          BreadthExplicitRaise(False);
        except
          on EAbort do begin
            Check(ExceptAddr = @BreadthInnerOrigin, 'breadth-exception-nested-explicit-origin');
            Inc(Seen, 10);
          end;
        end;
        Check(ExceptAddr = @BreadthOuterOrigin, 'breadth-exception-explicit-origin-restored');
        raise;
      end;
    end;
  except
    on EConvertError do begin
      Check(ExceptAddr = @BreadthOuterOrigin, 'breadth-exception-reraise-keeps-explicit-origin');
      Inc(Seen, 100);
    end;
  end;
  Check((Seen = 111) and (ExceptAddr = nil), 'breadth-exception-explicit-handlers-unwound');
  Mix(UInt64(Seen));
end;

function BreadthCapturedResult(Seed: Int64; Early: Boolean): TCrossEntry;

  procedure Patch(Delta: Int64; Flag: AnsiChar);

    function Contribution: Int64;
    begin
      Result := Seed * 2 + Delta;
    end;

  begin
    Inc(Result.Code, Contribution);
    Result.Text := Result.Text + Flag;
  end;

begin
  Result.Code := Seed;
  Result.Text := 'start';
  try
    Patch(5, 'P');
    If Early then
      Exit;
    Patch(-7, 'N');
  finally
    Result.Text := Result.Text + '-done';
  end;
end;

procedure RunBreadthCapturedResult;
var
  Answer: TCrossEntry;
begin
  Answer := BreadthCapturedResult(OpaqueI(42000000007), True);
  Check((Answer.Code = 126000000026) and (Answer.Text = AnsiString('startP-done')),
    'breadth-nested-hidden-result-through-early-exit');
  Mix(UInt64(Answer.Code));
  Answer := BreadthCapturedResult(OpaqueI(42000000007), False);
  Check((Answer.Code = 210000000033) and (Answer.Text = AnsiString('startPN-done')),
    'breadth-nested-hidden-result-and-local-function-result');
  Mix(UInt64(Answer.Code));
end;

procedure RunBreadthLanguageForms;
begin
  RunBreadthVirtualDefaultArguments;
  RunBreadthExplicitExceptionOrigins;
end;
