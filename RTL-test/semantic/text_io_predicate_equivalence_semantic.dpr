program text_io_predicate_equivalence_semantic;
{$mode delphi}
uses SysUtils;
var Cases:Integer; DriverData,DriverRepeat:Boolean;
procedure Check(Value:Boolean);
begin
  If not Value then Halt(1);
end;
procedure RefuseRead(var T:TextRec);
begin
  T.BufPos:=0;
  T.BufEnd:=0;
  Inc(T.UserData[1]);
  If DriverData and (T.UserData[1]=1) then begin
    T.BufEnd:=2;
    T.Buffer[0]:=AnsiChar(T.UserData[2]);
    If DriverRepeat then T.Buffer[1]:=T.Buffer[0] else T.Buffer[1]:='x';
  end;
  InOutRes:=99+T.UserData[1];
end;
procedure Configure(var T:Text; C:Integer; Empty:Boolean);
begin
  Assign(T,ShortString(''));
  TextRec(T).Mode:=fmInput;
  TextRec(T).BufPos:=0;
  TextRec(T).BufEnd:=2;
  TextRec(T).Buffer[0]:=AnsiChar(C);
  TextRec(T).Buffer[1]:='x';
  TextRec(T).UserData[2]:=C;
  TextRec(T).InOutFunc:=@RefuseRead;
  If Empty then TextRec(T).BufEnd:=0;
end;
{$I-}
function Reference(var T:Text; Operation:Integer):Boolean;
begin
  case Operation of
    0:Result:=Eof(T);
    1:Result:=Eoln(T);
    2:Result:=SeekEof(T);
    3:Result:=SeekEoln(T);
  end;
end;
{$I+}
function Checked(var T:Text; Operation:Integer):Boolean;
begin
  case Operation of
    0:Result:=Eof(T);
    1:Result:=Eoln(T);
    2:Result:=SeekEof(T);
    3:Result:=SeekEoln(T);
  end;
end;
procedure Compare(C,Operation,Pending:Integer; Empty:Boolean);
var A,B:Text; VA,VB,Caught:Boolean; ErrorA,ErrorB:Integer;
begin
  Configure(A,C,Empty);
  Configure(B,C,Empty);
  InOutRes:=Pending;
  VA:=Reference(A,Operation);
  ErrorA:=IOResult;
  InOutRes:=Pending;
  Caught:=False;
  ErrorB:=0;
  VB:=False;
  try
    VB:=Checked(B,Operation);
  except
    on E:EInOutError do begin
      Caught:=True;
      ErrorB:=E.ErrorCode;
    end;
  end;
  Check(IOResult=0);
  Check((ErrorA<>0)=Caught);
  Check(ErrorA=ErrorB);
  If not Caught then Check(VA=VB);
  If (TextRec(A).BufPos<>TextRec(B).BufPos) or (TextRec(A).BufEnd<>TextRec(B).BufEnd) then
    WriteLn('DIFFER C=',C,' operation=',Operation,' pending=',Pending,' data=',DriverData,
      ' A=',TextRec(A).BufPos,'/',TextRec(A).BufEnd,' B=',TextRec(B).BufPos,'/',TextRec(B).BufEnd);
  Check(TextRec(A).BufPos=TextRec(B).BufPos);
  Check(TextRec(A).BufEnd=TextRec(B).BufEnd);
  Check(TextRec(A).UserData[1]=TextRec(B).UserData[1]);
  Inc(Cases);
end;
var C,Operation,Pending,Z,R:Integer;
begin
  for Z:=0 to 1 do begin
    CtrlZMarksEOF:=Z<>0;
    for C:=0 to 255 do
      for Operation:=0 to 3 do
        for Pending:=0 to 1 do
          Compare(C,Operation,Pending*5,False);
    for Operation:=0 to 3 do
      for Pending:=0 to 1 do
        Compare(0,Operation,Pending*5,True);
  end;
  DriverData:=True;
  for R:=0 to 1 do begin
    DriverRepeat:=R<>0;
    for Z:=0 to 1 do begin
      CtrlZMarksEOF:=Z<>0;
      for C:=0 to 255 do
        for Operation:=0 to 3 do
          for Pending:=0 to 1 do
            Compare(C,Operation,Pending*5,True);
    end;
  end;
  Check(Cases=12304);
  WriteLn('TEXT_IO_PREDICATE_EQUIVALENCE_PASS',' ',Cases);
end.
