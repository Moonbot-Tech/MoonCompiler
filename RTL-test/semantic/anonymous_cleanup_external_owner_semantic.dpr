program anonymous_cleanup_external_owner_semantic;
{$APPTYPE CONSOLE}
uses
  {$ifdef UNIX}cthreads,{$endif}
  System.SysUtils, System.Classes;
type
  TTracked = class(TInterfacedObject)
    destructor Destroy; override;
  end;
var
  Value, Destroyed: Integer;
destructor TTracked.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;
begin
  TThread.Queue(nil, procedure
    var Text: string;
        Guard: IInterface;
    begin
      Guard := TTracked.Create;
      Text := IntToStr(42);
      Value := StrToInt(Text);
    end);
  If (Value <> 42) or (Destroyed <> 1) then
    raise Exception.Create('Normal anonymous cleanup');
  try
    TThread.Queue(nil, procedure
      var Text: string;
          Guard: IInterface;
      begin
        Guard := TTracked.Create;
        Text := IntToStr(43);
        raise EAbort.Create(Text);
      end);
    raise Exception.Create('Missing anonymous exception');
  except
    on E: EAbort do
      If E.Message <> '43' then raise;
  end;
  If Destroyed <> 2 then
    raise Exception.Create('Exceptional anonymous cleanup');
  WriteLn('ANONYMOUS_CLEANUP_EXTERNAL_OWNER_PASS');
end.
