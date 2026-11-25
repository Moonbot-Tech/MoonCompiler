program rtti_indexed_setter_semantic;
{$ifdef FPC}{$mode delphi}{$endif}
{$apptype console}
uses SysUtils, Rtti{$if defined(FPC) and defined(UNIX)}, ffi.manager{$ifend};

type
  {$RTTI EXPLICIT METHODS([vcPublic]) PROPERTIES([vcPublic])}
  TBook = class
  public
    Bank: Byte;
    Ticket: Int64;
    Text, Path: UnicodeString;
    Writes: Integer;
    function Fetch(B: Byte; T: Int64; const P: UnicodeString): UnicodeString; virtual;
    function ReadDirect(B: Byte; T: Int64; const P: UnicodeString): UnicodeString;
    procedure Store(B: Byte; T: Int64; const P, V: UnicodeString); virtual;
    procedure StoreDirect(B: Byte; T: Int64; const P, V: UnicodeString);
    property Entry[B: Byte; T: Int64; const P: UnicodeString]: UnicodeString read Fetch write Store;
    property Mixed[B: Byte; T: Int64; const P: UnicodeString]: UnicodeString read ReadDirect write Store;
    property Other[B: Byte; T: Int64; const P: UnicodeString]: UnicodeString read Fetch write StoreDirect;
    property WriteOnly[B: Byte; T: Int64; const P: UnicodeString]: UnicodeString write StoreDirect;
    property ReadOnly[B: Byte; T: Int64; const P: UnicodeString]: UnicodeString read ReadDirect;
  end;
  TDerived = class(TBook)
  public
    function Fetch(B: Byte; T: Int64; const P: UnicodeString): UnicodeString; override;
    procedure Store(B: Byte; T: Int64; const P,V: UnicodeString); override;
  end;
  TStaticBook = class
  public
    class var S: UnicodeString;
    class procedure Put(I: Integer; const V: UnicodeString); static;
    class function Get(I: Integer): UnicodeString; static;
    class property Items[I: Integer]: UnicodeString read Get write Put;
  end;
  TPointBook = record
  public
    S: UnicodeString;
    function Get(I: Integer): UnicodeString;
    procedure Put(I: Integer; const V: UnicodeString);
    property Items[I: Integer]: UnicodeString read Get write Put;
  end;
  {$RTTI INHERIT}
const
  Slot = 233;
  Num = Int64(-93000000061);
  Input: UnicodeString = 'a'+#0+#$03BB;
var
  Obj: TBook;
  Matched: Boolean;

procedure Check(Ok: Boolean; const Detail: string);
begin
  if not Ok then begin Writeln('FAIL ',Detail); Halt(1) end;
end;

function TBook.Fetch(B: Byte; T: Int64; const P: UnicodeString): UnicodeString;
begin Result:='base' end;

function TBook.ReadDirect(B: Byte; T: Int64; const P: UnicodeString): UnicodeString;
begin Result:=P+Text end;

procedure TBook.StoreDirect(B: Byte; T: Int64; const P,V: UnicodeString);
begin
  Matched:=(Self=Obj) and (B=Slot) and (T=Num);
  if Matched then begin
    Bank:=B;
    Ticket:=T;
    Path:=P;
    Text:=V;
    Inc(Writes);
  end;
end;

procedure TBook.Store(B: Byte; T: Int64; const P,V: UnicodeString);
begin StoreDirect(B,T,P,V) end;

procedure TDerived.Store(B: Byte; T: Int64; const P,V: UnicodeString);
begin inherited Store(B,T,P,V+'!') end;

function TDerived.Fetch(B: Byte; T: Int64; const P: UnicodeString): UnicodeString;
begin Result:=ReadDirect(B,T,P)+'?' end;

class procedure TStaticBook.Put(I: Integer; const V: UnicodeString);
begin S:=IntToStr(I)+V end;
class function TStaticBook.Get(I: Integer): UnicodeString;
begin Result:=S+IntToStr(I) end;

procedure TPointBook.Put(I: Integer; const V: UnicodeString);
begin S:=IntToStr(I)+V end;
function TPointBook.Get(I: Integer): UnicodeString;
begin Result:=S+IntToStr(I) end;

var
  C: TRttiContext;
  K: TRttiType;
  Prop: TRttiIndexedProperty;
  Point: TPointBook;

procedure CheckProperty(const Name: string; const Expected: UnicodeString; HasOverride: Boolean);
var P: TRttiIndexedProperty; Args: array[0..2] of TValue; Before: Integer; ReadBack: UnicodeString;
begin
  P:=K.GetIndexedProperty(Name);
  Check((P<>nil) and P.IsWritable,Name);
  Args[0]:=TValue.From<Byte>(Slot);
  Args[1]:=TValue.From<Int64>(Num);
  Args[2]:=TValue.From<UnicodeString>('key');
  Before:=Obj.Writes;
  Matched:=False;
  P.SetValue(Obj,Args,TValue.From<UnicodeString>(Input));
  Check(Matched and (Obj.Writes=Before+1) and (Obj.Bank=Slot) and
        (Obj.Ticket=Num) and (Obj.Path='key') and (Obj.Text=Expected),Name+' setter');
  if P.IsReadable then begin
    ReadBack:=P.GetValue(Obj,Args).AsType<UnicodeString>;
    if HasOverride then Check(ReadBack='key'+Expected+'?',Name+' virtual getter')
    else Check(ReadBack='key'+Expected,Name+' direct getter');
  end;
end;

begin
  C:=TRttiContext.Create;
  Obj:=TDerived.Create;
  try
    K:=C.GetType(TBook);
    CheckProperty('Entry',Input+'!',True);
    CheckProperty('Mixed',Input+'!',False);
    CheckProperty('Other',Input,True);
    CheckProperty('WriteOnly',Input,False);
    Prop:=K.GetIndexedProperty('ReadOnly');
    Check(Prop.IsReadable and not Prop.IsWritable and (Prop.WriteMethod=nil),'read-only metadata');
    Prop:=K.GetIndexedProperty('WriteOnly');
    Check(not Prop.IsReadable and (Prop.ReadMethod=nil) and (Prop.WriteMethod<>nil),'write-only metadata');
    Prop:=C.GetType(TStaticBook).GetIndexedProperty('Items');
    Prop.SetValue(nil,[7],TValue.From<UnicodeString>(Input));
    Check(Prop.GetValue(nil,[8]).AsType<UnicodeString> = '7'+Input+'8','static class accessors');
{$ifdef FPC}
    { The Delphi 12.2 record has no indexed-property descriptor. }
    Prop:=C.GetType(TypeInfo(TPointBook)).GetIndexedProperty('Items');
    Check(Prop<>nil,'record indexed metadata');
    Prop.SetValue(@Point,[9],TValue.From<UnicodeString>(Input));
    Check((Point.S='9'+Input) and (Prop.GetValue(@Point,[3]).AsType<UnicodeString> = Point.S+'3'),
      'record accessors mutate the original record');
{$endif}
  finally
    Obj.Free;
    C.Free;
  end;
  WriteLn('RTTI_INDEXED_SETTER_PASS');
end.
