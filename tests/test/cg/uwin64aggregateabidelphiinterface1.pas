unit uwin64aggregateabidelphiinterface1;

{$mode unleashed}

interface

uses
  uwin64aggregateabilegacy1;

type
  IDelphiRead8 = interface
    ['{CC56EF4B-EAAB-487F-BDF6-C1B7CD61991A}']
    function Read8(const Value: TRec8): QWord;
    function ReadArray8(const Value: TArray8): QWord;
  end;

implementation

end.
