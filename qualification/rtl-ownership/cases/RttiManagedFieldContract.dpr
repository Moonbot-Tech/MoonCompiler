program RttiManagedFieldContract;

uses
  mormot.core.fpcx64mm, System.SysUtils, System.Rtti;

{$RTTI EXPLICIT FIELDS([vcPublic])}
type
  TRow = class
  public
    Text: string;
  end;

procedure Run;
begin
  var Context := TRttiContext.Create;
  try
    var Field := Context.GetType(TRow).GetField('Text');
    If Field = nil then raise Exception.Create('Missing field RTTI');
    for var I := 1 to 32 do begin
      var Row := TRow.Create;
      try
        Row.Text := StringOfChar('A', 100 + I);
        var Value := StringOfChar('B', 200 + I);
        If ParamStr(1) = '--rtti' then Field.SetValue(Row, TValue.From<string>(Value))
        else Row.Text := Value;
        If Row.Text <> Value then raise Exception.Create('Field assignment failed');
      finally
        Row.Free;
      end;
    end;
  finally
    Context.Free;
  end;
end;

begin
  Run;
  Writeln('RTTI_MANAGED_FIELD_VALUES_PASS assignments=32 mode=', ParamStr(1));
end.
