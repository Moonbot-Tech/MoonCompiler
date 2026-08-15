program copyfrom_partial_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils,
  Classes;

type
  TPartialReadStream = class(TMemoryStream)
  public
    function Read(var Buffer; Count: LongInt): LongInt; override;
  end;

function TPartialReadStream.Read(var Buffer; Count: LongInt): LongInt;
begin
  if Count > 7 then
    Count := 7;
  Result := inherited Read(Buffer, Count);
end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create('COPYFROM_PARTIAL_READ_FAIL: ' + AMessage);
end;

procedure TestCountZeroPartialReads;
var
  Source: TPartialReadStream;
  Target: TMemoryStream;
  SourceBytes, TargetBytes: TBytes;
  I: Integer;
begin
  SetLength(SourceBytes, 257);
  for I := 0 to High(SourceBytes) do
    SourceBytes[I] := Byte((I * 29 + 3) and 255);
  Source := TPartialReadStream.Create;
  Target := TMemoryStream.Create;
  try
    Source.WriteBuffer(SourceBytes[0], Length(SourceBytes));
    Source.Position := 99;
    Check(Target.CopyFrom(Source, 0) = Length(SourceBytes), 'result byte count');
    Check((Source.Position = Source.Size) and (Target.Size = Source.Size),
      'source/target positions');
    SetLength(TargetBytes, Target.Size);
    Target.Position := 0;
    Target.ReadBuffer(TargetBytes[0], Length(TargetBytes));
    Check(CompareByte(SourceBytes[0], TargetBytes[0], Length(SourceBytes)) = 0,
      'complete payload across partial reads');
  finally
    Target.Free;
    Source.Free;
  end;
end;

procedure TestExplicitCountAdjacentPath;
var
  Source: TPartialReadStream;
  Target: TMemoryStream;
  Buffer: array[0..31] of Byte;
  I: Integer;
begin
  for I := 0 to High(Buffer) do
    Buffer[I] := Byte(I + 1);
  Source := TPartialReadStream.Create;
  Target := TMemoryStream.Create;
  try
    Source.WriteBuffer(Buffer[0], SizeOf(Buffer));
    Source.Position := 3;
    Check(Target.CopyFrom(Source, 20) = 20, 'explicit count result');
    Check((Source.Position = 23) and (Target.Size = 20),
      'explicit count loops partial reads');
  finally
    Target.Free;
    Source.Free;
  end;
end;

begin
  try
    TestCountZeroPartialReads;
    TestExplicitCountAdjacentPath;
    WriteLn('COPYFROM_PARTIAL_PASS');
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
