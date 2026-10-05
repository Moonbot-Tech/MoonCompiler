{
    This file is part of the Free Component Library
    Copyright (c) 2026 by Michael Van Canneyt michael@freepascal.org

    Delphi-compatible JSON BUilder (Fluid API) unit

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
unit System.JSON.Builders;

{$mode objfpc}
{$h+}
{$modeswitch functionreferences}
{$modeswitch advancedrecords}

interface

uses
  {$IFDEF FPC_DOTTEDUNITS}
  System.Rtti, System.SysUtils, System.Classes, System.Types, System.Generics.Collections,
  {$ELSE}
  Rtti, SysUtils, Classes, Types, Generics.Collections,
  {$ENDIF }
  System.JSON.Writers, System.JSON, System.JSON.Types, System.JSON.Readers;

type
  EJSONCollectionBuilderError = class(Exception);
  EJSONIteratorError = class(Exception);

  TJSONCollectionBuilder = class abstract
  public type

    TElements = class;
    TPairs = class;
    TParentCollection = class;

    TBaseCollection = class
    strict private
      FOwner: TJSONCollectionBuilder;
      FRootDepth: Integer;
      FWriter: TJSONWriter;
    private
      procedure addingElement;
      procedure addingPair;
      class procedure ErrorInvalidSetOfItems; static;
      procedure WriteVarRec(const aValue: TVarRec);
      procedure WriteVariant(const aValue: Variant);
      procedure WriteOpenArray(const aItems: array of const);
      function WriteReader(const aReader: TJsonReader; aOnlyEnclosed: Boolean): Boolean;
      procedure WriteBuilder(const aBuilder: TJSONCollectionBuilder);
      procedure WriteJSON(const aJSON: string);

      function add(const aValue: string): TElements; overload;
      function add(const aValue: Int32): TElements; overload;
      function add(const aValue: UInt32): TElements; overload;
      function add(const aValue: Int64): TElements; overload;
      function add(const aValue: UInt64): TElements; overload;
      function add(const aValue: Single): TElements; overload;
      function add(const aValue: Double): TElements; overload;
{$IFDEF FPC_HAS_TYPE_EXTENDED}
      function add(const aValue: Extended): TElements; overload;
{$ENDIF FPC_HAS_TYPE_EXTENDED}
      function add(const aValue: Boolean): TElements; overload;
      function add(const aValue: Char): TElements; overload;
      function add(const aValue: Byte): TElements; overload;
      function add(const aValue: TDateTime): TElements; overload;
      function add(const aValue: TGUID): TElements; overload;
      function add(const aValue: TBytes;
        aBinaryType: TJsonBinaryType = TJsonBinaryType.Generic): TElements; overload;
      function add(const aValue: TJsonOid): TElements; overload;
      function add(const aValue: TJsonRegEx): TElements; overload;
      function add(const aValue: TJsonDBRef): TElements; overload;
      function add(const aValue: TJsonCodeWScope): TElements; overload;
      function add(const aValue: TJsonDecimal128): TElements; overload;
      function add(const aValue: TValue): TElements; overload;
      function add(const aValue: TVarRec): TElements; overload;
      function add(const aValue: Variant): TElements; overload;
      function addElements(const aElements: array of const): TElements; overload;
      function addElements(const aBuilder: TJSONCollectionBuilder): TElements; overload;
      function addElements(const aJSON: string): TElements; overload;
      function addNull: TElements; overload;
      function addUndefined: TElements; overload;
      function addMinKey: TElements; overload;
      function addMaxKey: TElements; overload;

      function add(const aKey: string; const aValue: string): TPairs; overload;
      function add(const aKey: string; const aValue: Int32): TPairs; overload;
      function add(const aKey: string; const aValue: UInt32): TPairs; overload;
      function add(const aKey: string; const aValue: Int64): TPairs; overload;
      function add(const aKey: string; const aValue: UInt64): TPairs; overload;
      function add(const aKey: string; const aValue: Single): TPairs; overload;
      function add(const aKey: string; const aValue: Double): TPairs; overload;
{$IFDEF FPC_HAS_TYPE_EXTENDED}
      function add(const aKey: string; const aValue: Extended): TPairs; overload;
{$ENDIF FPC_HAS_TYPE_EXTENDED}
      function add(const aKey: string; const aValue: Boolean): TPairs; overload;
      function add(const aKey: string; const aValue: Char): TPairs; overload;
      function add(const aKey: string; const aValue: Byte): TPairs; overload;
      function add(const aKey: string; const aValue: TDateTime): TPairs; overload;
      function add(const aKey: string; const aValue: TGUID): TPairs; overload;
      function add(const aKey: string; const aValue: TBytes;
        aBinaryType: TJsonBinaryType = TJsonBinaryType.Generic): TPairs; overload;
      function add(const aKey: string; const aValue: TJsonOid): TPairs; overload;
      function add(const aKey: string; const aValue: TJsonRegEx): TPairs; overload;
      function add(const aKey: string; const aValue: TJsonDBRef): TPairs; overload;
      function add(const aKey: string; const aValue: TJsonCodeWScope): TPairs; overload;
      function add(const aKey: string; const aValue: TJsonDecimal128): TPairs; overload;
      function add(const aKey: string; const aValue: TValue): TPairs; overload;
      function add(const aKey: string; const aValue: TVarRec): TPairs; overload;
      function add(const aKey: string; const aValue: Variant): TPairs; overload;
      function addPairs(const aPairs: array of const): TPairs; overload;
      function addPairs(const aBuilder: TJSONCollectionBuilder): TPairs; overload;
      function addPairs(const aJSON: string): TPairs; overload;
      function addNull(const aKey: string): TPairs; overload;
      function addUndefined(const aKey: string): TPairs; overload;
      function addMinKey(const aKey: string): TPairs; overload;
      function addMaxKey(const aKey: string): TPairs; overload;

      function EndArray: TParentCollection;  
      function EndObject: TParentCollection;  

      function BeginObject: TPairs; overload;
      function BeginArray: TElements; overload;
      function BeginObject(const aKey: string): TPairs; overload;
      function BeginArray(const aKey: string): TElements; overload;

      property Owner: TJSONCollectionBuilder read FOwner;
      property Writer: TJSONWriter read FWriter;
      property RootDepth: Integer read FRootDepth;
    public
      constructor Create(const aOwner: TJSONCollectionBuilder; const aRootDepth: Integer);
      procedure EndAll;
      function Ended: Boolean;
    end;

    TElements = class(TBaseCollection)
    public
      function add(const aValue: string): TElements; overload; inline;
      function add(const aValue: Int32): TElements; overload; inline;
      function add(const aValue: UInt32): TElements; overload; inline;
      function add(const aValue: Int64): TElements; overload; inline;
      function add(const aValue: UInt64): TElements; overload; inline;
      function add(const aValue: Single): TElements; overload; inline;
      function add(const aValue: Double): TElements; overload; inline;
{$IFDEF FPC_HAS_TYPE_EXTENDED}
      function add(const aValue: Extended): TElements; overload; inline;
{$ENDIF FPC_HAS_TYPE_EXTENDED}
      function add(const aValue: Boolean): TElements; overload; inline;
      function add(const aValue: Char): TElements; overload; inline;
      function add(const aValue: Byte): TElements; overload; inline;
      function add(const aValue: TDateTime): TElements; overload; inline;
      function add(const aValue: TGUID): TElements; overload; inline;
      function add(const aValue: TBytes;
        aBinaryType: TJsonBinaryType = TJsonBinaryType.Generic): TElements; overload; inline;
      function add(const aValue: TJsonOid): TElements; overload; inline;
      function add(const aValue: TJsonRegEx): TElements; overload; inline;
      function add(const aValue: TJsonDBRef): TElements; overload; inline;
      function add(const aValue: TJsonCodeWScope): TElements; overload; inline;
      function add(const aValue: TJsonDecimal128): TElements; overload; inline;
      function add(const aValue: TValue): TElements; overload; inline;
      function add(const aValue: TVarRec): TElements; overload; inline;
      function add(const aValue: Variant): TElements; overload; inline;
      function addNull: TElements; inline;
      function addUndefined: TElements; inline;
      function addMinKey: TElements; inline;
      function addMaxKey: TElements; inline;
      function addElements(const aElements: array of const): TElements; overload;
      function addElements(const aBuilder: TJSONCollectionBuilder): TElements; overload; inline;
      function addElements(const aJSON: string): TElements; overload; inline;

      function BeginObject: TPairs; overload; inline;
      function BeginArray: TElements; overload; inline;
      function EndArray: TParentCollection; inline; 

      function asRoot: TElements;
    end;

    TPairs = class(TBaseCollection)
    public
      function add(const aKey: string; const aValue: string): TPairs; overload; inline;
      function add(const aKey: string; const aValue: Int32): TPairs; overload; inline;
      function add(const aKey: string; const aValue: UInt32): TPairs; overload; inline;
      function add(const aKey: string; const aValue: Int64): TPairs; overload; inline;
      function add(const aKey: string; const aValue: UInt64): TPairs; overload; inline;
      function add(const aKey: string; const aValue: Single): TPairs; overload; inline;
      function add(const aKey: string; const aValue: Double): TPairs; overload; inline;
{$IFDEF FPC_HAS_TYPE_EXTENDED}
      function add(const aKey: string; const aValue: Extended): TPairs; overload; inline;
{$ENDIF FPC_HAS_TYPE_EXTENDED}
      function add(const aKey: string; const aValue: Boolean): TPairs; overload; inline;
      function add(const aKey: string; const aValue: Char): TPairs; overload; inline;
      function add(const aKey: string; const aValue: Byte): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TDateTime): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TGUID): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TBytes;
        aBinaryType: TJsonBinaryType = TJsonBinaryType.Generic): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TJsonOid): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TJsonRegEx): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TJsonDBRef): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TJsonCodeWScope): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TJsonDecimal128): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TValue): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TVarRec): TPairs; overload; inline;
      function add(const aKey: string; const aValue: Variant): TPairs; overload; inline;
      function addNull(const aKey: string): TPairs; inline;
      function addUndefined(const aKey: string): TPairs; inline;
      function addMinKey(const aKey: string): TPairs; inline;
      function addMaxKey(const aKey: string): TPairs; inline;
      function addPairs(const aPairs: array of const): TPairs; overload;
      function addPairs(const aBuilder: TJSONCollectionBuilder): TPairs; overload; inline;
      function addPairs(const aJSON: string): TPairs; overload; inline;

      function BeginObject(const aKey: string): TPairs; overload; inline;
      function BeginArray(const aKey: string): TElements; overload; inline;
      function EndObject: TParentCollection; inline; 

      function asRoot: TPairs;
    end;

    TParentCollection = class(TBaseCollection)
    public
      function add(const aValue: string): TElements; overload; inline;
      function add(const aValue: Int32): TElements; overload; inline;
      function add(const aValue: UInt32): TElements; overload; inline;
      function add(const aValue: Int64): TElements; overload; inline;
      function add(const aValue: UInt64): TElements; overload; inline;
      function add(const aValue: Single): TElements; overload; inline;
      function add(const aValue: Double): TElements; overload; inline;
{$IFDEF FPC_HAS_TYPE_EXTENDED}
      function add(const aValue: Extended): TElements; overload; inline;
{$ENDIF FPC_HAS_TYPE_EXTENDED}
      function add(const aValue: Boolean): TElements; overload; inline;
      function add(const aValue: Char): TElements; overload; inline;
      function add(const aValue: Byte): TElements; overload; inline;
      function add(const aValue: TDateTime): TElements; overload; inline;
      function add(const aValue: TGUID): TElements; overload; inline;
      function add(const aValue: TBytes;
        aBinaryType: TJsonBinaryType = TJsonBinaryType.Generic): TElements; overload; inline;
      function add(const aValue: TJsonOid): TElements; overload; inline;
      function add(const aValue: TJsonRegEx): TElements; overload; inline;
      function add(const aValue: TJsonDBRef): TElements; overload;
      function add(const aValue: TJsonCodeWScope): TElements; overload;
      function add(const aValue: TJsonDecimal128): TElements; overload;
      function add(const aValue: TValue): TElements; overload; inline;
      function add(const aValue: TVarRec): TElements; overload; inline;
      function add(const aValue: Variant): TElements; overload; inline;
      function addNull: TElements; overload; inline;
      function addUndefined: TElements; overload; inline;
      function addMinKey: TElements; overload; inline;
      function addMaxKey: TElements; overload; inline;
      function addElements(const aElements: array of const): TElements; overload;
      function addElements(const aBuilder: TJSONCollectionBuilder): TElements; overload; inline;
      function addElements(const aJSON: string): TElements; overload; inline;

      function add(const aKey: string; const aValue: string): TPairs; overload; inline;
      function add(const aKey: string; const aValue: Int32): TPairs; overload; inline;
      function add(const aKey: string; const aValue: UInt32): TPairs; overload; inline;
      function add(const aKey: string; const aValue: Int64): TPairs; overload; inline;
      function add(const aKey: string; const aValue: UInt64): TPairs; overload; inline;
      function add(const aKey: string; const aValue: Single): TPairs; overload; inline;
      function add(const aKey: string; const aValue: Double): TPairs; overload; inline;
{$IFDEF FPC_HAS_TYPE_EXTENDED}
      function add(const aKey: string; aValue: Extended): TPairs; overload; inline;
{$ENDIF FPC_HAS_TYPE_EXTENDED}
      function add(const aKey: string; aValue: Boolean): TPairs; overload; inline;
      function add(const aKey: string; aValue: Char): TPairs; overload; inline;
      function add(const aKey: string; aValue: Byte): TPairs; overload; inline;
      function add(const aKey: string; aValue: TDateTime): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TGUID): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TBytes;
        aBinaryType: TJsonBinaryType = TJsonBinaryType.Generic): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TJsonOid): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TJsonRegEx): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TJsonDBRef): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TJsonCodeWScope): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TJsonDecimal128): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TValue): TPairs; overload; inline;
      function add(const aKey: string; const aValue: TVarRec): TPairs; overload; inline;
      function add(const aKey: string; const aValue: Variant): TPairs; overload; inline;
      function addNull(const aKey: string): TPairs; overload; inline;
      function addUndefined(const aKey: string): TPairs; overload; inline;
      function addMinKey(const aKey: string): TPairs; overload; inline;
      function addMaxKey(const aKey: string): TPairs; overload; inline;
      function addPairs(const aPairs: array of const): TPairs; overload;
      function addPairs(const aBuilder: TJSONCollectionBuilder): TPairs; overload; inline;
      function addPairs(const aJSON: string): TPairs; overload; inline;

      function BeginObject: TPairs; overload; inline;
      function BeginArray: TElements; overload; inline;
      function BeginObject(const aKey: string): TPairs; overload; inline;
      function BeginArray(const aKey: string): TElements; overload; inline;
      function EndArray: TParentCollection; inline;  
      function EndObject: TParentCollection; inline;  

      function asArray: TElements;
      function asObject: TPairs;
    end;

    TParentType = (None, Elements, Pairs);
    TGetReaderProc = reference to function (aWriter: TJsonWriter): TJsonReader;
    TReleaseReaderProc = reference to procedure (aWriter: TJsonWriter; aReader: TJsonReader);
    TResetWriterProc = reference to procedure (aWriter: TJsonWriter);

  strict private
    FEmpty: Boolean;
    FPairs: specialize TObjectDictionary<Integer, TPairs>;
    FElements: specialize TObjectDictionary<Integer, TElements>;
    FParentCollections: specialize TObjectDictionary<Integer, TParentCollection>;
    FParentTypes: specialize TStack<TParentType>;
    FJSONWriter: TJSONWriter;
    FGetReader: TGetReaderProc;
    FReleaseReader: TReleaseReaderProc;
    FResetWriter: TResetWriterProc;
    FDateTimeZoneHandling: TJsonDateTimeZoneHandling;
    FExtendedJsonMode: TJsonExtendedJsonMode;
  private
    procedure CheckParentType(aRootDepth: Integer; aParentType: TParentType);
    procedure CheckEmpty;
    function EndArray(aRootDepth: Integer): TParentCollection;
    function EndObject(aRootDepth: Integer): TParentCollection;
    procedure Complete(const aRootDepth: Integer);
    function GetPairs(aRootDepth: Integer): TPairs;
    function GetElements(aRootDepth: Integer): TElements;
    function GetParentCollection(aRootDepth: Integer): TParentCollection;
    function BeginObject(aRootDepth: Integer): TPairs; overload;
    function BeginArray(aRootDepth: Integer): TElements; overload;
    function PairsAsRoot: TPairs;
    function ElementsAsRoot: TElements;
    function asArray(aRootDepth: Integer): TElements;
    function asObject(aRootDepth: Integer): TPairs;
    function Ended(aRootDepth: Integer): Boolean;
    function GetAsJSON: string;
    procedure ClearContent;
    function GetParentType: TParentType;
    function GetParentArray: TElements;
    function GetParentObject: TPairs;
    procedure SetExtendedJsonMode(Value: TJsonExtendedJsonMode);
    procedure SetDateTimeZoneHandling(Value: TJsonDateTimeZoneHandling);
  protected
    procedure DoResetWriter(aWriter: TJsonWriter); virtual;
    function DoGetReader(aWriter: TJsonWriter): TJsonReader; virtual;
    procedure DoReleaseReader(aWriter: TJsonWriter; aReader: TJsonReader); virtual;
    procedure DoWriteCustomVariant(aWriter: TJsonWriter; const aValue: Variant); virtual;

    function DoBeginArray: TElements;
    function DoBeginObject: TPairs;
  public
    constructor Create(const aJSONWriter: TJSONWriter); overload;
    constructor Create(const aJSONWriter: TJSONWriter;
      aGetReader: TGetReaderProc; aReleaseReader: TReleaseReaderProc;
      aResetWriter: TResetWriterProc); overload;
    destructor Destroy; override;
    property asJSON: string read GetAsJSON;
    property ParentType: TParentType read GetParentType;
    property ParentArray: TElements read GetParentArray;
    property ParentObject: TPairs read GetParentObject;
    property ExtendedJsonMode: TJsonExtendedJsonMode read FExtendedJsonMode
      write SetExtendedJsonMode default TJsonExtendedJsonMode.None;
    property DateTimeZoneHandling: TJsonDateTimeZoneHandling read FDateTimeZoneHandling
      write SetDateTimeZoneHandling default TJsonDateTimeZoneHandling.Local;
  end;

  TJSONArrayBuilder = class(TJSONCollectionBuilder)
  public
    function BeginArray: TJSONCollectionBuilder.TElements;
    function Clear: TJSONArrayBuilder;
  end;

  TJSONObjectBuilder = class(TJSONCollectionBuilder)
  public
    function BeginObject: TJSONCollectionBuilder.TPairs;
    function Clear: TJSONObjectBuilder;
  end;

  TJSONIterator = class
  private type
    TContext = record
      FToken: TJsonToken;
      FIndex: Integer;
      FPath: string;
      constructor Create(aToken: TJsonToken);
    end;
  public type
    TRewindReaderProc = reference to procedure (aReader: TJsonReader);
    TIterateFunc = reference to function(aIter: TJSONIterator): Boolean;
  private
    FReader: TJsonReader;
    FStack: specialize TStack<TContext>;
    FKey: String;
    FPath: String;
    FType: TJsonToken;
    FStarting: Boolean;
    FFinished: Boolean;
    FRecursion: Boolean;
    FContainerPending: Boolean;
    FLevelEnded: Boolean;
    FRewindReader: TRewindReaderProc;
    procedure SkipContainer;
    function GetAsBoolean: Boolean; inline;
    function GetAsString: String; inline;
    function GetAsInteger: Int32; inline;
    function GetAsInt64: Int64; inline;
    function GetAsDouble: Double; inline;
    function GetAsExtended: Extended; inline;
    function GetAsDateTime: TDateTime; inline;
    function GetAsGUID: TGUID; inline;
    function GetAsBytes: TBytes; inline;
    function GetAsOid: TJsonOid; inline;
    function GetAsRegEx: TJsonRegEx; inline;
    function GetAsDBRef: TJsonDBRef; inline;
    function GetAsCodeWScope: TJsonCodeWScope; inline;
    function GetAsDecimal: TJsonDecimal128; inline;
    function GetAsVariant: Variant; inline;
    function GetAsValue: TValue; inline;
    function GetIsNull: Boolean; inline;
    function GetIsUndefined: Boolean; inline;
    function GetIsMinKey: Boolean; inline;
    function GetIsMaxKey: Boolean; inline;
    function GetParentType: TJsonToken; inline;
    function GetIndex: Integer; inline;
    function GetInRecurse: Boolean; inline;
    function GetDepth: Integer; inline;
    function GetPath: String; inline;
  protected
    procedure DoRewindReader(aReader: TJsonReader); virtual;
  public
    constructor Create(aReader: TJsonReader); overload;
    constructor Create(aReader: TJsonReader; aRewindReader: TRewindReaderProc); overload;
    destructor Destroy; override;
    procedure Rewind;
    function Next(const aKey: String = ''): Boolean;
    function Recurse: Boolean;
    procedure Return;
    function Find(const aPath: String): Boolean;
    procedure Iterate(aFunc: TIterateFunc);
    function GetPath(aFromDepth: Integer): String; overload; inline;
    property Reader: TJSONReader read FReader;
    
    property Key: String read FKey;
    property Path: String read GetPath;
    property &Type: TJsonToken read FType;
    property ParentType: TJsonToken read GetParentType;
    property &Index: Integer read GetIndex;
    property InRecurse: Boolean read GetInRecurse;
    property Depth: Integer read GetDepth;
    
    property asString: String read GetAsString;
    property asInteger: Int32 read GetAsInteger;
    property asInt64: Int64 read GetAsInt64;
    property asDouble: Double read GetAsDouble;
    property asExtended: Extended read GetAsExtended;
    property asBoolean: Boolean read GetAsBoolean;
    property asDateTime: TDateTime read GetAsDateTime;
    property asGUID: TGUID read GetAsGUID;
    property asBytes: TBytes read GetAsBytes;
    property asOid: TJsonOid read GetAsOid;
    property asRegEx: TJsonRegEx read GetAsRegEx;
    property asDBRef: TJsonDBRef read GetAsDBRef;
    property asCodeWScope: TJsonCodeWScope read GetAsCodeWScope;
    property asDecimal: TJsonDecimal128 read GetAsDecimal;
    property asVariant: Variant read GetAsVariant;
    property asValue: TValue read GetAsValue;
    property IsNull: Boolean read GetIsNull;
    property IsUndefined: Boolean read GetIsUndefined;
    property IsMinKey: Boolean read GetIsMinKey;
    property IsMaxKey: Boolean read GetIsMaxKey;
  end;

  TJSONObjectBuilderPairs = TJSONObjectBuilder.TPairs;
  TJSONArrayBuilderElements = TJSONArrayBuilder.TElements;

implementation

uses
  {$IFDEF FPC_DOTTEDUNITS}
  System.TypInfo, System.Variants, Fcl.Streams.Extra,
  {$ELSE}
  TypInfo, Variants, StreamEx,
  {$ENDIF}
  System.JSONConsts, System.NetEncoding;

{ TJSONCollectionBuilder.TBaseCollection }

constructor TJSONCollectionBuilder.TBaseCollection.Create(
  const aOwner: TJSONCollectionBuilder; const aRootDepth: Integer);
begin
  FRootDepth := aRootDepth;
  FOwner := aOwner;
  FWriter := aOwner.FJSONWriter;
end;

procedure TJSONCollectionBuilder.TBaseCollection.AddingElement;
begin
  Owner.CheckParentType(FRootDepth,TParentType.Elements);
end;

procedure TJSONCollectionBuilder.TBaseCollection.AddingPair;
begin
  Owner.CheckParentType(FRootDepth,TParentType.Pairs);
end;

class procedure TJSONCollectionBuilder.TBaseCollection.ErrorInvalidSetOfItems;
begin
  raise EJSONCollectionBuilderError.Create('Invalid set of items');
end;

procedure TJSONCollectionBuilder.TBaseCollection.WriteVarRec(const aValue: TVarRec);

  procedure Error;
  begin
    raise EJSONCollectionBuilderError.CreateFmt('Unsupported VarRec type: %d', [AValue.VType]);
  end;

begin
  case aValue.VType of
    vtInteger:
      Writer.WriteValue(aValue.VInteger);
    vtBoolean:
      Writer.WriteValue(aValue.VBoolean);
    vtChar:
      Writer.WriteValue(string(aValue.VChar));
    vtWideChar:
      Writer.WriteValue(string(aValue.VWideChar));
    vtExtended:
      Writer.WriteValue(aValue.VExtended^);
    vtString:
      Writer.WriteValue(string(aValue.VString^));
    vtPChar:
      Writer.WriteValue(string(aValue.VPChar));
    vtPWideChar:
      Writer.WriteValue(string(aValue.VPWideChar));
    vtPointer:
      if aValue.VPointer = nil then
        Writer.WriteNull
      else
        Error;
    vtObject:
      if aValue.VObject = nil then
        Writer.WriteNull
      else
        Error;
    vtAnsiString:
      Writer.WriteValue(string(ansiString(aValue.VAnsiString)));
    vtCurrency:
      Writer.WriteValue(Extended(aValue.VCurrency^));
    vtVariant:
      WriteVariant(aValue.VVariant^);
    vtWideString:
      Writer.WriteValue(string(aValue.VWideString));
    vtInt64:
      Writer.WriteValue(aValue.VInt64^);
    vtUnicodeString:
      Writer.WriteValue(string(aValue.VUnicodeString));
  else
    Error;
  end;
end;

procedure TJSONCollectionBuilder.TBaseCollection.WriteVariant(const aValue: Variant);

  procedure Error;
  begin
    raise EJSONCollectionBuilderError.CreateFmt('Unsupported variant type: %d', [VarType(aValue)]);
  end;

  procedure addBytes;
  var
    pData: Pointer;
    Bytes: TBytes;
  begin
    SetLength(Bytes, VarArrayHighBound(aValue, 1) - VarArrayLowBound(aValue, 1) + 1);
    pData := VarArrayLock(aValue);
    try
      If Length(Bytes) <> 0 then
        Move(pData^, Bytes[0], Length(Bytes));
    finally
      VarArrayUnlock(aValue);
    end;
    Writer.WriteValue(Bytes, TJsonBinaryType.Generic);
  end;

  procedure addArray;
  var
    I: Integer;
    LElems: TElements;
  begin
    LElems := Owner.BeginArray(FRootDepth);
    for I := VarArrayLowBound(aValue, 1) to VarArrayHighBound(aValue, 1) do
      LElems.Add(aValue[I]);
    LElems.EndArray;
  end;

begin
  if VarIsArray(aValue) then
    if VarArrayDimCount(aValue) <> 1 then
      Error
    else if (VarType(aValue) and VarTypeMask) = varByte then
      addBytes
    else
      addArray
  else
    case VarType(aValue) and varTypeMask of
      varEmpty:
        Writer.WriteUndefined;
      varNull:
        Writer.WriteNull;
      varSmallint,
      varShortInt,
      varInteger:
        Writer.WriteValue(Integer(aValue));
      varByte,
      varWord,
      varUInt32:
        Writer.WriteValue(Cardinal(aValue));
      varInt64:
        Writer.WriteValue(Int64(aValue));
      varUInt64:
        Writer.WriteValue(UInt64(aValue));
      varSingle,
      varDouble:
        Writer.WriteValue(Double(aValue));
      varCurrency:
        Writer.WriteValue(Extended(aValue));
      varDate:
        Writer.WriteValue(TDateTime(aValue));
      varOleStr,
      varStrArg,
      varUStrArg,
      varString,
      varUString:
        Writer.WriteValue(string(aValue));
      varBoolean:
        Writer.WriteValue(Boolean(aValue));
      else
        Owner.DoWriteCustomVariant(Writer, aValue);
    end;
end;

procedure TJSONCollectionBuilder.TBaseCollection.WriteOpenArray(const aItems: array of const);
var
  iItem: Integer;
  sKey: string;
  LPriorLevel: Integer;
  LPriorType: TParentType;

  procedure Error;
  begin
    raise EJSONCollectionBuilderError.CreateFmt('Invalid open array item at index %d', [iItem]);
  end;

  function GetStr(aIndex: Integer; out aValue: string): Boolean;
  var
    pRec: PVarRec;
  begin
    pRec := @TVarRec(aItems[AIndex]);
    Result := True;
    case pRec^.VType of
      vtChar:
        aValue := string(pRec^.VChar);
      vtWideChar:
        aValue := pRec^.VWideChar;
      vtString:
        aValue := string(pRec^.VString^);
      vtAnsiString:
        aValue := string(ansiString(pRec^.VAnsiString));
      vtWideString:
        aValue := string(pRec^.VWideString);
      vtPChar:
        aValue := string(pRec^.VPChar);
      vtPWideChar:
        aValue := string(pRec^.VPWideChar);
      vtUnicodeString:
        aValue := string(pRec^.VUnicodeString);
    else
      Result := False;
    end;
  end;

begin
  LPriorType := Owner.GetParentType;
  LPriorLevel := Owner.FParentTypes.Count;
  iItem := 0;

  while iItem < Length(aItems) do
  begin
    if (LPriorType = TParentType.Pairs) and ((iItem and 1) = 0) then
    begin
      if not GetStr(iItem, sKey) then
        Error;
      Inc(iItem);
      if iItem >= Length(aItems) then
        Error;
      Writer.WritePropertyName(sKey);
      WriteVarRec(aItems[iItem]);
    end
    else if (LPriorType = TParentType.Elements) then
    begin
      WriteVarRec(aItems[iItem]);
    end
    else
      Error;

    Inc(iItem);
  end;
end;

function TJSONCollectionBuilder.TBaseCollection.WriteReader(const aReader: TJsonReader; aOnlyEnclosed: Boolean): Boolean;
var
  Nesting: Integer;
  Expected: TJsonToken;
begin
  if (aReader.TokenType=TJsonToken.None) and not aReader.Read then
    raise EJSONCollectionBuilderError.Create('Empty JSON input');
  if not aOnlyEnclosed then
    begin
    Writer.WriteToken(aReader,True);
    Exit(True);
    end;
  if Owner.GetParentType=TParentType.Elements then
    Expected:=TJsonToken.StartArray
  else
    Expected:=TJsonToken.StartObject;
  if aReader.TokenType<>Expected then
    raise EJSONCollectionBuilderError.Create('JSON collection type does not match the destination');
  Nesting:=1;
  while aReader.Read do
    begin
    case aReader.TokenType of
      TJsonToken.StartArray,TJsonToken.StartObject: Inc(Nesting);
      TJsonToken.EndArray,TJsonToken.EndObject: Dec(Nesting);
    end;
    if Nesting=0 then
      Exit(True);
    Writer.WriteToken(aReader,False);
    end;
  raise EJSONCollectionBuilderError.Create('Unterminated JSON collection');
end;

procedure TJSONCollectionBuilder.TBaseCollection.WriteBuilder(const aBuilder: TJSONCollectionBuilder);
var
  Reader: TJsonReader;
begin
  aBuilder.FJSONWriter.Flush;
  Reader:=aBuilder.DoGetReader(aBuilder.FJSONWriter);
  try
    WriteReader(Reader,True);
  finally
    aBuilder.DoReleaseReader(aBuilder.FJSONWriter,Reader);
  end;
end;

procedure TJSONCollectionBuilder.TBaseCollection.WriteJSON(const aJSON: string);
var
  Parsed: TJSONValue;
  Reader: TJsonReader;
begin
  Parsed:=TJSONValue.ParseJSONValue(UnicodeString(aJSON),True,True);
  if Parsed=nil then
    raise EJSONCollectionBuilderError.Create('Empty JSON input');
  try
    Reader:=TJsonTextReader.Create(TStringReader.Create(Parsed.ToJSON));
    try
      WriteReader(Reader,True);
    finally
      Reader.Free;
    end;
  finally
    Parsed.Free;
  end;
end;

procedure TJSONCollectionBuilder.TBaseCollection.EndAll;
begin
  Owner.Complete(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Ended: Boolean;
begin
  Result := Owner.Ended(FRootDepth);
end;

{ TJSONCollectionBuilder }

constructor TJSONCollectionBuilder.Create(const aJSONWriter: TJSONWriter);
begin
  inherited Create;
  if aJSONWriter=nil then
    raise EJSONCollectionBuilderError.Create('A JSON writer is required');
  FEmpty := True;
  FJSONWriter := aJSONWriter;
  FParentTypes := specialize TStack<TParentType>.Create;
  FExtendedJsonMode := TJsonExtendedJsonMode.None;
  FDateTimeZoneHandling := TJsonDateTimeZoneHandling.Local;
end;

constructor TJSONCollectionBuilder.Create(const aJSONWriter: TJSONWriter;
  aGetReader: TGetReaderProc; aReleaseReader: TReleaseReaderProc;
  aResetWriter: TResetWriterProc);
begin
  Create(aJSONWriter);
  if Assigned(aGetReader)<>Assigned(aReleaseReader) then
    raise EJSONCollectionBuilderError.Create('Reader acquisition and release callbacks must be paired');
  FGetReader := aGetReader;
  FReleaseReader := aReleaseReader;
  FResetWriter := aResetWriter;
end;

destructor TJSONCollectionBuilder.Destroy;
begin
  FElements.Free;
  FPairs.Free;
  FParentTypes.Free;
  FParentCollections.Free;
  inherited Destroy;
end;

procedure TJSONCollectionBuilder.CheckEmpty;
begin
  if not FEmpty then
    raise EJSONCollectionBuilderError.Create('Builder is not empty');
end;

procedure TJSONCollectionBuilder.CheckParentType(aRootDepth: Integer; aParentType: TParentType);
begin
  if (FParentTypes.Count = 0) or Ended(aRootDepth) or (FParentTypes.Peek <> aParentType) then
    raise EJSONCollectionBuilderError.Create('Invalid parent type');
end;

function TJSONCollectionBuilder.Ended(aRootDepth: Integer): Boolean;
begin
  Result := FParentTypes.Count<=aRootDepth;
end;

procedure TJSONCollectionBuilder.Complete(const aRootDepth: Integer);
var
  LType: TParentType;
begin
  while FParentTypes.Count > aRootDepth do
  begin
    LType := FParentTypes.Pop;
    case LType of
      TParentType.Elements:
        FJSONWriter.WriteEndArray;
      TParentType.Pairs:
        FJSONWriter.WriteEndObject;
    end;
  end;
end;

function TJSONCollectionBuilder.GetElements(aRootDepth: Integer): TElements;
begin
  if FElements = nil then
    FElements := specialize TObjectDictionary<Integer, TElements>.Create([doOwnsValues]);
  if not FElements.TryGetValue(aRootDepth, Result) then
  begin
    Result := TElements.Create(Self, aRootDepth);
    FElements.Add(aRootDepth, Result);
  end;
end;

function TJSONCollectionBuilder.GetPairs(aRootDepth: Integer): TPairs;
begin
  if FPairs = nil then
    FPairs := specialize TObjectDictionary<Integer, TPairs>.Create([doOwnsValues]);
  if not FPairs.TryGetValue(aRootDepth, Result) then
  begin
    Result := TPairs.Create(Self, aRootDepth);
    FPairs.Add(aRootDepth, Result);
  end;
end;

function TJSONCollectionBuilder.GetParentCollection(aRootDepth: Integer): TParentCollection;
begin
  if FParentCollections = nil then
    FParentCollections := specialize TObjectDictionary<Integer, TParentCollection>.Create([doOwnsValues]);
  if not FParentCollections.TryGetValue(aRootDepth, Result) then
  begin
    Result := TParentCollection.Create(Self, aRootDepth);
    FParentCollections.Add(aRootDepth, Result);
  end;
end;

function WriterJSONSnapshot(Writer: TJsonWriter): string;
var
  Output: TTextWriter;
  StreamWriter: TStreamWriter;
  Stream: TStream;
  Saved: Int64;
  Bytes, Preamble: TBytes;
  Start: Integer;
begin
  Writer.Flush;
  if Writer is TJsonObjectWriter then
    begin
    if TJsonObjectWriter(Writer).JSON=nil then
      Exit('');
    Exit(TJsonObjectWriter(Writer).JSON.ToJSON);
    end;
  if Writer is TJsonTextWriter then
    begin
    Output:=TJsonTextWriter(Writer).Writer;
    if Output is TStringWriter then
      Exit(Output.ToString);
    if Output is TStreamWriter then
      begin
      StreamWriter:=TStreamWriter(Output);
      Stream:=StreamWriter.BaseStream;
      Saved:=Stream.Position;
      try
        if Stream.Size>High(Integer) then
          raise EJSONCollectionBuilderError.Create('JSON content is too large for a string');
        SetLength(Bytes,Stream.Size);
        Stream.Position:=0;
        if Length(Bytes)>0 then
          Stream.ReadBuffer(Bytes[0],Length(Bytes));
      finally
        Stream.Position:=Saved;
      end;
      Start:=0;
      Preamble:=StreamWriter.Encoding.GetPreamble;
      if (Length(Preamble)>0) and (Length(Bytes)>=Length(Preamble)) and
         CompareMem(@Bytes[0],@Preamble[0],Length(Preamble)) then
        Start:=Length(Preamble);
      Exit(StreamWriter.Encoding.GetString(Bytes,Start,Length(Bytes)-Start));
      end;
    end;
  raise EJSONCollectionBuilderError.Create('This writer requires a reader callback');
end;

function TJSONCollectionBuilder.GetAsJSON: string;
var
  Reader: TJsonReader;
  Output: TStringWriter;
  Writer: TJsonTextWriter;
begin
  if not Assigned(FGetReader) then
    Exit(WriterJSONSnapshot(FJSONWriter));
  FJSONWriter.Flush;
  Reader:=DoGetReader(FJSONWriter);
  try
    Output:=TStringWriter.Create;
    Writer:=TJsonTextWriter.Create(Output,True);
    try
      Writer.WriteToken(Reader,True);
      Writer.Flush;
      Result:=Output.ToString;
    finally
      Writer.Free;
    end;
  finally
    DoReleaseReader(FJSONWriter,Reader);
  end;
end;

procedure TJSONCollectionBuilder.SetExtendedJsonMode(Value: TJsonExtendedJsonMode);
begin
  FExtendedJsonMode := Value;
  If FJSONWriter is TJsonTextWriter then
    TJsonTextWriter(FJSONWriter).ExtendedJsonMode := Value;
end;

procedure TJSONCollectionBuilder.SetDateTimeZoneHandling(Value: TJsonDateTimeZoneHandling);
begin
  FDateTimeZoneHandling := Value;
  FJSONWriter.DateTimeZoneHandling := Value;
end;

function TJSONCollectionBuilder.GetParentType: TParentType;
begin
  if FParentTypes.Count > 0 then
    Result := FParentTypes.Peek
  else
    Result := TParentType.None;
end;

function TJSONCollectionBuilder.GetParentArray: TElements;
begin
  if (FParentTypes.Count > 0) and (FParentTypes.Peek = TParentType.Elements) then
    Result := GetElements(0)
  else
    raise EJSONCollectionBuilderError.Create('Not in array context');
end;

function TJSONCollectionBuilder.GetParentObject: TPairs;
begin
  if (FParentTypes.Count > 0) and (FParentTypes.Peek = TParentType.Pairs) then
    Result := GetPairs(0)
  else
    raise EJSONCollectionBuilderError.Create('Not in object context');
end;

procedure TJSONCollectionBuilder.DoResetWriter(aWriter: TJsonWriter);
var
  Output: TTextWriter;
begin
  if Assigned(FResetWriter) then
    begin
    FResetWriter(aWriter);
    Exit;
    end;
  if aWriter is TJsonObjectWriter then
    Exit;
  if aWriter is TJsonTextWriter then
    begin
    Output:=TJsonTextWriter(aWriter).Writer;
    if Output is TStringWriter then
      begin
      TStringWriter(Output).GetStringBuilder.Clear;
      Exit;
      end;
    if Output is TStreamWriter then
      begin
      Output.Flush;
      TStreamWriter(Output).BaseStream.Size:=0;
      TStreamWriter(Output).BaseStream.Position:=0;
      Exit;
      end;
    end;
  raise EJSONCollectionBuilderError.Create('This writer requires a reset callback');
end;

function TJSONCollectionBuilder.DoGetReader(aWriter: TJsonWriter): TJsonReader;
begin
  if Assigned(FGetReader) then
    Result:=FGetReader(aWriter)
  else
    Result:=TJsonTextReader.Create(TStringReader.Create(WriterJSONSnapshot(aWriter)));
  if Result=nil then
    raise EJSONCollectionBuilderError.Create('Reader callback returned nil');
end;

procedure TJSONCollectionBuilder.DoReleaseReader(aWriter: TJsonWriter; aReader: TJsonReader);
begin
  if Assigned(FReleaseReader) then
    FReleaseReader(aWriter,aReader)
  else
    aReader.Free;
end;

procedure TJSONCollectionBuilder.DoWriteCustomVariant(aWriter: TJsonWriter; const aValue: Variant);
var
  S: string;
begin
  try
    S := aValue;
  except
    raise EJSONCollectionBuilderError.CreateFmt('Unsupported variant type: %d', [VarType(aValue)]);
  end;
  aWriter.WriteValue(S);
end;

function TJSONCollectionBuilder.DoBeginArray: TElements;
begin
  CheckEmpty;
  FEmpty := False;
  Result := BeginArray(0);
end;

function TJSONCollectionBuilder.DoBeginObject: TPairs;
begin
  CheckEmpty;
  FEmpty := False;
  Result := BeginObject(0);
end;

function TJSONCollectionBuilder.BeginArray(aRootDepth: Integer): TElements;
begin
  FParentTypes.Push(TParentType.Elements);
  FJSONWriter.WriteStartArray;
  Result := GetElements(aRootDepth);
end;

function TJSONCollectionBuilder.BeginObject(aRootDepth: Integer): TPairs;
begin
  FParentTypes.Push(TParentType.Pairs);
  FJSONWriter.WriteStartObject;
  Result := GetPairs(aRootDepth);
end;

function TJSONCollectionBuilder.EndArray(aRootDepth: Integer): TParentCollection;
begin
  if FParentTypes.Count > aRootDepth then
  begin
    case FParentTypes.Peek of
      TParentType.Elements:
      begin
        FParentTypes.Pop;
        FJSONWriter.WriteEndArray;
        if FParentTypes.Count > aRootDepth then
          Result := GetParentCollection(aRootDepth)
        else
          Result := GetParentCollection(MaxInt);
      end;
    else
      raise EJSONCollectionBuilderError.Create('Not in array context');
    end;
  end
  else
    Result := GetParentCollection(MaxInt);
end;

function TJSONCollectionBuilder.EndObject(aRootDepth: Integer): TParentCollection;
begin
  if FParentTypes.Count > aRootDepth then
  begin
    case FParentTypes.Peek of
      TParentType.Pairs:
      begin
        FParentTypes.Pop;
        FJSONWriter.WriteEndObject;
        if FParentTypes.Count > aRootDepth then
          Result := GetParentCollection(aRootDepth)
        else
          Result := GetParentCollection(MaxInt);
      end;
    else
      raise EJSONCollectionBuilderError.Create('Not in object context');
    end;
  end
  else
    Result := GetParentCollection(MaxInt);
end;

function TJSONCollectionBuilder.PairsAsRoot: TPairs;
begin
  CheckParentType(0,TParentType.Pairs);
  Result := GetPairs(FParentTypes.Count-1);
end;

function TJSONCollectionBuilder.ElementsAsRoot: TElements;
begin
  CheckParentType(0,TParentType.Elements);
  Result := GetElements(FParentTypes.Count-1);
end;

function TJSONCollectionBuilder.AsArray(aRootDepth: Integer): TElements;
begin
  Result := nil;
  if FParentTypes.Count > 0 then
    if FParentTypes.Peek = TParentType.Elements then
      Result := GetElements(aRootDepth);
  if Result = nil then
    raise EJSONCollectionBuilderError.Create('Not in array context');
end;

function TJSONCollectionBuilder.AsObject(aRootDepth: Integer): TPairs;
begin
  Result := nil;
  if FParentTypes.Count > 0 then
    if FParentTypes.Peek = TParentType.Pairs then
      Result := GetPairs(aRootDepth);
  if Result = nil then
    raise EJSONCollectionBuilderError.Create('Not in object context');
end;

procedure TJSONCollectionBuilder.ClearContent;
begin
  FreeAndNil(FElements);
  FreeAndNil(FPairs);
  FreeAndNil(FParentCollections);
  FParentTypes.Clear;
  FEmpty := True;
  FJSONWriter.Rewind;
  DoResetWriter(FJSONWriter);
end;

{ TJSONCollectionBuilder.TBaseCollection add methods }

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: string): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: Int32): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: UInt32): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: Int64): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: UInt64): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: Single): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: Double): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

{$IFDEF FPC_HAS_TYPE_EXTENDED}
function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: Extended): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;
{$ENDIF FPC_HAS_TYPE_EXTENDED}

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: Boolean): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: Char): TElements;
begin
  AddingElement;
  FWriter.WriteValue(string(aValue));
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: Byte): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: TDateTime): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: TGUID): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: TBytes; aBinaryType: TJsonBinaryType): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue, aBinaryType);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: TJsonOid): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: TJsonRegEx): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: TJsonDBRef): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: TJsonCodeWScope): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: TJsonDecimal128): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: TValue): TElements;
begin
  AddingElement;
  FWriter.WriteValue(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: TVarRec): TElements;
begin
  AddingElement;
  WriteVarRec(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aValue: Variant): TElements;
begin
  AddingElement;
  WriteVariant(aValue);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.AddElements(const aElements: array of const): TElements;
begin
  AddingElement;
  WriteOpenArray(aElements);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.AddElements(const aBuilder: TJSONCollectionBuilder): TElements;
begin
  AddingElement;
  WriteBuilder(aBuilder);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.AddElements(const aJSON: string): TElements;
begin
  AddingElement;
  WriteJSON(aJSON);
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.AddNull: TElements;
begin
  AddingElement;
  FWriter.WriteNull;
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.AddUndefined: TElements;
begin
  AddingElement;
  FWriter.WriteUndefined;
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.AddMinKey: TElements;
begin
  AddingElement;
  FWriter.WriteMinKey;
  Result := Owner.GetElements(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.AddMaxKey: TElements;
begin
  AddingElement;
  FWriter.WriteMaxKey;
  Result := Owner.GetElements(FRootDepth);
end;

// Key-value pair methods
function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: string): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: Int32): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: UInt32): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: Int64): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: UInt64): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: Single): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: Double): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

{$IFDEF FPC_HAS_TYPE_EXTENDED}
function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: Extended): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;
{$ENDIF FPC_HAS_TYPE_EXTENDED}

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: Boolean): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: Char): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(string(aValue));
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: Byte): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: TDateTime): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: TGUID): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: TBytes; aBinaryType: TJsonBinaryType): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue, aBinaryType);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: TJsonOid): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: TJsonRegEx): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: TJsonDBRef): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: TJsonCodeWScope): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: TJsonDecimal128): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: TValue): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteValue(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: TVarRec): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  WriteVarRec(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.Add(const aKey: string; const aValue: Variant): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  WriteVariant(aValue);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.AddPairs(const aPairs: array of const): TPairs;
begin
  AddingPair;
  WriteOpenArray(aPairs);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.AddPairs(const aBuilder: TJSONCollectionBuilder): TPairs;
begin
  AddingPair;
  WriteBuilder(aBuilder);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.AddPairs(const aJSON: string): TPairs;
begin
  AddingPair;
  WriteJSON(aJSON);
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.AddNull(const aKey: string): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteNull;
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.AddUndefined(const aKey: string): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteUndefined;
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.AddMinKey(const aKey: string): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteMinKey;
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.AddMaxKey(const aKey: string): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  FWriter.WriteMaxKey;
  Result := Owner.GetPairs(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.BeginObject: TPairs;
begin
  AddingElement;
  Result := Owner.BeginObject(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.BeginArray: TElements;
begin
  AddingElement;
  Result := Owner.BeginArray(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.BeginObject(const aKey: string): TPairs;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  Result := Owner.BeginObject(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.BeginArray(const aKey: string): TElements;
begin
  AddingPair;
  FWriter.WritePropertyName(aKey);
  Result := Owner.BeginArray(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.EndArray: TParentCollection;
begin
  Result := Owner.EndArray(FRootDepth);
end;

function TJSONCollectionBuilder.TBaseCollection.EndObject: TParentCollection;
begin
  Result := Owner.EndObject(FRootDepth);
end;

{ TJSONArrayBuilder }

function TJSONArrayBuilder.BeginArray: TJSONCollectionBuilder.TElements;
begin
  Result := DoBeginArray;
end;

function TJSONArrayBuilder.Clear: TJSONArrayBuilder;
begin
  ClearContent;
  Result := Self;
end;

{ TJSONObjectBuilder }

function TJSONObjectBuilder.BeginObject: TJSONCollectionBuilder.TPairs;
begin
  Result := DoBeginObject;
end;

function TJSONObjectBuilder.Clear: TJSONObjectBuilder;
begin
  ClearContent;
  Result := Self;
end;

{ TJSONIterator.TContext }

constructor TJSONIterator.TContext.Create(aToken: TJsonToken);
begin
  FToken := aToken;
  FIndex := -1;
  FPath := '';
end;

{ TJSONIterator }

constructor TJSONIterator.Create(aReader: TJsonReader);
begin
  inherited Create;
  FReader := aReader;
  FStack := specialize TStack<TContext>.Create;
  FType := TJsonToken.None;
  FStarting := True;
  FFinished := False;
  FRecursion := False;
  FContainerPending := False;
  FLevelEnded := False;
end;

constructor TJSONIterator.Create(aReader: TJsonReader; aRewindReader: TRewindReaderProc);
begin
  Create(aReader);
  FRewindReader := aRewindReader;
end;

destructor TJSONIterator.Destroy;
begin
  FStack.Free;
  inherited Destroy;
end;

procedure TJSONIterator.DoRewindReader(aReader: TJsonReader);
begin
  if not Assigned(FRewindReader) then
    raise EJSONIteratorError.Create('Rewind requires a reader rewind callback');
  FRewindReader(aReader);
end;

procedure TJSONIterator.Rewind;
begin
  DoRewindReader(FReader);
  FStack.Clear;
  FKey := '';
  FPath := '';
  FType := TJsonToken.None;
  FStarting := True;
  FFinished := False;
  FRecursion := False;
  FContainerPending := False;
  FLevelEnded := False;
end;

procedure TJSONIterator.SkipContainer;
var
  Nesting: Integer;
begin
  if not FContainerPending then
    Exit;
  Nesting:=1;
  while FReader.Read do
    begin
    case FReader.TokenType of
      TJsonToken.StartObject,TJsonToken.StartArray: Inc(Nesting);
      TJsonToken.EndObject,TJsonToken.EndArray: Dec(Nesting);
    end;
    if Nesting=0 then
      begin
      FContainerPending:=False;
      Exit;
      end;
    end;
  raise EJSONIteratorError.Create('Unterminated JSON container');
end;

function IteratorPropertyPath(const Parent, Key: string): string;
var
  Quoted: TJSONString;
  I: Integer;
  Simple: Boolean;
begin
  Simple:=Key<>'';
  for I:=1 to Length(Key) do
    if not (Key[I] in ['A'..'Z','a'..'z','0'..'9','_','$']) then
      Simple:=False;
  if Simple then
    begin
    if Parent='' then
      Result:=Key
    else
      Result:=Parent+'.'+Key;
    end
  else
    begin
    Quoted:=TJSONString.Create(Key);
    try
      Result:=Parent+'['+Quoted.ToJSON+']';
    finally
      Quoted.Free;
    end;
    end;
end;

function TJSONIterator.Next(const aKey: String): Boolean;
var
  Context: TContext;
  HaveToken: Boolean;
begin
  Result:=False;
  if FFinished or FLevelEnded then
    Exit;
  HaveToken:=False;
  if FStarting then
    begin
    FStarting:=False;
    if not FReader.Read then
      begin
      FFinished:=True;
      Exit;
      end;
    FType:=FReader.TokenType;
    FContainerPending:=FType in [TJsonToken.StartObject,TJsonToken.StartArray];
    if FRecursion and FContainerPending then
      begin
      FRecursion:=False;
      Recurse;
      end
    else
      HaveToken:=True;
    end;
  repeat
    if not HaveToken then
      begin
      SkipContainer;
      if not FReader.Read then
        begin
        if FStack.Count<>0 then
          raise EJSONIteratorError.Create('Unexpected end of JSON');
        FFinished:=True;
        Exit;
        end;
      end;
    HaveToken:=False;
    FType:=FReader.TokenType;
    if FType=TJsonToken.Comment then
      Continue;
    if FType in [TJsonToken.EndObject,TJsonToken.EndArray] then
      begin
      FLevelEnded:=True;
      Exit;
      end;
    FKey:='';
    FPath:='';
    if FType=TJsonToken.PropertyName then
      begin
      FKey:=FReader.Value.AsString;
      if not FReader.Read then
        raise EJSONIteratorError.Create('Object property has no value');
      FType:=FReader.TokenType;
      end;
    if FStack.Count>0 then
      begin
      Context:=FStack.Pop;
      if Context.FToken=TJsonToken.StartArray then
        begin
        Inc(Context.FIndex);
        FPath:=Context.FPath+'['+IntToStr(Context.FIndex)+']';
        end
      else
        FPath:=IteratorPropertyPath(Context.FPath,FKey);
      FStack.Push(Context);
      end;
    FContainerPending:=FType in [TJsonToken.StartObject,TJsonToken.StartArray];
    if (aKey='') or ((GetParentType=TJsonToken.StartArray) and (aKey=IntToStr(GetIndex))) or
       ((GetParentType=TJsonToken.StartObject) and (aKey=FKey)) then
      Exit(True);
  until False;
end;

function TJSONIterator.Recurse: Boolean;
var
  Context: TContext;
begin
  if FStarting then
    begin
    FRecursion:=True;
    Exit(True);
    end;
  Result:=FContainerPending and not FFinished and not FLevelEnded;
  if Result then
    begin
    Context:=TContext.Create(FType);
    Context.FPath:=FPath;
    FStack.Push(Context);
    FContainerPending:=False;
    end;
end;

procedure TJSONIterator.Return;
var
  Nesting: Integer;
  Context: TContext;
begin
  if FStack.Count=0 then
    Exit;
  if not FLevelEnded then
    begin
    SkipContainer;
    Nesting:=1;
    while (Nesting>0) and FReader.Read do
      case FReader.TokenType of
        TJsonToken.StartObject,TJsonToken.StartArray: Inc(Nesting);
        TJsonToken.EndObject,TJsonToken.EndArray: Dec(Nesting);
      end;
    if Nesting<>0 then
      raise EJSONIteratorError.Create('Unterminated JSON container');
    end;
  Context:=FStack.Pop;
  FPath:=Context.FPath;
  FKey:='';
  FType:=FReader.TokenType;
  FLevelEnded:=False;
  FContainerPending:=False;
end;

function TJSONIterator.Find(const aPath: String): Boolean;
var
  Parser: TJSONPathParser;
  Token: TJSONPathToken;
  SearchPath: UnicodeString;
  KeyName: string;
begin
  Rewind;
  if not Next then
    Exit(False);
  SearchPath:=UnicodeString(aPath);
  Parser:=TJSONPathParser.Create(SearchPath);
  while not Parser.IsEof do
    begin
    Token:=Parser.NextToken;
    case Token of
      TJSONPathToken.Eof: Break;
      TJSONPathToken.Name:
        begin
        if FType<>TJsonToken.StartObject then
          Exit(False);
        KeyName:=Parser.TokenName;
        end;
      TJSONPathToken.ArrayIndex:
        begin
        if (FType<>TJsonToken.StartArray) or (Parser.TokenArrayIndex<0) then
          Exit(False);
        KeyName:=IntToStr(Parser.TokenArrayIndex);
        end;
      else
        Exit(False);
    end;
    if not Recurse then
      Exit(False);
    repeat
      if not Next(KeyName) then
        Exit(False);
    until (KeyName<>'') or (FKey='');
    end;
  Result:=True;
end;

procedure TJSONIterator.Iterate(aFunc: TIterateFunc);
begin
  if not Assigned(aFunc) then
    raise EJSONIteratorError.Create('An iteration callback is required');
  while Next do
    if not aFunc(Self) then
      Break;
end;

function TJSONIterator.GetPath(aFromDepth: Integer): String;
var
  Frames: array of TContext;
  Parent: string;
begin
  if aFromDepth<=0 then
    Exit(FPath);
  Frames:=FStack.ToArray;
  if aFromDepth>Length(Frames) then
    Exit('');
  Parent:=Frames[aFromDepth-1].FPath;
  Result:=Copy(FPath,Length(Parent)+1,MaxInt);
  if (Result<>'') and (Result[1]='.') then
    Delete(Result,1,1);
end;

function TJSONIterator.GetAsBoolean: Boolean;
begin
  Result := FReader.Value.AsBoolean;
end;

function TJSONIterator.GetAsString: String;
begin
  Result := FReader.Value.AsString;
end;

function TJSONIterator.GetAsInteger: Int32;
begin
  Result := FReader.Value.AsInteger;
end;

function TJSONIterator.GetAsInt64: Int64;
begin
  Result := FReader.Value.AsInt64;
end;

function TJSONIterator.GetAsDouble: Double;
begin
  Result := FReader.Value.AsDouble;
end;

function TJSONIterator.GetAsExtended: Extended;
begin
  Result := FReader.Value.AsExtended;
end;

function TJSONIterator.GetAsDateTime: TDateTime;
begin
  Result := FReader.Value.AsDateTime;
end;

function TJSONIterator.GetAsGUID: TGUID;
begin
  if FReader.Value.IsType(TypeInfo(TGUID)) then
    Result:=FReader.Value.specialize AsType<TGUID>(False)
  else
    Result:=StringToGUID(FReader.Value.AsString);
end;

function TJSONIterator.GetAsBytes: TBytes;
begin
  Result:=FReader.Value.specialize AsType<TBytes>(False);
end;

function TJSONIterator.GetAsOid: TJsonOid;
begin
  Result:=FReader.Value.specialize AsType<TJsonOid>(False);
end;

function TJSONIterator.GetAsRegEx: TJsonRegEx;
begin
  Result:=FReader.Value.specialize AsType<TJsonRegEx>(False);
end;

function TJSONIterator.GetAsDBRef: TJsonDBRef;
begin
  Result:=FReader.Value.specialize AsType<TJsonDBRef>(False);
end;

function TJSONIterator.GetAsCodeWScope: TJsonCodeWScope;
begin
  Result:=FReader.Value.specialize AsType<TJsonCodeWScope>(False);
end;

function TJSONIterator.GetAsDecimal: TJsonDecimal128;
begin
  Result:=FReader.Value.specialize AsType<TJsonDecimal128>(False);
end;

function TJSONIterator.GetAsVariant: Variant;
begin
  // Handle TValue to Variant conversion based on token type
  case FType of
    TJsonToken.&String:
      Result := FReader.Value.AsString;
    TJsonToken.Integer:
      Result := FReader.Value.AsInt64;
    TJsonToken.Float:
      Result := FReader.Value.AsExtended;
    TJsonToken.Boolean:
      Result := FReader.Value.AsBoolean;
    TJsonToken.Null:
      Result := Null;
  else
    Result:=FReader.Value.AsVariant;
  end;
end;

function TJSONIterator.GetAsValue: TValue;
begin
  Result:=FReader.Value;
end;

function TJSONIterator.GetIsNull: Boolean;
begin
  Result := FType = TJsonToken.Null;
end;

function TJSONIterator.GetIsUndefined: Boolean;
begin
  Result := FType = TJsonToken.Undefined;
end;

function TJSONIterator.GetIsMinKey: Boolean;
begin
  Result := FType = TJsonToken.MinKey;
end;

function TJSONIterator.GetIsMaxKey: Boolean;
begin
  Result := FType = TJsonToken.MaxKey;
end;

function TJSONIterator.GetParentType: TJsonToken;
var
  Context: TContext;
begin
  if FStack.Count > 0 then
  begin
    Context := FStack.Peek;
    Result := Context.FToken;
  end
  else
    Result := TJsonToken.None;
end;

function TJSONIterator.GetIndex: Integer;
var
  Context: TContext;
begin
  if FStack.Count > 0 then
  begin
    Context := FStack.Peek;
    if Context.FToken=TJsonToken.StartArray then
      Result:=Context.FIndex
    else
      Result:=-1;
  end
  else
    Result := -1;
end;

function TJSONIterator.GetInRecurse: Boolean;
begin
  Result := FStack.Count>0;
end;

function TJSONIterator.GetDepth: Integer;
begin
  Result := FStack.Count;
end;

function TJSONIterator.GetPath: String;
begin
  Result := GetPath(0);
end;

{ TJSONCollectionBuilder.TParentCollection }

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: string): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: Int32): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: UInt32): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: Int64): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: UInt64): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: Single): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: Double): TElements;
begin
  Result := inherited add(aValue);
end;

{$IFDEF FPC_HAS_TYPE_EXTENDED}
function TJSONCollectionBuilder.TParentCollection.Add(const aValue: Extended): TElements;
begin
  Result := inherited add(aValue);
end;
{$ENDIF FPC_HAS_TYPE_EXTENDED}

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: Boolean): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: Char): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: Byte): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: TDateTime): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: TGUID): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: TBytes; aBinaryType: TJsonBinaryType): TElements;
begin
  Result := inherited add(aValue, aBinaryType);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: TJsonOid): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: TJsonRegEx): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: TJsonDBRef): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: TJsonCodeWScope): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: TJsonDecimal128): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: TValue): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: TVarRec): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aValue: Variant): TElements;
begin
  Result := inherited add(aValue);
end;

function TJSONCollectionBuilder.TParentCollection.AddNull: TElements;
begin
  Result := inherited addNull;
end;

function TJSONCollectionBuilder.TParentCollection.AddUndefined: TElements;
begin
  Result := inherited addUndefined;
end;

function TJSONCollectionBuilder.TParentCollection.AddMinKey: TElements;
begin
  Result := inherited addMinKey;
end;

function TJSONCollectionBuilder.TParentCollection.AddMaxKey: TElements;
begin
  Result := inherited addMaxKey;
end;

function TJSONCollectionBuilder.TParentCollection.AddElements(const aElements: array of const): TElements;
begin
  Result := inherited addElements(aElements);
end;

function TJSONCollectionBuilder.TParentCollection.AddElements(const aBuilder: TJSONCollectionBuilder): TElements;
begin
  Result := inherited addElements(aBuilder);
end;

function TJSONCollectionBuilder.TParentCollection.AddElements(const aJSON: string): TElements;
begin
  Result := inherited addElements(aJSON);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: string): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: Int32): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: UInt32): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: Int64): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: UInt64): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: Single): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: Double): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

{$IFDEF FPC_HAS_TYPE_EXTENDED}
function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; aValue: Extended): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;
{$ENDIF FPC_HAS_TYPE_EXTENDED}

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; aValue: Boolean): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; aValue: Char): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; aValue: Byte): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; aValue: TDateTime): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: TGUID): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: TBytes; aBinaryType: TJsonBinaryType): TPairs;
begin
  Result := inherited add(aKey, aValue, aBinaryType);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: TJsonOid): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: TJsonRegEx): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: TJsonDBRef): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: TJsonCodeWScope): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: TJsonDecimal128): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: TValue): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: TVarRec): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.Add(const aKey: string; const aValue: Variant): TPairs;
begin
  Result := inherited add(aKey, aValue);
end;

function TJSONCollectionBuilder.TParentCollection.AddNull(const aKey: string): TPairs;
begin
  Result := inherited addNull(aKey);
end;

function TJSONCollectionBuilder.TParentCollection.AddUndefined(const aKey: string): TPairs;
begin
  Result := inherited addUndefined(aKey);
end;

function TJSONCollectionBuilder.TParentCollection.AddMinKey(const aKey: string): TPairs;
begin
  Result := inherited addMinKey(aKey);
end;

function TJSONCollectionBuilder.TParentCollection.AddMaxKey(const aKey: string): TPairs;
begin
  Result := inherited addMaxKey(aKey);
end;

function TJSONCollectionBuilder.TParentCollection.AddPairs(const aPairs: array of const): TPairs;
begin
  Result := inherited addPairs(aPairs);
end;

function TJSONCollectionBuilder.TParentCollection.AddPairs(const aBuilder: TJSONCollectionBuilder): TPairs;
begin
  Result := inherited addPairs(aBuilder);
end;

function TJSONCollectionBuilder.TParentCollection.AddPairs(const aJSON: string): TPairs;
begin
  Result := inherited addPairs(aJSON);
end;

function TJSONCollectionBuilder.TParentCollection.BeginObject: TPairs;
begin
  Result := inherited BeginObject;
end;

function TJSONCollectionBuilder.TParentCollection.BeginArray: TElements;
begin
  Result := inherited BeginArray;
end;

function TJSONCollectionBuilder.TParentCollection.BeginObject(const aKey: string): TPairs;
begin
  Result := inherited BeginObject(aKey);
end;

function TJSONCollectionBuilder.TParentCollection.BeginArray(const aKey: string): TElements;
begin
  Result := inherited BeginArray(aKey);
end;

function TJSONCollectionBuilder.TParentCollection.EndArray: TParentCollection;
begin
  Result := inherited EndArray;
end;

function TJSONCollectionBuilder.TParentCollection.EndObject: TParentCollection;
begin
  Result := inherited EndObject;
end;

function TJSONCollectionBuilder.TParentCollection.AsArray: TElements;
begin
  Result := Owner.AsArray(RootDepth);
end;

function TJSONCollectionBuilder.TParentCollection.AsObject: TPairs;
begin
  Result := Owner.AsObject(RootDepth);
end;

{ TJSONCollectionBuilder.TElements }

function TJSONCollectionBuilder.TElements.Add(const aValue: string): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: Int32): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: UInt32): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: Int64): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: UInt64): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: Single): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: Double): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

{$IFDEF FPC_HAS_TYPE_EXTENDED}
function TJSONCollectionBuilder.TElements.Add(const aValue: Extended): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;
{$ENDIF FPC_HAS_TYPE_EXTENDED}

function TJSONCollectionBuilder.TElements.Add(const aValue: Boolean): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: Char): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: Byte): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: TDateTime): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: TGUID): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: TBytes; aBinaryType: TJsonBinaryType): TElements;
begin
  inherited add(aValue, aBinaryType);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: TJsonOid): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: TJsonRegEx): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: TJsonDBRef): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: TJsonCodeWScope): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: TJsonDecimal128): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: TValue): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: TVarRec): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.Add(const aValue: Variant): TElements;
begin
  inherited add(aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.AddNull: TElements;
begin
  inherited addNull;
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.AddUndefined: TElements;
begin
  inherited addUndefined;
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.AddMinKey: TElements;
begin
  inherited addMinKey;
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.AddMaxKey: TElements;
begin
  inherited addMaxKey;
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.AddElements(const aElements: array of const): TElements;
begin
  inherited addElements(aElements);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.AddElements(const aBuilder: TJSONCollectionBuilder): TElements;
begin
  inherited addElements(aBuilder);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.AddElements(const aJSON: string): TElements;
begin
  inherited addElements(aJSON);
  Result := Self;
end;

function TJSONCollectionBuilder.TElements.BeginObject: TPairs;
begin
  Result := inherited BeginObject;
end;

function TJSONCollectionBuilder.TElements.BeginArray: TElements;
begin
  Result := inherited BeginArray;
end;

function TJSONCollectionBuilder.TElements.EndArray: TParentCollection;
begin
  Result := inherited EndArray;
end;

function TJSONCollectionBuilder.TElements.AsRoot: TElements;
begin
  Result := Owner.ElementsAsRoot;
end;

{ TJSONCollectionBuilder.TPairs }

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: string): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: Int32): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: UInt32): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: Int64): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: UInt64): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: Single): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: Double): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

{$IFDEF FPC_HAS_TYPE_EXTENDED}
function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: Extended): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;
{$ENDIF FPC_HAS_TYPE_EXTENDED}

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: Boolean): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: Char): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: Byte): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: TDateTime): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: TGUID): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: TBytes; aBinaryType: TJsonBinaryType): TPairs;
begin
  inherited add(aKey, aValue, aBinaryType);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: TJsonOid): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: TJsonRegEx): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: TJsonDBRef): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: TJsonCodeWScope): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: TJsonDecimal128): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: TValue): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: TVarRec): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.Add(const aKey: string; const aValue: Variant): TPairs;
begin
  inherited add(aKey, aValue);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.AddNull(const aKey: string): TPairs;
begin
  inherited addNull(aKey);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.AddUndefined(const aKey: string): TPairs;
begin
  inherited addUndefined(aKey);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.AddMinKey(const aKey: string): TPairs;
begin
  inherited addMinKey(aKey);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.AddMaxKey(const aKey: string): TPairs;
begin
  inherited addMaxKey(aKey);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.AddPairs(const aPairs: array of const): TPairs;
begin
  inherited addPairs(aPairs);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.AddPairs(const aBuilder: TJSONCollectionBuilder): TPairs;
begin
  inherited addPairs(aBuilder);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.AddPairs(const aJSON: string): TPairs;
begin
  inherited addPairs(aJSON);
  Result := Self;
end;

function TJSONCollectionBuilder.TPairs.BeginObject(const aKey: string): TPairs;
begin
  Result := inherited BeginObject(aKey);
end;

function TJSONCollectionBuilder.TPairs.BeginArray(const aKey: string): TElements;
begin
  Result := inherited BeginArray(aKey);
end;

function TJSONCollectionBuilder.TPairs.EndObject: TParentCollection;
begin
  Result := inherited EndObject;
end;

function TJSONCollectionBuilder.TPairs.AsRoot: TPairs;
begin
  Result := Owner.PairsAsRoot;
end;

end.

