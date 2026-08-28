{ %FAIL }
{ %CPU=x86_64 }

program tdelphimanagedoveralign1;

{$mode delphi}

type
  TAligned32 = record
    Data: array[0..31] of Byte;
    class operator Initialize(out Dest: TAligned32);
    class operator Finalize(var Dest: TAligned32);
    class operator Assign(var Dest: TAligned32; const [ref] Src: TAligned32);
  end align 32;

  TAligned64 = record
    Data: array[0..63] of Byte;
    class operator Initialize(out Dest: TAligned64);
    class operator Finalize(var Dest: TAligned64);
    class operator Assign(var Dest: TAligned64; const [ref] Src: TAligned64);
  end align 64;

class operator TAligned32.Initialize(out Dest: TAligned32);
begin
end;

class operator TAligned32.Finalize(var Dest: TAligned32);
begin
end;

class operator TAligned32.Assign(var Dest: TAligned32; const [ref] Src: TAligned32);
begin
  Dest.Data := Src.Data;
end;

class operator TAligned64.Initialize(out Dest: TAligned64);
begin
end;

class operator TAligned64.Finalize(var Dest: TAligned64);
begin
end;

class operator TAligned64.Assign(var Dest: TAligned64; const [ref] Src: TAligned64);
begin
  Dest.Data := Src.Data;
end;

procedure RealCall(A, B: TAligned32);
begin
end;

procedure InlineCall(A, B: TAligned32); inline;
begin
end;

procedure RealCall64(A, B: TAligned64);
begin
end;

procedure InlineCall64(A, B: TAligned64); inline;
begin
end;

var
  A, B: TAligned32;
  C, D: TAligned64;
begin
  { A stack carrier with only the platform's 16-byte guarantee may not be
    accepted for 32-byte managed values: compile failure is safer than calling
    user operators on an invalid address. }
  RealCall(A,B);
  InlineCall(A,B);
  RealCall64(C,D);
  InlineCall64(C,D);
end.
