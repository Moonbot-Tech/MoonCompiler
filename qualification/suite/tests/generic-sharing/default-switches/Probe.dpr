program Probe;
{$APPTYPE CONSOLE}
uses System.SysUtils,A,B;
var RA,RB,OA,OB:Boolean;
begin RA:=False;RB:=False;OA:=False;OB:=False;
 try A.RangeRead(1);except on E:ERangeError do RA:=True;end;
 try B.RangeRead(1);except on E:ERangeError do RB:=True;end;
 try A.AddRead(High(Integer));except on E:EIntOverflow do OA:=True;end;
 try B.AddRead(High(Integer));except on E:EIntOverflow do OB:=True;end;
 Writeln('RANGE=',RA,'/',RB);Writeln('OVERFLOW=',OA,'/',OB);
end.
