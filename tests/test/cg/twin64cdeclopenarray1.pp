{ %CPU=x86_64 }
program twin64cdeclopenarray1;

{$mode unleashed}
{$R+}

{$ifdef WIN64}
{$asmmode intel}

function RawOpenArrayHigh: NativeInt; cdecl; assembler; nostackframe; public name 'RawOpenArrayHigh';
asm
  MOV RAX,RDX
end;

function RawArrayConstHigh: NativeInt; cdecl; assembler; nostackframe; public name 'RawArrayConstHigh';
asm
  MOV RAX,RDX
end;

function ExternalOpenArrayHigh(const Values: array of Integer): NativeInt; cdecl;
  external name 'RawOpenArrayHigh';
function ExternalArrayConstHigh(const Values: array of const): NativeInt; cdecl;
  external name 'RawArrayConstHigh';

function LocalOpenArrayLast(const Values: array of Integer): Integer; cdecl;
begin
  Result:=Values[High(Values)];
end;

function LocalValueOpenArray(Values: array of Integer): NativeInt; cdecl;
begin
  Result:=High(Values);
  if Result>=0 then
    Values[0]:=99;
end;

function LocalManagedValueOpenArray(Values: array of UnicodeString): NativeInt; cdecl;
begin
  Result:=High(Values);
  if Result>=0 then
    Values[0]:='changed';
end;

function LocalOpenStringHigh(const Value: OpenString): NativeInt; cdecl;
begin
  Result:=High(Value);
end;

var
  Integers: array[0..2] of Integer;
  Strings: array[0..1] of UnicodeString;

begin
  Integers[0]:=11;
  Integers[1]:=22;
  Integers[2]:=33;
  Strings[0]:='first';
  Strings[1]:='second';

  if ExternalOpenArrayHigh([])<>-1 then
    Halt(1);
  if ExternalOpenArrayHigh([11])<>0 then
    Halt(2);
  if ExternalOpenArrayHigh(Integers)<>2 then
    Halt(3);

  if ExternalArrayConstHigh([])<>-1 then
    Halt(4);
  if ExternalArrayConstHigh([11])<>0 then
    Halt(5);
  if ExternalArrayConstHigh([11,'x',3.5])<>2 then
    Halt(6);

  if LocalOpenArrayLast(Integers)<>33 then
    Halt(7);
  if LocalValueOpenArray(Integers)<>2 then
    Halt(8);
  if Integers[0]<>11 then
    Halt(9);

  if LocalManagedValueOpenArray(Strings)<>1 then
    Halt(10);
  if Strings[0]<>'first' then
    Halt(11);

  { Delphi cdecl OpenString is the C-compatible one-pointer form. }
  if LocalOpenStringHigh('abc')<>255 then
    Halt(12);
end.
{$else WIN64}
begin
end.
{$endif WIN64}
