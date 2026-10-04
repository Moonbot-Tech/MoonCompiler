{ %OPT=-O3 -OoAUTOINLINE }
program tinlineaddressresult1;
{$IFDEF FPC}{$mode delphi}{$ENDIF}
{$inline on}
{ A function returns a value even when its const consumer receives an address.
  Changing the source inside that consumer must not change the returned value.
  The non-inlined getter is the negative control (-dNOINLINE). Delphi 12.2
  agrees for aggregates and their fields; it also loses the scalar const[ref]
  snapshot, so that one is checked against the non-inlined call instead. }
type
  TRec = record
    Value, Padding, More: UInt64;
    function ReadAfterChange: UInt64; {$IFDEF FPC}noinline;{$ENDIF}
  end;
  PRec = ^TRec;
  TSmall = record Value: UInt64; end;
  TWrapper = record Item: TRec; Tail: UInt64; end;
  TValues = array[0..2] of UInt64;
  TText = string[31];
var
  Shared: TRec;
  Small: TSmall;
  Wrapped: TWrapper;
  Values: TValues;
  Text: TText;
  Scalar: UInt64;
  Failures: Integer;

function GetRec: TRec; {$IFDEF NOINLINE}{$IFDEF FPC}noinline;{$ENDIF}{$ELSE}inline;{$ENDIF}
begin
  Result := Shared;
end;
function GetSmall: TSmall; {$IFDEF NOINLINE}{$IFDEF FPC}noinline;{$ENDIF}{$ELSE}inline;{$ENDIF}
begin
  Result := Small;
end;
function GetWrapped: TWrapper; {$IFDEF NOINLINE}{$IFDEF FPC}noinline;{$ENDIF}{$ELSE}inline;{$ENDIF}
begin
  Result := Wrapped;
end;
function GetValues: TValues; {$IFDEF NOINLINE}{$IFDEF FPC}noinline;{$ENDIF}{$ELSE}inline;{$ENDIF}
begin
  Result := Values;
end;
function GetText: TText; {$IFDEF NOINLINE}{$IFDEF FPC}noinline;{$ENDIF}{$ELSE}inline;{$ENDIF}
begin
  Result := Text;
end;
function GetScalar: UInt64; {$IFDEF NOINLINE}{$IFDEF FPC}noinline;{$ENDIF}{$ELSE}inline;{$ENDIF}
begin
  Result := Scalar;
end;
function GetAgain: TRec; {$IFDEF NOINLINE}{$IFDEF FPC}noinline;{$ENDIF}{$ELSE}inline;{$ENDIF}
begin
  Result := GetRec();
end;
function GetThird: TRec; {$IFDEF NOINLINE}{$IFDEF FPC}noinline;{$ENDIF}{$ELSE}inline;{$ENDIF}
begin
  Result := GetAgain();
end;

procedure Reset; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Shared.Value := 17;
  Small.Value := 17;
  Wrapped.Item.Value := 17;
  Values[0] := 17;
  Scalar := 17;
  Text := 'before';
end;

procedure Change; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Shared.Value := 99;
  Small.Value := 99;
  Wrapped.Item.Value := 99;
  Values[0] := 99;
  Scalar := 99;
  Text := 'after';
end;

function ConsumeRec(const V: TRec): UInt64; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Change;
  Result := V.Value;
end;
function TRec.ReadAfterChange: UInt64;
begin
  Change;
  Result := Value;
end;
function ConsumeSmall(const V: TSmall): UInt64; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Change;
  Result := V.Value;
end;
function ConsumeValue(V: TRec): UInt64; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Change;
  Result := V.Value;
end;
function ConsumeArray(const V: TValues): UInt64; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Change;
  Result := V[0];
end;
function ConsumeOpenArray(const V: array of UInt64): UInt64; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Change;
  Result := V[0];
end;
function ConsumeText(const V: TText): TText; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Change;
  Result := V;
end;
function ConsumeRef(const [ref] V: UInt64): UInt64; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Change;
  Result := V;
end;
function ConsumeInline(const V: TRec): UInt64; {$IFDEF NOINLINE}{$IFDEF FPC}noinline;{$ENDIF}{$ELSE}inline;{$ENDIF}
begin
  Change;
  Result := V.Value;
end;
function ReadInline(const V: TRec): UInt64; {$IFDEF NOINLINE}{$IFDEF FPC}noinline;{$ENDIF}{$ELSE}inline;{$ENDIF}
begin
  Result := V.Value;
end;

{ Ordinary reads must keep the same code when address consumers are repaired. }
function HotField(const R: TRec): UInt64; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result := R.Value;
end;
function HotElement(const A: TValues; I: Integer): UInt64; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result := A[I];
end;
function HotPointer(P: PRec): UInt64; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result := P^.Value;
end;
function HotGetter: UInt64; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result := GetRec().Value;
end;
function HotInline: UInt64; {$IFDEF FPC}noinline;{$ENDIF}
begin
  Result := ReadInline(GetRec());
end;

procedure Check(N: UInt64; const Name: string);
begin
  If N <> 17 then begin
    Writeln('FAIL ', Name, ': ', N);
    Inc(Failures);
  end;
end;

begin
  Reset;
  Check(ConsumeRec(GetRec()), 'record');
  Reset;
  Check(GetRec().ReadAfterChange(), 'record method');
  Reset;
  Check(ConsumeRec(GetAgain()), 'nested inline result');
  Reset;
  Check(ConsumeRec(GetThird()), 'nested inline result twice');
  Reset;
  Check(ConsumeRec(GetWrapped().Item), 'nested record');
  Reset;
  Check(ConsumeSmall(GetSmall()), 'small value ABI');
  Reset;
  Check(ConsumeValue(GetRec()), 'value parameter');
  Reset;
  Check(ConsumeArray(GetValues()), 'array');
  Reset;
  Check(ConsumeOpenArray(GetValues()), 'open array');
  Reset;
  Check(ConsumeRef(GetScalar()), 'scalar ref');
  Reset;
  Check(ConsumeRef(GetRec().Value), 'record field ref');
  Reset;
  Check(ConsumeRef(GetValues()[0]), 'array element ref');
  Reset;
  Check(ConsumeInline(GetRec()), 'inline consumer');
  Reset;
  Check(ReadInline(GetRec()), 'pure inline consumer');
  Reset;
  Check(HotField(Shared), 'ordinary field');
  Check(HotElement(Values, 0), 'ordinary element');
  Check(HotPointer(@Shared), 'ordinary pointer');
  Check(HotGetter(), 'ordinary getter');
  Check(HotInline(), 'ordinary inline consumer');
  Reset;
  with GetRec() do begin
    Change;
    Check(Value, 'with result');
  end;
  Reset;
  If ConsumeText(GetText()) <> 'before' then begin
    Writeln('FAIL shortstring');
    Inc(Failures);
  end;
  If Failures <> 0 then Halt(1);
  Writeln('RESULT_ADDRESS_OK');
end.
