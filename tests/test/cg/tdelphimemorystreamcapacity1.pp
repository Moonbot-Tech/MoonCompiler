program tdelphimemorystreamcapacity1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
  Classes;

type
  TProbeMemoryStream = class(TMemoryStream)
  private
    FCalls: Integer;
  protected
    procedure SetCapacity(NewCapacity: NativeInt); override;
  public
    procedure Reserve(NewCapacity: NativeInt);
    property Calls: Integer read FCalls;
  end;

procedure TProbeMemoryStream.SetCapacity(NewCapacity: NativeInt);
begin
  Inc(FCalls);
  inherited SetCapacity(NewCapacity);
end;

procedure TProbeMemoryStream.Reserve(NewCapacity: NativeInt);
begin
  SetCapacity(NewCapacity);
end;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

var
  Stream: TProbeMemoryStream;
begin
  Stream:=TProbeMemoryStream.Create;
  try
    Stream.Reserve(4096);
    Check((Stream.Capacity>=4096) and (Stream.Calls=1),1);
    Stream.Reserve(0);
    Check((Stream.Capacity=0) and (Stream.Calls=2),2);
  finally
    Stream.Free;
  end;
end.
