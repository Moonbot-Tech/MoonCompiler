program Fpc41794PointerRecordHelper;

{$mode delphi}

type
  TPayload = record
  end;
  PPayload = ^TPayload;

  PPayloadHelper = record helper for PPayload
    function IsNil: Boolean;
  end;

function PPayloadHelper.IsNil: Boolean;
begin
  Result := Self = nil;
end;

var
  P: PPayload;
begin
  P := nil;
  if not P.IsNil then
    Halt(1);
end.
