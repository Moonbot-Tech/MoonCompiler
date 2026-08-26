program tdelphimemorystreamsetsize1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
{$ifdef FPC}
  Classes,
  SysUtils;
{$else}
  System.Classes,
  System.SysUtils;
{$endif}

type
  TProbeMemoryStream = class(TMemoryStream)
  private
    FLongIntCalls: Integer;
    FInt64Calls: Integer;
    FLastSize: Int64;
  public
    procedure SetSize(NewSize: LongInt); override;
    procedure SetSize(const NewSize: Int64); override;
    property LongIntCalls: Integer read FLongIntCalls;
    property Int64Calls: Integer read FInt64Calls;
    property LastSize: Int64 read FLastSize;
  end;

procedure TProbeMemoryStream.SetSize(NewSize: LongInt);
begin
  Inc(FLongIntCalls);
  inherited SetSize(NewSize);
end;

procedure TProbeMemoryStream.SetSize(const NewSize: Int64);
begin
  Inc(FInt64Calls);
  FLastSize := NewSize;
  if NewSize <= 1024 * 1024 then
    inherited SetSize(NewSize);
end;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

var
  Stream: TProbeMemoryStream;
  Base: TStream;
  CardinalSize: Cardinal;
  Factor: Integer;
  LargeSize: Int64;
  Raised: Boolean;
begin
  Stream := TProbeMemoryStream.Create;
  try
    Stream.SetSize(8);
    Check((Stream.Size = 8) and (Stream.LongIntCalls = 1) and
      (Stream.Int64Calls = 1) and (Stream.LastSize = 8), 1);

    Stream.Position := Stream.Size;
    Base := Stream;
    Base.Size := 3;
    Check((Stream.Size = 3) and (Stream.Position = 3) and
      (Stream.LongIntCalls = 1) and (Stream.Int64Calls = 2), 2);

    CardinalSize := 12;
    Stream.SetSize(CardinalSize);
    Check((Stream.Size = 12) and (Stream.LongIntCalls = 1) and
      (Stream.Int64Calls = 3), 3);

    Factor := 2;
    Stream.SetSize(CardinalSize * Factor);
    Check((Stream.Size = 24) and (Stream.LongIntCalls = 1) and
      (Stream.Int64Calls = 4), 4);

    LargeSize := Int64(High(LongInt)) + 1;
    Stream.SetSize(LargeSize);
    Check((Stream.LongIntCalls = 1) and (Stream.Int64Calls = 5) and
      (Stream.LastSize = LargeSize), 5);

{$ifdef FPC}
    TMemoryStream(Stream).SetSize(QWord(32));
    Check((Stream.LongIntCalls = 1) and (Stream.Int64Calls = 6) and
      (Stream.LastSize = 32), 6);

    Raised := False;
    try
      TMemoryStream(Stream).SetSize(QWord(High(Int64)) + 1);
    except
      on E: ERangeError do
        Raised := True;
    end;
    Check(Raised and (Stream.Int64Calls = 6), 7);
{$endif}

    Stream.SetSize(0);
    Check((Stream.Size = 0) and (Stream.LongIntCalls = 2) and
{$ifdef FPC}
      (Stream.Int64Calls = 7), 8);
{$else}
      (Stream.Int64Calls = 6), 8);
{$endif}
  finally
    Stream.Free;
  end;
end.
