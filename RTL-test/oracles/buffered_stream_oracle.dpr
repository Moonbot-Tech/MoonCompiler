program buffered_stream_oracle;

{ TBufferedFileStream differential oracle: one deterministic sequence of
  Read/Write/Seek/Size/FlushBuffer calls with a 64-byte buffer, every result
  printed, the file's content hashed at checkpoints and at the end.  Compiled
  by Delphi 12.2 and by MoonCompiler; both must print the same lines, which
  is also what a plain TFileStream prints (the third column). }

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}
{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

uses
  SysUtils, Classes;

var
  Seed: Cardinal = 12345;

function Rnd(N: Cardinal): Cardinal;
begin
  Seed := Seed * 1103515245 + 12345;
  Result := (Seed shr 8) mod N;
end;

function Digest(const Bytes: TBytes): string;
var
  H: Cardinal;
  I: Integer;
begin
  H := 2166136261;
  for I := 0 to High(Bytes) do
    H := (H xor Bytes[I]) * 16777619;
  Result := IntToHex(H, 8);
end;

function FileDigest(const Name: string): string;
var
  F: TFileStream;
  B: TBytes;
begin
  F := TFileStream.Create(Name, fmOpenRead or fmShareDenyNone);
  try
    SetLength(B, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(B[0], F.Size);
  finally
    F.Free;
  end;
  Result := IntToStr(Length(B)) + ':' + Digest(B);
end;

procedure Drive(const Name: string; S: TStream; const Tag: string);
var
  I, N, R: Integer;
  Buf: TBytes;
  Pos: Int64;
begin
  SetLength(Buf, 300);
  Seed := 777;
  for I := 1 to 400 do
  begin
    case Rnd(9) of
      0, 1:
        begin
          N := 1 + Rnd(200);
          for R := 0 to N - 1 do
            Buf[R] := Byte(I + R);
          R := S.Write(Buf[0], N);
          WriteLn(Tag, ' ', I, ' write ', N, ' -> ', R, ' pos ', S.Position, ' size ', S.Size);
        end;
      2, 3:
        begin
          N := 1 + Rnd(200);
          FillChar(Buf[0], N, 0);
          R := S.Read(Buf[0], N);
          SetLength(Buf, R);
          WriteLn(Tag, ' ', I, ' read ', N, ' -> ', R, ' ', Digest(Buf), ' pos ', S.Position, ' size ', S.Size);
          SetLength(Buf, 300);
        end;
      4:
        begin
          Pos := S.Seek(Int64(Rnd(700)) - 50, soBeginning);
          WriteLn(Tag, ' ', I, ' seek-begin -> ', Pos, ' pos ', S.Position);
        end;
      5:
        begin
          Pos := S.Seek(Int64(Rnd(120)) - 60, soCurrent);
          WriteLn(Tag, ' ', I, ' seek-cur -> ', Pos, ' pos ', S.Position);
        end;
      6:
        begin
          Pos := S.Seek(-Int64(Rnd(100)), soEnd);
          WriteLn(Tag, ' ', I, ' seek-end -> ', Pos, ' pos ', S.Position);
        end;
      7:
        begin
          N := Rnd(600);
          S.Size := N;
          WriteLn(Tag, ' ', I, ' size:=', N, ' pos ', S.Position, ' size ', S.Size);
        end;
      8:
        begin
          if S is TBufferedFileStream then
            TBufferedFileStream(S).FlushBuffer;
          WriteLn(Tag, ' ', I, ' flush file ', FileDigest(Name), ' pos ', S.Position, ' size ', S.Size);
        end;
    end;
  end;
end;

var
  Name: string;
  S: TStream;
begin
  Name := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'buffered-oracle-' + ParamStr(1) + '.bin';
  S := TBufferedFileStream.Create(Name, fmCreate or fmShareDenyNone, 64);
  try
    Drive(Name, S, 'B');
  finally
    S.Free;
  end;
  WriteLn('B final ', FileDigest(Name));
  S := TFileStream.Create(Name, fmCreate or fmShareDenyNone);
  try
    Drive(Name, S, 'F');
  finally
    S.Free;
  end;
  WriteLn('F final ', FileDigest(Name));
  DeleteFile(Name);
  { a buffered stream over an existing file, opened read/write, reads what
    the file has and writes over it }
  S := TFileStream.Create(Name, fmCreate);
  try
    SetLength(Name, Length(Name));
    S.WriteBuffer(PAnsiChar('0123456789abcdefghijklmnopqrstuvwxyz')^, 36);
  finally
    S.Free;
  end;
  S := TBufferedFileStream.Create(Name, fmOpenReadWrite or fmShareDenyNone, 8);
  try
    Seed := 99;
    Drive(Name, S, 'R');
  finally
    S.Free;
  end;
  WriteLn('R final ', FileDigest(Name));
  DeleteFile(Name);
  WriteLn('BUFFERED_ORACLE_END');
end.
