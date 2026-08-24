program resourcestring_typed_const_semantic;

{ Delphi accepts resourcestring references in typed string constants.  The
  static image receives the resourcestring default text.  FPC additionally
  supports SetResourceStrings(): constants whose destination has the native
  RTL string width track the translated value; cross-width constants keep
  their statically converted default and must never be put into that table. }

{$APPTYPE CONSOLE}

uses
  {$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  {$endif FPC}
  SysUtils,
  resourcestring_typed_const_probe;

type
  TState = (stFirst, stSecond);

resourcestring
  RSFirst = 'first %s';
  RSSecond = 'second';

const
  States: array[TState] of string = (
    RSFirst,
    RSSecond);
  LocalUnicode: UnicodeString = RSFirst;
  LocalAnsi: AnsiString = RSSecond;
  LocalWide: WideString = RSSecond;

var
  FailCount: Integer;

procedure Check(const Name, Got, Expected: string);
begin
  If Got <> Expected then
  begin
    WriteLn('FAIL ', Name, ': "', Got, '" expected "', Expected, '"');
    Inc(FailCount);
  end;
end;

{$ifdef FPC}
function Translate(Name: AnsiString; Value: string; Hash: LongInt;
  Arg: Pointer): string;
begin
  Result := 'x-' + Value;
end;
{$endif FPC}

begin
  FailCount := 0;

  Check('local array first', States[stFirst], 'first %s');
  Check('local array second', States[stSecond], 'second');
  Check('local unicode', LocalUnicode, 'first %s');
  Check('local ansi', string(LocalAnsi), 'second');
  Check('local wide', string(LocalWide), 'second');
  Check('local format', Format(States[stFirst], ['X']), 'first X');

  Check('PPU array first', RemoteStates[remoteStateFirst], 'remote first %s');
  Check('PPU array second', RemoteStates[remoteStateSecond], 'remote second');
  Check('PPU unicode', RemoteUnicode, 'remote first %s');
  Check('PPU ansi', string(RemoteAnsi), 'remote second');
  Check('PPU wide', string(RemoteWide), 'remote second');

{$ifdef FPC}
  SetResourceStrings(@Translate, nil);

  Check('translated local array', States[stFirst], 'x-first %s');
  Check('translated local unicode', LocalUnicode, 'x-first %s');
  Check('static local ansi', string(LocalAnsi), 'second');
  Check('static local wide', string(LocalWide), 'second');

  Check('translated PPU array', RemoteStates[remoteStateFirst], 'x-remote first %s');
  Check('translated PPU unicode', RemoteUnicode, 'x-remote first %s');
  Check('static PPU ansi', string(RemoteAnsi), 'remote second');
  Check('static PPU wide', string(RemoteWide), 'remote second');
{$endif FPC}

  If FailCount = 0 then
    WriteLn('RESOURCESTRING_TYPED_CONST_OK')
  else
  begin
    WriteLn('RESOURCESTRING_TYPED_CONST_FAIL count=', FailCount);
    Halt(1);
  end;
end.
