unit B;
interface
uses System.TypInfo;
{$RTTI EXPLICIT METHODS([vcPublic])}
{$ifdef POOL_ALIGN_SPLIT}
{$CODEALIGN CONSTMIN=32}
{$endif}
{$PACKRECORDS 8}
type TProbe=class
 function Shared(Value:Integer):Integer;
 procedure mixedcase;
 procedure PoolLongxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxB;
end;
function Method(Index:Integer):PVmtMethodExEntry;
implementation
function TProbe.Shared(Value:Integer):Integer;begin Result:=Value+1;end;
procedure TProbe.mixedcase;begin end;
procedure TProbe.PoolLongxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxB;begin end;
function Method(Index:Integer):PVmtMethodExEntry;
begin Result:=PClassData(GetTypeData(TProbe.ClassInfo))^.ExMethodTable^.Method[Index];end;
end.
