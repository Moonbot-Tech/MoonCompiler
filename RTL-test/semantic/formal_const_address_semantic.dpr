program formal_const_address_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{ Semantic pin for untyped const parameters fed from inlined constants:
  Move(S[1], ...) inside an inline routine must read from the real
  string data even after the parameter is substituted by a literal.
  Folding the indexed load into a single materialized character makes
  the callee copy garbage past the first element (wrong code caught on
  TStringBuilder.Append literals, 2026-08-18). }

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$endif}
  SysUtils;

type
  TSink = class
  public
    FData: array of WideChar;
    FBytes: array of Byte;
    FLength: Integer;
    FByteLength: Integer;
    procedure Push(const AValue: UnicodeString); inline;
    procedure PushRaw(const AValue: RawByteString); inline;
  end;

procedure Fail(const Msg: string);
begin
  WriteLn('FAIL ', Msg);
  Halt(1);
end;

procedure TSink.Push(const AValue: UnicodeString);
var
  SL: Integer;
begin
  SL := System.Length(AValue);
  if SL = 0 then
    exit;
  if FLength + SL > System.Length(FData) then
    Fail('capacity');
  Move(AValue[1], FData[FLength], SL * SizeOf(WideChar));
  Inc(FLength, SL);
end;

procedure TSink.PushRaw(const AValue: RawByteString);
var
  SL: Integer;
begin
  { same shape through the ansi path: one byte per element }
  SL := System.Length(AValue);
  if SL = 0 then
    exit;
  if FByteLength + SL > System.Length(FBytes) then
    Fail('capacity raw');
  Move(AValue[1], FBytes[FByteLength], SL);
  Inc(FByteLength, SL);
end;

var
  Sink: TSink;
  S: UnicodeString;
  ExpectBytes: RawByteString;
  Got: RawByteString;
  I: Integer;

begin
  Sink := TSink.Create;
  try
    System.SetLength(Sink.FData, 64);

    { unicode literals through the inline body }
    Sink.FLength := 0;
    Sink.Push('abc');
    Sink.Push('DEFG');
    Sink.Push('hi');
    SetString(S, PWideChar(@Sink.FData[0]), Sink.FLength);
    If S <> 'abcDEFGhi' then
      Fail(Format('unicode literals: got "%s"', [AnsiString(S)]));

    { raw literals through the inline body: check every byte }
    System.SetLength(Sink.FBytes, 64);
    Sink.FByteLength := 0;
    Sink.PushRaw('xyz');
    Sink.PushRaw('0123');
    ExpectBytes := 'xyz0123';
    System.SetLength(Got, Sink.FByteLength);
    Move(Sink.FBytes[0], Got[1], Sink.FByteLength);
    If Got <> ExpectBytes then
      Fail('raw literals');

    { non-constant path stays intact }
    S := 'runtime';
    UniqueString(S);
    Sink.FLength := 0;
    Sink.Push(S);
    Sink.Push(S);
    SetString(S, PWideChar(@Sink.FData[0]), Sink.FLength);
    If S <> 'runtimeruntime' then
      Fail('runtime strings');

    { direct literal argument without any inline wrapper }
    Sink.FLength := 0;
    FillChar(Sink.FData[0], System.Length(Sink.FData) * SizeOf(WideChar), 0);
    Move('PQRST'[1], Sink.FData[0], 5);
    ExpectBytes := 'PQRST';
    System.SetLength(Got, 5);
    Move(Sink.FData[0], Got[1], 5);
    If Got <> ExpectBytes then
      Fail('direct literal move');

    for I := 1 to 1 do ;
    WriteLn('FORMAL_CONST_ADDRESS_PASS');
  finally
    Sink.Free;
  end;
end.
