program dictionary_rehash_ownership_semantic;

{$mode delphiunicode}{$H+}

uses SysUtils, Generics.Collections, Generics.Defaults, Generics.MemoryExpanders;

type
  ITracked = interface
    ['{8D970A16-AF29-4F7B-B068-F56ECB802530}']
    function Number: Integer;
  end;
  TTracked = class(TInterfacedObject, ITracked)
    Id: Integer;
    constructor Create(AId: Integer);
    destructor Destroy; override;
    function Number: Integer;
  end;
  TAssignOnly = record
    Value: Integer;
    class operator Assign(var Dest: TAssignOnly; const [ref] Source: TAssignOnly);
  end;
  TThrowProbe = class(TLinearProbing)
    class function Probe(I, Hash: UInt32): UInt32; static;
  end;

var
  Live, Copies, ProbeCalls: Integer;
  ThrowProbe: Boolean;

procedure Check(Value: Boolean; const What: string);
begin
  if not Value then
  begin
    WriteLn('FAILED: ', What);
    Halt(1);
  end;
end;

constructor TTracked.Create(AId: Integer);
begin
  inherited Create;
  Id := AId;
  Inc(Live);
end;

destructor TTracked.Destroy;
begin
  Dec(Live);
  inherited;
end;

function TTracked.Number: Integer;
begin
  Result := Id;
end;

class operator TAssignOnly.Assign(var Dest: TAssignOnly; const [ref] Source: TAssignOnly);
begin
  Inc(Copies);
  Dest.Value := Source.Value;
end;

class function TThrowProbe.Probe(I, Hash: UInt32): UInt32;
begin
  if ThrowProbe then
  begin
    Inc(ProbeCalls);
    if ProbeCalls = 3 then raise Exception.Create('probe failure');
  end;
  Result := I + Hash;
end;

function ReadNumber(D: TDictionary<UnicodeString, ITracked>; const Key: UnicodeString): Integer;
begin
  Result := D[Key].Number;
end;

procedure AddOwned(D: TDictionary<UnicodeString, ITracked>; Id: Integer);
begin
  D.Add(IntToStr(Id), TTracked.Create(Id));
end;

var
  D: TDictionary<UnicodeString, ITracked>;
  R: TDictionary<Integer, TAssignOnly>;
  P: TOpenAddressingLP<Integer, UnicodeString, TDefaultHashFactory, TThrowProbe>;
  Owners: array[0..31] of ITracked;
  Item: TAssignOnly;
  I, Round: Integer;
  Raised: Boolean;
begin
  D := TDictionary<UnicodeString, ITracked>.Create;
  for I := 0 to High(Owners) do
  begin
    Owners[I] := TTracked.Create(I);
    D.Add(IntToStr(I), Owners[I]);
  end;
  for Round := 1 to 4 do
  begin
    D.Capacity := 64 shl Round;
    D.TrimExcess;
    Check((Live = Length(Owners)) and (D.Count = Length(Owners)), 'rehash keeps owners');
    for I := 0 to High(Owners) do Check(ReadNumber(D, IntToStr(I)) = I, 'rehash keeps payload');
  end;
  D.Clear;
  Check(Live = Length(Owners), 'clear keeps external owners');
  D.Free;
  for I := 0 to High(Owners) do Owners[I] := nil;
  Check(Live = 0, 'all owners released');

  D := TDictionary<UnicodeString, ITracked>.Create;
  for I := 0 to 15 do AddOwned(D, I);
  D.Capacity := 256;
  Check(Live = 16, 'rehash keeps dictionary-only owners');
  D.Clear;
  Check(Live = 0, 'clear releases dictionary-only owners');
  D.Free;

  Check(IsManagedType(TAssignOnly), 'Assign-only record is managed');
  R := TDictionary<Integer, TAssignOnly>.Create;
  for I := 0 to 15 do
  begin
    Item.Value := I;
    R.Add(I, Item);
  end;
  Copies := 0;
  R.Capacity := 256;
  Check(Copies >= 16, 'rehash invokes custom Assign');
  for I := 0 to 15 do Check(R[I].Value = I, 'custom Assign payload');
  R.Free;

  P := TOpenAddressingLP<Integer, UnicodeString, TDefaultHashFactory, TThrowProbe>.Create;
  for I := 0 to 5 do P.Add(I, 'value-' + IntToStr(I));
  ThrowProbe := True;
  Raised := False;
  try
    P.Capacity := 256;
  except
    on E: Exception do Raised := E.Message = 'probe failure';
  end;
  ThrowProbe := False;
  Check(Raised and (P.Count = 6), 'custom Probe exception');
  for I := 0 to 5 do Check(P[I] = 'value-' + IntToStr(I), 'custom Probe keeps old payload');
  P.Free;
  WriteLn('DICTIONARY_REHASH_OWNERSHIP_OK');
end.
