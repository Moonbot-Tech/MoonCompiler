program moonbot_inline_pointer_new;

{$ifdef FPC}
  {$mode delphiunicode}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch inlinevars}
{$endif}

type
  TManagedRecord = record
    Text: UnicodeString;
  end;
  PManagedRecord = ^TManagedRecord;
  TProc = reference to procedure;

var
  Callback: TProc;

begin
  Callback := procedure
    begin
      var Value: PManagedRecord;
      New(Value);
      Value^.Text := 'managed-ok';
      WriteLn(Value^.Text);
      Dispose(Value);
    end;
  Callback();
end.
