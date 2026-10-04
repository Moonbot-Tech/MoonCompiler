unit explicit_memory_clear_unit;
{$IFDEF FPC}{$mode delphi}{$ENDIF}
{$INLINE ON}
interface
procedure ClearInline(var Key); inline;
implementation
procedure ClearInline(var Key);
begin
  FillChar(Key, 64, 0);
end;
end.
