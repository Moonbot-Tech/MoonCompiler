program pulse_rtl;

{$ifndef FPC}
  {$APPTYPE CONSOLE}
{$endif}

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  SysUtils,
  Classes,
  Generics.Collections,
  pulse_harness in '..\common\pulse_harness.pas';

type
  TPulseObject = class
  private
    FValue: UInt64;
  public
    constructor Create(AValue: UInt64);
    function Mix(AValue: UInt64): UInt64; virtual;
  end;

var
  SearchText: UnicodeString;
  ByteData: TBytes;
  PulseFormatSettings: TFormatSettings;

constructor TPulseObject.Create(AValue: UInt64);
begin
  inherited Create;
  FValue := AValue;
end;

function TPulseObject.Mix(AValue: UInt64): UInt64;
begin
  Result := (FValue xor AValue) * UInt64($9E3779B185EBCA87);
end;

function CaseUnicodePos(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + UInt64(Pos('needle-255', SearchText));
end;

function CaseUnicodeCopy(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := Copy(SearchText, 1024 + (I and 31), 96);
    Result := Result + UInt64(Length(Value)) + UInt64(Ord(Value[1]));
  end;
end;

function CaseUnicodeConcat32(Iterations: Integer): UInt64;
var
  I, J: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := '';
    for J := 0 to 31 do
      Value := Value + UnicodeString('part-') + UnicodeString(IntToStr(J));
    Result := Result + UInt64(Length(Value));
  end;
end;

function CaseUtf8EncodeDecode(Iterations: Integer): UInt64;
var
  I: Integer;
  Raw: UTF8String;
  Text: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Raw := UTF8Encode(SearchText);
    Text := UTF8ToString(Raw);
    Result := Result + UInt64(Length(Raw)) + UInt64(Length(Text));
  end;
end;

function CaseIntToStr(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := IntToStr(Int64(I) * 1000003 - 7000001);
    Result := Result + UInt64(Length(Value)) + UInt64(Ord(Value[1]));
  end;
end;

function CaseStrToInt(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do
    Result := Result + UInt64(StrToInt64(IntToStr(Int64(I) * 1000003)));
end;

function CaseFloatToStr(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := FloatToStr(I * 0.125, PulseFormatSettings);
    Result := Result + UInt64(Length(Value)) + UInt64(Ord(Value[1]));
  end;
end;

function CaseStrToFloat(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: Double;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := StrToFloat(IntToStr(I) + '.125', PulseFormatSettings);
    Result := Result + UInt64(Trunc(Value * 1000));
  end;
end;

function CaseFormat(Iterations: Integer): UInt64;
var
  I: Integer;
  Value: UnicodeString;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Value := Format('%d:%.3f', [I, I * 0.125], PulseFormatSettings);
    Result := Result + UInt64(Length(Value));
  end;
end;

function CaseStringListSort(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  List: TStringList;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    List := TStringList.Create;
    try
      for I := 127 downto 0 do
        List.Add(Format('key-%.4d', [I]));
      List.Sort;
      Result := Result + UInt64(Length(List[0])) + UInt64(Length(List[127]));
    finally
      List.Free;
    end;
  end;
end;

function CaseMemoryStream(Iterations: Integer): UInt64;
var
  Iteration: Integer;
  Stream: TMemoryStream;
  Value: Byte;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    Stream := TMemoryStream.Create;
    try
      Stream.WriteBuffer(ByteData[0], Length(ByteData));
      Stream.Position := Length(ByteData) div 2;
      Stream.ReadBuffer(Value, SizeOf(Value));
      Result := Result + UInt64(Value) + UInt64(Stream.Size);
    finally
      Stream.Free;
    end;
  end;
end;

function CaseGenericList(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  List: TList<Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    List := TList<Integer>.Create;
    try
      for I := 0 to 511 do
        List.Add(I xor Iteration);
      for I := 0 to List.Count - 1 do
        Result := Result + UInt64(List[I]);
    finally
      List.Free;
    end;
  end;
end;

function CaseDictionary(Iterations: Integer): UInt64;
var
  Iteration, I, Value: Integer;
  Dictionary: TDictionary<Integer, Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    Dictionary := TDictionary<Integer, Integer>.Create;
    try
      for I := 0 to 511 do
        Dictionary.Add(I * 17, I xor $55AA);
      for I := 0 to 511 do
        If Dictionary.TryGetValue(I * 17, Value) then
          Result := Result + UInt64(Value);
    finally
      Dictionary.Free;
    end;
  end;
end;

function CaseQueue(Iterations: Integer): UInt64;
var
  Iteration, I: Integer;
  Queue: TQueue<Integer>;
begin
  Result := 0;
  for Iteration := 1 to Iterations do
  begin
    Queue := TQueue<Integer>.Create;
    try
      for I := 0 to 511 do
        Queue.Enqueue(I xor Iteration);
      while Queue.Count <> 0 do
        Result := Result + UInt64(Queue.Dequeue);
    finally
      Queue.Free;
    end;
  end;
end;

function CaseObjectLifecycle(Iterations: Integer): UInt64;
var
  I: Integer;
  Instance: TPulseObject;
begin
  Result := 0;
  for I := 1 to Iterations do
  begin
    Instance := TPulseObject.Create(UInt64(I));
    try
      Result := Result xor Instance.Mix(UInt64(I * 17));
    finally
      Instance.Free;
    end;
  end;
end;

procedure InitializeData;
var
  I: Integer;
begin
  PulseFormatSettings := TFormatSettings.Create;
  PulseFormatSettings.DecimalSeparator := '.';
  SearchText := '';
  for I := 0 to 255 do
    SearchText := SearchText + UnicodeString('market-') + UnicodeString(IntToStr(I)) +
      UnicodeString(':needle-') + UnicodeString(IntToStr(I)) + UnicodeString(';');
  SetLength(ByteData, 65536);
  for I := 0 to High(ByteData) do
    ByteData[I] := Byte(I * 17 + 29);
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
begin
  PulseInitialize('pulse_rtl', Profile, SelectedCase);
  InitializeData;
  Found := False;
  PulseRunCase('pulse_rtl', 'unicode-pos-4k', 'rtl', 'UnicodeString',
    @CaseUnicodePos, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'unicode-copy-96', 'rtl+mm', 'UnicodeString',
    @CaseUnicodeCopy, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'unicode-concat-32', 'rtl+mm', 'UnicodeString',
    @CaseUnicodeConcat32, 32, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'utf8-encode-decode-4k', 'rtl+mm', 'UTF8String',
    @CaseUtf8EncodeDecode, Length(SearchText), Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'inttostr-int64', 'rtl+mm', 'IntToStr', @CaseIntToStr,
    1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'strtoint-int64', 'rtl+mm', 'StrToInt64', @CaseStrToInt,
    1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'floattostr-double', 'rtl+mm', 'FloatToStr',
    @CaseFloatToStr, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'strtofloat-double', 'rtl+mm', 'StrToFloat',
    @CaseStrToFloat, 1, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'format-mixed', 'rtl+mm', 'Format', @CaseFormat, 1,
    Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'stringlist-sort-128', 'rtl+mm', 'TStringList',
    @CaseStringListSort, 128, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'memorystream-64k', 'rtl+mm', 'TMemoryStream',
    @CaseMemoryStream, Length(ByteData), Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'generic-list-512', 'rtl+mm', 'TList<Integer>',
    @CaseGenericList, 512, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'dictionary-512', 'rtl+mm',
    'TDictionary<Integer,Integer>', @CaseDictionary, 1024, Profile,
    SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'queue-512', 'rtl+mm', 'TQueue<Integer>', @CaseQueue,
    1024, Profile, SelectedCase, Found);
  PulseRunCase('pulse_rtl', 'object-create-virtual-free', 'rtl+mm', 'TObject',
    @CaseObjectLifecycle, 1, Profile, SelectedCase, Found);
  PulseFinish('pulse_rtl', SelectedCase, Found);
end;

begin
  try
    Run;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
