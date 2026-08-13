program medium_owner_stress;

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  cthreads,
{$else}
  Winapi.Windows,
{$endif}
  SysUtils,
  Classes;

const
  ConsumerCount = 4;
  SizeCount = 6;
  BlockSizes: array[0..SizeCount - 1] of Integer =
    (17497, 17504, 32768, 65536, 100500, 200000);

type
  TBlock = record
    Data: Pointer;
    Size: Integer;
    Pattern: Byte;
  end;
  TBlocks = array of TBlock;

  TProducer = class(TThread)
  private
    FBlocks: ^TBlocks;
    FCycle: Integer;
  public
    ErrorCode: Integer;
    constructor Create(var ABlocks: TBlocks; ACycle: Integer);
  protected
    procedure Execute; override;
  end;

  TConsumer = class(TThread)
  private
    FBlocks: ^TBlocks;
    FIndex: Integer;
  public
    ErrorCode: Integer;
    constructor Create(var ABlocks: TBlocks; AIndex: Integer);
  protected
    procedure Execute; override;
  end;

function PatternAt(Index, Cycle: Integer): Byte; inline;
begin
  Result := Byte(Index * 37 + Cycle * 13 + 1);
end;

function BufferMatches(Data: Pointer; Size: Integer; Pattern: Byte): Boolean;
  inline;
var
  P: PByte;
begin
  P := Data;
  Result := (P <> nil) and
    (P[0] = Pattern) and
    (P[Size div 2] = Pattern) and
    (P[Size - 1] = Pattern);
end;

function ContentMatches(const Block: TBlock): Boolean; inline;
begin
  Result := BufferMatches(Block.Data, Block.Size, Block.Pattern);
end;

constructor TProducer.Create(var ABlocks: TBlocks; ACycle: Integer);
begin
  inherited Create(True);
  FBlocks := @ABlocks;
  FCycle := ACycle;
end;

procedure TProducer.Execute;
var
  I: Integer;
  Block: ^TBlock;
begin
  try
    for I := 0 to High(FBlocks^) do begin
      Block := @FBlocks^[I];
      Block.Size := BlockSizes[I mod SizeCount];
      Block.Pattern := PatternAt(I, FCycle);
      GetMem(Block.Data, Block.Size);
      If Block.Data = nil then begin
        ErrorCode := 1;
        Exit;
      end;
      FillChar(Block.Data^, Block.Size, Block.Pattern);
    end;
  except
    ErrorCode := 2;
  end;
end;

constructor TConsumer.Create(var ABlocks: TBlocks; AIndex: Integer);
begin
  inherited Create(True);
  FBlocks := @ABlocks;
  FIndex := AIndex;
end;

procedure TConsumer.Execute;
var
  I, OldSize, NewSize, PreservedSize: Integer;
  Block: ^TBlock;
begin
  try
    I := FIndex;
    while I <= High(FBlocks^) do begin
      Block := @FBlocks^[I];
      If not ContentMatches(Block^) then begin
        ErrorCode := 10;
        Exit;
      end;
      OldSize := Block.Size;
      case I mod 4 of
        0: NewSize := OldSize + 8192;
        1: NewSize := 18000;
        2: NewSize := 300000;
      else
        NewSize := 16000;
      end;
      ReallocMem(Block.Data, NewSize);
      If Block.Data = nil then begin
        ErrorCode := 11;
        Exit;
      end;
      PreservedSize := OldSize;
      If PreservedSize > NewSize then
        PreservedSize := NewSize;
      If not BufferMatches(Block.Data, PreservedSize, Block.Pattern) then begin
        ErrorCode := 12;
        Exit;
      end;
      If NewSize > OldSize then
        FillChar((PByte(Block.Data) + OldSize)^, NewSize - OldSize,
          Block.Pattern);
      Block.Size := NewSize;
      If not ContentMatches(Block^) then begin
        ErrorCode := 13;
        Exit;
      end;
      FreeMem(Block.Data);
      Block.Data := nil;
      Inc(I, ConsumerCount);
    end;
  except
    ErrorCode := 14;
  end;
end;

procedure ReleaseBlocks(var Blocks: TBlocks);
var
  I: Integer;
begin
  for I := 0 to High(Blocks) do
    If Blocks[I].Data <> nil then begin
      FreeMem(Blocks[I].Data);
      Blocks[I].Data := nil;
    end;
end;

var
  Blocks: TBlocks;
  Producer: TProducer;
  Consumers: array[0..ConsumerCount - 1] of TConsumer;
  Cycle, Cycles, I, BlockCount, Code: Integer;
  StartedAt: UInt64;
begin
  Cycles := 100;
  BlockCount := 512;
  If ParamCount > 0 then begin
    Val(ParamStr(1), Cycles, Code);
    If (Code <> 0) or (Cycles < 1) then
      Cycles := 100;
  end;
  If ParamCount > 1 then begin
    Val(ParamStr(2), BlockCount, Code);
    If (Code <> 0) or (BlockCount < ConsumerCount) then
      BlockCount := 512;
  end;
  SetLength(Blocks, BlockCount);
  StartedAt := GetTickCount64;
  for Cycle := 1 to Cycles do begin
    Producer := TProducer.Create(Blocks, Cycle);
    Producer.Start;
    Producer.WaitFor;
    Code := Producer.ErrorCode;
    Producer.Free;
    If Code <> 0 then begin
      ReleaseBlocks(Blocks);
      raise Exception.CreateFmt('producer failed: cycle=%d code=%d',
        [Cycle, Code]);
    end;
    for I := 0 to High(Consumers) do
      Consumers[I] := TConsumer.Create(Blocks, I);
    for I := 0 to High(Consumers) do
      Consumers[I].Start;
    for I := 0 to High(Consumers) do
      Consumers[I].WaitFor;
    Code := 0;
    for I := 0 to High(Consumers) do begin
      If Consumers[I].ErrorCode <> 0 then
        Code := Consumers[I].ErrorCode;
      Consumers[I].Free;
    end;
    If Code <> 0 then begin
      ReleaseBlocks(Blocks);
      raise Exception.CreateFmt('consumer failed: cycle=%d code=%d',
        [Cycle, Code]);
    end;
  end;
  WriteLn(Format('PASS cycles=%d blocks=%d realloc_free=%d elapsed_ms=%d',
    [Cycles, BlockCount, Int64(Cycles) * BlockCount,
     GetTickCount64 - StartedAt]));
end.
