{
    This file is part of the Free Component Library
    Copyright (c) 2026 by Michael Van Canneyt michael@freepascal.org

    Delphi-compatible JSON Reader unit

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{$mode objfpc}
{$h+}
{$modeswitch advancedrecords}
{$modeswitch typehelpers}
{$scopedenums on}
{$macro on}

unit System.JSON.Readers;

interface

uses
  {$IFDEF FPC_DOTTEDUNITS}
  System.SysUtils, System.Classes, System.Generics.Collections, System.Rtti, Fcl.Streams.Extra,
  System.TypInfo, FpJson.Scanner,
  {$ELSE}
  SysUtils, Classes, Generics.Collections, Rtti, StreamEx, TypInfo,
  Moon.Internal.Json.Scanner,
  {$ENDIF}
  System.JSON.Utils, System.JSON,  System.NetEncoding, System.JSON.Types;

{$IFDEF FPC_DOTTEDUNITS}
{$define jscan:=FpJson.Scanner}
{$ELSE}
{$define jscan:=Moon.Internal.Json.Scanner}
{$ENDIF}

type
  TJSONAncestorList = specialize TList<TJSONAncestor>;
  TJsonToken = System.JSON.Types.TJsonToken;

  { TJsonTokenHelper }

  TJsonTokenHelper = type helper for TJsonToken
    function ToString : String;
  end;


  TJsonExtendedJsonMode = System.JSON.Types.TJsonExtendedJsonMode;
  TJsonDateParseHandling = System.JSON.Types.TJsonDateParseHandling;
  TJsonDateTimeZoneHandling = System.JSON.Types.TJsonDateTimeZoneHandling;

  TState = (Start, Complete, &Property, ObjectStart, &Object, arrayStart,
            &Array, Closed, PostValue, ConstructorStart, &Constructor,
            Error, Finished);

  { TJsonReader }
  TJsonReader = class(TJsonFiler)
  public
  type
    TReadType = (Read, ReadAsInteger, ReadAsBytes, ReadAsString, ReadAsDouble,
      ReadAsDateTime, ReadAsOid, ReadAsInt64, ReadAsUInt64);
  private
    FCloseInput: boolean;
    FDateTimeZoneHandling: TJsonDateTimeZoneHandling;
    FFormatSettings: TFormatSettings;
    FMaxDepth: integer;
    FQuoteChar: char;
    FSupportMultipleContent: boolean;
    FTokenType: TJsonToken;
    FValue: TValue;
    function GetDepth: integer;
  protected
    FCurrentState: TState;
    Procedure DoError(const aMsg : String); overload;
    Procedure DoError(const aFmt : String; const aArgs : Array of const); overload;

    function GetInsideContainer: boolean; override;
    procedure SetStateBasedOnCurrent;
    function ReadAsBytesInternal: TBytes;
    function ReadAsDateTimeInternal: TDateTime;
    function ReadAsDoubleInternal: double;
    function ReadAsIntegerInternal: integer;
    function ReadAsInt64Internal: int64;
    function ReadAsUInt64Internal: uint64;
    function ReadAsStringInternal: string;
    function ReadInternal: boolean; virtual; abstract;
    procedure SetPostValueState(aUpdateIndex: boolean);
    procedure SetToken(aNewToken: TJsonToken); overload; inline;
    procedure SetToken(aNewToken: TJsonToken; const aValue: TValue); overload; inline;
    procedure SetToken(aNewToken: TJsonToken; const aValue: TValue;
      aUpdateIndex: boolean); overload; inline;
    procedure SetNumberToken(const Text: string);
    generic procedure SetToken<T>(aNewToken: TJsonToken; const aValue: T; aUpdateIndex: boolean);
      overload; inline;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Close; virtual;
    procedure Rewind; override;
    function Read: boolean; virtual;
    function ReadAsInteger: integer; virtual;
    function ReadAsInt64: int64; virtual;
    function ReadAsUInt64: uint64; virtual;
    function ReadAsString: string; virtual;
    function ReadAsBytes: TBytes; virtual;
    function ReadAsDouble: double; virtual;
    function ReadAsDateTime: TDateTime; virtual;
    procedure Skip; virtual;
    property CloseInput: boolean read FCloseInput write FCloseInput;
    property CurrentState: TState read FCurrentState;
    property Depth: integer read GetDepth;
    property TokenType: TJsonToken read FTokenType;
    property MaxDepth: integer read FMaxDepth write FMaxDepth;
    property QuoteChar: char read FQuoteChar write FQuoteChar;
    property SupportMultipleContent: boolean
      read FSupportMultipleContent write FSupportMultipleContent;
    property DateTimeZoneHandling: TJsonDateTimeZoneHandling
      read FDateTimeZoneHandling write FDateTimeZoneHandling;
    property FormatSettings: TFormatSettings read FFormatSettings write FFormatSettings;
    property Value: TValue read FValue;
  end;

  { EJsonReaderException }
  EJsonReaderException = class(EJsonException)
  private
    FLineNumber: integer;
    FLinePosition: integer;
    FPath: string;
  public
    constructor Create(const Msg: string; const aPath: string;
      aLineNumber: integer; aLinePosition: integer); overload;
    constructor Create(const Reader: TJsonReader; const Msg: string); overload;
    constructor Create(const LineInfo: TJsonLineInfo; const Path, Msg: string); overload;
    constructor CreateFmt(const Reader: TJsonReader; const Msg: string;
      const args: array of const); overload;
    constructor CreateFmt(const LineInfo: TJsonLineInfo; const Path, Msg: string;
      const args: array of const); overload;
    property LineNumber: integer read FLineNumber;
    property LinePosition: integer read FLinePosition;
    property Path: string read FPath;
  end;

  { TJsonTextReader }
  TJsonTextReader = class(TJsonReader)
  private
    FDateParseHandling: TJsonDateParseHandling;
    FExtendedJsonMode: TJsonExtendedJsonMode;
    FReader: TTextReader;
    FScanner: TJSONScanner;
    FNeedSeparator, FAfterComma: Boolean;
    FContent: string;
  protected
    function ReadInternal: boolean; override;
  public
    constructor Create(const aReader: TTextReader);
    destructor Destroy; override;
    procedure Close; override;
    procedure Rewind; override;
    function GetLineNumber: integer; override;
    function GetLinePosition: integer; override;
    function HasLineInfo: boolean; override;
    property Reader: TTextReader read FReader;
    property LineNumber: integer read GetLineNumber;
    property LinePosition: integer read GetLinePosition;
    property DateParseHandling: TJsonDateParseHandling
      read FDateParseHandling write FDateParseHandling;
    property ExtendedJsonMode: TJsonExtendedJsonMode
      read FExtendedJsonMode write FExtendedJsonMode;
  end;

  { TJsonObjectReader }

  { TJSONAncestorData }


  TJsonObjectReader = class(TJsonReader)
  private
    Type
       TContainerData = Class
         Ancestor : TJSONAncestor;
         CurrentIndex : Integer;
         constructor Create(aAncestor : TJSONAncestor);
       end;
       TJSONAncestorDataList = specialize TObjectList<TContainerData>;
  private
    FRoot: TContainerData;
    FReadDone: Boolean;
    FCurrentNode: TJSONAncestor;
    FAncestors : TJSONAncestorDataList;
    function GetCurrent: TJSONAncestor;
    function GetCurrentData : TContainerData;
  protected
    function ReadInternal: boolean; override;
  public
    constructor Create(const aRoot: TJSONAncestor);
    destructor Destroy; override;
    procedure Close; override;
    procedure Rewind; override;
    property Current: TJSONAncestor read GetCurrent;
  end;

implementation

uses
  {$IFDEF FPC_DOTTEDUNITS}
  System.DateUtils, System.Math, System.Character,
  {$ELSE}
  DateUtils, Math, Character,
  {$ENDIF}
  System.JSONConsts;

{ TJsonTokenHelper }

function TJsonTokenHelper.ToString: String;
begin
  Result:=GetEnumName(TypeInfo(TJSONToken),Ord(Self));
end;

{ TJsonReader }

function TJsonReader.GetDepth: integer;
begin
  Result:=FStack.Count;
end;

procedure TJsonReader.DoError(const aMsg: String);
begin
  raise EJsonReaderException.Create(Self,aMsg)
end;

procedure TJsonReader.DoError(const aFmt: String; const aArgs: array of const);
begin
  raise EJsonReaderException.CreateFmt(Self,aFmt,aArgs)
end;

function TJsonReader.GetInsideContainer: boolean;
begin
  Result:=(FCurrentState in [TState.&Object, TState.&Array, TState.&Constructor]) and
    (FTokenType <> TJsonToken.PropertyName);
end;

procedure TJsonReader.SetStateBasedOnCurrent;
begin
  case FTokenType of
    TJsonToken.StartObject:
      FCurrentState:=TState.ObjectStart;
    TJsonToken.StartArray:
      FCurrentState:=TState.ArrayStart;
    TJsonToken.StartConstructor:
      FCurrentState:=TState.ConstructorStart;
    TJsonToken.PropertyName:
      FCurrentState:=TState.&Property;
    TJsonToken.Comment:
      ; // No state change for comments
    TJsonToken.EndObject,
    TJsonToken.EndArray,
    TJsonToken.EndConstructor:
      FCurrentState:=TState.PostValue;
    else
      FCurrentState:=TState.PostValue;
  end;
end;

function TJsonReader.ReadAsBytesInternal: TBytes;
begin
  ReadInternal;
  if FTokenType = TJsonToken.Bytes then
    Result:=FValue.specialize AsType<TBytes>
  else if FTokenType = TJsonToken.&String then
    Result:=TNetEncoding.Base64.DecodeStringToBytes(FValue.AsString)
  else if FTokenType = TJsonToken.Null then
    Result:=nil
  else
    DoError(SUnexpectedTokenReadBytes,[GetEnumName(TypeInfo(TJsonToken), Ord(FTokenType))]);
end;

function TJsonReader.ReadAsDateTimeInternal: TDateTime;
var
  S: string;
  Parsed: Boolean;
begin
  ReadInternal;
  if FTokenType = TJsonToken.Date then
    Result:=FValue.specialize AsType<TDateTime>
  else if FTokenType = TJsonToken.&String then
    begin
    S:=FValue.AsString;
    Parsed:=False;
    if (Length(S)<=10) or (S[11]='T') or (S[9]='T') then
      Parsed:=TryISO8601ToDate(S,Result,True);
    if not Parsed then
      Parsed:=TryStrToDateTime(S,Result,FFormatSettings);
    if not Parsed then
      DoError('Invalid date');
    if FDateTimeZoneHandling=TJsonDateTimeZoneHandling.Local then
      Result:=TTimeZone.Local.ToLocalTime(Result);
    end
  else if FTokenType = TJsonToken.Null then
    Result:=0
  else
    DoError(SUnexpectedTokenDate ,[GetEnumName(TypeInfo(TJsonToken), Ord(FTokenType))]);
end;

function TJsonReader.ReadAsDoubleInternal: double;
var
  S: string;
begin
  ReadInternal;
  case FTokenType of
    TJsonToken.integer:
      Result:=FValue.specialize AsType<integer>;
    TJsonToken.Float:
      Result:=FValue.specialize AsType<double>;
    TJsonToken.&String:
      begin
      S:=FValue.AsString;
      if not TryStrToFloat(S, Result, FFormatSettings) then
        DoError(SInputInvalidDouble,[S]);
      end;
    TJsonToken.Null:
      Result:=0.0;
    else
      DoError(SInputInvalidDouble,[GetEnumName(TypeInfo(TJsonToken), Ord(FTokenType))]);
  end;
end;

function TJsonReader.ReadAsIntegerInternal: integer;
var
  S: string;
begin
  ReadInternal;
  case FTokenType of
    TJsonToken.integer:
      Result:=FValue.specialize AsType<integer>;
    TJsonToken.Float:
      Result:=Trunc(FValue.Specialize AsType<double>);
    TJsonToken.&String:
      begin
      S:=FValue.AsString;
      if not TryStrToInt(S, Result) then
        DoError(SInputInvalidInteger,[S]);
      end;
    TJsonToken.Null:
      Result:=0;
    else
      DoError(SInputInvalidInteger,[GetEnumName(TypeInfo(TJsonToken), Ord(FTokenType))]);
  end;
end;

function TJsonReader.ReadAsInt64Internal: int64;
var
  S: string;
begin
  ReadInternal;
  case FTokenType of
    TJsonToken.integer:
      Result:=FValue.specialize AsType<int64>;
    TJsonToken.Float:
      Result:=Trunc(FValue.specialize AsType<double>);
    TJsonToken.&String:
      begin
      S:=FValue.AsString;
      if not TryStrToInt64(S, Result) then
        DoError(SInputInvalidInt64,[S]);
      end;
    TJsonToken.Null:
      Result:=0;
    else
      DoError(SInputInvalidInt64,[GetEnumName(TypeInfo(TJsonToken), Ord(FTokenType))]);
  end;
end;

function TJsonReader.ReadAsUInt64Internal: uint64;
var
  S: string;
begin
  ReadInternal;
  case FTokenType of
    TJsonToken.integer:
      Result:=FValue.specialize AsType<uint64>;
    TJsonToken.Float:
      Result:=Trunc(FValue.specialize AsType<double>);
    TJsonToken.&String:
      begin
      S:=FValue.AsString;
      if not TryStrToUInt64(S, Result) then
        DoError(SInputInvalidUInt64,[S]);
      end;
    TJsonToken.Null:
      Result:=0;
    else
      DoError(SInputInvalidUInt64,[GetEnumName(TypeInfo(TJsonToken), Ord(FTokenType))]);
  end;
end;

function TJsonReader.ReadAsStringInternal: string;
begin
  ReadInternal;
  case FTokenType of
    TJsonToken.&String,
    TJsonToken.PropertyName:
      Result:=FValue.AsString;
    TJsonToken.integer:
      Result:=IntToStr(FValue.specialize AsType<integer>);
    TJsonToken.Float:
      Result:=FloatToStr(FValue.specialize AsType<double>, FFormatSettings);
    TJsonToken.boolean:
      Result:=BoolToStr(FValue.specialize AsType<boolean>, True);
    TJsonToken.Null:
      Result:='';
    else
      Result:=FValue.AsString;
  end;
end;

procedure TJsonReader.SetPostValueState(aUpdateIndex: boolean);
begin
  if Peek = TJsonContainerType.&Array then
    begin
    FCurrentPosition.Position:=FCurrentPosition.Position + 1;
    FCurrentState:=TState.&Array;
    end
  else if Peek = TJsonContainerType.&Object then
    FCurrentState:=TState.&Object
  else
    FCurrentState:=TState.PostValue;
end;

procedure TJsonReader.SetToken(aNewToken: TJsonToken);
begin
  SetToken(aNewToken, TValue.Empty, True);
end;

procedure TJsonReader.SetToken(aNewToken: TJsonToken; const aValue: TValue);
begin
  SetToken(aNewToken, aValue, True);
end;

procedure TJsonReader.SetToken(aNewToken: TJsonToken; const aValue: TValue;
  aUpdateIndex: boolean);
begin
  FTokenType:=aNewToken;
  FValue:=aValue;

  case aNewToken of
    TJsonToken.StartObject:
      begin
      Push(TJsonContainerType.&Object);
      FCurrentState:=TState.ObjectStart;
      end;
    TJsonToken.StartArray:
      begin
      Push(TJsonContainerType.&Array);
      FCurrentState:=TState.ArrayStart;
      end;
    TJsonToken.StartConstructor:
      begin
      Push(TJsonContainerType.&Constructor);
      FCurrentState:=TState.ConstructorStart;
      end;
    TJsonToken.PropertyName:
      begin
      FCurrentPosition.PropertyName:=aValue.AsString;
      FCurrentState:=TState.&Property;
      end;
    TJsonToken.EndObject:
      begin
      if FCurrentState = TState.&Property then
        DoError(SInvalidState, [GetEnumName(typeInfo(TState), Ord(FCurrentState))]);
      Pop;
      SetPostValueState(aUpdateIndex);
      end;

    TJsonToken.EndArray,
    TJsonToken.EndConstructor:
      begin
      Pop;
      SetPostValueState(aUpdateIndex);
      end;
    else
      SetPostValueState(aUpdateIndex);
  end;
end;

generic procedure TJsonReader.SetToken<T>(aNewToken: TJsonToken; const aValue: T;
  aUpdateIndex: boolean);
begin
  SetToken(aNewToken, TValue.specialize From<T>(aValue), aUpdateIndex);
end;

procedure TJsonReader.SetNumberToken(const Text: string);
var
  SignedValue: Int64;
  UnsignedValue: UInt64;
  RealValue: Double;
begin
  if (Pos('.',Text)>0) or (Pos('e',Text)>0) or (Pos('E',Text)>0) then
    begin
    if not TryStrToFloat(Text,RealValue,TFormatSettings.Invariant) then
      DoError('Invalid or overflowing JSON number');
    specialize SetToken<Double>(TJsonToken.Float,RealValue,True);
    end
  else if TryStrToInt64(Text,SignedValue) then
    specialize SetToken<Int64>(TJsonToken.Integer,SignedValue,True)
  else if TryStrToQWord(Text,UnsignedValue) then
    specialize SetToken<UInt64>(TJsonToken.Integer,UnsignedValue,True)
  else
    DoError('JSON integer is outside the 64-bit range');
end;

constructor TJsonReader.Create;
begin
  inherited Create;
  FCloseInput:=True; 
  FMaxDepth:=64;
  FQuoteChar:='"';
  FDateTimeZoneHandling:=TJsonDateTimeZoneHandling.Local;
  FFormatSettings:=JSONFormatSettings;
  FCurrentState:=TState.Start;
  FSupportMultipleContent:=False;
end;

destructor TJsonReader.Destroy;
begin
  inherited Destroy;
end;

procedure TJsonReader.Close;
begin
  FCurrentState:=TState.Closed;
end;

procedure TJsonReader.Rewind;
begin
  inherited Rewind;
end;

function TJsonReader.Read: boolean;
begin
  Result:=ReadInternal;
end;

function TJsonReader.ReadAsInteger: integer;
begin
  Result:=ReadAsIntegerInternal;
end;

function TJsonReader.ReadAsInt64: int64;
begin
  Result:=ReadAsInt64Internal;
end;

function TJsonReader.ReadAsUInt64: uint64;
begin
  Result:=ReadAsUInt64Internal;
end;

function TJsonReader.ReadAsString: string;
begin
  Result:=ReadAsStringInternal;
end;

function TJsonReader.ReadAsBytes: TBytes;
begin
  Result:=ReadAsBytesInternal;
end;

function TJsonReader.ReadAsDouble: double;
begin
  Result:=ReadAsDoubleInternal;
end;

function TJsonReader.ReadAsDateTime: TDateTime;
begin
  Result:=ReadAsDateTimeInternal;
end;

procedure TJsonReader.Skip;
var
  lDepth: integer;
  lState: TState;
begin
  if FTokenType = TJsonToken.PropertyName then
    Read;

  if FTokenType in [TJsonToken.StartObject, TJsonToken.StartArray,
    TJsonToken.StartConstructor] then
    begin
    lDepth:=GetDepth;
    // Skip until we're back to the original depth
    while Read and (GetDepth >= lDepth) do ;
{
      begin
      lState:=CurrentState;
      Writeln(FTokenType,' : ',lState);
      end;
}
    end;
end;

{ EJsonReaderException }

constructor EJsonReaderException.Create(const Msg: string; const aPath: string;
  aLineNumber: integer; aLinePosition: integer);
begin
  inherited Create(Msg);
  FPath:=aPath;
  FLineNumber:=aLineNumber;
  FLinePosition:=aLinePosition;
end;

constructor EJsonReaderException.Create(const Reader: TJsonReader; const Msg: string);
begin
  inherited Create(Msg);
  if assigned(Reader) then
    begin
    FPath:=Reader.Path;
    FLineNumber:=Reader.GetLineNumber;
    FLinePosition:=Reader.GetLinePosition;
    end;
end;

constructor EJsonReaderException.Create(const LineInfo: TJsonLineInfo;
  const Path, Msg: string);
begin
  inherited Create(Msg);
  FPath:=Path;
  if assigned(LineInfo) then
    begin
    FLineNumber:=LineInfo.GetLineNumber;
    FLinePosition:=LineInfo.GetLinePosition;
    end;
end;

constructor EJsonReaderException.CreateFmt(const Reader: TJsonReader;
  const Msg: string; const args: array of const);
begin
  Create(Reader, Format(Msg, args));
end;

constructor EJsonReaderException.CreateFmt(const LineInfo: TJsonLineInfo;
  const Path, Msg: string; const args: array of const);
begin
  Create(LineInfo, Path, Format(Msg, args));
end;

{ TJsonTextReader }

function TJsonTextReader.ReadInternal: boolean;
var
  Token: jscan.TJSONToken;
  Text: string;
  PropertyName: Boolean;
begin
  Result:=False;
  if not Assigned(FScanner) or (FCurrentState in [TState.Closed,TState.Finished]) then
    Exit;
  try
    repeat
      Token:=FScanner.FetchToken;
      if Token in [jscan.tkWhitespace,jscan.tkComment] then
        Continue;
      if Token=jscan.tkEOF then
        begin
        if Peek<>TJsonContainerType.None then
          DoError('Unexpected end of JSON');
        SetToken(TJsonToken.None);
        FCurrentState:=TState.Finished;
        Exit;
        end;
      if Token=jscan.tkComma then
        begin
        if not FNeedSeparator or (Peek=TJsonContainerType.None) then
          DoError('Unexpected JSON comma');
        FNeedSeparator:=False;
        FAfterComma:=True;
        Continue;
        end;
      if Token in [jscan.tkCurlyBraceClose,jscan.tkSquaredBraceClose] then
        begin
        if FAfterComma or (FCurrentState=TState.&Property) then
          DoError('Missing JSON value');
        if Token=jscan.tkCurlyBraceClose then
          begin
          if Peek<>TJsonContainerType.&Object then
            DoError('Mismatched JSON object end');
          SetToken(TJsonToken.EndObject);
          end
        else
          begin
          if Peek<>TJsonContainerType.&Array then
            DoError('Mismatched JSON array end');
          SetToken(TJsonToken.EndArray);
          end;
        FNeedSeparator:=True;
        Exit(True);
        end;
      if FNeedSeparator then
        begin
        if (Peek<>TJsonContainerType.None) or not SupportMultipleContent then
          DoError('Missing JSON separator');
        end;
      FAfterComma:=False;
      PropertyName:=(Peek=TJsonContainerType.&Object) and (FCurrentState<>TState.&Property);
      if PropertyName and not (Token in [jscan.tkString,jscan.tkIdentifier]) then
        DoError('Object property name expected');
      case Token of
        jscan.tkString,jscan.tkIdentifier:
          begin
          Text:=UTF8Decode(FScanner.CurTokenString);
          if PropertyName then
            begin
            specialize SetToken<string>(TJsonToken.PropertyName,Text,True);
            repeat
              Token:=FScanner.FetchToken;
            until not (Token in [jscan.tkWhitespace,jscan.tkComment]);
            if Token<>jscan.tkColon then
              DoError('Property colon expected');
            FNeedSeparator:=False;
            end
          else
            begin
            if Token=jscan.tkIdentifier then
              DoError('Unexpected JSON identifier');
            specialize SetToken<string>(TJsonToken.&String,Text,True);
            FNeedSeparator:=True;
            end;
          end;
        jscan.tkNumber:
          begin
          SetNumberToken(string(FScanner.CurTokenString));
          FNeedSeparator:=True;
          end;
        jscan.tkTrue,jscan.tkFalse:
          begin
          specialize SetToken<Boolean>(TJsonToken.Boolean,Token=jscan.tkTrue,True);
          FNeedSeparator:=True;
          end;
        jscan.tkNull:
          begin
          SetToken(TJsonToken.Null);
          FNeedSeparator:=True;
          end;
        jscan.tkCurlyBraceOpen,jscan.tkSquaredBraceOpen:
          begin
          if (MaxDepth>0) and (Depth>=MaxDepth) then
            DoError('Maximum JSON nesting depth exceeded');
          if Token=jscan.tkCurlyBraceOpen then
            SetToken(TJsonToken.StartObject)
          else
            SetToken(TJsonToken.StartArray);
          FNeedSeparator:=False;
          end;
        else
          DoError('Unexpected JSON token');
      end;
      Exit(True);
    until False;
  except
    on E: EScannerError do
      DoError(E.Message);
  end;
end;

constructor TJsonTextReader.Create(const aReader: TTextReader);
begin
  inherited Create;
  FReader:=aReader;
  FDateParseHandling:=TJsonDateParseHandling.DateTime;
  FExtendedJsonMode:=TJsonExtendedJsonMode.None;

  FContent:='';
  while not FReader.EOF do
    FContent:=FContent+FReader.ReadLine+sLineBreak;
  FScanner:=TJSONScanner.Create(UTF8Encode(FContent),[joUTF8]);
end;

destructor TJsonTextReader.Destroy;
begin
  FreeAndNil(FScanner);
  if CloseInput then
    FreeAndNil(FReader);
  inherited Destroy;
end;

procedure TJsonTextReader.Close;
begin
  inherited Close;
  if CloseInput then
    FreeAndNil(FReader);
end;

procedure TJsonTextReader.Rewind;
begin
  inherited Rewind;
  FCurrentState:=TState.Start;

  // Recreate scanner to reset position
  FreeAndNil(FScanner);
  FScanner:=TJSONScanner.Create(UTF8Encode(FContent),[joUTF8]);
  FNeedSeparator:=False;
  FAfterComma:=False;
end;

function TJsonTextReader.GetLineNumber: integer;
begin
  if assigned(FScanner) then
    Result:=FScanner.CurRow
  else
    Result:=0;
end;

function TJsonTextReader.GetLinePosition: integer;
begin
  if assigned(FScanner) then
    Result:=FScanner.CurColumn
  else
    Result:=0;
end;

function TJsonTextReader.HasLineInfo: boolean;
begin
  Result:=assigned(FScanner);
end;

{ TContainerData }

constructor TJsonObjectReader.TContainerData.Create(aAncestor: TJSONAncestor);
begin
  Ancestor:=aAncestor;
  CurrentIndex:=-2;
end;

{ TJsonObjectReader }

function TJsonObjectReader.GetCurrent: TJSONAncestor;
begin
  Result:=FCurrentNode;
end;

function TJsonObjectReader.GetCurrentData: TContainerData;
begin
  if (FAncestors.Count > 0) then
    Result:=FAncestors[FAncestors.Count - 1]
  else
    Result:=FRoot;
end;

function TJsonObjectReader.ReadInternal: boolean;
var
  Frame: TContainerData;
  Node: TJSONAncestor;
  Obj: TJSONObject;
  Arr: TJSONArray;

  procedure FinishFrame;
  begin
    if FAncestors.Count=0 then
      FReadDone:=True
    else
      FAncestors.Delete(FAncestors.Count-1);
  end;

begin
  if FReadDone then
    begin
    SetToken(TJsonToken.None);
    FCurrentState:=TState.Finished;
    Exit(False);
    end;
  repeat
    Frame:=GetCurrentData;
    Node:=Frame.Ancestor;
    FCurrentNode:=Node;
    if Node=nil then
      begin
      FReadDone:=True;
      Exit(False);
      end;
    if Node is TJSONObject then
      begin
      Obj:=TJSONObject(Node);
      if Frame.CurrentIndex=-2 then
        begin
        Frame.CurrentIndex:=0;
        SetToken(TJsonToken.StartObject);
        Exit(True);
        end;
      if Frame.CurrentIndex>=Obj.Count*2 then
        begin
        SetToken(TJsonToken.EndObject);
        FinishFrame;
        Exit(True);
        end;
      if (Frame.CurrentIndex and 1)=0 then
        begin
        specialize SetToken<UnicodeString>(TJsonToken.PropertyName,
          Obj.Pairs[Frame.CurrentIndex div 2].JsonString.Value,True);
        Inc(Frame.CurrentIndex);
        Exit(True);
        end;
      Node:=Obj.Pairs[Frame.CurrentIndex div 2].JsonValue;
      Inc(Frame.CurrentIndex);
      FAncestors.Add(TContainerData.Create(Node));
      end
    else if Node is TJSONArray then
      begin
      Arr:=TJSONArray(Node);
      if Frame.CurrentIndex=-2 then
        begin
        Frame.CurrentIndex:=0;
        SetToken(TJsonToken.StartArray);
        Exit(True);
        end;
      if Frame.CurrentIndex>=Arr.Count then
        begin
        SetToken(TJsonToken.EndArray);
        FinishFrame;
        Exit(True);
        end;
      Node:=Arr.Items[Frame.CurrentIndex];
      Inc(Frame.CurrentIndex);
      FAncestors.Add(TContainerData.Create(Node));
      end
    else
      begin
      if Node is TJSONNumber then
        SetNumberToken(TJSONNumber(Node).Value)
      else if Node is TJSONString then
        specialize SetToken<UnicodeString>(TJsonToken.&String,TJSONString(Node).Value,True)
      else if Node is TJSONBool then
        specialize SetToken<Boolean>(TJsonToken.Boolean,TJSONBool(Node).Value='true',True)
      else if Node is TJSONNull then
        SetToken(TJsonToken.Null)
      else
        DoError('Unsupported JSON node type');
      FinishFrame;
      Exit(True);
      end;
  until False;
end;

constructor TJsonObjectReader.Create(const aRoot: TJSONAncestor);
begin
  inherited Create;
  FRoot:=TContainerData.Create(aRoot);
  FAncestors:=TJSONAncestorDataList.Create(True);
end;

destructor TJsonObjectReader.Destroy;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FAncestors);
  inherited Destroy;
end;

procedure TJsonObjectReader.Close;
begin
  inherited Close;
end;

procedure TJsonObjectReader.Rewind;
begin
  inherited Rewind;
  FAncestors.Clear;
  FRoot.CurrentIndex:=-2;
  FReadDone:=False;
  FCurrentNode:=nil;
  FCurrentState:=TState.Start;
end;

end.
