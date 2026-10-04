{ %CPU=x86_64 }
{ %FAIL }
program twin64aggregateabiinterfaceancestorconflict1;

{$mode objfpc}

{$ifdef WIN64}
uses
  uwin64aggregateabilegacy1,
  uwin64aggregateabidelphiinterface1;

type
  TConflictingInheritedReader = class(TLegacyInterfaceBase, IDelphiRead8);
{$else WIN64}
{$error This negative ABI test applies to Win64 only}
{$endif WIN64}

begin
end.
