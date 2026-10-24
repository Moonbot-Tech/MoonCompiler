unit UnwindEncodingUnit;
{$mode delphiunicode}
{$inline off}
interface
var Cleaned, Returned: Integer;
procedure WithoutLSDA;
procedure WithLSDA;
implementation
uses SysUtils;
procedure RaiseLeaf;
begin
  raise Exception.Create('unwind');
end;
procedure WithoutLSDA;
begin
  RaiseLeaf;
  Inc(Returned);
end;
procedure WithLSDA;
var S: UnicodeString;
begin
  S := IntToStr(Cleaned) + ' managed';
  try
    WithoutLSDA;
  finally
    If S = '' then Halt(10);
    Inc(Cleaned);
  end;
end;
end.
