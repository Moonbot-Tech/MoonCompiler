program json_public_members_semantic;
{$ifdef FPC}{$mode delphiunicode}{$endif}

{$APPTYPE CONSOLE}

uses
  SysUtils, System.JSON.Serializers;

type
  {$RTTI EXPLICIT FIELDS([vcPrivate, vcPublic]) PROPERTIES([vcPublic])}
  TStrategyBase = class
  private
    FMarker: Integer;
  public
    Ancestor: Integer;
    property Marker: Integer read FMarker write FMarker;
  end;

  TStrategy = class(TStrategyBase)
  private
    [JsonIn]
    OptIn: Integer;
  public
    [JsonIgnore]
    Omitted: Integer;
    Ordinary: Integer;
  end;
  {$RTTI INHERIT}

const
  Wire = '{"Ancestor":11,"OptIn":22,"Omitted":33,"Ordinary":44,"Marker":101}';

function Check(Mode: TJsonMemberSerialization; IncludeAncestor, IncludeOptIn, IncludeOrdinary: Boolean): Boolean;
var
  Serializer: TJsonSerializer;
  Decoded, Outgoing: TStrategy;
  Encoded: string;
begin
  Serializer := TJsonSerializer.Create;
  Outgoing := nil;
  Decoded := nil;
  try
    Serializer.ContractResolver := TJsonDefaultContractResolver.Create(Mode);
    Decoded := Serializer.Deserialize<TStrategy>(Wire);
    Outgoing := TStrategy.Create;
    Outgoing.Ancestor := 51;
    Outgoing.OptIn := 62;
    Outgoing.Omitted := 73;
    Outgoing.Ordinary := 84;
    Outgoing.Marker := 202;
    Encoded := Serializer.Serialize<TStrategy>(Outgoing);
    Writeln('mode=', Ord(Mode), ' read ancestor=', Decoded.Ancestor, ' opt-in=', Decoded.OptIn,
      ' ignored=', Decoded.Omitted, ' ordinary=', Decoded.Ordinary, ' write=', Encoded);
    Result := (Decoded.Marker=101*Ord(Mode=TJsonMemberSerialization.&Public))
      and ((Pos('"Marker":202',Encoded)>0)=(Mode=TJsonMemberSerialization.&Public))
      and (Decoded.Ancestor = 11 * Ord(IncludeAncestor)) and (Decoded.OptIn = 22 * Ord(IncludeOptIn))
      and (Decoded.Omitted = 0) and (Decoded.Ordinary = 44 * Ord(IncludeOrdinary))
      and ((Pos('"Ancestor":51', Encoded) > 0) = IncludeAncestor)
      and ((Pos('"OptIn":62', Encoded) > 0) = IncludeOptIn)
      and (Pos('"Omitted"', Encoded) = 0)
      and ((Pos('"Ordinary":84', Encoded) > 0) = IncludeOrdinary);
  finally
    Outgoing.Free;
    Decoded.Free;
    Serializer.Free;
  end;
end;

type
  {$RTTI EXPLICIT FIELDS([vcPublic])}
  TWireRecord = record
  public
    [JsonName('strategy_id')]
    ID: Int64;
    Title: UnicodeString;
  end;
  {$RTTI INHERIT}

const
  RecordInput = '{"strategy_id":9007199254740993,"Title":"strategy"}';

function CheckRecord(Mode: TJsonMemberSerialization): Boolean;
var
  Serializer: TJsonSerializer;
  Strategy: TWireRecord;
  Output: string;
begin
  Serializer := TJsonSerializer.Create;
  try
    Serializer.ContractResolver := TJsonDefaultContractResolver.Create(Mode);
    Strategy := Serializer.Deserialize<TWireRecord>(RecordInput);
    Output := Serializer.Serialize<TWireRecord>(Strategy);
    Writeln('mode=', Ord(Mode), ' id=', Strategy.ID, ' title=', Strategy.Title, ' output=', Output);
    Result := (Strategy.ID = 9007199254740993) and (Strategy.Title = 'strategy')
      and (Pos('"strategy_id":9007199254740993', Output) > 0) and (Pos('"Title":"strategy"', Output) > 0);
  finally
    Serializer.Free;
  end;
end;

begin
  If not CheckRecord(TJsonMemberSerialization.&Public) or not CheckRecord(TJsonMemberSerialization.Fields) then
    Halt(8);
  If not Check(TJsonMemberSerialization.&Public, True, False, True) then
    ExitCode := ExitCode or 1;
  If not Check(TJsonMemberSerialization.Fields, True, True, True) then
    ExitCode := ExitCode or 2;
  If not Check(TJsonMemberSerialization.&In, False, True, False) then
    ExitCode := ExitCode or 4;
  if ExitCode=0 then WriteLn('JSON_PUBLIC_MEMBERS_PASS');
end.
