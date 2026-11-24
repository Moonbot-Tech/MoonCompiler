{ DefineBinaryProperty streams a private payload through virtual filer callbacks. }

type
  TBreadthFilerPayload = array[0..7] of Byte;

  TBreadthPrivatePayload = class(TComponent)
  private
    procedure ReadEnvelope(Stream: TStream);
    procedure WriteEnvelope(Stream: TStream);
  protected
    procedure DefineProperties(Filer: TFiler); override;
  public
    Payload: TBreadthFilerPayload;
    HasPayload: Boolean;
    Reads: Integer;
  end;

procedure TBreadthPrivatePayload.DefineProperties(Filer: TFiler);
begin
  inherited;
  Filer.DefineBinaryProperty('Envelope', ReadEnvelope, WriteEnvelope, HasPayload);
end;

procedure TBreadthPrivatePayload.ReadEnvelope(Stream: TStream);
begin
  Stream.ReadBuffer(Payload[0], SizeOf(Payload));
  Inc(Reads);
end;

procedure TBreadthPrivatePayload.WriteEnvelope(Stream: TStream);
begin
  Stream.WriteBuffer(Payload[0], SizeOf(Payload));
end;

procedure RunBreadthPrivateFiler;
const
  Expected: TBreadthFilerPayload = ($E1, 0, $FD, $11, $27, $99, $6A, 0);
var
  Stream: TMemoryStream;
  Source, Target: TBreadthPrivatePayload;
begin
  Stream := TMemoryStream.Create;
  try
    Source := TBreadthPrivatePayload.Create(nil);
    try
      Target := TBreadthPrivatePayload.Create(nil);
      try
        Source.Name := 'EnvelopeSubject';
        Source.Payload := Expected;
        Source.HasPayload := True;
        Stream.WriteComponent(Source);
        Stream.Position := 0;
        Stream.ReadComponent(Target);
        Check((Target.Reads = 1) and CompareMem(@Target.Payload[0], @Expected[0], SizeOf(Expected)),
          'breadth-private-filer-calls-private-decoder-and-keeps-each-byte');

        Source.HasPayload := False;
        Stream.Size := 0;
        Stream.Position := 0;
        Stream.WriteComponent(Source);
        Target.Payload[0] := $5A;
        Stream.Position := 0;
        Stream.ReadComponent(Target);
        Check((Target.Reads = 1) and (Target.Payload[0] = $5A) and (Target.Payload[2] = $FD),
          'breadth-private-filer-omits-property-and-preserves-existing-target');
      finally
        Target.Free;
      end;
    finally
      Source.Free;
    end;
  finally
    Stream.Free;
  end;
end;
