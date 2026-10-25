program mccompact;
{$mode objfpc}{$H+}
{ Stand native final-link transformer. Input and output are uncompressed DWARF
  sections; objcopy owns the executable container. No target code is decoded. }
uses Classes, SysUtils, Process {$ifdef unix}, BaseUnix {$endif};
type
  TBytes = RawByteString;
  TAttr = record Name, Form: QWord; Pos, Len: SizeInt; Value: QWord; Text: TBytes end;
  TAttrs = array of TAttr;
  TAbbrev = class
    Tag: QWord; Children: Boolean; Attrs: TAttrs;
  end;
  TMethod = record First, Last: SizeInt; Lo, Hi: QWord; Name: TBytes; Keep: Boolean end;
  TMethods = array of TMethod;
  TSequence = record First, Last: SizeInt; Lo, Hi: QWord; Key: TBytes; Keep: Boolean end;
  TSequences = array of TSequence;
  TCU = class
    First, Last, RootEnd, NewOffset, StmtPos: SizeInt;
    Stmt, AddrSize: QWord; Eligible: Boolean; Methods: TMethods;
    CompDir: TBytes; LineFirst, LineLast, LineHeaderEnd: SizeInt; Seqs: TSequences;
  end;
  TMethodOwner = class
    CU: TCU; Index: SizeInt; Next: TMethodOwner;
  end;
  TBinaryStrings = class(TStringList)
    function CompareStrings(const S1,S2: string): Integer; override;
  end;
  TSection = record Name: string; Header, Offset, Size: SizeInt; Addr, Flags: QWord end;
  TSections = array of TSection;
var
  Info, Abbrev, Lines, Aranges, NewInfo, NewLines, NewAranges: TBytes;
  Units: array of TCU;
  Maps, Seen: TStringList;
  RemovedMethods, RemovedSequences: SizeInt;

function TBinaryStrings.CompareStrings(const S1,S2: string): Integer;
var I,N: SizeInt;
begin
  N:=Length(S1); if Length(S2)<N then N:=Length(S2);
  for I:=1 to N do if S1[I]<>S2[I] then Exit(Ord(S1[I])-Ord(S2[I]));
  if Length(S1)<Length(S2) then Result:=-1
  else if Length(S1)>Length(S2) then Result:=1 else Result:=0;
end;

procedure Need(Condition: Boolean; const Msg: string);
begin
  if not Condition then raise Exception.Create(Msg);
end;

function ReadN(const B: TBytes; var P: SizeInt; N: SizeInt): QWord;
var I: SizeInt;
begin
  Need((N>=0) and (N<=8) and (P>=0) and (P<=Length(B)-N),'truncated integer');
  Result:=0;
  for I:=0 to N-1 do Result:=Result or (QWord(Byte(B[P+I+1])) shl (I*8));
  Inc(P,N);
end;

function ULEB(const B: TBytes; var P: SizeInt): QWord;
var C, Shift: QWord;
begin
  Result:=0; Shift:=0;
  repeat
    C:=ReadN(B,P,1);
    Need(Shift<64,'LEB overflow');
    Result:=Result or ((C and 127) shl Shift);
    Inc(Shift,7);
  until C<128;
end;

function SLEB(const B: TBytes; var P: SizeInt): Int64;
var C, Shift, V: QWord;
begin
  V:=0; Shift:=0;
  repeat
    C:=ReadN(B,P,1); Need(Shift<64,'signed LEB overflow');
    V:=V or ((C and 127) shl Shift); Inc(Shift,7);
  until C<128;
  if (Shift<64) and (C and 64<>0) then V:=V or (QWord(-1) shl Shift);
  Result:=Int64(V);
end;

function ZString(const B: TBytes; var P: SizeInt): TBytes;
var S: SizeInt;
begin
  S:=P;
  while ReadN(B,P,1)<>0 do ;
  Result:=Copy(B,S+1,P-S-1);
end;

function Slice(const B: TBytes; First, Last: SizeInt): TBytes;
begin
  Need((First>=0) and (Last>=First) and (Last<=Length(B)),'invalid byte range');
  Result:=Copy(B,First+1,Last-First);
end;

procedure Put(var B: TBytes; P, N: SizeInt; V: QWord);
var I: SizeInt;
begin
  Need((P>=0) and (P<=Length(B)-N),'write overflow');
  for I:=0 to N-1 do B[P+I+1]:=AnsiChar((V shr (I*8)) and 255);
end;

procedure AddN(var B: TBytes; V: QWord; N: SizeInt);
var P: SizeInt;
begin
  P:=Length(B); SetLength(B,P+N); Put(B,P,N,V);
end;

function Load(const Name: string): TBytes;
var F: TFileStream;
begin
  F:=TFileStream.Create(Name,fmOpenRead or fmShareDenyWrite);
  try SetLength(Result,F.Size); if F.Size<>0 then F.ReadBuffer(Result[1],F.Size); finally F.Free end;
end;

procedure Save(const Name: string; const B: TBytes);
var F: TFileStream;
begin
  F:=TFileStream.Create(Name,fmCreate);
  try if Length(B)<>0 then F.WriteBuffer(B[1],Length(B)); finally F.Free end;
end;

procedure FreeMaps;
var I: Integer;
begin
  for I:=0 to Maps.Count-1 do Maps.Objects[I].Free;
  Maps.Clear;
end;

procedure ReadAbbrevs(Offset: QWord);
var P, N: SizeInt; Code, A, F: QWord; V: TAbbrev;
begin
  FreeMaps; P:=Offset;
  repeat
    Code:=ULEB(Abbrev,P); if Code=0 then Break;
    V:=TAbbrev.Create; V.Tag:=ULEB(Abbrev,P); V.Children:=ReadN(Abbrev,P,1)<>0;
    Maps.AddObject(IntToStr(Code),V);
    repeat
      A:=ULEB(Abbrev,P); F:=ULEB(Abbrev,P);
      if (A=0) and (F=0) then Break;
      N:=Length(V.Attrs); SetLength(V.Attrs,N+1); V.Attrs[N].Name:=A; V.Attrs[N].Form:=F;
      Need(F<>$21,'DW_FORM_implicit_const requires DWARF5');
    until False;
  until False;
end;

procedure ReadAttr(var A: TAttr; var P: SizeInt; AddrSize: QWord);
begin
  A.Pos:=P; A.Value:=0; A.Text:='';
  case A.Form of
    $01: A.Value:=ReadN(Info,P,AddrSize);
    $06,$17: A.Value:=ReadN(Info,P,4);
    $08: A.Text:=ZString(Info,P);
    $0b: A.Value:=ReadN(Info,P,1);
    $10: raise Exception.Create('global DW_FORM_ref_addr: preserve original sections');
    else raise Exception.CreateFmt('unsupported DWARF form %x: preserve original sections',[A.Form]);
  end;
  Need(P<=Length(Info),'truncated attribute'); A.Len:=P-A.Pos;
end;

procedure ParseInfo;
var P, E, I, J, K, N, First, Depth: SizeInt; Len, Version, AOffset, Code: QWord;
    C: TCU; A: TAttrs; V: TAbbrev; Producer: TBytes; M: TMethod; CompactShape: Boolean;
begin
  P:=0;
  while P<Length(Info) do begin
    C:=TCU.Create; N:=Length(Units); SetLength(Units,N+1); Units[N]:=C;
    C.First:=P; Len:=ReadN(Info,P,4); Need(Len<$fffffff0,'DWARF64 unsupported: preserve original sections');
    E:=P+Len; Need(E<=Length(Info),'truncated CU'); C.Last:=E;
    Version:=ReadN(Info,P,2); Need(Version in [2,3,4],'unsupported CU version');
    AOffset:=ReadN(Info,P,4); C.AddrSize:=ReadN(Info,P,1); Need(C.AddrSize in [4,8],'unsupported address size');
    ReadAbbrevs(AOffset); Depth:=0; CompactShape:=True; Producer:=''; C.StmtPos:=-1;
    while P<E do begin
      First:=P; Code:=ULEB(Info,P);
      if Code=0 then begin Dec(Depth); Need(Depth>=0,'unbalanced DIE tree'); Continue end;
      I:=Maps.IndexOf(IntToStr(Code)); Need(I>=0,'unknown abbrev'); V:=TAbbrev(Maps.Objects[I]);
      if First<>C.First+11 then
        Need((Depth=1) and (V.Tag=$2e) and not V.Children and (Length(V.Attrs)=3),
          'full or external DIE graph: preserve original sections');
      A:=Copy(V.Attrs); for J:=0 to High(A) do ReadAttr(A[J],P,C.AddrSize);
      if First=C.First+11 then begin
        Need(V.Tag=$11,'non compile unit'); Need(V.Children,'CU without children');
        C.RootEnd:=P;
        for J:=0 to High(A) do case A[J].Name of
          $03: Need(A[J].Form=$08,'unsupported CU name');
          $25: begin Need(A[J].Form=$08,'unsupported producer form'); Producer:=A[J].Text end;
          $1b: begin Need(A[J].Form=$08,'unsupported comp_dir form'); C.CompDir:=A[J].Text end;
          $13,$42: Need(A[J].Form=$0b,'unsupported CU language or identifier case');
          $11,$12: Need(A[J].Form=$01,'unsupported CU address form');
          $10: begin
            Need(A[J].Form in [$06,$17],'unsupported stmt_list form');
            C.Stmt:=A[J].Value; C.StmtPos:=A[J].Pos; Need(A[J].Len=4,'non32 stmt_list');
          end;
          else raise Exception.Create('external CU attributes: preserve original sections');
        end;
      end else begin
        M.Name:=''; FillChar(M,SizeOf(M),0); M.First:=First; M.Last:=P; M.Keep:=True;
        K:=0;
        for J:=0 to High(A) do case A[J].Name of
          $03: begin M.Name:=A[J].Text; if A[J].Form=$08 then Inc(K) end;
          $11: begin M.Lo:=A[J].Value; if A[J].Form=$01 then Inc(K) end;
          $12: begin M.Hi:=A[J].Value; if A[J].Form=$01 then Inc(K) end;
        end;
        if K<>3 then CompactShape:=False;
        N:=Length(C.Methods); SetLength(C.Methods,N+1); C.Methods[N]:=M;
      end;
      if V.Children then Inc(Depth);
    end;
    Need((P=E) and (Depth=0),'invalid CU extent');
    Need(CompactShape,'full or external DIE graph: preserve original sections');
    C.Eligible:=CompactShape and (Pos('[MCcompact1]',Producer)<>0) and (C.StmtPos>=0);
    if not C.Eligible then C.Methods:=nil;
  end;
end;

procedure ParseLines(C: TCU);
var P, E, H, SeqStart, N, I, J: SizeInt;
    Version, Len, HeaderLen, MinInst, MaxOps, DefStmt, LineRange, OpBase, Op, Ext, L: QWord;
    Address, FileNo, Column, IsStmt, Basic, Prologue, Epilogue, Isa, Discriminator, OpIndex: QWord;
    LineNo, LineBase: Int64;
    Dirs, Files: array of TBytes; StdLens: array of QWord;
    S, Key, Name: TBytes; Started: Boolean; SeqLo, SeqHi: QWord;
  function AbsolutePath(const Path: TBytes): Boolean;
  begin
    Result:=(Length(Path)>0) and (Path[1]='/') or
      (Length(Path)>1) and (Path[1]='\') and (Path[2]='\') or
      (Length(Path)>2) and (Path[2]=':') and (Path[3] in ['/','\']);
  end;
  procedure Reset;
  begin
    Address:=0; FileNo:=1; LineNo:=1; Column:=0; IsStmt:=DefStmt;
    Basic:=0; Prologue:=0; Epilogue:=0; Isa:=0; Discriminator:=0; OpIndex:=0;
    Key:=''; Started:=False; SeqLo:=0; SeqHi:=0;
  end;
  procedure Advance(Delta: QWord);
  begin
    Inc(Address,MinInst*((OpIndex+Delta) div MaxOps)); OpIndex:=(OpIndex+Delta) mod MaxOps;
  end;
  procedure Row(IsEnd: Boolean);
  begin
    Need((FileNo>0) and (FileNo<=QWord(Length(Files))),'invalid line file index');
    if Started and (SeqLo<>0) then Need(Address>=SeqHi,'non-monotonic live line sequence');
    if not Started then begin SeqLo:=Address; Started:=True end;
    SeqHi:=Address;
    AddN(Key,Address,8); AddN(Key,QWord(LineNo),8); AddN(Key,Column,8);
    AddN(Key,IsStmt,1); AddN(Key,Basic,1); AddN(Key,Ord(IsEnd),1);
    AddN(Key,Prologue,1); AddN(Key,Epilogue,1); AddN(Key,Isa,8);
    AddN(Key,Discriminator,8); AddN(Key,OpIndex,8);
    S:=Files[FileNo-1]; AddN(Key,Length(S),4); Key:=Key+S;
    Basic:=0; Prologue:=0; Epilogue:=0; Discriminator:=0;
  end;
  procedure ReadFile;
  var D: QWord; Directory: TBytes;
  begin
    Name:=ZString(Lines,P); if Name='' then Exit;
    D:=ULEB(Lines,P); ULEB(Lines,P); ULEB(Lines,P);
    if not AbsolutePath(Name) then begin
      Directory:=C.CompDir;
      if D<>0 then begin
        Need(D<=QWord(Length(Dirs)),'invalid directory index'); Directory:=Dirs[D-1];
        if not AbsolutePath(Directory) then Directory:=C.CompDir+'/'+Directory;
      end;
      Name:=Directory+'/'+Name;
    end;
    N:=Length(Files); SetLength(Files,N+1); Files[N]:=Name;
  end;
begin
  Dirs:=nil; Files:=nil;
  P:=C.Stmt; C.LineFirst:=P; Len:=ReadN(Lines,P,4); Need(Len<$fffffff0,'DWARF64 line table');
  E:=P+Len; Need(E<=Length(Lines),'truncated line table'); C.LineLast:=E;
  Version:=ReadN(Lines,P,2); Need(Version in [2,3,4],'unsupported line version');
  HeaderLen:=ReadN(Lines,P,4); H:=P+HeaderLen; Need(H<=E,'line header outside unit');
  MinInst:=ReadN(Lines,P,1); MaxOps:=1;
  if Version>=4 then MaxOps:=ReadN(Lines,P,1);
  Need(MaxOps<>0,'zero max operations'); DefStmt:=ReadN(Lines,P,1);
  LineBase:=ShortInt(ReadN(Lines,P,1)); LineRange:=ReadN(Lines,P,1); Need(LineRange<>0,'zero line range');
  OpBase:=ReadN(Lines,P,1); Need(OpBase>0,'zero opcode base'); SetLength(StdLens,OpBase);
  for I:=1 to OpBase-1 do StdLens[I]:=ReadN(Lines,P,1);
  repeat S:=ZString(Lines,P); if S='' then Break; N:=Length(Dirs); SetLength(Dirs,N+1); Dirs[N]:=S until False;
  repeat ReadFile until Name='';
  Need(P=H,'unexpected line header bytes'); C.LineHeaderEnd:=H; SeqStart:=P; Reset;
  while P<E do begin
    Op:=ReadN(Lines,P,1);
    if Op=0 then begin
      L:=ULEB(Lines,P); J:=P+L; Need(J<=E,'extended opcode outside line unit'); Ext:=ReadN(Lines,P,1);
      case Ext of
        1: begin
          Row(True); N:=Length(C.Seqs); SetLength(C.Seqs,N+1);
          C.Seqs[N].First:=SeqStart; C.Seqs[N].Last:=J; C.Seqs[N].Lo:=SeqLo; C.Seqs[N].Hi:=SeqHi;
          C.Seqs[N].Key:=Key; C.Seqs[N].Keep:=True; SeqStart:=J; Reset;
        end;
        2: begin Address:=ReadN(Lines,P,C.AddrSize); OpIndex:=0 end;
        3: raise Exception.Create('dynamic line file definitions: preserve original sections');
        4: Discriminator:=ULEB(Lines,P);
        else raise Exception.Create('unknown extended line opcode');
      end;
      Need(P=J,'extended opcode length mismatch');
    end else if Op<OpBase then case Op of
      1: Row(False);
      2: Advance(ULEB(Lines,P));
      3: Inc(LineNo,SLEB(Lines,P));
      4: FileNo:=ULEB(Lines,P);
      5: Column:=ULEB(Lines,P);
      6: IsStmt:=1-IsStmt;
      7: Basic:=1;
      8: Advance((255-OpBase) div LineRange);
      9: begin Inc(Address,ReadN(Lines,P,2)); OpIndex:=0 end;
      10: Prologue:=1;
      11: Epilogue:=1;
      12: Isa:=ULEB(Lines,P);
      else raise Exception.Create('unknown standard line opcode');
    end else begin
      Advance((Op-OpBase) div LineRange); Inc(LineNo,LineBase+Int64((Op-OpBase) mod LineRange)); Row(False);
    end;
  end;
  Need((P=E) and (SeqStart=E),'unterminated line sequence');
end;

function Overlap(ALo,AHi,BLo,BHi: QWord): Boolean;
begin Result:=(ALo<BHi) and (BLo<AHi) end;

procedure SelectRecords;
var I,J,K,Slot: SizeInt; C: TCU; Key: TBytes; KeepOverlap,DropOverlap: Boolean;
    Owner,NewOwner: TMethodOwner;
  function SameLines(A: TCU; AM: SizeInt; B: TCU; BM: SizeInt): Boolean;
  var X,Y: SizeInt;
  begin
    X:=0; Y:=0;
    repeat
      while (X<Length(A.Seqs)) and not Overlap(A.Methods[AM].Lo,A.Methods[AM].Hi,A.Seqs[X].Lo,A.Seqs[X].Hi) do Inc(X);
      while (Y<Length(B.Seqs)) and not Overlap(B.Methods[BM].Lo,B.Methods[BM].Hi,B.Seqs[Y].Lo,B.Seqs[Y].Hi) do Inc(Y);
      if (X=Length(A.Seqs)) or (Y=Length(B.Seqs)) then Exit((X=Length(A.Seqs)) and (Y=Length(B.Seqs)));
      if A.Seqs[X].Key<>B.Seqs[Y].Key then Exit(False);
      Inc(X); Inc(Y);
    until False;
  end;
begin
  { A line table shared with another CU cannot be changed independently. }
  for I:=0 to High(Units) do begin
    C:=Units[I];
    for J:=0 to High(Units) do if (I<>J) and (C.Stmt=Units[J].Stmt) then C.Eligible:=False;
  end;
  for I:=0 to High(Units) do begin
    C:=Units[I]; if not C.Eligible then Continue; ParseLines(C);
    for J:=0 to High(C.Methods) do begin
      Need(C.Methods[J].Hi>=C.Methods[J].Lo,'invalid live method range: producer must be fixed');
      Need((C.Methods[J].Lo<>0) or (C.Methods[J].Hi=0),'inconsistent discarded method boundaries');
      if C.Methods[J].Lo=0 then begin C.Methods[J].Keep:=False; Inc(RemovedMethods); Continue end;
      Key:=C.Methods[J].Name+#0; AddN(Key,C.Methods[J].Lo,8); AddN(Key,C.Methods[J].Hi,8);
      Slot:=Seen.IndexOf(string(Key)); Owner:=nil;
      if Slot>=0 then Owner:=TMethodOwner(Seen.Objects[Slot]);
      while Owner<>nil do begin
        if SameLines(C,J,Owner.CU,Owner.Index) then begin
          C.Methods[J].Keep:=False; Inc(RemovedMethods); Break;
        end;
        Owner:=Owner.Next;
      end;
      if C.Methods[J].Keep then begin
        NewOwner:=TMethodOwner.Create; NewOwner.CU:=C; NewOwner.Index:=J;
        if Slot<0 then Seen.AddObject(string(Key),NewOwner)
        else begin NewOwner.Next:=TMethodOwner(Seen.Objects[Slot]); Seen.Objects[Slot]:=NewOwner end;
      end;
    end;
    for J:=0 to High(C.Seqs) do begin
      KeepOverlap:=False; DropOverlap:=False;
      for K:=0 to High(C.Methods) do if Overlap(C.Seqs[J].Lo,C.Seqs[J].Hi,C.Methods[K].Lo,C.Methods[K].Hi) then begin
        if C.Methods[K].Keep then KeepOverlap:=True else DropOverlap:=True;
      end;
      C.Seqs[J].Keep:=(C.Seqs[J].Lo<>0) and (not DropOverlap or KeepOverlap);
      if not C.Seqs[J].Keep then Inc(RemovedSequences);
    end;
  end;
end;

procedure Rewrite;
var I,J,P,E,First,NewStmt: SizeInt; C: TCU; B,L,A: TBytes; OldCU,Len,AddrSize,SegSize: QWord;
    Covered: Boolean;
begin
  NewInfo:=''; NewLines:=''; NewAranges:='';
  { Process line units in their physical order, preserving unclaimed tables. }
  P:=0;
  while P<Length(Lines) do begin
    First:=P; Len:=ReadN(Lines,P,4); Need(Len<$fffffff0,'DWARF64 line table'); E:=P+Len;
    Need(E<=Length(Lines),'truncated line unit'); C:=nil;
    for I:=0 to High(Units) do if Units[I].Eligible and (Units[I].LineFirst=First) then C:=Units[I];
    NewStmt:=Length(NewLines);
    if C<>nil then begin
      L:=Slice(Lines,First,C.LineHeaderEnd);
      for J:=0 to High(C.Seqs) do if C.Seqs[J].Keep then L:=L+Slice(Lines,C.Seqs[J].First,C.Seqs[J].Last);
      Put(L,0,4,Length(L)-4);
    end else L:=Slice(Lines,First,E);
    for I:=0 to High(Units) do if Units[I].Stmt=QWord(First) then Units[I].Stmt:=QWord(NewStmt) or (QWord(1) shl 63);
    NewLines:=NewLines+L; P:=E;
  end;
  for I:=0 to High(Units) do begin
    C:=Units[I]; C.NewOffset:=Length(NewInfo);
    if C.Eligible then begin
      B:=Slice(Info,C.First,C.RootEnd);
      for J:=0 to High(C.Methods) do if C.Methods[J].Keep then B:=B+Slice(Info,C.Methods[J].First,C.Methods[J].Last);
      B:=B+#0; Put(B,0,4,Length(B)-4);
    end else B:=Slice(Info,C.First,C.Last);
    if C.StmtPos>=0 then begin
      Need(C.Stmt and (QWord(1) shl 63)<>0,'stmt_list did not reference a line unit');
      C.Stmt:=C.Stmt and not (QWord(1) shl 63); Put(B,C.StmtPos-C.First,4,C.Stmt);
    end;
    NewInfo:=NewInfo+B;
  end;
  P:=0;
  while P<Length(Aranges) do begin
    First:=P; Len:=ReadN(Aranges,P,4); Need(Len<$fffffff0,'DWARF64 aranges'); E:=P+Len;
    Need(E<=Length(Aranges),'truncated aranges'); Need(ReadN(Aranges,P,2)=2,'aranges version');
    OldCU:=ReadN(Aranges,P,4); AddrSize:=ReadN(Aranges,P,1); SegSize:=ReadN(Aranges,P,1);
    C:=nil; for I:=0 to High(Units) do if QWord(Units[I].First)=OldCU then C:=Units[I];
    Need(C<>nil,'aranges references unknown CU');
    if C.Eligible then begin
      Need((AddrSize in [4,8]) and (SegSize=0),'unsupported aranges addressing');
      A:=Slice(Aranges,First,P); while Length(A) mod (2*AddrSize)<>0 do A:=A+#0;
      for I:=0 to High(C.Methods) do if C.Methods[I].Keep and (C.Methods[I].Hi>C.Methods[I].Lo) then begin
        AddN(A,C.Methods[I].Lo,AddrSize); AddN(A,C.Methods[I].Hi-C.Methods[I].Lo,AddrSize);
      end;
      for I:=0 to High(C.Seqs) do if C.Seqs[I].Keep and (C.Seqs[I].Hi>C.Seqs[I].Lo) then begin
        Covered:=False;
        for J:=0 to High(C.Methods) do
          if C.Methods[J].Keep and (C.Methods[J].Lo<=C.Seqs[I].Lo) and (C.Methods[J].Hi>=C.Seqs[I].Hi) then Covered:=True;
        if not Covered then begin
          AddN(A,C.Seqs[I].Lo,AddrSize); AddN(A,C.Seqs[I].Hi-C.Seqs[I].Lo,AddrSize);
        end;
      end;
      AddN(A,0,AddrSize); AddN(A,0,AddrSize); Put(A,0,4,Length(A)-4);
    end else A:=Slice(Aranges,First,E);
    Put(A,6,4,C.NewOffset); NewAranges:=NewAranges+A; P:=E;
  end;
end;

function AtN(const B: TBytes; P,N: SizeInt): QWord;
begin Result:=ReadN(B,P,N) end;

function Sections(const B: TBytes; out IsPE,Compressed: Boolean): TSections;
var P,H,N,I,Names,Base,Opt,Sym,Count: SizeInt; Name: TBytes;
begin
  Result:=nil; Compressed:=False; IsPE:=Copy(B,1,2)='MZ';
  if IsPE then begin
    Base:=AtN(B,$3c,4); Need(Slice(B,Base,Base+4)='PE'#0#0,'invalid PE');
    N:=AtN(B,Base+6,2); Opt:=AtN(B,Base+20,2); H:=Base+24+Opt;
    Need(AtN(B,Base+24,2)=$20b,'only PE64 supported');
    Sym:=AtN(B,Base+12,4); Count:=AtN(B,Base+16,4); Names:=Sym+Count*18;
    SetLength(Result,N);
    for I:=0 to N-1 do begin
      P:=H+I*40; Name:=Slice(B,P,P+8); if Pos(#0,Name)>0 then SetLength(Name,Pos(#0,Name)-1);
      if (Name<>'') and (Name[1]='/') then begin
        Base:=Names+StrToInt(Copy(Name,2,Length(Name))); Name:=ZString(B,Base);
      end;
      Result[I].Name:=Name; Result[I].Header:=P; Result[I].Size:=AtN(B,P+8,4);
      Result[I].Addr:=AtN(B,P+12,4); Result[I].Offset:=AtN(B,P+20,4); Result[I].Flags:=AtN(B,P+36,4);
    end;
  end else begin
    Need((Copy(B,1,4)=#127'ELF') and (AtN(B,4,1)=2) and (AtN(B,5,1)=1),'only little endian ELF64 supported');
    H:=AtN(B,40,8); Need(AtN(B,58,2)=64,'unexpected ELF section entry size');
    N:=AtN(B,60,2); Names:=AtN(B,62,2); Need((N>0) and (Names<N),'extended ELF numbering unsupported');
    Names:=AtN(B,H+Names*64+24,8); SetLength(Result,N);
    for I:=0 to N-1 do begin
      P:=H+I*64; Base:=Names+AtN(B,P,4); Result[I].Name:=ZString(B,Base);
      Result[I].Header:=P; Result[I].Offset:=AtN(B,P+24,8); Result[I].Size:=AtN(B,P+32,8);
      Result[I].Addr:=AtN(B,P+16,8); Result[I].Flags:=AtN(B,P+8,8);
      if Result[I].Flags and $800<>0 then Compressed:=True;
      Need(Pos('.zdebug_',Result[I].Name)<>1,'legacy GNU compression unsupported');
    end;
  end;
end;

procedure Execute(const Tool,Directory: string; const Args: array of string);
var P: TProcess; I: Integer;
begin
  P:=TProcess.Create(nil);
  try
    P.Executable:=Tool; P.CurrentDirectory:=Directory; P.Options:=[poWaitOnExit];
    for I:=0 to High(Args) do P.Parameters.Add(Args[I]);
    P.Execute; Need(P.ExitStatus=0,'objcopy failed');
  finally P.Free end;
end;

procedure FixPE(var B: TBytes; const S, OriginalSections: TSections);
var I,J,P,PE,Align: SizeInt; NextRVA: QWord; Started: Boolean;
begin
  PE:=AtN(B,$3c,4); Align:=AtN(B,PE+24+32,4); Need(Align>0,'zero PE alignment');
  Started:=False; NextRVA:=0;
  for I:=0 to High(S) do begin
    { BFD adds COFF object alignment bits to PE image characteristics. Preserve
      the original image flags, including runtime protection/discardability. }
    for J:=0 to High(OriginalSections) do if S[I].Name=OriginalSections[J].Name then
      Put(B,S[I].Header+36,4,OriginalSections[J].Flags);
    if Pos('.debug_',S[I].Name)=1 then begin
      P:=S[I].Header;
      if not Started then begin NextRVA:=S[I].Addr; Started:=True end;
      if S[I].Name='.debug_info' then Put(B,P+8,4,Length(NewInfo))
      else if S[I].Name='.debug_line' then Put(B,P+8,4,Length(NewLines))
      else if S[I].Name='.debug_aranges' then Put(B,P+8,4,Length(NewAranges));
      Put(B,P+12,4,NextRVA); NextRVA:=((NextRVA+AtN(B,P+8,4)+Align-1) div Align)*Align;
    end else Need(not Started,'PE non-debug section after debug tail');
  end;
  if Started then Put(B,PE+24+56,4,NextRVA);
  Put(B,PE+24+64,4,0); { Checksum is optional for a user-mode PE. }
end;

procedure TransformFile(const InputName,OutputName,Objcopy: string);
const Required: array[0..3] of string=('debug_info','debug_abbrev','debug_line','debug_aranges');
var Original,Final: TBytes; Before,After: TSections; IsPE,Compressed,Dummy,OtherPE: Boolean;
    I,J: SizeInt; Dir,Image: string; Found,DirCreated: Boolean;
    {$ifdef unix} Mode: Stat; {$endif}
begin
  Need(ExpandFileName(InputName)<>ExpandFileName(OutputName),'input and output must differ');
  Need(not FileExists(OutputName),'output already exists'); Original:=Load(InputName);
  Dir:=ExtractFilePath(ExpandFileName(OutputName))+'.mccompact-'+IntToStr(GetProcessID); DirCreated:=False;
  Save(OutputName,Original);
  {$ifdef unix}
  Need(fpStat(InputName,Mode)=0,'cannot read input permissions');
  Need(fpChmod(OutputName,Mode.st_mode)=0,'cannot preserve input permissions');
  {$endif}
  try
    Before:=Sections(Original,IsPE,Compressed);
    for I:=0 to High(Before) do begin
      Need((Before[I].Name<>'.debug_pubnames') and (Before[I].Name<>'.debug_pubtypes') and
        (Before[I].Name<>'.debug_names') and (Before[I].Name<>'.gdb_index') and
        (Before[I].Name<>'.debug_types') and (Before[I].Name<>'.debug_macro') and
        (Before[I].Name<>'.debug_macinfo'),'cross-section DWARF references: preserve original');
    end;
    Need(CreateDir(Dir),'cannot create temporary directory'); DirCreated:=True; Dir:=IncludeTrailingPathDelimiter(Dir);
    { External binutils need only short ASCII paths, even for Unicode output. }
    Image:=Dir+'image.bin'; Need(RenameFile(OutputName,Image),'cannot stage executable');
    if Compressed then Execute(Objcopy,Dir,['--decompress-debug-sections','image.bin']);
    for I:=0 to High(Required) do begin
      Found:=False; for J:=0 to High(Before) do if Before[J].Name='.'+Required[I] then Found:=True;
      Need(Found,'required DWARF section missing');
      Execute(Objcopy,Dir,['--dump-section','.'+Required[I]+'='+Required[I],'image.bin']);
    end;
    Info:=Load(Dir+'debug_info'); Abbrev:=Load(Dir+'debug_abbrev'); Lines:=Load(Dir+'debug_line'); Aranges:=Load(Dir+'debug_aranges');
    ParseInfo; SelectRecords; Rewrite;
    Need((RemovedMethods<>0) or (RemovedSequences<>0),'no removable compact records');
    Save(Dir+'debug_info.new',NewInfo); Save(Dir+'debug_line.new',NewLines); Save(Dir+'debug_aranges.new',NewAranges);
    Execute(Objcopy,Dir,['--update-section','.debug_info=debug_info.new',
      '--update-section','.debug_line=debug_line.new',
      '--update-section','.debug_aranges=debug_aranges.new','image.bin']);
    Final:=Load(Image); After:=Sections(Final,OtherPE,Dummy);
    if IsPE then begin FixPE(Final,After,Before); Save(Image,Final) end;
    if Compressed then Execute(Objcopy,Dir,['--compress-debug-sections=zlib','image.bin']);
    Final:=Load(Image); After:=Sections(Final,OtherPE,Dummy);
    for I:=0 to High(Before) do begin
      if IsPE then Found:=Pos('.debug_',Before[I].Name)<>1
      else Found:=Before[I].Flags and 2<>0;
      if not Found then Continue;
      Found:=False;
      for J:=0 to High(After) do if Before[I].Name=After[J].Name then begin
        Need((Before[I].Addr=After[J].Addr) and (Before[I].Size=After[J].Size) and
          (Before[I].Flags=After[J].Flags),'runtime section layout changed');
        { NOBITS/.bss has no file content. }
        if (Before[I].Offset<>0) and
           (IsPE and (Before[I].Flags and $80=0) or not IsPE and (AtN(Original,Before[I].Header+4,4)<>8)) then
          Need(Slice(Original,Before[I].Offset,Before[I].Offset+Before[I].Size)=
            Slice(Final,After[J].Offset,After[J].Offset+After[J].Size),'runtime section bytes changed');
        Found:=True; Break;
      end;
      Need(Found,'runtime section disappeared');
    end;
    Need(RenameFile(Image,OutputName),'cannot install compact output');
    WriteLn('COMPACT methods=',RemovedMethods,' sequences=',RemovedSequences,' bytes=',Length(Original)-Length(Final));
  except
    on E: Exception do begin
      Save(OutputName,Original);
      {$ifdef unix}
      Need(fpChmod(OutputName,Mode.st_mode)=0,'cannot preserve input permissions');
      {$endif}
      WriteLn('UNCHANGED: ',E.Message);
    end;
  end;
  { Every path is inside our newly created temporary directory. }
  if DirCreated then begin
    DeleteFile(Dir+'image.bin');
    for I:=0 to High(Required) do DeleteFile(Dir+Required[I]);
    DeleteFile(Dir+'debug_info.new'); DeleteFile(Dir+'debug_line.new'); DeleteFile(Dir+'debug_aranges.new');
    RemoveDir(ExcludeTrailingPathDelimiter(Dir));
  end;
end;

var Dir: string; I: SizeInt; Owner,NextOwner: TMethodOwner;
begin
  if (ParamCount=1) and (ParamStr(1)='--version') then begin
    WriteLn('MoonCompiler compact DWARF helper 1'); Halt(0);
  end;
  Maps:=TStringList.Create; Maps.Sorted:=True; Maps.CaseSensitive:=True;
  Seen:=TBinaryStrings.Create; Seen.Sorted:=True; Seen.CaseSensitive:=True;
  try
    if ParamCount=3 then begin TransformFile(ParamStr(1),ParamStr(2),ParamStr(3)); Halt(0) end;
    Need(ParamCount=1,'usage: mccompact sections-directory'); Dir:=IncludeTrailingPathDelimiter(ParamStr(1));
    Info:=Load(Dir+'debug_info'); Abbrev:=Load(Dir+'debug_abbrev'); Lines:=Load(Dir+'debug_line'); Aranges:=Load(Dir+'debug_aranges');
    ParseInfo; SelectRecords; Rewrite;
    Save(Dir+'debug_info.new',NewInfo); Save(Dir+'debug_line.new',NewLines); Save(Dir+'debug_aranges.new',NewAranges);
    WriteLn('{"methods_removed":',RemovedMethods,',"sequences_removed":',RemovedSequences,
      ',"info_before":',Length(Info),',"info_after":',Length(NewInfo),
      ',"line_before":',Length(Lines),',"line_after":',Length(NewLines),
      ',"aranges_before":',Length(Aranges),',"aranges_after":',Length(NewAranges),'}');
  except
    on E: Exception do begin WriteLn(StdErr,'UNCHANGED: ',E.Message); Halt(2) end;
  end;
  for I:=0 to High(Units) do Units[I].Free;
  for I:=0 to Seen.Count-1 do begin
    Owner:=TMethodOwner(Seen.Objects[I]);
    while Owner<>nil do begin NextOwner:=Owner.Next; Owner.Free; Owner:=NextOwner end;
  end;
  FreeMaps; Maps.Free; Seen.Free;
end.
