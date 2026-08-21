program guid;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$endif}
{$APPTYPE CONSOLE}
uses {$ifdef FPC}mormot.core.fpcx64mm,{$endif} SysUtils;

procedure Try_(const S: string);
var
  G: TGUID;
begin
  Write(S, ' -> ');
  try
    G := StringToGUID(S);
    WriteLn('ok  D1=', IntToHex(G.D1, 8), ' D2=', IntToHex(G.D2, 4),
            ' D3=', IntToHex(G.D3, 4), ' back=', GUIDToString(G));
  except
    on E: Exception do
      WriteLn('RAISED ', E.ClassName);
  end;
end;

begin
  Try_('{00000000-0000-0000-0000-000000000000}');
  Try_('{12345678-1234-1234-1234-123456789ABC}');
  Try_('{4D5A0001-0000-0000-0000-0000524553FF}');
  Try_('{4D5A0001-0000-0000-0000-0000524553FE}');
  Try_('{4D5A0001-0000-0000-0000-0000524553AF}');
  Try_('{4D5A0001-0000-0000-0000-0000524553Fa}');
  Try_('{FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF}');
  Try_('{4d5a0001-0000-0000-0000-0000524553ff}');
  Try_('{4D5A0001-0000-0000-0000-00005245530F}');
  Try_('{4D5A0001-0000-0000-0000-0000524553F0}');
  WriteLn('done');
end.
