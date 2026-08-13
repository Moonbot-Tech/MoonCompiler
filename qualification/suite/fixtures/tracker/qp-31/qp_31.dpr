program tracker_qp_31;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch nestedprocvars}
  {$modeswitch inlinevars}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  SysUtils, Classes, Math, Variants, TypInfo, Rtti,
  Generics.Defaults, Generics.Collections;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then
    raise Exception.Create(Name);
end;

type
  ITracked = interface
    ['{2C1AB237-995F-44E9-B506-C7E593351B04}']
    function Marker: Integer;
  end;
  TTracked = class(TInterfacedObject, ITracked)
  private
    FMarker: Integer;
  public
    class var Alive: Integer;
    constructor Create(AMarker: Integer);
    destructor Destroy; override;
    function Marker: Integer;
  end;
  TTrackedArray = array of ITracked;
constructor TTracked.Create(AMarker: Integer);
begin inherited Create; Inc(Alive); FMarker := AMarker; end;
destructor TTracked.Destroy;
begin Dec(Alive); inherited; end;
function TTracked.Marker: Integer;
begin Result := FMarker; end;
procedure ExerciseTrackedQueue;
var
  Queue: TQueue<TTrackedArray>;
  Input, Output: TTrackedArray;
begin
  Queue := TQueue<TTrackedArray>.Create;
  try
    SetLength(Input, 2);
    Input[0] := TTracked.Create(11); Input[1] := TTracked.Create(22);
    Queue.Enqueue(Input);
    Input := nil;
    Check(TTracked.Alive = 2, 'owned-by-queue');
    Output := Queue.Dequeue;
    Check((Length(Output) = 2) and (Output[0].Marker = 11) and (Output[1].Marker = 22), 'tracked-payload');
    Output := nil;
  finally Queue.Free; end;
end;

procedure Run;
begin
var BytesQueue := TQueue<TBytes>.Create;
  try
    BytesQueue.Enqueue(TBytes.Create(1, 2));
    BytesQueue.Enqueue(TBytes.Create(3, 4, 5));
    var Bytes := BytesQueue.Dequeue;
    Check((Length(Bytes) = 2) and (Bytes[0] = 1) and (Bytes[1] = 2), 'bytes-first');
    Bytes := BytesQueue.Dequeue;
    Check((Length(Bytes) = 3) and (Bytes[2] = 5), 'bytes-second');
  finally BytesQueue.Free; end;
  ExerciseTrackedQueue;
  Check(TTracked.Alive = 0, 'final-lifetime');
end;

begin
  try
    Run;
    WriteLn('PASS QP-31');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-31: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
