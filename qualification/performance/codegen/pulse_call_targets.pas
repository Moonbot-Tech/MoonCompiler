unit pulse_call_targets;

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

interface

type
  IPulseAdder = interface
    ['{0CF61331-B409-4B3D-8CF4-2C8D75DA7FF0}']
    function Add(Value: UInt64): UInt64;
  end;

  TPulseAdder = class(TInterfacedObject, IPulseAdder)
  public
    function Add(Value: UInt64): UInt64; virtual;
  end;

  TPulseVirtualAdder = class
  public
    function Add(Value: UInt64): UInt64; virtual;
  end;

function PulseDirectAdd(Value: UInt64): UInt64;
function PulseManyArgs(A0, A1, A2, A3, A4, A5, A6, A7: UInt64): UInt64;

implementation

function PulseDirectAdd(Value: UInt64): UInt64;
begin
  Result := (Value xor (Value shr 17)) + UInt64($9E3779B185EBCA87);
end;

function PulseManyArgs(A0, A1, A2, A3, A4, A5, A6, A7: UInt64): UInt64;
begin
  Result := A0 + A1 * 3 + A2 * 5 + A3 * 7 + A4 * 11 + A5 * 13 +
    A6 * 17 + A7 * 19;
end;

function TPulseAdder.Add(Value: UInt64): UInt64;
begin
  Result := PulseDirectAdd(Value);
end;

function TPulseVirtualAdder.Add(Value: UInt64): UInt64;
begin
  Result := PulseDirectAdd(Value);
end;

end.
