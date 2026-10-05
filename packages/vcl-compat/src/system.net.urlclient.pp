{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2026 by the MoonCompiler contributors

    Header, request and certificate types of the Delphi System.Net.URLClient
    surface that System.Net.HttpClient and its callers use.

    Provenance: written for MoonCompiler from the behavioural contract in the
    planning document "DELPHI_SURFACE_ADDITIONS_20260920" (section 3.1) and
    RFC 9110.  No Embarcadero source, interface text or documentation excerpt
    was consulted or copied for the original implementation. Release 2.1 additions
    use public API declarations and RFC contracts, not Delphi implementation. Author: MoonCompiler team, 2026-09-21.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
unit System.Net.URLClient;

{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}
{$SCOPEDENUMS ON}
{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Classes, Types, SyncObjs, RtlConsts;

type
  TNameValuePair = record
    Name: string;
    Value: string;
    constructor Create(const AName, AValue: string);
  end;
  TNetHeader = TNameValuePair;
  TNetHeaders = array of TNetHeader;

  { A header collection over a TNetHeaders array, kept in insertion order.
    Value[] reads the first header of that name (the case of the name does
    not matter), '' when absent; writing it replaces the first one or appends.
    Add always appends (a second Set-Cookie is legitimate); Delete(name)
    removes every header of the name; the mutators answer the collection
    itself, so calls chain.  Iterable with for-in.  Names[]/Values[] by
    index raise EListError outside 0..Count-1. }
  TURLHeaders = class(TPersistent)
  public type
    TEnumerator = record
    private
      FOwner: TURLHeaders;
      FNext: Integer;
      function GetCurrent: TNetHeader;
    public
      function MoveNext: Boolean;
      property Current: TNetHeader read GetCurrent;
    end;
  private
    FHeaders: TNetHeaders;
    function GetCount: Integer;
    function GetNames(AIndex: Integer): string;
    function GetValues(AIndex: Integer): string;
    function GetValue(const AName: string): string;
    procedure SetValue(const AName, AValue: string);
    procedure Guard(AIndex: Integer);
  public
    function FindItem(const AName: string): Integer;
    function Add(const AHeader: TNetHeader): TURLHeaders; overload;
    function Add(const AName, AValue: string): TURLHeaders; overload;
    function Append(const AHeaders: TNetHeaders): TURLHeaders; overload;
    function Append(const AHeaders: TURLHeaders): TURLHeaders; overload;
    function Clear: TURLHeaders;
    function Delete(AIndex: Integer): TURLHeaders; overload;
    function Delete(const AName: string): TURLHeaders; overload;
    procedure Assign(ASource: TPersistent); overload; override;
    procedure Assign(const AHeaders: TNetHeaders); reintroduce; overload;
    function GetEnumerator: TEnumerator;
    function ToString: string; override;
    property Count: Integer read GetCount;
    property Headers: TNetHeaders read FHeaders;
    property Names[AIndex: Integer]: string read GetNames;
    property Values[AIndex: Integer]: string read GetValues;
    property Value[const AName: string]: string read GetValue write SetValue; default;
  end;

  {$i urlclient.types.inc}

  TCertificate = record
    CertName: string;
    SerialNum: string;
    Subject: string;
    Issuer: string;
    Expiry: TDateTime;
    Start: TDateTime;
  end;

  TValidateCertificateEvent = procedure(const Sender: TObject; const ARequest: TURLRequest;
    const Certificate: TCertificate; var Accepted: Boolean) of object;

  ENetException = class(Exception);
  ENetURIException = class(ENetException);
  ENetURIClientException = class(ENetException);
  ENetURIRequestException = class(ENetException);
  ENetURIResponseException = class(ENetException);

implementation

uses URIParser, System.NetEncoding;

{$i urlclient.impl.inc}

constructor TNameValuePair.Create(const AName, AValue: string);
begin
  Name := AName;
  Value := AValue;
end;

{ TURLHeaders.TEnumerator }

function TURLHeaders.TEnumerator.MoveNext: Boolean;
begin
  Result := FNext < Length(FOwner.FHeaders);
  if Result then
    Inc(FNext);
end;

function TURLHeaders.TEnumerator.GetCurrent: TNetHeader;
begin
  Result := FOwner.FHeaders[FNext - 1];
end;

{ TURLHeaders }

function TURLHeaders.GetEnumerator: TEnumerator;
begin
  Result.FOwner := Self;
  Result.FNext := 0;
end;

function TURLHeaders.GetCount: Integer;
begin
  Result := Length(FHeaders);
end;

procedure TURLHeaders.Guard(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= Length(FHeaders)) then
    raise EListError.CreateFmt(SListIndexError, [AIndex]);
end;

function TURLHeaders.GetNames(AIndex: Integer): string;
begin
  Guard(AIndex);
  Result := FHeaders[AIndex].Name;
end;

function TURLHeaders.GetValues(AIndex: Integer): string;
begin
  Guard(AIndex);
  Result := FHeaders[AIndex].Value;
end;

{ the first header of that name, -1 when there is none }
function TURLHeaders.FindItem(const AName: string): Integer;
begin
  Result := 0;
  while (Result < Length(FHeaders)) and not SameText(FHeaders[Result].Name, AName) do
    Inc(Result);
  if Result = Length(FHeaders) then
    Result := -1;
end;

function TURLHeaders.GetValue(const AName: string): string;
var
  At: Integer;
begin
  At := FindItem(AName);
  if At < 0 then
    Exit('');
  Result := FHeaders[At].Value;
end;

procedure TURLHeaders.SetValue(const AName, AValue: string);
var
  At: Integer;
begin
  At := FindItem(AName);
  if At >= 0 then
    FHeaders[At].Value := AValue
  else
    Add(AName, AValue);
end;

function TURLHeaders.Add(const AHeader: TNetHeader): TURLHeaders;
begin
  SetLength(FHeaders, Length(FHeaders) + 1);
  FHeaders[High(FHeaders)] := AHeader;
  Result := Self;
end;

function TURLHeaders.Add(const AName, AValue: string): TURLHeaders;
begin
  Result := Add(TNetHeader.Create(AName, AValue));
end;

function TURLHeaders.Append(const AHeaders: TNetHeaders): TURLHeaders;
var
  H: TNetHeader;
begin
  for H in AHeaders do
    Add(H);
  Result := Self;
end;

function TURLHeaders.Append(const AHeaders: TURLHeaders): TURLHeaders;
begin
  if AHeaders <> nil then
    Append(AHeaders.FHeaders);
  Result := Self;
end;

function TURLHeaders.Clear: TURLHeaders;
begin
  FHeaders := nil;
  Result := Self;
end;

function TURLHeaders.Delete(AIndex: Integer): TURLHeaders;
begin
  Guard(AIndex);
  FHeaders := Concat(Copy(FHeaders, 0, AIndex), Copy(FHeaders, AIndex + 1, MaxInt));
  Result := Self;
end;

function TURLHeaders.Delete(const AName: string): TURLHeaders;
var
  Keep: TNetHeaders;
  H: TNetHeader;
  N: Integer;
begin
  SetLength(Keep, Length(FHeaders));
  N := 0;
  for H in FHeaders do
    if not SameText(H.Name, AName) then
    begin
      Keep[N] := H;
      Inc(N);
    end;
  SetLength(Keep, N);
  FHeaders := Keep;
  Result := Self;
end;

{ a header collection copies the array; a TStrings of name=value lines is
  read line by line (the last line of a name wins, as Value[] replaces);
  anything else is left to TPersistent, which raises EConvertError }
procedure TURLHeaders.Assign(ASource: TPersistent);
var
  Lines: TStrings;
  I: Integer;
begin
  if (ASource <> nil) and ASource.InheritsFrom(TStrings) then
  begin
    Lines := TStrings(ASource);
    Clear;
    for I := 0 to Lines.Count - 1 do
      Value[Lines.Names[I]] := Lines.ValueFromIndex[I];
    Exit;
  end;
  if (ASource = nil) or not ASource.InheritsFrom(TURLHeaders) then
  begin
    inherited Assign(ASource);
    Exit;
  end;
  FHeaders := Copy(TURLHeaders(ASource).FHeaders);
end;

procedure TURLHeaders.Assign(const AHeaders: TNetHeaders);
begin
  FHeaders := Copy(AHeaders);
end;

function TURLHeaders.ToString: string;
var
  H: TNetHeader;
begin
  Result := '';
  for H in FHeaders do
    Result := Result + H.Name + ': ' + H.Value + #13#10;
end;

initialization
  InitCriticalSection(URLSchemesLock);
finalization
  DoneCriticalSection(URLSchemesLock);
end.
