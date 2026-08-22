program strength_guarded_enum_semantic;

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  {$endif}
  SysUtils;

type
  TText = type AnsiString;
  TKind = (kindUndefined, kindArg, kindOption, kindParam, kindAfter);
  THandler = procedure;

const
  DESCRIPTIONS: array[kindOption .. kindParam] of TText = (
    'options', 'params');

var
  Values: array[kindArg .. kindParam] of TText;
  Kind: TKind;
  ForwardText, BackwardText: TText;
  RangeRaised: Boolean;
  Handlers: array[0 .. 1] of THandler;
  HandlerTotal: Integer;

function CheckedStart: TKind; noinline;
begin
  Result := TKind(Ord(kindArg) + ParamCount);
end;

procedure CheckedAccessMustRaise;
var
  CheckedKind: TKind;
begin
{$push}{$R+}{$Q+}
  for CheckedKind := CheckedStart to kindParam do
    ForwardText := ForwardText + DESCRIPTIONS[CheckedKind];
{$pop}
end;

procedure AddOne;
begin
  Inc(HandlerTotal);
end;

procedure AddTen;
begin
  Inc(HandlerTotal, 10);
end;

procedure RunHandlers;
var
  I: Integer;
begin
  for I := Low(Handlers) to High(Handlers) do
    Handlers[I]();
end;

begin
  Values[kindArg] := 'arg';
  Values[kindOption] := 'option';
  Values[kindParam] := 'param';

  ForwardText := '';
  for Kind := Low(Values) to High(Values) do
  begin
    ForwardText := ForwardText + Values[Kind] + ';';
    if Kind in [Low(DESCRIPTIONS) .. High(DESCRIPTIONS)] then
      ForwardText := ForwardText + DESCRIPTIONS[Kind] + ';';
  end;
  if ForwardText <> 'arg;option;options;param;params;' then
    Halt(1);

  BackwardText := '';
  for Kind := kindAfter downto kindUndefined do
    if Kind in [Low(DESCRIPTIONS) .. High(DESCRIPTIONS)] then
      BackwardText := BackwardText + DESCRIPTIONS[Kind] + ';';
  if BackwardText <> 'params;options;' then
    Halt(2);

  RangeRaised := False;
  try
    CheckedAccessMustRaise;
  except
    on E: ERangeError do
      RangeRaised := True;
  end;
  if not RangeRaised then
    Halt(3);

  Handlers[0] := @AddOne;
  Handlers[1] := @AddTen;
  HandlerTotal := 0;
  RunHandlers;
  if HandlerTotal <> 11 then
    Halt(4);

  WriteLn('STRENGTH_GUARDED_ENUM_OK');
end.
