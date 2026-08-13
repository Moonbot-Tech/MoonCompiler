unit qp36_base;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}{$modeswitch nestedprocvars}{$modeswitch inlinevars}{$endif}
interface
type
  TBase<T> = class
  protected
    function Data: Integer; virtual;
  end;
implementation
function TBase<T>.Data: Integer;
begin Result := 41; end;
end.
