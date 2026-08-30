program inttohex_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  {$ifdef FPC}SysUtils{$else}System.SysUtils{$endif};

procedure Check(const Actual, Expected, Name: UnicodeString);
begin
  If Actual<>Expected then begin
    WriteLn('FAIL ',Name,' actual=',Actual,' expected=',Expected);
    Halt(1);
  end;
end;

var
  Signed32: LongInt;
  Signed64: Int64;
begin
  Check(IntToHex(UInt64(0),0),'0','zero width zero');
  Check(IntToHex(UInt64(0),-7),'0','negative width');
  Check(IntToHex(UInt64(1),1),'1','one');
  Check(IntToHex(UInt64($F),1),'F','one nibble');
  Check(IntToHex(UInt64($10),1),'10','two nibbles');
  Check(IntToHex(UInt64($FF),2),'FF','one byte');
  Check(IntToHex(UInt64($100),2),'100','width does not truncate');
  Check(IntToHex(UInt64($123456789ABCDEF0),16),'123456789ABCDEF0',
    'all nibbles');
  Check(IntToHex(UInt64($8000000000000000),1),'8000000000000000',
    'high bit');
  Check(IntToHex(High(UInt64),16),'FFFFFFFFFFFFFFFF','max qword');
  Check(IntToHex(UInt64($ABCD),20),'0000000000000000ABCD','padding');
  Check(IntToHex(UInt64($ABCD),70),StringOfChar('0',66)+'ABCD',
    'padding beyond machine width');

  Signed32:=-1;
  Signed64:=-1;
  Check(IntToHex(Signed32,1),'FFFFFFFF','signed 32');
  Check(IntToHex(Signed64,1),'FFFFFFFFFFFFFFFF','signed 64');

  WriteLn('INTTOHEX_SEMANTIC_OK');
end.
