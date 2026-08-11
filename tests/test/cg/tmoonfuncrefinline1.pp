{ %OPT=-O3 }
program tmoonfuncrefinline1;

{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

type
  TProc = reference to procedure;

var
  Count: Integer;

procedure Invoke(const Callback: TProc); inline;
begin
  Callback();
end;

function HasProc(const Callback: TProc): Boolean; inline;
begin
  Result := Assigned(Callback);
end;

procedure CopyProc(const Callback: TProc; var Dest: TProc); inline;
begin
  Dest := Callback;
end;

var
  Materialized, CopyOfMaterialized: TProc;
begin
  Materialized :=
    procedure
    begin
      Inc(Count);
    end;
  Invoke(Materialized);
  if not HasProc(Materialized) then
    Halt(1);
  CopyProc(Materialized, CopyOfMaterialized);
  CopyOfMaterialized();
  if Count <> 2 then
    Halt(2);
  CopyOfMaterialized := nil;
  Materialized := nil;
end.
