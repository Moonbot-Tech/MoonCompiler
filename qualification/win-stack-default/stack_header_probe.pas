program stack_header_probe;

{$ifdef FPC}
  {$mode delphi}
{$endif}

{$ifdef USE_MEMORY_DIRECTIVE}
  {$M 4194304}
{$endif}

{$ifdef USE_STACK_DIRECTIVES}
  {$MINSTACKSIZE 32768}
  {$MAXSTACKSIZE 3145728}
{$endif}

begin
  WriteLn('STACK_HEADER_PROBE_OK');
end.
