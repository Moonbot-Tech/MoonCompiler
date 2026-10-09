program lazarus_hash_contract;
{$mode objfpc}{$H+}{$R+}{$Q+}

uses SysUtils, LazEditHighlighterUtils;

type
  TRange = class(TLazHighlighterRangeForDictionary)
    Key: Integer;
    Hash: UInt32;
    procedure Assign(Src: TLazHighlighterRange); override;
    function Compare(Range: TLazHighlighterRange): Integer; override;
    function GetHashCode(AnInitVal: UInt32 = 0): UInt32; override;
    destructor Destroy; override;
  end;

var
  Destroyed: Integer;

procedure TRange.Assign(Src: TLazHighlighterRange);
begin
  Key := TRange(Src).Key;
  Hash := TRange(Src).Hash;
end;

function TRange.Compare(Range: TLazHighlighterRange): Integer;
begin
  Result := Key - TRange(Range).Key;
end;

function TRange.GetHashCode(AnInitVal: UInt32): UInt32;
begin
  Result := Hash;
end;

destructor TRange.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;

procedure Check(Hash: UInt32);
var
  Pool: TLazHighlighterRangesDictionary;
  Probe: TRange;
  Saved: array[1..64] of TLazHighlighterRange;
  I, Before: Integer;
begin
  Before := Destroyed;
  Pool := TLazHighlighterRangesDictionary.Create;
  Probe := TRange.Create(nil);
  try
    Probe.Hash := Hash;
    If Pool.GetEqual(nil) <> nil then
      raise Exception.Create('nil range');
    for I := 1 to 64 do begin
      Probe.Key := I;
      Saved[I] := Pool.GetEqual(Probe);
      If (Saved[I] = Probe) or (TRange(Saved[I]).Key <> I) then
        raise Exception.Create('range ownership or value');
    end;
    for I := 64 downto 1 do begin
      Probe.Key := I;
      If Pool.GetEqual(Probe) <> Saved[I] then
        raise Exception.Create('high-bit hash lookup or collision');
    end;
  finally
    Probe.Free;
    Pool.Free;
  end;
  If Destroyed - Before <> 65 then
    raise Exception.Create('range lifetime');
end;

begin
  Check($80000000);
  Check($FFFFFFFF);
  WriteLn('LAZARUS_HASH_CONTRACT_PASS');
end.
