program tdelphistringlistbom1;

{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
  Classes, SysUtils;

procedure RequireBytes(Stream: TMemoryStream; const Expected: TBytes;
  ErrorCode: Byte);
var
  Actual: array of Byte;
  I: Integer;
begin
  if Stream.Size<>Length(Expected) then
    Halt(ErrorCode);
  SetLength(Actual,Stream.Size);
  Stream.Position:=0;
  if Length(Actual)>0 then
    Stream.ReadBuffer(Actual[0],Length(Actual));
  for I:=0 to High(Actual) do
    if Actual[I]<>Expected[I] then
      Halt(ErrorCode);
end;

procedure RequireEncoded(Stream: TMemoryStream; Encoding: TEncoding;
  const Text: string; WithBOM: Boolean; ErrorCode: Byte);
var
  Expected, Payload, Preamble: TBytes;
  Offset: Integer;
begin
  Payload:=Encoding.GetBytes(Text);
  if WithBOM then
    Preamble:=Encoding.GetPreamble
  else
    Preamble:=nil;
  SetLength(Expected,Length(Preamble)+Length(Payload));
  Offset:=Length(Preamble);
  if Offset>0 then
    Move(Preamble[0],Expected[0],Offset);
  if Length(Payload)>0 then
    Move(Payload[0],Expected[Offset],Length(Payload));
  RequireBytes(Stream,Expected,ErrorCode);
end;

procedure PutBytes(Stream: TMemoryStream; const Bytes: array of Byte);
begin
  Stream.Clear;
  if Length(Bytes)>0 then
    Stream.WriteBuffer(Bytes[0],Length(Bytes));
  Stream.Position:=0;
end;

var
  Lines: TStringList;
  Stream: TMemoryStream;
begin
  Lines:=TStringList.Create;
  Stream:=TMemoryStream.Create;
  try
    if not Lines.WriteBOM then
      Halt(1);

    Lines.Add('ab');
    Lines.SaveToStream(Stream,TEncoding.UTF8);
    RequireEncoded(Stream,TEncoding.UTF8,'ab'+sLineBreak,True,2);

    Stream.Clear;
    Lines.WriteBOM:=False;
    Lines.SaveToStream(Stream,TEncoding.UTF8);
    RequireEncoded(Stream,TEncoding.UTF8,'ab'+sLineBreak,False,3);

    Lines.Clear;
    Lines.WriteBOM:=True;
    Stream.Clear;
    Lines.SaveToStream(Stream,TEncoding.UTF8);
    RequireEncoded(Stream,TEncoding.UTF8,'',True,4);

    Stream.Clear;
    Lines.SaveToStream(Stream,TEncoding.Unicode);
    RequireEncoded(Stream,TEncoding.Unicode,'',True,5);

    PutBytes(Stream,[$61,$62,$0d,$0a]);
    Lines.LoadFromStream(Stream,TEncoding.UTF8);
    if Lines.Text<>'ab'+sLineBreak then
      Halt(6);
    if not Lines.WriteBOM then
      Halt(7);

    PutBytes(Stream,[$ef,$bb,$bf,$63,$64,$0d,$0a]);
    Lines.LoadFromStream(Stream,TEncoding.UTF8);
    if Lines.Text<>'cd'+sLineBreak then
      Halt(8);
    if not Lines.WriteBOM then
      Halt(9);

{$ifdef FPC}
    Lines.Options:=Lines.Options+[soPreserveBOM];
    PutBytes(Stream,[$65,$66,$0d,$0a]);
    Lines.LoadFromStream(Stream,TEncoding.UTF8);
    if Lines.WriteBOM then
      Halt(10);
    PutBytes(Stream,[$ef,$bb,$bf,$67,$68,$0d,$0a]);
    Lines.LoadFromStream(Stream,TEncoding.UTF8);
    if not Lines.WriteBOM then
      Halt(11);
{$endif}
  finally
    Stream.Free;
    Lines.Free;
  end;
end.
