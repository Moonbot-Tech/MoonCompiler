program locale_identity_semantic;
{$mode delphiunicode}
uses {$ifdef UNIX}cwstring,{$endif} SysUtils, Classes;
type TCustomList=class(TStringList)
  protected
    function DoCompareText(const A,B:UnicodeString):PtrInt; override;
  end;
var Checks,Calls,CompareCalls:Integer;
procedure Check(B:Boolean;const What:UnicodeString);
begin
  Inc(Checks);
  if not B then begin WriteLn('FAIL ',What);Halt(1);end;
end;
function TCustomList.DoCompareText(const A,B:UnicodeString):PtrInt;
begin
  Inc(CompareCalls);
  Result:=inherited DoCompareText(A,B);
end;
function CustomCompare(const A,B:UnicodeString;Options:TCompareOptions):PtrInt;
begin
  Inc(Calls);
  Result:=19;
end;
var Original,Custom:TUnicodeStringManager;
    U,V,E:UnicodeString;
    W:WideString;
    List:TCustomList;
    I:Integer;
    Raised:Boolean;
begin
  GetWideStringManager(Original);
  U:='Abc'#0#$0416#$4E2D;
  V:=Copy(U,1,Length(U));
  UniqueString(V);
  Check(Pointer(U)<>Pointer(V),'distinct equal fixture');
  Check(AnsiCompareText(U,U)=0,'same pointer text');
  Check(AnsiCompareStr(U,U)=0,'same pointer string');
  Check(AnsiCompareText(U,V)=0,'distinct equal text');
  Check(AnsiCompareStr(U,V)=0,'distinct equal string');
  Check(AnsiCompareText(E,E)=0,'nil text');
  Check(AnsiCompareStr(E,E)=0,'nil string');
  W:=U;
  Check(Original.CompareWideStringProc(W,W,[])=0,'WideString identity');
  Check(Original.CompareWideStringProc(W,W,[coIgnoreCase])=0,'WideString text identity');
  Check(Original.CompareUnicodeBufferToStringProc(Pointer(U),Length(U),U,[])=0,'buffer identity');
{$ifdef MSWINDOWS}
  Raised:=False;
  try
    Original.CompareUnicodeBufferToStringProc(nil,0,E,[]);
  except on EOSError do Raised:=True;end;
  Check(Raised,'nil buffer keeps OS validation');
{$else}
  Check(Original.CompareUnicodeBufferToStringProc(nil,0,E,[])=0,'nil buffer');
{$endif}
  Check(Original.CompareUnicodeBufferToStringProc(Pointer(U),0,E,[])=0,'empty buffer');
  Check(Original.CompareUnicodeBufferToStringProc(Pointer(U),Length(U)-1,U,[])=
    AnsiCompareStr(Copy(U,1,Length(U)-1),U),'same pointer different length');
  Custom:=Original;
  Custom.CompareUnicodeStringProc:=@CustomCompare;
  SetWideStringManager(Custom);
  try
    Calls:=0;
    Check(AnsiCompareText(U,U)=1,'custom text manager');
    Check(AnsiCompareStr(U,U)=1,'custom string manager');
    Check(Calls=2,'custom manager remains observable');
  finally SetWideStringManager(Original);end;
  List:=TCustomList.Create;
  try
    List.Sorted:=True;
    List.Add(U);
    CompareCalls:=0;
    Check(List.Find(U,I) and (I=0),'custom list Find');
    Check(CompareCalls=1,'custom list comparer remains observable');
  finally List.Free;end;
  WriteLn('LOCALE_IDENTITY_PASS',' checks=',Checks);
end.
