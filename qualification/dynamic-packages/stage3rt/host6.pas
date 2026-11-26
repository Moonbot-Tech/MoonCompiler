program host6;

{$mode delphi}

uses
  Windows;

var
  GLib: HMODULE;
begin
  WriteLn('LoadLibrary...');
  GLib := LoadLibrary('SalesPkg.fpl');
  WriteLn('  handle <> 0 : ', GLib <> 0);
  WriteLn('FreeLibrary...');
  WriteLn('  result      : ', FreeLibrary(GLib));
  WriteLn('host6 ok');
end.
