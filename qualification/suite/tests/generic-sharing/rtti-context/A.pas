unit A;
interface
uses System.TypInfo,Core;
{$RTTI EXPLICIT FIELDS([]) METHODS([]) PROPERTIES([])}
type TExport=TBox<Integer>;
 TLocal=class public Visible:Integer; end;
function RecordInfo:PTypeInfo;
function InnerInfo:PTypeInfo;
function LocalInfo:PTypeInfo;
function Info:PTypeInfo;
implementation
function RecordInfo:PTypeInfo;begin Result:=TypeInfo(TRec<Integer>);end;
function InnerInfo:PTypeInfo;begin Result:=TypeInfo(TExport.TInner);end;
function LocalInfo:PTypeInfo;begin Result:=TypeInfo(TLocal);end;
function Info:PTypeInfo;begin Result:=TypeInfo(TExport);end;
end.
