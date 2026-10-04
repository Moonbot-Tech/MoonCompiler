program seh_vmt_symbol_semantic;
{$mode delphiunicode}
uses SysUtils, seh_vmt_foreign_unit;
type
  ELocalForeignAlias = type EForeign;
  EChain = type ELocalForeignAlias;
  ELocal = class(Exception);
  ELocalAlias = type ELocal;
  EGeneric<T> = class(Exception);
  EInteger = EGeneric<Integer>;
var Checks: Integer;
procedure LocalOnce;
begin
  try
    raise ELocal.Create('local');
  except
    on ELocal do Inc(Checks);
  end;
end;
procedure LocalTwice;
begin
  try
    raise ELocal.Create('local');
  except
    on E: ELocal do If E.Message='local' then Inc(Checks);
  end;
end;
procedure ForeignOnce;
begin
  try
    RaiseForeign;
  except
    on EForeign do Inc(Checks);
  end;
end;
procedure GenericOnce;
begin
  try
    raise EInteger.Create('generic');
  except
    on EInteger do Inc(Checks);
  end;
end;
begin
  LocalOnce;
  LocalTwice;
  ForeignOnce;
  GenericOnce;
  try
    raise ELocal.Create('local');
  except
    on E: ELocal do If E.Message='local' then Inc(Checks);
  end;
  try
    raise ELocalAlias.Create('alias');
  except
    on ELocalAlias do Inc(Checks);
  end;
  try
    RaiseForeign;
  except
    on E: EForeignAlias do If E.Message='foreign' then Inc(Checks);
  end;
  try
    raise EInteger.Create('generic');
  except
    on EInteger do Inc(Checks);
  end;
  try
    RaiseForeign;
  except
    on ELocalForeignAlias do Inc(Checks);
  end;
  try
    RaiseForeign;
  except
    on EChain do Inc(Checks);
  end;
  If Checks<>10 then Halt(1);
  WriteLn('SEH_VMT_PASS', ' ', Checks);
end.
