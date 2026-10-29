program ScalarGuardPage;
{$mode delphiunicode}{$H+}{$inline off}
uses SysUtils, Math,
{$ifdef Windows} Windows {$else} BaseUnix {$endif};
type TData=record P,Q,Z:Double; Side:Integer; end;
     PData=^TData;

function Observe(const V:TData):Double;
var A,B:Double;
begin
  A:=1;
  B:=2;
  If V.Side=0 then A:=A+V.P/V.Z else B:=B+V.P/V.Z;
  Result:=A+B;
end;

var Memory:Pointer; V:PData; Saved:TFPUExceptionMask;
{$ifdef Windows} OldProtect:Cardinal; {$endif}
begin
  {$ifdef Windows}
  Memory:=VirtualAlloc(nil,8192,MEM_COMMIT or MEM_RESERVE,PAGE_READWRITE);
  If Memory=nil then Halt(2);
  If not VirtualProtect(PByte(Memory)+4096,4096,PAGE_NOACCESS,OldProtect) then Halt(3);
  {$else}
  Memory:=fpMMap(nil,8192,PROT_READ or PROT_WRITE,MAP_PRIVATE or MAP_ANONYMOUS,-1,0);
  If Memory=Pointer(-1) then Halt(2);
  If fpMProtect(PByte(Memory)+4096,4096,PROT_NONE)<>0 then Halt(3);
  {$endif}
  V:=PData(PByte(Memory)+4096-24);
  V^.P:=1;
  V^.Q:=2;
  V^.Z:=0;
  Saved:=GetExceptionMask;
  try
    SetExceptionMask(Saved-[exZeroDivide]);
    try
      Writeln(Observe(V^));
      Halt(4);
    except
      on E:EAccessViolation do Writeln('ACCESS_FIRST');
      on E:EZeroDivide do Writeln('DIVIDE_FIRST');
    end;
  finally
    SetExceptionMask(Saved);
    {$ifdef Windows} VirtualFree(Memory,0,MEM_RELEASE);
    {$else} fpMUnMap(Memory,8192); {$endif}
  end;
end.
