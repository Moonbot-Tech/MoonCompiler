program rtl_api_text_operations_contracts;

{$mode delphiunicode}{$Q-}{$R-}{$POINTERMATH ON}

uses
  {$ifdef MSWINDOWS}Windows,{$else}BaseUnix,{$endif}
  SysUtils;

var Checks: UInt64;
procedure Require(Condition: Boolean; const Why: ShortString);
begin
  If not Condition then raise Exception.Create(Why);
  Inc(Checks);
end;

function CompareSign(Value: Integer): Integer;
begin
  If Value<0 then Result := -1
  else If Value>0 then Result := 1
  else Result := 0;
end;

function ReferenceCompare(const A, B: UnicodeString): Integer;
var
  I, Count, C1, C2: Integer;
begin
  Count := Length(A);
  If Length(B)<Count then Count := Length(B);
  for I := 1 to Count do
  begin
    C1 := Ord(A[I]);
    C2 := Ord(B[I]);
    If (C1>=97) and (C1<=122) then Dec(C1,32);
    If (C2>=97) and (C2<=122) then Dec(C2,32);
    If C1<>C2 then Exit(CompareSign(C1-C2));
  end;
  If Length(A)<Length(B) then Result := -1
  else If Length(A)>Length(B) then Result := 1
  else Result := 0;
end;

{$I rtl_api_text_guard.inc}

procedure CheckCompare;
const
  Neighbors: array[0..13] of WideChar = (#0,#31,#32,'a','z','A','Z',#127,#255,#256,#$7fff,#$8000,#$d800,#$ffff);
  Counts: array[0..9] of Integer = (1,2,7,8,9,15,16,17,31,32);
var
  A, B: UnicodeString;
  C, Count, Code, N, Position, Test: Integer;
  Ch: WideChar;
begin
  for N in Counts do
  begin
    A := StringOfChar('X',N);
    B := StringOfChar('X',N);
    for Test := 0 to 2 do
    begin
      case Test of
        0: Position := 1;
        1: Position := N div 2+1;
      else Position := N;
      end;
      Count := Length(Neighbors);
      If (N=8) or (N=17) then Count := $10000;
      for C := 0 to Count-1 do
      begin
        Code := C;
        If Count<>$10000 then Code := Ord(Neighbors[C]);
        A[Position] := WideChar(Code);
        for Ch in Neighbors do
        begin
          B[Position] := Ch;
          Require(CompareSign(CompareText(A,B))=ReferenceCompare(A,B),'ASCII fold/UTF16 ordinal ordering');
          Require(CompareSign(CompareText(B,A))=ReferenceCompare(B,A),'reverse UTF16 ordering');
          Require(SameText(A,B)=(ReferenceCompare(A,B)=0),'SameText ASCII fold/UTF16 equality');
          Require(SameText(B,A)=(ReferenceCompare(B,A)=0),'reverse SameText equality');
        end;
      end;
      A[Position] := 'X';
      B[Position] := 'X';
    end;
    for C := 0 to 4 do
    begin
      B := A+StringOfChar('x',C*7);
      Require(CompareSign(CompareText(A,B))=ReferenceCompare(A,B),'prefix length ordering');
      Require(CompareSign(CompareText(B,A))=ReferenceCompare(B,A),'reverse prefix length ordering');
      Require(SameText(A,B)=(ReferenceCompare(A,B)=0),'SameText unequal lengths');
    end;
  end;
  GuardCompare;
  Require(SameText('',''),'SameText empty identity');
  Require(not SameText('','a'),'SameText nil and nonempty');
  Require(not SameText('a',''),'SameText nonempty and nil');
end;

function ReferenceEncode(const S: UnicodeString): RawByteString;
var
  I, J: SizeInt;
  C: Cardinal;
  procedure Put(B: Byte);
  begin
    Inc(J);
    Result[J] := AnsiChar(B);
  end;
begin
  SetLength(Result,3*Length(S));
  I := 1;
  J := 0;
  while I<=Length(S) do
  begin
    C := Ord(S[I]);
    If (C>=$d800) and (C<=$dbff) and (I<Length(S)) and
       (Ord(S[I+1])>=$dc00) and (Ord(S[I+1])<=$dfff) then
    begin
      C := $10000+((C-$d800) shl 10)+Ord(S[I+1])-$dc00;
      Inc(I);
    end
    else If (C>=$d800) and (C<=$dfff) then C := $fffd;
    If C<$80 then Put(Byte(C))
    else If C<$800 then
    begin
      Put(Byte($c0 or (C shr 6)));
      Put(Byte($80 or (C and $3f)));
    end
    else If C<$10000 then
    begin
      Put(Byte($e0 or (C shr 12)));
      Put(Byte($80 or ((C shr 6) and $3f)));
      Put(Byte($80 or (C and $3f)));
    end
    else
    begin
      Put(Byte($f0 or (C shr 18)));
      Put(Byte($80 or ((C shr 12) and $3f)));
      Put(Byte($80 or ((C shr 6) and $3f)));
      Put(Byte($80 or (C and $3f)));
    end;
    Inc(I);
  end;
  SetLength(Result,J);
end;

procedure CheckUTF8;
const
  Prefixes: array[0..8] of Integer = (0,1,7,8,15,16,127,4096,65536);
  Neighbors: array[0..11] of WideChar = (#0,#127,#128,#$7ff,#$800,#$d7ff,#$d800,#$dbff,#$dc00,#$dfff,#$e000,#$ffff);
var
  S: UnicodeString;
  Expected, Actual: RawByteString;
  N, C, Count, Code: Integer;
begin
  for N in Prefixes do
  begin
    Count := Length(Neighbors);
    If N=7 then Count := $10000;
    for C := 0 to Count-1 do
    begin
      Code := C;
      If Count<>$10000 then Code := Ord(Neighbors[C]);
      S := StringOfChar('x',N)+WideChar(Code)+UnicodeString(#$d83d#$de00#0#$d800);
      Expected := ReferenceEncode(S);
      Actual := UTF8Encode(S);
      Require(Length(Actual)=Length(Expected),'UTF8 output length');
      Require(CompareMem(Pointer(Actual),Pointer(Expected),Length(Expected)),'UTF8 output bytes');
    end;
  end;
end;

procedure CheckSplit;
const Indexes: array[0..1] of Integer = (0,20);
var
  A, Saved: TStringArray;
  I, J, Index: Integer;
  Shared: Boolean;
begin
  A := nil;
  Require(DynArrayRefCount(Pointer(A))=0,'nil dynamic array reference count');
  SetLength(A,3);
  A[0] := 'first';
  A[2] := 'last';
  Require(DynArrayRefCount(Pointer(A))=1,'unique dynamic array reference count');
  Saved := A;
  Require(DynArrayRefCount(Pointer(A))=2,'shared dynamic array reference count');
  SetLength(A,Length(A));
  Require((DynArrayRefCount(Pointer(A))=1) and (DynArrayRefCount(Pointer(Saved))=1),'same-length copy on write');
  A[0] := 'changed';
  Require((Saved[0]='first') and (Saved[2]='last'),'retained array fields after copy on write');
  A := nil;
  Require(DynArrayRefCount(Pointer(A))=0,'released dynamic array reference count');
  Saved := nil;
  Require(Length('a,b'.Split([','],#0,#0,-1))=0,'negative Split count');
  for Shared in [False,True] do
    for Index in Indexes do
    begin
      Saved := nil;
      SetLength(A,32);
      for I := 0 to High(A) do A[I] := 'retained-'+IntToStr(I);
      { Build a unique heap-owned source directly in the old destination. }
      SetLength(A[Index],261);
      A[Index][1] := 'a';
      A[Index][2] := ',';
      for J := 3 to 258 do A[Index][J] := 'b';
      A[Index][259] := ',';
      A[Index][260] := 'c';
      A[Index][261] := 'd';
      If Shared then Saved := A;
      A := A[Index].Split([',']);
      Require(Length(A)=3,'direct source-alias field count');
      Require((A[0]='a') and (A[1]=StringOfChar('b',256)) and (A[2]='cd'),'direct source-alias contents');
      If Shared then
      begin
        Require(Length(Saved)=32,'retained old array length');
        Require(Length(Saved[Index])=261,'retained source length');
        for I := 0 to High(Saved) do
          If I<>Index then Require(Saved[I]='retained-'+IntToStr(I),'retained field contents');
      end;
    end;
  A := 'a,"b,c",d'.Split([','],'"','"');
  Require((Length(A)=3) and (A[1]='"b,c"'),'quoted Split remains intact');
  A := ',a,,b,'.Split([','],TStringSplitOptions.ExcludeEmpty);
  Require((Length(A)=2) and (A[0]='a') and (A[1]='b'),'Split empty options');
  A := UnicodeString('a').Split([',']);
  Require((Length(A)=1) and (A[0]='a'),'shrink previous result');
end;

begin
  CheckCompare;
  CheckUTF8;
  CheckSplit;
  Writeln('RTL_API_TEXT_OPERATIONS_CONTRACTS_OK');
end.
