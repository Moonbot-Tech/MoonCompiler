program pstring_unicode_abi_semantic;

{$mode delphi}{$H+}

uses
  SysUtils;

procedure Check(Condition: Boolean; Code: Integer);
begin
  if not Condition then
    Halt(Code);
end;

var
  Parsed: string;
  Number: LongInt;
  Value: Extended;
  Text: string;
  TextPointer: PString;

begin
  Check(SizeOf(Char)=2,1);
  Text:='Moon '+#$0416;
  TextPointer:=NewStr(Text);
  Check(TextPointer<>nil,2);
  Check(TextPointer^=Text,3);
  AssignStr(TextPointer,'Compiler '+#$03C0);
  Check(TextPointer^='Compiler '+#$03C0,4);
  DisposeStr(TextPointer);

  Parsed:='unchanged';
  Number:=0;
  Value:=0;
  Check(SSCanF('token 1'+DecimalSeparator+'25 42','%s %f %d',
    [@Parsed,@Value,@Number])=3,5);
  Check(Parsed='token',6);
  Check(Abs(Value-1.25)<1E-12,7);
  Check(Number=42,8);
  WriteLn('PSTRING_UNICODE_ABI_PASS');
end.
