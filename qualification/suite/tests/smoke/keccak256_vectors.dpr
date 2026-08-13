program keccak256_vectors;

{$IFDEF FPC}
{$mode delphi}
{$ENDIF}

uses
{$IFDEF FPC}
  mormot.core.fpcx64mm,
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF UNIX}
{$ENDIF}
  SysUtils,
  mormot.core.base,
  mormot.core.text,
  mormot.crypt.core;

procedure Check(const Actual, Expected, Name: RawUtf8);
begin
  If Actual <> Expected then begin
    WriteLn('FAIL ', Name, ' expected=', Expected, ' actual=', Actual);
    Halt(1);
  end;
end;

function DigestHex(const Digest: THash256): RawUtf8;
begin
  Result := BinToHexLower(@Digest, SizeOf(Digest));
end;

var
  Data: array[0..255] of Byte;
  Digest: THash256;
  Hasher: TSha3;
  I: Integer;
begin
  Check(Keccak256(''),
    'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470',
    'empty');
  Check(Keccak256('abc'),
    '4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45',
    'abc');
  Check(Keccak256('hello'),
    '1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8',
    'hello');

  for I := Low(Data) to High(Data) do
    Data[I] := I;
  Keccak256Full(@Data[0], Length(Data), Digest);
  Check(DigestHex(Digest),
    'dc924469b334aed2a19fac7252e9961aea41f8d91996366029dbe0884229bf36',
    'bytes-0-255');

  Hasher.Init(KECCAK_256);
  Hasher.Update(@Data[0], 17);
  Hasher.Update(@Data[17], 101);
  Hasher.Update(@Data[118], Length(Data) - 118);
  Hasher.Final(Digest);
  Check(DigestHex(Digest),
    'dc924469b334aed2a19fac7252e9961aea41f8d91996366029dbe0884229bf36',
    'segmented-update');
  WriteLn('KECCAK256_VECTORS_OK');
end.
