{ Inlining a function that uses `absolute` to alias its Result (or a
  parameter) to a differently-laid-out type must not turn field writes
  into register subset-insert ops against an uninitialized register.
  Previously the non-inlined path was correct but the inlined path
  dropped all fields except the first. }

{$mode delphi}

type
  TFoobar = packed record
    A, B, C: uint16;
  end;

  TA = packed record
    Foobar: TFoobar;
    R: uint16;
  end;

  TB = packed record
    R: uint16;
    Foobar: TFoobar;
  end;

function Convert_Normal(const P: Pointer): Pointer;
var
  LA: TA absolute P;
  LB: TB absolute Result;
begin
  LB.R := LA.R;
  LB.Foobar.A := LA.Foobar.A;
  LB.Foobar.B := LA.Foobar.B;
  LB.Foobar.C := LA.Foobar.C;
end;

function Convert_Inlined(const P: Pointer): Pointer; inline;
var
  LA: TA absolute P;
  LB: TB absolute Result;
begin
  LB.R := LA.R;
  LB.Foobar.A := LA.Foobar.A;
  LB.Foobar.B := LA.Foobar.B;
  LB.Foobar.C := LA.Foobar.C;
end;

var
  P, RNormal, RInlined: Pointer;
  error_count: byte;
begin
  error_count:=0;
  P := Pointer(PtrUInt($1122334455667788));
  writeln('P=0x',hexstr(PtrUInt(P),2*sizeof(P)));
  RNormal := Convert_Normal(P);
  RInlined := Convert_Inlined(P);
  if RNormal <> RInlined then
    begin
      writeln('Error: inlined function generates a different output');
      inc(error_count);
    end;
  { Expected byte rotation: [R, A, B, C] = [P[6..7], P[0..1], P[2..3], P[4..5]] }
  if PtrUInt(RInlined) <> PtrUInt($3344556677881122) then
    begin
      writeln('PtrUInt(RInlined)=0x',hexstr(PtrUInt(RInlined),2*sizeof(RInlined)));
      writeln('Expecting         0x',hexstr(PtrUInt($3344556677881122),2*sizeof(RInlined)));
      writeln('Error: inlined function generates a wrong output');
      inc(error_count);
    end;
  if PtrUInt(RNormal) <> PtrUInt($3344556677881122) then
    begin
      writeln('PtrUInt(RNormal)=0x',hexstr(PtrUInt(RNormal),2*sizeof(RNormal)));
      writeln('Expecting        0x',hexstr(PtrUInt($3344556677881122),2*sizeof(RNormal)));
      writeln('Error: normal function generates a wrong output');
      inc(error_count);
    end;
  if error_count>0 then
    halt(error_count);
end.
