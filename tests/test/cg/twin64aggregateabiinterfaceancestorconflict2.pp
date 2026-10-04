{ %CPU=x86_64 }
{ %FAIL }
program twin64aggregateabiinterfaceancestorconflict2;

{$mode unleashed}

{$ifdef WIN64}
uses
  uwin64aggregateabidelphivirtual1,
  uwin64aggregateabilegacyinterface1;

type
  TConflictingInheritedReader = class(TDelphiInterfaceBase, ILegacyDelphiRead8);
{$else WIN64}
{$error This negative ABI test applies to Win64 only}
{$endif WIN64}

begin
end.
