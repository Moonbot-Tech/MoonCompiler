program Probe;
{$APPTYPE CONSOLE}
uses {$IFDEF UNIX} cthreads, ffi.manager, {$ENDIF} System.SysUtils,A,B;
var RA,RB:Boolean; X:Integer;
begin
 {$IFNDEF FPC}Writeln('FUNC_ID=',A.GetFunc=B.GetFunc);{$ENDIF}
 Writeln('FUNC_VALUES=',A.CallFunc,'/',B.CallFunc);
 Writeln('ARRAY_ID=',A.GetArray=B.GetArray);
 Writeln('HELPERS=',A.HelperValue,'/',B.HelperValue);
 Writeln('LAYOUT=',A.LayoutSize,'/',B.LayoutSize);
 X:=1;RA:=False;RB:=False;
 try A.RangeValue(X); except on E:ERangeError do RA:=True; end;
 try B.RangeValue(X); except on E:ERangeError do RB:=True; end;
 Writeln('RANGE=',RA,'/',RB);
 X:=High(Integer);RA:=False;RB:=False;
 try A.OverflowValue(X); except on E:EIntOverflow do RA:=True; end;
 try B.OverflowValue(X); except on E:EIntOverflow do RB:=True; end;
 Writeln('OVERFLOW=',RA,'/',RB);
end.
