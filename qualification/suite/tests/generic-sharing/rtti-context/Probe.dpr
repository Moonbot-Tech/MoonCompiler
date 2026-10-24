program Probe;
{$APPTYPE CONSOLE}
uses {$IFDEF UNIX} cthreads, ffi.manager, {$ENDIF} System.SysUtils,System.TypInfo,System.Rtti,A,B;
var C:TRttiContext; X,Y:TRttiType;
procedure Check(const N:string; R:TRttiType);
var F:TRttiField; M:TRttiMethod;
begin
 Writeln(N,'_PROPERTY=',R.GetProperty('VisibleProperty')<>nil);
 Writeln(N,'_HIDDEN=',R.GetField('Hidden')<>nil);
 F:=R.GetField('Visible'); Writeln(N,'_VISIBLE=',F<>nil);
 Writeln(N,'_HIDDEN_METHOD=',R.GetMethod('HiddenMethod')<>nil);
 M:=R.GetMethod('VisibleMethod');Writeln(N,'_VISIBLE_METHOD=',M<>nil);
 Writeln(N,'_ATTRS=',Length(R.GetAttributes));
 if F<>nil then Writeln(N,'_FIELD_ATTRS=',Length(F.GetAttributes));
 if M<>nil then Writeln(N,'_METHOD_ATTRS=',Length(M.GetAttributes));
end;
begin
 C:=TRttiContext.Create;
 try X:=C.GetType(A.Info);Y:=C.GetType(B.Info);Check('A',X);Check('B',Y);Check('AR',C.GetType(A.RecordInfo));Check('BR',C.GetType(B.RecordInfo));Check('AI',C.GetType(A.InnerInfo));Check('BI',C.GetType(B.InnerInfo));Writeln('AL=',C.GetType(A.LocalInfo).GetField('Visible')<>nil);Writeln('BL=',C.GetType(B.LocalInfo).GetField('Visible')<>nil);finally C.Free;end;
end.
