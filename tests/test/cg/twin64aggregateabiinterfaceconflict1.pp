{ %CPU=x86_64 }
{ %FAIL }
program twin64aggregateabiinterfaceconflict1;

{$mode objfpc}

{$ifdef WIN64}
uses
  uwin64aggregateabilegacy1,
  uwin64aggregateabidelphiinterface1;

type
  TConflictingReader = class(TInterfacedObject, ILegacyRead8, IDelphiRead8)
    function Read8(const Value: TRec8): QWord;
    function ReadArray8(const Value: TArray8): QWord;
  end;

function TConflictingReader.Read8(const Value: TRec8): QWord;
begin
  Result:=Value.Bits;
end;

function TConflictingReader.ReadArray8(const Value: TArray8): QWord;
begin
  Result:=0;
  Move(Value,Result,SizeOf(Value));
end;
{$else WIN64}
{$error This negative ABI test applies to Win64 only}
{$endif WIN64}

begin
end.
