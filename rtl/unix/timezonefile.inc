function ResolveUnixTimezoneFile(const LocationFile, PrimaryFile, AlternativeFile: string): string;
var
  f,len: LongInt;
  s: ShortString;
  info: stat;
begin
  ResolveUnixTimezoneFile:='';
  f:=fpOpen(LocationFile,Open_RdOnly);
  if f>=0 then
    begin
      len:=fpRead(f,s[1],High(s));
      fpClose(f);
      if len>0 then
        begin
          s[0]:=Chr(len);
          len:=Pos(#10,s);
          if len<>0 then
            s[0]:=Chr(len-1);
          if Length(s)>0 then
            Exit(s);
        end;
    end;
  if fpStat(PrimaryFile,{$ifdef oldlinuxstat}baseunix.stat(info){$else}info{$endif})>=0 then
    Exit(PrimaryFile);
  if fpStat(AlternativeFile,{$ifdef oldlinuxstat}baseunix.stat(info){$else}info{$endif})>=0 then
    ResolveUnixTimezoneFile:=AlternativeFile;
end;
