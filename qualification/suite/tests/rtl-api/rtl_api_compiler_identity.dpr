program rtl_api_compiler_identity;
{$if not defined(MOONCOMPILER_FULLVERSION)}{$fatal Product identity missing}{$endif}
{$if CompilerVersion <> 2.4}{$fatal Wrong Moon compiler version}{$endif}
{$if MOONCOMPILER_FULLVERSION <> 20403}{$fatal Wrong ordered product version}{$endif}
{$if FPC_FULLVERSION <> 30301}{$fatal The FPC base ABI must not be rewritten}{$endif}
uses SysUtils;
begin
  if Abs(System.CompilerVersion - 2.4) > 0.000001 then
    raise Exception.Create('Runtime and conditional compiler versions differ');
  Writeln('RTL_API_COMPILER_IDENTITY_OK');
end.
