{%MainUnit sysutils.pp}
var
  OldPat,Srch: SRstring; // Srch and Oldp can contain uppercase versions of S,OldPattern
  PatLength,NewPatLength,P,Cnt,PrevP,OutLen: Integer;

begin
  aCount:=0;
  Result:='';
  OldPat:='';
  Srch:='';

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

  PatLength:=Length(OldPat);
  if Length(NewPattern)=PatLength then begin
    //Result length will not change
    Result:=S;
    P:=1;
    repeat
      P:=Pos(OldPat,Srch,P);
      if P>0 then begin
        inc(aCount);
        move(NewPattern[1],Result[P],PatLength*SizeOf(SRChar));
        if not (rfReplaceAll in Flags) then exit;
        inc(P,PatLength);
      end;
    until p=0;
  end else begin
    //Different pattern length -> Result length will change.
    //A single scan copies as it goes: the former count-then-copy scheme
    //walked the subject twice through Pos, which dominated short inputs.
    NewPatLength:=Length(NewPattern);
    if NewPatLength>PatLength then
      SetLength(Result,Length(S)+(NewPatLength-PatLength)*4)
    else
      SetLength(Result,Length(S));
    OutLen:=0;
    PrevP:=1;
    repeat
      P:=Pos(OldPat,Srch,PrevP);
      if P=0 then
        Cnt:=Length(S)-PrevP+1
      else
        Cnt:=P-PrevP;
      if OutLen+Cnt+NewPatLength>Length(Result) then
        SetLength(Result,(OutLen+Cnt+NewPatLength)*2);
      if Cnt>0 then begin
        Move(SRPChar(S)[PrevP-1],SRPChar(Result)[OutLen],Cnt*SizeOf(SRChar));
        inc(OutLen,Cnt);
      end;
      if P=0 then
        break;
      inc(aCount);
      if NewPatLength>0 then begin
        Move(NewPattern[1],SRPChar(Result)[OutLen],NewPatLength*SizeOf(SRChar));
        inc(OutLen,NewPatLength);
      end;
      PrevP:=P+PatLength;
      if not (rfReplaceAll in Flags) then begin
        Cnt:=Length(S)-PrevP+1;
        if OutLen+Cnt>Length(Result) then
          SetLength(Result,OutLen+Cnt);
        if Cnt>0 then begin
          Move(SRPChar(S)[PrevP-1],SRPChar(Result)[OutLen],Cnt*SizeOf(SRChar));
          inc(OutLen,Cnt);
        end;
        break;
      end;
    until False;
    if aCount=0 then begin
      Result:=S;
      exit;
    end;
    SetLength(Result,OutLen);
  end;
end;

(*
var
  Srch,OldP,RemS: SRString; // Srch and Oldp can contain uppercase versions of S,OldPattern
  P : Integer;
begin
  Srch:=S;
  OldP:=OldPattern;
  if rfIgnoreCase in Flags then
    begin
    Srch:=SRUpperCase(Srch);
    OldP:=SRUpperCase(OldP);
    end;
  RemS:=S;
  Result:='';
  while (Length(Srch)<>0) do
    begin
    P:=AnsiPos(OldP, Srch);
    if P=0 then
      begin
      Result:=Result+RemS;
      Srch:='';
      end
    else
      begin
      Result:=Result+Copy(RemS,1,P-1)+NewPattern;
      P:=P+Length(OldP);
      RemS:=Copy(RemS,P,Length(RemS)-P+1);
      if not (rfReplaceAll in Flags) then
        begin
        Result:=Result+RemS;
        Srch:='';
        end
      else
         Srch:=Copy(Srch,P,Length(Srch)-P+1);
      end;
    end;
end;
*)
