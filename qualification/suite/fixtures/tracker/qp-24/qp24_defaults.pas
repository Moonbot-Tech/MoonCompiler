unit qp24_defaults;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$modeswitch advancedrecords}{$modeswitch anonymousfunctions}{$modeswitch functionreferences}{$modeswitch nestedprocvars}{$modeswitch inlinevars}{$endif}
interface
procedure Test(Token: string = ''; Headers: TArray<Cardinal> = []);
implementation
procedure Test(Token: string = 'x'; Headers: TArray<Cardinal> = []);
begin end;
end.
