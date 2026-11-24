{ A retired field can be rejected or skipped without losing the next field. }

type
  TBreadthReadPolicy = class
  public
    AllowRetired: Boolean;
    Errors: Integer;
    procedure Error(Reader: TReader; const MessageText: string; var Handled: Boolean);
  end;

procedure TBreadthReadPolicy.Error(Reader: TReader; const MessageText: string; var Handled: Boolean);
begin
  Inc(Errors);
  Handled := AllowRetired and (Pos('RetiredSetting', MessageText) <> 0);
end;

procedure BreadthLoadRetiredSetting(Binary: TStream; AllowRetired: Boolean);
var
  Policy: TBreadthReadPolicy;
  Target: TBreadthResourceComponent;
  Reader: TReader;
  Rejected: Boolean;
begin
  Target := TBreadthResourceComponent.Create(nil);
  try
    Policy := TBreadthReadPolicy.Create;
    try
      Policy.AllowRetired := AllowRetired;
      Binary.Position := 0;
      Reader := TReader.Create(Binary, 32);
      try
        Reader.OnError := Policy.Error;
        Rejected := False;
        try
          Reader.ReadRootComponent(Target);
        except
          on EReadError do Rejected := True;
        end;
        Check((Rejected <> AllowRetired) and (Policy.Errors = 1), 'breadth-reader-rejects-or-skips-retired-setting');
        If AllowRetired then begin
          Check((Target.Level = 619) and (Target.Trace = 12) and Assigned(Target.OnPulse),
            'breadth-reader-continues-through-fields-and-loaded-after-skip');
          If Assigned(Target.OnPulse) then
            Target.OnPulse(Target);
          Check((Target.Level = 1461) and (Target.Trace = 123), 'breadth-reader-binds-live-handler-after-recovery');
        end else
          Check(Target.Level = 0, 'breadth-reader-stops-before-following-field-on-rejection');
        Mix(UInt64(Target.Level));
      finally
        Reader.Free;
      end;
    finally
      Policy.Free;
    end;
  finally
    Target.Free;
  end;
end;

procedure RunBreadthReaderRecovery;
const
  Resource: AnsiString =
    'object Migrated: TBreadthResourceComponent'#10 +
    '  RetiredSetting = [one, two]'#10 +
    '  Level = 619'#10 +
    '  OnPulse = ApplyPulse'#10 +
    'end'#10;
var
  Text, Binary: TMemoryStream;
begin
  Text := TMemoryStream.Create;
  try
    Binary := TMemoryStream.Create;
    try
      Text.WriteBuffer(Resource[1], Length(Resource));
      Text.Position := 0;
      ObjectTextToBinary(Text, Binary);
      BreadthLoadRetiredSetting(Binary, False);
      BreadthLoadRetiredSetting(Binary, True);
    finally
      Binary.Free;
    end;
  finally
    Text.Free;
  end;
end;
