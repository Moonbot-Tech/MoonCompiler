{%MainUnit sysutils.pp}
{ Single scan, allocation-free until the first match, and the substring
  search runs inline: an SRINDEXCHAR (SIMD) sweep for the last pattern
  character plus one prefix compare per candidate.  The former engine
  paid a Pos->IndexChar->CompareChar call chain per probe and walked the
  subject twice for length-changing replacements. }
var
  OldPat,Srch: SRstring; // Srch and OldPat can hold uppercased copies of S,OldPattern
  PatLength,NewPatLength,P,Cnt,PrevP,OutLen,SL,MaxStart,SBase: Integer;
  D: SizeInt;
  LastPat: SRChar;

begin
  aCount:=0;
  PatLength:=Length(OldPattern);
  if PatLength=0 then begin
    Result:=S;
    exit;
  end;

  if rfIgnoreCase in Flags then begin
    Srch:=SRUpperCase(S);
    OldPat:=SRUpperCase(OldPattern);
  end else begin
    Srch:=S;
    OldPat:=OldPattern;
  end;

  SL:=Length(Srch);
  NewPatLength:=Length(NewPattern);
  LastPat:=SRPChar(Pointer(OldPat))[PatLength-1];
  MaxStart:=SL-PatLength+1;
  Result:='';
  OutLen:=0;
  PrevP:=1;
  repeat
    { find OldPat in Srch at or after PrevP }
    P:=0;
    SBase:=PrevP;
    while SBase<=MaxStart do begin
      D:=SRINDEXCHAR(SRPChar(Pointer(Srch))[SBase+PatLength-2],MaxStart-SBase+1,Ord(LastPat));
      if D<0 then
        break;
      if (PatLength=1) or
         (SRCOMPARECHAR(SRPChar(Pointer(OldPat))^,SRPChar(Pointer(Srch))[SBase+D-1],PatLength-1)=0) then begin
        P:=SBase+Integer(D);
        break;
      end;
      SBase:=SBase+Integer(D)+1;
    end;

    if P=0 then begin
      if aCount=0 then begin
        { no match: hand back the original without touching the heap }
        Result:=S;
        exit;
      end;
      Cnt:=Length(S)-PrevP+1;
      if OutLen+Cnt>Length(Result) then
        SetLength(Result,OutLen+Cnt);
      if Cnt>0 then begin
        Move(SRPChar(Pointer(S))[PrevP-1],SRPChar(Pointer(Result))[OutLen],Cnt*SizeOf(SRChar));
        inc(OutLen,Cnt);
      end;
      break;
    end;

    inc(aCount);
    if aCount=1 then begin
      { first match: size the output once - subject length for shrinking
        replacements, four replacements of headroom for growing ones }
      if NewPatLength>PatLength then
        SetLength(Result,Length(S)+(NewPatLength-PatLength)*4)
      else
        SetLength(Result,Length(S));
    end;
    Cnt:=P-PrevP;
    if OutLen+Cnt+NewPatLength>Length(Result) then
      SetLength(Result,(OutLen+Cnt+NewPatLength)*2);
    if Cnt>0 then begin
      Move(SRPChar(Pointer(S))[PrevP-1],SRPChar(Pointer(Result))[OutLen],Cnt*SizeOf(SRChar));
      inc(OutLen,Cnt);
    end;
    if NewPatLength>0 then begin
      Move(SRPChar(Pointer(NewPattern))^,SRPChar(Pointer(Result))[OutLen],NewPatLength*SizeOf(SRChar));
      inc(OutLen,NewPatLength);
    end;
    PrevP:=P+PatLength;
    if not (rfReplaceAll in Flags) then begin
      Cnt:=Length(S)-PrevP+1;
      if OutLen+Cnt>Length(Result) then
        SetLength(Result,OutLen+Cnt);
      if Cnt>0 then begin
        Move(SRPChar(Pointer(S))[PrevP-1],SRPChar(Pointer(Result))[OutLen],Cnt*SizeOf(SRChar));
        inc(OutLen,Cnt);
      end;
      break;
    end;
  until False;
  SetLength(Result,OutLen);
end;
