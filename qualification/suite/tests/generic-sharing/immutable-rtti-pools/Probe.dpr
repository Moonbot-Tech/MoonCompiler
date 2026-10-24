program Probe;
uses {$if defined(LINUX) and defined(CPUX86_64)}cthreads,ffi.manager,{$endif}
 System.SysUtils,System.TypInfo,System.Rtti,A,B;
procedure Check(C:Boolean;const Why:string);begin if not C then raise Exception.Create(Why);end;
var X,Y:PVmtMethodExEntry; I:Integer; C:TRttiContext; O1:A.TProbe; O2:B.TProbe;
begin
 X:=A.Method(0);Y:=B.Method(0);
 Check(A.TProbe.ClassInfo<>B.TProbe.ClassInfo,'distinct TypeInfo');
 Check(TClass(A.TProbe)<>TClass(B.TProbe),'distinct VMT');
 {$ifdef POOL_STRIPPED}
 Check((X^.Name='') and (Y^.Name=''),'empty stripped names');
 {$else}
 Check((X^.Name='Shared') and (Y^.Name='Shared'),'shared name bytes');
 Check(A.Method(1)^.Name='MixedCase','case A');
 Check(B.Method(1)^.Name='mixedcase','case B');
 Check(A.Method(1)^.NamePtr<>B.Method(1)^.NamePtr,'case identity');
 Check((Length(A.Method(2)^.Name)=127) and (A.Method(2)^.Name[127]='A'),'long name A');
 Check((Length(B.Method(2)^.Name)=127) and (B.Method(2)^.Name[127]='B'),'long name B');
 Check(A.Method(2)^.NamePtr<>B.Method(2)^.NamePtr,'long exact identity');
 {$endif}
 {$ifdef POOL_ALIGN_SPLIT}
 Check((PtrUInt(X^.NamePtr) mod 16=0) and (PtrUInt(Y^.NamePtr) mod 32=0),'alignment');
 Check(X^.NamePtr<>Y^.NamePtr,'separate alignment contracts');
 {$else}
 {$ifdef EXPECT_IMMUTABLE_POOL}
 Check(X^.NamePtr=Y^.NamePtr,'cross-unit name pool');
 Check(PPointer(X^.ResultLocs)^=PPointer(Y^.ResultLocs)^,'cross-unit result pool');
 for I:=0 to X^.ParamCount-1 do
  Check(X^.Param[I]^.ParaLocs=Y^.Param[I]^.ParaLocs,'cross-unit parameter pool');
 {$endif}
 {$endif}
 {$ifndef POOL_STRIPPED}
 C:=TRttiContext.Create(False);O1:=A.TProbe.Create;O2:=B.TProbe.Create;
 try
  Check(C.GetType(A.TProbe).GetMethod('Shared').Invoke(O1,[41]).AsInteger=42,'Invoke A');
  Check(C.GetType(B.TProbe).GetMethod('Shared').Invoke(O2,[41]).AsInteger=42,'Invoke B');
 finally O2.Free;O1.Free;C.Free;end;
 {$endif}
 Writeln('IMMUTABLE_RTTI_POOL_PASS');
end.
