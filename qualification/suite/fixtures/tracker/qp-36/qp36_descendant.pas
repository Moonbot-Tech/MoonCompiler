unit qp36_descendant;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}{$modeswitch nestedprocvars}{$modeswitch inlinevars}{$endif}
interface
uses qp36_base;
type
  TUnrelated = record Value: Integer; end;
  TUnrelatedHelper = record helper for TUnrelated
    function Data: Integer;
  end;
  TDescendant<T> = class(TBase<T>)
    function ReadData: Integer;
  end;
implementation
function TUnrelatedHelper.Data: Integer; begin Result := Self.Value + 1; end;
function TDescendant<T>.ReadData: Integer; begin Result := Data; end;
end.
