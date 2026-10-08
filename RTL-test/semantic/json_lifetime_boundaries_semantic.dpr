program json_lifetime_boundaries_semantic;
{$APPTYPE CONSOLE}
{$IFDEF FPC}{$mode delphiunicode}{$ENDIF}
{$RTTI EXPLICIT METHODS([vcPublic]) PROPERTIES([vcPublished]) FIELDS([])}
uses
  {$IFDEF UNIX}cthreads, cwstring,{$ENDIF}
  SysUtils, Classes, DateUtils, System.JSON.Readers, System.JSON.Serializers, System.JSON.Types;

procedure Check(Value: Boolean; const Context: string);
begin
  if not Value then raise Exception.Create(Context);
end;

type
  TTracked = class
  private
    FNumber: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AfterConstruction; override;
  published
    property Number: Integer read FNumber write FNumber;
  end;
  TChild = class(TTracked);
  TBroken = class(TTracked)
  public
    constructor Create;
  end;
  TTrackedArray = array of TTracked;
var
  Created, Destroyed, Completed: Integer;

constructor TTracked.Create;
begin
  inherited;
  Inc(Created);
  FNumber:=777;
end;

destructor TTracked.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

procedure TTracked.AfterConstruction;
begin
  inherited;
  Inc(Completed);
end;

constructor TBroken.Create;
begin
  inherited;
  raise Exception.Create('constructor boundary');
end;

procedure CheckConstruction;
var
  Serializer: TJsonSerializer;
  Value: TTracked;
  Child: TChild;
  Values: TTrackedArray;
  I, Before: Integer;
  Raised: Boolean;
begin
  Serializer:=TJsonSerializer.Create;
  Serializer.ContractResolver:=TJsonDefaultContractResolver.Create(TJsonMemberSerialization.&Public);
  try
    Value:=Serializer.Deserialize<TTracked>('{}');
    try
      Check((Value.Number=777) and (Created=1) and (Completed=1),'real constructor and AfterConstruction');
    finally Value.Free; end;
    Child:=Serializer.Deserialize<TChild>('{}');
    try
      Check((Child.ClassType=TChild) and (Child.Number=777),'inherited constructor and runtime class');
    finally Child.Free; end;
    Values:=Serializer.Deserialize<TTrackedArray>('[{}, {"Number":42}]');
    try
      Check((Length(Values)=2) and (Values[0].Number=777) and (Values[1].Number=42),'array constructors');
    finally for I:=0 to High(Values) do Values[I].Free; end;
    Check(Created=Destroyed,'successful ownership');
    Raised:=False;
    try Values:=Serializer.Deserialize<TTrackedArray>('[{},5]');
    except on E: Exception do Raised:=True; end;
    Check(Raised and (Created=Destroyed),'partial array cleanup');
    Before:=Created;
    Raised:=False;
    try Value:=Serializer.Deserialize<TBroken>('{}');
    except on E: Exception do Raised:=E.Message='constructor boundary'; end;
    Check(Raised and (Created=Before+1) and (Created=Destroyed),'throwing constructor cleanup');
  finally Serializer.Free; end;
end;

procedure CheckRead(const Input: string; Kind: Integer; Invalid: Boolean; UTC: Boolean = False);
var
  Source: TStringReader;
  Reader: TJsonTextReader;
  Raised: Boolean;
begin
  Source:=TStringReader.Create('{"x":'+Input+'}');
  Reader:=TJsonTextReader.Create(Source);
  Reader.CloseInput:=False;
  if UTC then Reader.DateTimeZoneHandling:=TJsonDateTimeZoneHandling.Utc;
  try
    Check((Reader.FormatSettings.ShortDateFormat='MM/dd/yyyy') and
      (Reader.FormatSettings.DateSeparator='/') and (Reader.FormatSettings.DecimalSeparator='.'),
      'JSON invariant reader defaults');
    Check(Reader.Read and Reader.Read,'reader positioning');
    Raised:=False;
    try
      case Kind of
        0: Check(Reader.ReadAsInteger=42,'integer value');
        1: Check(Reader.ReadAsInt64=5000000000,'int64 value');
        2: Check(Abs(Reader.ReadAsDouble-1.5)<1E-12,'double value');
        3: Check(Reader.ReadAsDateTime>EncodeDate(2024,1,1),'ISO date value');
        4: if UTC then
             Check(Reader.ReadAsDateTime=EncodeDate(2024,1,2),'invariant UTC date value')
           else
             Check(Reader.ReadAsDateTime=TTimeZone.Local.ToLocalTime(EncodeDate(2024,1,2)),
               'invariant local date value');
        5: Check(Abs(Reader.ReadAsDateTime-
             TTimeZone.Local.ToLocalTime(EncodeDateTime(2024,1,2,3,4,5,0)))<1E-9,'basic ISO datetime');
      end;
    except on E: EJsonReaderException do Raised:=True; end;
    Check(Raised=Invalid,'typed reader conversion exception');
  finally
    Reader.Free;
    Source.Free;
  end;
end;

var
  Kind: Integer;
  SavedSettings: TFormatSettings;
begin
  CheckConstruction;
  SavedSettings:=FormatSettings;
  try
    FormatSettings.DecimalSeparator:=',';
    FormatSettings.ShortDateFormat:='dd.MM.yyyy';
    FormatSettings.DateSeparator:='.';
    CheckRead('"42"',0,False);
    CheckRead('"5000000000"',1,False);
    CheckRead('"1.5"',2,False);
    CheckRead('"2024-01-02T03:04:05Z"',3,False);
    CheckRead('"01/02/2024"',4,False);
    CheckRead('"1/2/2024"',4,False);
    CheckRead('"01/02/2024"',4,False,True);
    CheckRead('"20240102T030405Z"',5,False);
    for Kind:=0 to 3 do CheckRead('"not a value"',Kind,True);
    CheckRead('"2024/01/02"',3,True);
    CheckRead('"2024-01-02 03:04:05"',3,True);
    CheckRead('"2147483648"',0,True);
    CheckRead('"9223372036854775808"',1,True);
  finally FormatSettings:=SavedSettings; end;
  WriteLn('JSON_LIFETIME_BOUNDARIES_PASS');
end.
