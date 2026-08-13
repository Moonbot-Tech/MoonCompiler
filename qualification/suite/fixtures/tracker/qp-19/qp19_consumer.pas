unit qp19_consumer;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}{$modeswitch nestedprocvars}{$modeswitch inlinevars}{$endif}
interface
procedure RunLoops;
implementation
uses SysUtils, qp19_enumerable;
procedure Check(Value: Boolean; const Name: string);
begin if not Value then raise Exception.Create(Name); end;
procedure RunLoops;
var Source: TCountedEnumerable; Sum: Integer;
begin
  Source := TCountedEnumerable.Create;
  try
    Sum := 0;
    for var Value in Source do Inc(Sum, Value);
    Check(Sum = 6, 'complete');
    Check(TCountedEnumerator.Alive = 0, 'complete-lifetime');
    for var Value in Source do begin Check(Value = 1, 'break-value'); Break; end;
    Check(TCountedEnumerator.Alive = 0, 'break-lifetime');
  finally Source.Free; end;
end;
end.
