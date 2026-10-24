unit A;
interface
uses System.TypInfo;
{$RTTI EXPLICIT METHODS([vcPublic])}
{$ifdef POOL_ALIGN_SPLIT}
{$CODEALIGN CONSTMIN=16}
{$endif}
{$PACKRECORDS 1}
type TProbe=class
 function Shared(Value:Integer):Integer;
 procedure MixedCase;
 procedure PoolLongxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxA;
end;
function Method(Index:Integer):PVmtMethodExEntry;
implementation
function TProbe.Shared(Value:Integer):Integer;begin Result:=Value+1;end;
procedure TProbe.MixedCase;begin end;
procedure TProbe.PoolLongxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxA;begin end;
function Method(Index:Integer):PVmtMethodExEntry;
begin Result:=PClassData(GetTypeData(TProbe.ClassInfo))^.ExMethodTable^.Method[Index];end;
end.
