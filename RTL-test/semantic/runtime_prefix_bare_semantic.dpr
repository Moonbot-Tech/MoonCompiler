program runtime_prefix_bare_semantic;

{$mode delphi}

{ No uses clause: even a bare product program must receive the exact runtime
  prefix from the compiler rather than from source boilerplate. }
begin
  WriteLn('RUNTIME_PREFIX_BARE_OK');
end.
