program RtlSystemCpuTimes;

uses System.SysUtils, System.Classes;

function ReadNative: TThread.TSystemTimes;
var
  F: TextFile;
  Line: string;
begin
  AssignFile(F, '/proc/stat');
  Reset(F);
  try
    Readln(F, Line);
  finally
    CloseFile(F);
  end;
  Writeln(Line);
  var Fields := Line.Split([' '], TStringSplitOptions.ExcludeEmpty);
  Result := Default(TThread.TSystemTimes);
  Result.UserTime := StrToUInt64(Fields[1]);
  Result.NiceTime := StrToUInt64(Fields[2]);
  Result.IdleTime := StrToUInt64(Fields[4]) + StrToUInt64(Fields[5]);
  Result.KernelTime := StrToUInt64(Fields[3]) + Result.IdleTime +
    StrToUInt64(Fields[6]) + StrToUInt64(Fields[7]) + StrToUInt64(Fields[8]);
end;

begin
  var Before := ReadNative;
  var Actual: TThread.TSystemTimes;
  If not TThread.GetSystemTimes(Actual) then Halt(2);
  var After := ReadNative;
  Writeln('SDK user=', Actual.UserTime, ' nice=', Actual.NiceTime,
    ' kernel=', Actual.KernelTime, ' idle=', Actual.IdleTime);
  Writeln('Native inclusive kernel=', Before.KernelTime, '..', After.KernelTime,
    ' idle=', Before.IdleTime, '..', After.IdleTime);
  If (Actual.KernelTime < Before.KernelTime) or (Actual.KernelTime > After.KernelTime) or
     (Actual.IdleTime < Before.IdleTime) or (Actual.IdleTime > After.IdleTime) then begin
    Writeln('SYSTEM_CPU_INCOMPLETE');
    Halt(1);
  end;
  Writeln('SYSTEM_CPU_PASS');
end.
