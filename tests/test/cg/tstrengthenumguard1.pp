{ %OPT=-O3 }
program tstrengthenumguard1;

{$mode delphi}

type
  TText = type AnsiString;
  TKind = (kindUndefined, kindArg, kindOption, kindParam, kindAfter);
  THandler = procedure;

const
  KIND_TEXT: array[kindOption .. kindParam] of TText = (
    ' [options]', ' [params]');
  KIND_DESCRIPTION: array[kindOption .. kindParam] of TText = (
    'Options', 'Params');

type
  TCommandLine = class
  private
    FDescription: array[kindArg .. kindParam] of TText;
    FDetail: array[kindArg .. kindParam] of TText;
  public
    constructor Create;
    function FullDescription: TText;
  end;

constructor TCommandLine.Create;
begin
  FDescription[kindOption] := 'o';
  FDescription[kindParam] := 'p';
  FDetail[kindArg] := 'arg;';
  FDetail[kindOption] := 'option;';
  FDetail[kindParam] := 'param;';
end;

function TCommandLine.FullDescription: TText;
var
  Kind: TKind;
begin
  Result := '';
  for Kind := Low(KIND_TEXT) to High(KIND_TEXT) do
    if FDescription[Kind] <> '' then
      Result := Result + KIND_TEXT[Kind];
  for Kind := Low(FDetail) to High(FDetail) do
    if FDetail[Kind] <> '' then
    begin
      if Kind in [Low(KIND_DESCRIPTION) .. High(KIND_DESCRIPTION)] then
        Result := Result + KIND_DESCRIPTION[Kind] + ':';
      Result := Result + FDetail[Kind];
    end;
  for Kind := kindAfter downto kindUndefined do
    if Kind in [Low(KIND_DESCRIPTION) .. High(KIND_DESCRIPTION)] then
      Result := Result + KIND_DESCRIPTION[Kind] + ';';
end;

var
  CommandLine: TCommandLine;
  Handlers: array[0 .. 1] of THandler;
  HandlerTotal: Integer;

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
  CommandLine := TCommandLine.Create;
  try
    if CommandLine.FullDescription <>
       ' [options] [params]arg;Options:option;Params:param;Params;Options;' then
      Halt(1);
  finally
    CommandLine.Free;
  end;

  Handlers[0] := @AddOne;
  Handlers[1] := @AddTen;
  HandlerTotal := 0;
  RunHandlers;
  if HandlerTotal <> 11 then
    Halt(2);
end.
