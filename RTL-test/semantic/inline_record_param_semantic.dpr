program inline_record_param_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{ Semantic pin for the inline value-record repair: an inlined by-value
  record parameter whose body only reads it is substituted without a
  private copy.  Every case where the copy is semantically required must
  keep it: the body writes the parameter, the body takes its address, or
  the call is not inlined at all. }

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$endif}
  SysUtils;

type
  TRec16 = record
    A, B: UInt64;
  end;

procedure Fail(const Msg: string);
begin
  WriteLn('FAIL ', Msg);
  Halt(1);
end;

function ReadOnlyBody(Value: TRec16): UInt64; inline;
begin
  Result := Value.A * 3 + Value.B;
end;

function WritingBody(Value: TRec16): UInt64; inline;
begin
  { the parameter is a private copy by value semantics: writes must never
    reach the caller's record }
  Value.A := Value.A + 100;
  Value.B := Value.B * 2;
  Result := Value.A + Value.B;
end;

procedure BumpBoth(var R: TRec16);
begin
  Inc(R.A);
  Inc(R.B);
end;

function AddressTakingBody(Value: TRec16): UInt64; inline;
begin
  { passing the parameter to a var argument takes its address: the
    private copy must stay so the caller's record is untouched }
  BumpBoth(Value);
  Result := Value.A + Value.B;
end;

type
  TFn = function(Value: TRec16): UInt64;

var
  R: TRec16;
  Fn: TFn;
  Got: UInt64;
begin
  { plain read-only inline: no copy needed, values exact }
  R.A := 11;
  R.B := 7;
  Got := ReadOnlyBody(R);
  If Got <> 11 * 3 + 7 then
    Fail('read-only value');
  { caller mutates between calls: each call must observe fresh values }
  R.A := 100;
  Got := ReadOnlyBody(R);
  If Got <> 100 * 3 + 7 then
    Fail('read-only fresh value');

  { body writes its parameter: caller record must keep its values }
  R.A := 5;
  R.B := 9;
  Got := WritingBody(R);
  If Got <> (5 + 100) + 9 * 2 then
    Fail('writing body result');
  If (R.A <> 5) or (R.B <> 9) then
    Fail('writing body leaked into caller');

  { body takes the parameter address: caller record must keep its values }
  R.A := 21;
  R.B := 42;
  Got := AddressTakingBody(R);
  If Got <> 22 + 43 then
    Fail('address-taking result');
  If (R.A <> 21) or (R.B <> 42) then
    Fail('address-taking leaked into caller');

  { non-inlined path through a procedural variable: by-value contract }
  Fn := WritingBody;
  R.A := 1;
  R.B := 2;
  Got := Fn(R);
  If Got <> (1 + 100) + 2 * 2 then
    Fail('indirect call result');
  If (R.A <> 1) or (R.B <> 2) then
    Fail('indirect call leaked into caller');

  WriteLn('INLINE_RECORD_PARAM_OK');
end.
