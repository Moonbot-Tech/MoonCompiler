{ %CPU=x86_64 }
program twin64varargsabi1;

{$mode unleashed}

{$ifdef WIN64}
{$asmmode intel}

function RawCheckNoFixed: LongInt; cdecl; assembler; nostackframe; public name 'CheckNoFixed';
asm
  MOVQ RAX,XMM0
  CMP RCX,RAX
  JNE @@fail1
  MOV RAX,$3ff4000000000000
  CMP RCX,RAX
  JNE @@fail1

  MOVQ RAX,XMM1
  CMP RDX,RAX
  JNE @@fail2
  MOV RAX,$c004000000000000
  CMP RDX,RAX
  JNE @@fail2

  MOVQ RAX,XMM2
  CMP R8,RAX
  JNE @@fail3
  MOV RAX,$400e000000000000
  CMP R8,RAX
  JNE @@fail3

  MOVQ RAX,XMM3
  CMP R9,RAX
  JNE @@fail4
  MOV RAX,$4012000000000000
  CMP R9,RAX
  JNE @@fail4
  XOR EAX,EAX
  RET
@@fail1:
  MOV EAX,1
  RET
@@fail2:
  MOV EAX,2
  RET
@@fail3:
  MOV EAX,3
  RET
@@fail4:
  MOV EAX,4
end;

function RawCheckFloatSlots(Tag: QWord): LongInt; cdecl; assembler; nostackframe; public name 'CheckFloatSlots';
asm
  MOV RAX,$1122334455667788
  CMP RCX,RAX
  JNE @@fail1

  MOVQ RAX,XMM1
  CMP RDX,RAX
  JNE @@fail2
  MOV RAX,$3ff4000000000000
  CMP RDX,RAX
  JNE @@fail2

  MOVQ RAX,XMM2
  CMP R8,RAX
  JNE @@fail3
  MOV RAX,$c004000000000000
  CMP R8,RAX
  JNE @@fail3

  MOVQ RAX,XMM3
  CMP R9,RAX
  JNE @@fail4
  MOV RAX,$400e000000000000
  CMP R9,RAX
  JNE @@fail4

  MOV RAX,$4012000000000000
  CMP [RSP+40],RAX
  JNE @@fail5

  MOV RAX,$4015000000000000
  CMP [RSP+48],RAX
  JNE @@fail6
  XOR EAX,EAX
  RET
@@fail1:
  MOV EAX,1
  RET
@@fail2:
  MOV EAX,2
  RET
@@fail3:
  MOV EAX,3
  RET
@@fail4:
  MOV EAX,4
  RET
@@fail5:
  MOV EAX,5
  RET
@@fail6:
  MOV EAX,6
end;

function RawCheckMixedSlots(Tag: QWord): LongInt; cdecl; assembler; nostackframe; public name 'CheckMixedSlots';
asm
  MOV RAX,$1122334455667788
  CMP RCX,RAX
  JNE @@fail1

  MOVQ RAX,XMM1
  CMP RDX,RAX
  JNE @@fail2
  MOV RAX,$401a000000000000
  CMP RDX,RAX
  JNE @@fail2

  CMP R8,37
  JNE @@fail3

  MOVQ RAX,XMM3
  CMP R9,RAX
  JNE @@fail4
  MOV RAX,$401f000000000000
  CMP R9,RAX
  JNE @@fail4

  MOV RAX,$4021000000000000
  CMP [RSP+40],RAX
  JNE @@fail5
  XOR EAX,EAX
  RET
@@fail1:
  MOV EAX,1
  RET
@@fail2:
  MOV EAX,2
  RET
@@fail3:
  MOV EAX,3
  RET
@@fail4:
  MOV EAX,4
  RET
@@fail5:
  MOV EAX,5
end;

function RawCheckAfterFixedFloat(Tag: Double): LongInt; cdecl; assembler; nostackframe; public name 'CheckAfterFixedFloat';
asm
  MOVQ RAX,XMM0
  MOV R10,$4023000000000000
  CMP RAX,R10
  JNE @@fail1
  CMP RCX,RAX
  JNE @@fail1

  MOVQ RAX,XMM1
  CMP RDX,RAX
  JNE @@fail2
  MOV R10,$4025000000000000
  CMP RDX,R10
  JNE @@fail2
  XOR EAX,EAX
  RET
@@fail1:
  MOV EAX,1
  RET
@@fail2:
  MOV EAX,2
end;

function RawCheckFixedOnly(Tag: Double): LongInt; cdecl; assembler;
  nostackframe; public name 'CheckFixedOnly';
asm
  MOVQ RAX,XMM0
  CMP RCX,RAX
  JNE @@fail
  MOV R10,$4024800000000000
  CMP RAX,R10
  JNE @@fail
  XOR EAX,EAX
  RET
  @@fail:
  MOV EAX,1
end;

function RawCheckFixedPrefix(Tag: QWord; D: Double; S: Single; Tail: Double;
  StackValue: Double): LongInt; cdecl; assembler; nostackframe;
  public name 'CheckFixedPrefix';
asm
  MOV RAX,$1122334455667788
  CMP RCX,RAX
  JNE @@fail1

  MOVQ RAX,XMM1
  CMP RDX,RAX
  JNE @@fail2
  MOV R10,$4016000000000000
  CMP RAX,R10
  JNE @@fail2

  MOVD EAX,XMM2
  CMP R8D,EAX
  JNE @@fail3
  CMP EAX,$40c80000
  JNE @@fail3

  MOVQ RAX,XMM3
  CMP R9,RAX
  JNE @@fail4
  MOV R10,$401f000000000000
  CMP RAX,R10
  JNE @@fail4

  MOV RAX,$4021000000000000
  CMP [RSP+40],RAX
  JNE @@fail5
  XOR EAX,EAX
  RET
  @@fail1:
  MOV EAX,1
  RET
  @@fail2:
  MOV EAX,2
  RET
  @@fail3:
  MOV EAX,3
  RET
  @@fail4:
  MOV EAX,4
  RET
  @@fail5:
  MOV EAX,5
end;

var
  Code: LongInt;
  SingleValue: Single;
  Indirect: function(Tag: Double): LongInt; cdecl; varargs;

function CheckNoFixed: LongInt; cdecl; varargs; external name 'CheckNoFixed';
function CheckFloatSlots(Tag: QWord): LongInt; cdecl; varargs; external name 'CheckFloatSlots';
function CheckMixedSlots(Tag: QWord): LongInt; cdecl; varargs; external name 'CheckMixedSlots';
function CheckAfterFixedFloat(Tag: Double): LongInt; cdecl; varargs; external name 'CheckAfterFixedFloat';
function CheckFixedOnly(Tag: Double): LongInt; cdecl; varargs; external name 'CheckFixedOnly';
function CheckFixedPrefix(Tag: QWord; D: Double; S: Single; Tail: Double;
  StackValue: Double): LongInt; cdecl; varargs; external name 'CheckFixedPrefix';

begin
  Code:=CheckNoFixed(Double(1.25),Double(-2.5),Double(3.75),Double(4.5));
  if Code<>0 then Halt(Code);

  Code:=CheckFloatSlots($1122334455667788,Double(1.25),Double(-2.5),Double(3.75),Double(4.5),Double(5.25));
  if Code<>0 then Halt(10+Code);

  Code:=CheckMixedSlots($1122334455667788,Double(6.5),37,Double(7.75),Double(8.5));
  if Code<>0 then Halt(20+Code);

  SingleValue:=10.5;
  Code:=CheckAfterFixedFloat(Double(9.5),SingleValue);
  if Code<>0 then Halt(30+Code);

  Code:=CheckFixedOnly(Double(10.25));
  if Code<>0 then Halt(40+Code);

  Code:=CheckFixedPrefix($1122334455667788,Double(5.5),Single(6.25),
    Double(7.75),Double(8.5));
  if Code<>0 then Halt(50+Code);

  Indirect:=@CheckAfterFixedFloat;
  Code:=Indirect(Double(9.5),SingleValue);
  if Code<>0 then Halt(60+Code);
end.
{$else WIN64}
begin
end.
{$endif WIN64}
