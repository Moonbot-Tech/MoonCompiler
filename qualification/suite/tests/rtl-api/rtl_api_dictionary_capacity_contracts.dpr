program rtl_api_dictionary_capacity_contracts;

{$APPTYPE CONSOLE}
{$ifdef FPC}
  {$mode delphiunicode}
{$endif}

uses
  SysUtils,
  Generics.Collections;

procedure Check(Condition: Boolean; const Why: string);
begin
  If not Condition then
    raise Exception.Create(Why);
end;

procedure CheckReservation(Requested: Integer; UseConstructor: Boolean);
var
  Dictionary: TDictionary<Integer,Integer>;
  InitialCapacity, i, Value: Integer;
begin
  If UseConstructor then
    Dictionary := TDictionary<Integer,Integer>.Create(Requested)
  else begin
    Dictionary := TDictionary<Integer,Integer>.Create;
    Dictionary.Capacity := Requested;
  end;
  try
    InitialCapacity := Dictionary.Capacity;
    for i := 0 to Requested-1 do
    begin
      Dictionary.Add(i,i*3);
      Check(Dictionary.Capacity=InitialCapacity,'reserved additions must not grow the table');
    end;
    Check(Dictionary.Count=Requested,'reserved dictionary count');
    for i := 0 to Requested-1 do
    begin
      Check(Dictionary.TryGetValue(i,Value),'reserved dictionary lookup');
      Check(Value=i*3,'reserved dictionary value');
    end;
  finally
    Dictionary.Free;
  end;
end;

const
  Requests: array[0..6] of Integer = (1,7,8,16,512,1024,4096);
var
  Requested: Integer;
begin
  for Requested in Requests do
  begin
    CheckReservation(Requested,True);
    CheckReservation(Requested,False);
  end;
  Writeln('RTL_API_DICTIONARY_CAPACITY_CONTRACTS_OK');
end.
