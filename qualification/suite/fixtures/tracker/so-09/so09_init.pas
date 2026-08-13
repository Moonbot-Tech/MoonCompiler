unit so09_init;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}{$modeswitch nestedprocvars}{$modeswitch inlinevars}{$endif}
interface
type TAction = reference to procedure;
var Action: TAction;
implementation
initialization
  Action := procedure
    var Values: array of Byte;
    begin SetLength(Values, 3); Values[0] := 1; Values[1] := 2; Values[2] := 3; if Values[2] <> 3 then Halt(2); end;
finalization
  Action := nil;
end.
