program json_navigation_contract_semantic;
{$mode delphiunicode}{$H+}
uses mormot.core.fpcx64mm, {$IFDEF UNIX}cthreads,cwstring,{$ENDIF}
  System.SysUtils, System.Classes, System.Rtti, System.TypInfo, System.JSON, System.JSON.Types,
  System.JSON.Readers, System.JSON.Writers, System.JSON.Builders, System.JSON.Serializers;
type
  TPoint = record X,Y: Integer; end;
  TCreated = class
  public
    X: Integer;
    destructor Destroy; override;
  end;
  TPoolCreator = class(TInterfacedObject,IJsonCreator)
    function Invoke(const Params:array of TValue):TValue;
    procedure Release(var Value:TValue);
  end;
  TPoolResolver = class(TJsonDefaultContractResolver)
    function CreateObjectContract(ATypeInf:PTypeInfo):TJsonObjectContract; override;
  end;
  EConverterFailure = class(Exception);
  TBorrowedConverter = class(TJsonConverter)
    function CanConvert(ATypeInf:PTypeInfo):Boolean; override;
    function ReadJson(const aReader:TJsonReader; aTypeInf:PTypeInfo; const aExistingValue:TValue;
      const aSerializer:TJsonSerializer):TValue; override;
    procedure WriteJson(const aWriter:TJsonWriter; const aValue:TValue;
      const aSerializer:TJsonSerializer); override;
  end;
var Destroyed,Released: Integer; Pooled:TCreated; FailConverter:Boolean;
procedure Check(OK: Boolean; const Name: string);
begin
  if not OK then raise Exception.Create('JSON_NAVIGATION: '+Name);
end;
destructor TCreated.Destroy;
begin Inc(Destroyed); inherited; end;

function TPoolCreator.Invoke(const Params:array of TValue):TValue;
begin Result:=TValue.From<TObject>(Pooled); end;
procedure TPoolCreator.Release(var Value:TValue);
begin Inc(Released); Value:=TValue.Empty; end;
function TPoolResolver.CreateObjectContract(ATypeInf:PTypeInfo):TJsonObjectContract;
begin
  Result:=inherited;
  if ATypeInf=TypeInfo(TCreated) then Result.DefaultCreator:=TPoolCreator.Create;
end;
function TBorrowedConverter.CanConvert(ATypeInf:PTypeInfo):Boolean;
begin Result:=ATypeInf=TypeInfo(TCreated); end;
function TBorrowedConverter.ReadJson(const aReader:TJsonReader; aTypeInf:PTypeInfo;
  const aExistingValue:TValue; const aSerializer:TJsonSerializer):TValue;
begin
  if FailConverter then raise EConverterFailure.Create('application failure');
  aReader.Skip;
  Result:=TValue.From<TObject>(Pooled);
end;
procedure TBorrowedConverter.WriteJson(const aWriter:TJsonWriter; const aValue:TValue;
  const aSerializer:TJsonSerializer);
begin raise ENotSupportedException.Create('read-only fixture'); end;

procedure Traverse;
const Data='{"a":1,"nested":{"x":2},"arr":[3,{"y":4}],"z":5}';
var Source: TStringReader; Reader: TJsonReader; It: TJSONIterator;
  Root: TJSONValue; Backend: Integer;
begin
  for Backend:=0 to 1 do begin
    Root:=nil; Source:=nil;
    if Backend=0 then begin
      Source:=TStringReader.Create(Data);
      Reader:=TJsonTextReader.Create(Source);
      Reader.CloseInput:=False;
    end else begin
      Root:=TJSONValue.ParseJSONValue(Data);
      Reader:=TJsonObjectReader.Create(Root);
    end;
    It:=TJSONIterator.Create(Reader,procedure(R:TJsonReader) begin R.Rewind; end);
    try
      Check(not It.Recurse,'nothing to recurse before first Next');
      Check(It.Next and (It.Key='a') and (It.AsInteger=1),'first property');
      Check((It.Depth=1) and (It.ParentType=TJsonToken.StartObject),'root state');
      Check(It.Next and (It.Key='nested') and It.Recurse,'enter nested');
      Check(It.Next and (It.Path='nested.x') and (It.AsInteger=2),'nested property');
      Check(not It.Next and (It.Depth=1),'natural end returns parent');
      It.Return;
      Check(It.Next and (It.Key='arr') and It.Recurse,'parent continues');
      Check(It.Next and (It.Index=0) and (It.AsInteger=3),'array first');
      Check(It.Next and (It.Index=1) and It.Recurse,'array object');
      Check(It.Next and (It.Path='arr[1].y') and (It.AsInteger=4),'nested array object');
      It.Return;
      Check(not It.Next and (It.Depth=1),'manual return and array end');
      Check(It.Next and (It.Key='z') and (It.AsInteger=5),'continue without redundant Return');
      Check(not It.Next and not It.InRecurse,'root done');
      Check(not It.Next,'EOF stable');
      Check(It.Find('arr[1].y') and (It.AsInteger=4),'find nested');
      Check(not It.Find('nested.missing'),'find missing');
      It.Rewind;
      Check(It.Next('z') and (It.AsInteger=5),'skip unentered containers');
    finally It.Free; Reader.Free; Source.Free; Root.Free; end;
  end;
end;

procedure SerializerErrors;
var S: TJsonSerializer; P: TPoint; O: TCreated; Failed: Boolean;
  R: TJsonTextReader; Text: TStringReader;
  Objects:TArray<TCreated>; Nested:TArray<TArray<TCreated>>; Before:Integer;
begin
  S:=TJsonSerializer.Create;
  try
    P:=S.Deserialize<TPoint>('{"X":3,"Y":4}');
    Check((P.X=3) and (P.Y=4),'record control');
    Failed:=False;
    try P:=S.Deserialize<TPoint>('{"X":3,'); except on E:EJsonSerializationException do Failed:=True; end;
    Check(Failed,'string input error class');
    Text:=TStringReader.Create('{"X":');
    try
      Failed:=False;
      try P:=S.Deserialize<TPoint>(Text); except on E:EJsonSerializationException do Failed:=True; end;
      Check(Failed,'borrowed text reader error');
      Text.Rewind;
      Check(Text.Read=Ord('{'),'borrowed reader survives');
    finally Text.Free; end;
    Text:=TStringReader.Create('{"X":3,');
    R:=TJsonTextReader.Create(Text);
    try
      Failed:=False;
      try P:=S.Deserialize<TPoint>(R); except on E:EJsonSerializationException do Failed:=True; end;
      Check(Failed,'JSON reader error class');
    finally R.Free; end;
    Failed:=False;
    try O:=S.Deserialize<TCreated>('{"X":3,'); O.Free;
    except on E:EJsonSerializationException do Failed:=True; end;
    Check(Failed and (Destroyed=1),'failed new root object released');
    Before:=Destroyed;
    Failed:=False;
    try Objects:=S.Deserialize<TArray<TCreated>>('[{"X":1},{"X":');
    except on E:EJsonSerializationException do Failed:=True; end;
    Check(Failed and (Destroyed=Before+2),'failed array releases completed and incomplete elements');
    Before:=Destroyed;
    Failed:=False;
    try Nested:=S.Deserialize<TArray<TArray<TCreated>>>('[[{"X":1}],[{"X":');
    except on E:EJsonSerializationException do Failed:=True; end;
    Check(Failed and (Destroyed=Before+2),'failed nested array releases constructed objects');
  finally S.Free; end;
end;

procedure CustomOwnership;
var S:TJsonSerializer; Items:TArray<TCreated>; O:TCreated; Before:Integer; Failed:Boolean;
begin
  Pooled:=TCreated.Create;
  Before:=Destroyed;
  S:=TJsonSerializer.Create;
  try
    S.ContractResolver:=TPoolResolver.Create;
    Failed:=False;
    try O:=S.Deserialize<TCreated>('{"X":');
    except on E:EJsonSerializationException do Failed:=True; end;
    Check(Failed and (Released=1) and (Destroyed=Before),'creator release owns failed root');
    Failed:=False;
    try Items:=S.Deserialize<TArray<TCreated>>('[{"X":1},{"X":');
    except on E:EJsonSerializationException do Failed:=True; end;
    Check(Failed and (Released=3) and (Destroyed=Before),'declared creator releases array elements');
    S.ContractResolver:=TJsonDefaultContractResolver.Create;
    S.Converters.Add(TBorrowedConverter.Create);
    Failed:=False;
    try Items:=S.Deserialize<TArray<TCreated>>('[{},');
    except on E:EJsonSerializationException do Failed:=True; end;
    Check(Failed and (Destroyed=Before),'converter owns its returned objects');
    FailConverter:=True;
    Failed:=False;
    try O:=S.Deserialize<TCreated>('{}');
    except on E:EConverterFailure do Failed:=True; end;
    Check(Failed,'application converter exception is not translated');
  finally S.Free; Pooled.Free; Pooled:=nil; end;
end;
begin
  Traverse;
  SerializerErrors;
  CustomOwnership;
  WriteLn('JSON_NAVIGATION_CONTRACT_PASS');
end.
