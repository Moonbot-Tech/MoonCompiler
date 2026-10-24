program InflateProbe;
{$mode objfpc}{$H+}
uses zlibraw, SysUtils;
var F: File; P: PByte; N,I: LongInt; OK: Boolean;
begin
 N:=StrToInt(ParamStr(2));
 P:=GetMem(N+16);
 FillChar(P^,N+16,$5A);
 Assign(F,ParamStr(1)); Reset(F,1);
 OK:=InflateFile(F,FileSize(F),P,N);
 Close(F);
 for I:=N to N+15 do if P[I]<>$5A then Halt(9);
 Writeln('result=',OK);
 if OK then for I:=0 to N-1 do if P[I]<>I mod 251 then Halt(8);
 FreeMem(P);
 if OK<>(ParamStr(3)='pass') then Halt(7);
end.
