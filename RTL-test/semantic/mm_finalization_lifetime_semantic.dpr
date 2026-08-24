program mm_finalization_lifetime_semantic;

{ The bundled MM must still be alive when units initialized before it run
  their finalizers, and must perform its real leak census afterwards.
  SetResourceStrings gives ObjPas a managed CurrentValue that is released
  after the MM unit finalization point.  The historical early teardown printed
  the marker and then crashed; the intermediate no-teardown repair survived
  but never emitted the report markers required by the runner. }

{$APPTYPE CONSOLE}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils;

resourcestring
  RSLifetime = 'lifetime';

function Translate(Name: AnsiString; Value: string; Hash: LongInt;
  Arg: Pointer): string;
begin
  Result := 'translated-' + Value;
end;

begin
  SetResourceStrings(@Translate, nil);
  If RSLifetime <> 'translated-lifetime' then
    Halt(1);
  WriteLn('MM_FINALIZATION_LIFETIME_OK');
end.
