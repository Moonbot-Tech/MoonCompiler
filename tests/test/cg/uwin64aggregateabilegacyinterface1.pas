unit uwin64aggregateabilegacyinterface1;

{$mode objfpc}

interface

uses
  uwin64aggregateabidelphivirtual1;

type
  ILegacyDelphiRead8 = interface
    ['{410D241B-452E-48CF-A6F4-4DFC60B42C7F}']
    function Read8(const Value: TDelphiRec8): QWord;
  end;

implementation

end.
