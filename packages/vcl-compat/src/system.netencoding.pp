  {
    This file is part of the Free Pascal run time library.
    Copyright (c) 2019 by Michael Van Canneyt, member of the
    Free Pascal development team

    VCL compatible TNetEncoding unit

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{$mode objfpc}
{$H+}

unit System.NetEncoding;

interface

{$IFDEF FPC_DOTTEDUNITS}
uses System.SysUtils, System.Classes, System.Types, System.Hash.Base64;
{$ELSE FPC_DOTTEDUNITS}
uses Sysutils, Classes, Types, Base64;
{$ENDIF FPC_DOTTEDUNITS}

type
  // Not used here
  EHTTPException = class(Exception);

  UnsafeChar = Byte;
  TUnsafeChars = set of UnsafeChar;
  TURLEncoding = Class;

  { TNetEncoding }

  TNetEncoding = class
  private
    type
      TStandardEncoding = (
        seBase64,
        seBase64String,
        seBase64URL,
        seHTML,
        seURL);
    Class var
      FStdEncodings : Array[TStandardEncoding] of TNetEncoding;
    Class Function GetStdEncoding(aIndex : TStandardEncoding) : TNetEncoding; Static;
    Class Destructor Destroy;
    class function GetURLEncoding: TURLEncoding; static;
  protected
    // These must be implemented by descendents
    Function DoDecode(const aInput: RawByteString): RawByteString; overload; virtual; abstract;
    Function DoEncode(const aInput: RawByteString): RawByteString; overload; virtual; abstract;

    // These can be overridden by descendents for efficiency
    Function DoDecode(const aInput: UnicodeString): UnicodeString; overload; virtual;
    Function DoEncode(const aInput: UnicodeString): UnicodeString; overload; virtual;

    Function DoDecode(const aInput, aOutput: TStream): Integer; overload; virtual;
    Function DoEncode(const aInput, aOutput: TStream): Integer; overload; virtual;

    Function DoDecode(const aInput: array of Byte): TBytes; overload; virtual;
    Function DoEncode(const aInput: array of Byte): TBytes; overload; virtual;

    Function DoDecodeStringToBytes(const aInput: RawByteString): TBytes; virtual; overload;
    Function DoDecodeStringToBytes(const aInput: UnicodeString): TBytes; virtual; overload;
    Function DoEncodeBytesToString(const aInput: array of Byte): UnicodeString; overload; virtual;
    Function DoEncodeBytesToString(const aInput: Pointer; Size: Integer): UnicodeString; overload; virtual;
  public
    Class Procedure FreeStdEncodings;
    // Public stubs, they call the Do* versions
    // Stream
    Function Decode(const aInput, aOutput: TStream): Integer; overload;
    Function Encode(const aInput, aOutput: TStream): Integer; overload;
    // TBytes
    Function Decode(const aInput: array of Byte): TBytes; overload;
    Function Encode(const aInput: array of Byte): TBytes; overload;
    // Strings
    Function Decode(const aInput: UnicodeString): UnicodeString; overload;
    Function Encode(const aInput: UnicodeString): UnicodeString; overload;
    Function Decode(const aInput: RawByteString): RawByteString; overload;
    Function Encode(const aInput: RawByteString): RawByteString; overload;
    // UnicodeString to Bytes
    Function DecodeStringToBytes(const aInput: UnicodeString): TBytes;
    Function DecodeStringToBytes(const aInput: RawByteString): TBytes;
    Function EncodeBytesToString(const aInput: array of Byte): UnicodeString; overload;
    Function EncodeBytesToString(const aInput: Pointer; Size: Integer): UnicodeString; overload;
    // Default instances
    class property Base64: TNetEncoding Index seBase64 read GetStdEncoding;
    class property Base64URL: TNetEncoding Index seBase64URL read GetStdEncoding;
    class property Base64String: TNetEncoding Index seBase64String read GetStdEncoding;
    class property HTML: TNetEncoding Index seHTML read GetStdEncoding;
    class property URL: TURLEncoding read GetURLEncoding;
  end;

  { TCustomBase64Encoding }

  TCustomBase64Encoding = class(TNetEncoding)
  protected const
    kCharsPerLine = 76;
    kLineSeparator = #13#10;
  protected
    FCharsPerline: Integer;
    FLineSeparator: UnicodeString;
    FPadEnd: Boolean;
    function CreateDecoder(const aInput: TStream) : TBase64DecodingStream; virtual;
    function CreateEncoder(const aOutput: TStream) : TBase64EncodingStream; virtual;
  protected
    Function DoDecode(const aInput, aOutput: TStream): Integer; overload; override;
    Function DoEncode(const aInput, aOutput: TStream): Integer; overload; override;

    Function DoDecode(const aInput: RawByteString): RawByteString; overload; override;
    Function DoEncode(const aInput: RawByteString): RawByteString; overload; override;

    Function DoDecode(const aInput: array of Byte): TBytes; overload; override;
    Function DoEncode(const aInput: array of Byte): TBytes; overload; override;
  end;

  { TBase64Encoding }

  TBase64Encoding = class(TCustomBase64Encoding)
  public
    constructor Create; overload; virtual;
    constructor Create(CharsPerLine: Integer); overload; virtual;
    constructor Create(CharsPerLine: Integer; LineSeparator: UnicodeString); overload; virtual;
    constructor Create(CharsPerLine: Integer; LineSeparator: RawByteString); overload;
  end;

  { TBase64URLEncoding }

  TBase64URLEncoding = class(TBase64Encoding)
    function CreateDecoder(const aInput: TStream) : TBase64DecodingStream; override;
    function CreateEncoder(const aOutput: TStream) : TBase64EncodingStream; override;
  end;

  { TBase64StringEncoding }

  TBase64StringEncoding = class(TCustomBase64Encoding)
  public
    constructor Create; overload; virtual;
  end;

  { TURLEncoding }

  TURLEncoding = class(TNetEncoding)
  protected
    Function DoEncode(const aInput: RawBytestring): RawBytestring; overload; override;
    Function DoDecode(const aInput: RawBytestring): RawBytestring; overload; override;
    { raw URL bytes never pass through Unicode: the inherited byte
      overloads UTF8-decode the payload (measured DCC64 raises
      EEncodingError on a $FF byte there - a defect, not a canvas) }
    Function DoEncode(const aInput: array of Byte): TBytes; overload; override;
    Function DoDecode(const aInput: array of Byte): TBytes; overload; override;
  Public
    Type
      UnsafeChar = Byte;
      TUnsafeChars = set of UnsafeChar;
      TEncodeOption = (SpacesAsPlus, EncodePercent);
      TEncodeOptions = set of TEncodeOption;
      TDecodeOption = (PlusAsSpaces);
      TDecodeOptions = set of TDecodeOption;
  Public
    function Encode(const aInput: string; const aSet: TUnsafeChars; const aOptions: TEncodeOptions; aEncoding: TEncoding = nil): string; overload;
    function EncodeQuery(const aInput: string; const aExtraUnsafeChars: TUnsafeChars): string;
    function EncodePath(const aPath: string; const aExtraUnsafeChars: TUnsafeChars): string;
    class function URIDecode(const aValue: string; aPlusAsSpaces: Boolean): string;
  end;

  THTMLEncoding = class(TNetEncoding)
  protected
    Function DoDecode(const aInput: UnicodeString): UnicodeString; override;
    Function DoDecode(const aInput: RawBytestring): RawBytestring; overload; override;
    Function DoEncode(const aInput: UnicodeString): UnicodeString; override;
    Function DoEncode(const aInput: RawBytestring): RawBytestring; overload; override;
  end;

implementation

{$IFDEF FPC_DOTTEDUNITS}
uses System.RTLConsts, FpWeb.Http.Protocol, Html.Defs, Xml.Read;
{$ELSE FPC_DOTTEDUNITS}
uses RTLConsts, httpprotocol, HTMLDefs, xmlread;
{$ENDIF FPC_DOTTEDUNITS}

{$macro on}
{$define HTMLSPAN_ENCODE:=HTMLSpanEncodeRaw}
{$define HTMLSPAN_PCHAR:=PAnsiChar}
{$define HTMLSPAN_CHAR:=AnsiChar}
{$define HTMLSPAN_STRING:=RawByteString}
{$i system.netencoding.htmlspan.inc}
{$undef HTMLSPAN_ENCODE}
{$undef HTMLSPAN_PCHAR}
{$undef HTMLSPAN_CHAR}
{$undef HTMLSPAN_STRING}

{$define HTMLSPAN_ENCODE:=HTMLSpanEncodeUnicode}
{$define HTMLSPAN_PCHAR:=PWideChar}
{$define HTMLSPAN_CHAR:=UnicodeChar}
{$define HTMLSPAN_STRING:=UnicodeString}
{$i system.netencoding.htmlspan.inc}
{$undef HTMLSPAN_ENCODE}
{$undef HTMLSPAN_PCHAR}
{$undef HTMLSPAN_CHAR}
{$undef HTMLSPAN_STRING}
{$macro off}

{ TCustomBase64Encoding }

function TCustomBase64Encoding.CreateDecoder(const aInput: TStream) : TBase64DecodingStream;

begin
  Result:=TBase64DecodingStream.Create(aInput,bdmMIME);
end;


function TCustomBase64Encoding.CreateEncoder(const aOutput: TStream) : TBase64EncodingStream;

begin
  Result:=TBase64EncodingStream.Create(aOutput,FCharsPerline,FLineSeparator,FPadEnd);
end;


function TCustomBase64Encoding.DoDecode(const aInput, aOutput: TStream): Integer;

Var
  S : TBase64DecodingStream;
  P,Sz : Int64;

begin
  { the decoder wraps the source at its CURRENT position - the measured
    DCC64 contract transforms the remaining bytes; a negative, at-end or
    past-end position returns 0 without touching the output }
  Result:=0;
  P:=aInput.Position;
  Sz:=aInput.Size;
  if (P<0) or (P>=Sz) then
    exit;
  S:=CreateDecoder(aInput);
  try
    Result:=S.Size;
    aOutput.CopyFrom(S,Result);
  finally
    S.Free;
  end;
end;

function TCustomBase64Encoding.DoDecode(const aInput: array of Byte): TBytes;
var
  Instream  : TBytesStream;
  Outstream : TBytesStream;
  Decoder   : TBase64DecodingStream;
const
  cPad: AnsiChar = '=';
begin
  if Length(aInput)=0 then
    Exit(nil);
  Instream:=TBytesStream.Create;
  try
    Instream.WriteBuffer(aInput[0], Length(aInput));
    while Instream.Size mod 4 > 0 do
      Instream.WriteBuffer(cPad, 1);
    Instream.Position:=0;
    Outstream:=TBytesStream.Create;
    try
      Decoder:=CreateDecoder(Instream);
      try
         Outstream.CopyFrom(Decoder,Decoder.Size);
         Result:=Outstream.Bytes;
         SetLength(Result,Outstream.Size);
      finally
        Decoder.Free;
      end;
    finally
      Outstream.Free;
    end;
  finally
    Instream.Free;
  end;
end;

function TCustomBase64Encoding.DoEncode(const aInput, aOutput: TStream): Integer;
Var
  S : TBase64EncodingStream;
  P,Sz,OutStart : Int64;

begin
  { encode the REMAINING bytes from the current position and report the
    OUTPUT count - the measured DCC64 contract (the old CopyFrom(aInput,0)
    rewound the source and returned the input count); a negative, at-end
    or past-end position returns 0 without touching the output }
  Result:=0;
  P:=aInput.Position;
  Sz:=aInput.Size;
  if (P<0) or (P>=Sz) then
    exit;
  OutStart:=aOutput.Position;
  S:=CreateEncoder(aOutput); //,FCharsPerline,FLineSeparator,FPadEnd);
  try
    S.CopyFrom(aInput,Sz-P);
  finally
    S.Free;
  end;
  Result:=aOutput.Position-OutStart;
end;

function TCustomBase64Encoding.DoEncode(const aInput: array of Byte): TBytes;
var
  Outstream : TBytesStream;
  Encoder   : TBase64EncodingStream;
begin
  if Length(aInput)=0 then
    Exit(nil);
  Outstream:=TBytesStream.Create;
  try
    Encoder:=CreateEncoder(outstream);
    try
      Encoder.Write(aInput[0],Length(aInput));
    finally
      Encoder.Free;
    end;
    Result:=Outstream.Bytes;
    SetLength(Result,Outstream.Size);
  finally
    Outstream.free;
  end;
end;

function TCustomBase64Encoding.DoDecode(const aInput: RawByteString): RawByteString;
begin
  Result:=DecodeStringBase64(aInput,False);
end;

function TCustomBase64Encoding.DoEncode(const aInput: RawByteString): RawByteString;
var
  Outstream : TStringStream;
  Encoder   : TBase64EncodingStream;
begin
  if Length(aInput)=0 then
    Exit('');
  Outstream:=TStringStream.Create('');
  try
    Encoder:=CreateEncoder(outstream);
    try
      Encoder.Write(aInput[1],Length(aInput));
    finally
      Encoder.Free;
    end;
    Result:=Outstream.DataString;
  finally
    Outstream.free;
  end;
end;

{ TBase64Encoding }

constructor TBase64Encoding.Create(CharsPerLine: Integer);
begin
  Create(CharsPerLine, kLineSeparator);
end;

constructor TBase64Encoding.Create(CharsPerLine: Integer; LineSeparator: UnicodeString);
begin
  inherited Create;
  FCharsPerline:=CharsPerLine;
  FLineSeparator:=LineSeparator;
  FPadEnd:=True;
end;

constructor TBase64Encoding.Create(CharsPerLine: Integer; LineSeparator: RawByteString);
begin
  Create(CharsPerLine, UTF8Decode(LineSeparator));
end;

constructor TBase64Encoding.Create;
begin
  Create(kCharsPerLine, kLineSeparator);
end;

{ TBase64URLEncoding }

function TBase64URLEncoding.CreateDecoder(const aInput: TStream): TBase64DecodingStream;
begin
  Result:=TBase64URLDecodingStream.Create(aInput,bdmMIME);
end;

function TBase64URLEncoding.CreateEncoder(const aOutput: TStream): TBase64EncodingStream;
begin
  Result:=TBase64URLEncodingStream.Create(aOutput,FCharsPerline,FLineSeparator,FPadEnd);
end;

{ TBase64StringEncoding }

constructor TBase64StringEncoding.Create;
begin
  inherited Create;
  FCharsPerline:=0;
  FLineSeparator:='';
  FPadEnd:=True;
end;

{ ---------------------------------------------------------------------
  TNetEncoding
  ---------------------------------------------------------------------}

class procedure TNetEncoding.FreeStdEncodings;

Var
  I : TStandardEncoding;

begin
  For I in TStandardEncoding do
    FreeAndNil(FStdEncodings[i]);
end;

class destructor TNetEncoding.Destroy;
begin
  FreeStdEncodings;
end;

class function TNetEncoding.GetURLEncoding: TURLEncoding;
begin
  Result:=TURLEncoding(GetStdEncoding(seURL));
end;

class function TNetEncoding.GetStdEncoding(aIndex: TStandardEncoding): TNetEncoding;
begin
  Result:=FStdEncodings[aIndex];
  if Assigned(Result) then
  begin
{$ifdef FPC_HAS_FEATURE_THREADING}
    ReadDependencyBarrier; // Read Result contents (by caller) after Result pointer.
{$endif}
    Exit;
  end;

  case aIndex of
    seBase64: Result:=TBase64Encoding.Create;
    seBase64String: Result:=TBase64StringEncoding.Create;
    seBase64URL: Result:=TBase64URLEncoding.Create;
    seHTML: Result:=THTMLEncoding.Create;
    seURL: Result:=TURLEncoding.Create;
  end;

{$ifdef FPC_HAS_FEATURE_THREADING}
  WriteBarrier; // Write FStdEncodings[aIndex] after Result contents.
  if InterlockedCompareExchange(Pointer(FStdEncodings[aIndex]), Pointer(Result), nil) <> nil then
  begin
    Result.Free;
    Result := FStdEncodings[aIndex];
  end;
{$else}
  FStdEncodings[aIndex] := Result;
{$endif}
end;

// Public API

function TNetEncoding.Encode(const aInput: array of Byte): TBytes;
begin
  Result:=DoEncode(aInput);
end;

function TNetEncoding.Encode(const aInput, aOutput: TStream): Integer;
begin
  Result:=DoEncode(aInput, aOutput);
end;

function TNetEncoding.Decode(const aInput: RawByteString): RawByteString;
begin
  Result:=DoDecode(aInput);
end;

function TNetEncoding.Encode(const aInput: RawByteString): RawByteString;

begin
  Result:=DoEncode(aInput);
end;

function TNetEncoding.Encode(const aInput: UnicodeString): UnicodeString;
begin
  Result:=DoEncode(aInput);
end;

function TNetEncoding.EncodeBytesToString(const aInput: array of Byte): UnicodeString;
begin
  Result:=DoEncodeBytesToString(aInput);
end;

function TNetEncoding.EncodeBytesToString(const aInput: Pointer; Size: Integer): UnicodeString;
begin
  Result:=DoEncodeBytesToString(aInput, Size);
end;

function TNetEncoding.Decode(const aInput, aOutput: TStream): Integer;
begin
  Result:=DoDecode(aInput,aOutput);
end;

function TNetEncoding.Decode(const aInput: UnicodeString): UnicodeString;
begin
  Result:=DoDecode(aInput);
end;

function TNetEncoding.DecodeStringToBytes(const aInput: UnicodeString): TBytes;
begin
  Result:=DoDecodeStringToBytes(aInput);
end;

function TNetEncoding.DecodeStringToBytes(const aInput: RawByteString): TBytes;
begin
  Result:=DoDecodeStringToBytes(aInput);
end;

function TNetEncoding.Decode(const aInput: array of Byte): TBytes;
begin
  Result:=DoDecode(aInput);
end;

// Protected

function TNetEncoding.DoDecode(const aInput: UnicodeString): UnicodeString;

Var
  U : UTF8String;

begin
  U:=UTF8Encode(aInput);
  Result:=UTF8Decode(DoDecode(U));
end;

function TNetEncoding.DoEncode(const aInput: UnicodeString): UnicodeString;

Var
  U : UTF8String;

begin
  U:=UTF8Encode(aInput);
  Result:=UTF8Decode(DoEncode(U));
end;

function TNetEncoding.DoDecode(const aInput: array of Byte): TBytes;

begin
  if Length(aInput)=0 then
    Result:=Default(TBytes)
  else
    Result:=TEncoding.UTF8.GetBytes(DoDecode(UTF8ToString(aInput)));
end;

{ One stream-transform frame for Encode and Decode (R-014): Position and
  Size are read once as Int64; a negative, at-end or past-end position
  returns 0 - the measured DCC64 canvas; the buffer holds exactly the
  remaining bytes and is filled by a loop that treats a non-positive
  read as a broken stream (the old encode path used a single unchecked
  Read and silently encoded the zero tail it never received). }
function ReadRemainingBytes(aInput: TStream; out aBuf: TBytes): Boolean;

var
  P,Sz,Remain : Int64;
  Got : SizeInt;
  R : LongInt;

begin
  aBuf:=Default(TBytes);
  P:=aInput.Position;
  Sz:=aInput.Size;
  Result:=(P>=0) and (P<Sz);
  if not Result then
    exit;
  Remain:=Sz-P;
  if Remain>High(SizeInt) then
    raise EStreamError.CreateRes(@SReadError);
  SetLength(aBuf,Remain);
  Got:=0;
  while Got<Remain do
    begin
    if Remain-Got>High(LongInt) then
      R:=aInput.Read(aBuf[Got],High(LongInt))
    else
      R:=aInput.Read(aBuf[Got],LongInt(Remain-Got));
    if R<=0 then
      raise EReadError.CreateRes(@SReadError);
    Inc(Got,R);
    end;
end;

function TNetEncoding.DoDecode(const aInput, aOutput: TStream): Integer;

var
  Src,Dest: TBytes;

begin
  Result:=0;
  if not ReadRemainingBytes(aInput,Src) then
    exit;
  Dest:=DoDecode(Src);
  if Length(Dest)>High(Integer) then
    raise EStreamError.CreateRes(@SWriteError);
  Result:=Length(Dest);
  if Result>0 then
    aOutput.WriteBuffer(Dest[0],Result);
end;

function TNetEncoding.DoDecodeStringToBytes(const aInput: UnicodeString): TBytes;

begin
  { The base64 *text* is ASCII: turn it into a byte string and decode that as
    raw bytes. Do not pass aInput to DoDecode(UnicodeString) 
    Explicit RawByteString cast so this unambiguously selects the RawByteString }
  Result:=DoDecodeStringToBytes(RawByteString(UTF8Encode(aInput)));
end;

function TNetEncoding.DoEncode(const aInput: array of Byte): TBytes;
begin
  if Length(aInput)=0 then
    Result:=Default(TBytes)
  else
    Result:=TEncoding.UTF8.GetBytes(DoEncode(UTF8ToString(aInput)))
end;

function TNetEncoding.DoDecodeStringToBytes(const aInput: RawByteString): TBytes;

Var
  R : RawByteString;

begin
  { Decode straight to raw bytes via the RawByteString DoDecode (DecodeStringBase64). 
    No UTF8Decode/codepage round-trip, so arbitrary binary payloads survive intact. }
  R:=DoDecode(aInput);
  SetLength(Result, Length(R));
  if Length(R)>0 then
    Move(R[1], Result[0], Length(R));
end;

function TNetEncoding.DoEncodeBytesToString(const aInput: array of Byte): UnicodeString;
begin
  Result:=TEncoding.UTF8.GetString(DoEncode(aInput));
end;


function TNetEncoding.DoEncodeBytesToString(const aInput: Pointer; Size: Integer): UnicodeString;

Var
  Src : TBytes;

begin
  Src:=Default(TBytes);
  SetLength(Src,Size);
  Move(aInput^,Src[0],Size);
  Result:=DoEncodeBytesToString(Src);
end;

function TNetEncoding.DoEncode(const aInput, aOutput: TStream): Integer;
var
  Src,Dest: TBytes;
begin
  Result:=0;
  if not ReadRemainingBytes(aInput,Src) then
    exit;
  Dest:=DoEncode(Src);
  if Length(Dest)>High(Integer) then
    raise EStreamError.CreateRes(@SWriteError);
  Result:=Length(Dest);
  if Result>0 then
    aOutput.WriteBuffer(Dest[0],Result);
end;

{ TBase64Encoding }


{ TURLEncoding }

function DecodeURLBytes(const aInput: RawByteString;
  aPlusAsSpaces: Boolean): RawByteString;

  function HexValue(aValue: AnsiChar): Integer; inline;
  begin
    case aValue of
      '0'..'9': Result:=Ord(aValue)-Ord('0');
      'A'..'F': Result:=Ord(aValue)-Ord('A')+10;
      'a'..'f': Result:=Ord(aValue)-Ord('a')+10;
      else Result:=-1;
    end;
  end;

var
  HighNibble,I,LowNibble,OutPos: Integer;

begin
  SetLength(Result,Length(aInput));
  I:=1;
  OutPos:=1;
  while I<=Length(aInput) do
    begin
    if (aInput[I]='%') and (I+2<=Length(aInput)) then
      begin
      HighNibble:=HexValue(aInput[I+1]);
      LowNibble:=HexValue(aInput[I+2]);
      if (HighNibble>=0) and (LowNibble>=0) then
        begin
        Result[OutPos]:=AnsiChar((HighNibble shl 4) or LowNibble);
        Inc(I,3);
        Inc(OutPos);
        Continue;
        end;
      end;
    if aPlusAsSpaces and (aInput[I]='+') then
      Result[OutPos]:=' '
    else
      Result[OutPos]:=aInput[I];
    Inc(I);
    Inc(OutPos);
    end;
  SetLength(Result,OutPos-1);
end;

function TURLEncoding.DoDecode(const aInput: RawBytestring): RawBytestring;
begin
  Result:=DecodeURLBytes(aInput,True);
end;

function TURLEncoding.DoEncode(const aInput: array of Byte): TBytes;
var
  S,R : RawByteString;
begin
  Result:=Default(TBytes);
  if Length(aInput)=0 then
    exit;
  SetString(S,PAnsiChar(@aInput[0]),Length(aInput));
  R:=DoEncode(S);
  SetLength(Result,Length(R));
  if Length(R)>0 then
    Move(R[1],Result[0],Length(R));
end;

function TURLEncoding.DoDecode(const aInput: array of Byte): TBytes;
var
  S,R : RawByteString;
begin
  Result:=Default(TBytes);
  if Length(aInput)=0 then
    exit;
  SetString(S,PAnsiChar(@aInput[0]),Length(aInput));
  R:=DoDecode(S);
  SetLength(Result,Length(R));
  if Length(R)>0 then
    Move(R[1],Result[0],Length(R));
end;

function TURLEncoding.Encode(const aInput: string; const aSet: TUnsafeChars; const aOptions: TEncodeOptions; aEncoding: TEncoding): string;

const
  HexDigits = '0123456789ABCDEF';

var
  Bytes: TBytes;
  ByteValue: Byte;
  I,OutPos: Integer;
  S: TUnsafeChars;

  function IsHex(aValue: Byte): Boolean; inline;
  begin
    Result:=(aValue>=Ord('0')) and (aValue<=Ord('9')) or
      (aValue>=Ord('A')) and (aValue<=Ord('F')) or
      (aValue>=Ord('a')) and (aValue<=Ord('f'));
  end;

begin
  if aEncoding=Nil then
    aEncoding:=TEncoding.UTF8;
  Bytes:=aEncoding.GetBytes(aInput);
  S:=aSet;
  if (TEncodeOption.SpacesAsPlus in aOptions) then
    S:=S+[Ord('+')];
  if (TEncodeOption.EncodePercent in aOptions) then
    S:=S+[Ord('%')];
  SetLength(Result,Length(Bytes)*3);
  OutPos:=1;
  I:=0;
  while I<Length(Bytes) do
    begin
    ByteValue:=Bytes[I];
    if not (TEncodeOption.EncodePercent in aOptions) and
       (ByteValue=Ord('%')) and (I+2<Length(Bytes)) and
       IsHex(Bytes[I+1]) and IsHex(Bytes[I+2]) then
      begin
      Result[OutPos]:='%';
      Result[OutPos+1]:=Char(Bytes[I+1]);
      Result[OutPos+2]:=Char(Bytes[I+2]);
      Inc(I,3);
      Inc(OutPos,3);
      Continue;
      end;
    if (ByteValue>=Ord('!')) and (ByteValue<=Ord('~')) and
       not (ByteValue in S) then
      begin
      Result[OutPos]:=Char(ByteValue);
      Inc(OutPos);
      end
    else if (ByteValue=Ord(' ')) and
            (TEncodeOption.SpacesAsPlus in aOptions) then
      begin
      Result[OutPos]:='+';
      Inc(OutPos);
      end
    else
      begin
      Result[OutPos]:='%';
      Result[OutPos+1]:=HexDigits[(ByteValue shr 4)+1];
      Result[OutPos+2]:=HexDigits[(ByteValue and $0f)+1];
      Inc(OutPos,3);
      end;
    Inc(I);
    end;
  SetLength(Result,OutPos-1);
end;

function TURLEncoding.DoEncode(const aInput: RawBytestring): RawBytestring;

const
  HexDigits = '0123456789ABCDEF';

var
  C: Byte;
  I, OutPos: SizeInt;

begin
  { aInput already contains the UTF-8 bytes produced by TNetEncoding.DoEncode.
    HTTPEncode accepts the current-codepage String type, so passing a
    RawByteString through it may transcode those bytes when
    DefaultSystemCodePage is UTF-8. Encode the raw bytes directly instead. }
  SetLength(Result,Length(aInput)*3);
  OutPos:=1;
  for I:=1 to Length(aInput) do
    begin
    C:=Ord(aInput[I]);
    if C in [Ord('A')..Ord('Z'),Ord('a')..Ord('z'),
             Ord('*'),Ord('@'),Ord('.'),Ord('_'),Ord('-'),
             Ord('0')..Ord('9'),Ord('$'),Ord('!'),Ord(''''),
             Ord('('),Ord(')')] then
      begin
      Result[OutPos]:=AnsiChar(C);
      Inc(OutPos);
      end
    else if C=Ord(' ') then
      begin
      Result[OutPos]:='+';
      Inc(OutPos);
      end
    else
      begin
      Result[OutPos]:='%';
      Result[OutPos+1]:=HexDigits[(C shr 4)+1];
      Result[OutPos+2]:=HexDigits[(C and $0f)+1];
      Inc(OutPos,3);
      end;
    end;
  SetLength(Result,OutPos-1);
end;

function TURLEncoding.EncodeQuery(const aInput: string; const aExtraUnsafeChars: TUnsafeChars): string;

const
  QueryUnsafeChars: TUnsafeChars =
    [Ord('"'),Ord(''''),Ord('<'),Ord('>'),Ord('#')];

var
  Unsafe: TUnsafeChars;

begin
  Unsafe:=QueryUnsafeChars+aExtraUnsafeChars;
  Result:=Encode(aInput,Unsafe,[TEncodeOption.EncodePercent]);
end;

function TURLEncoding.EncodePath(const aPath: string; const aExtraUnsafeChars: TUnsafeChars): string;


var
  lPaths: TStringDynArray;
  I,Last: Integer;
  LUnsafeChars: TUnsafeChars;

begin
  if APath = '' then
    Exit('/');
  Result:='';
  lPaths:=APath.Split(['/'], TStringSplitOptions.ExcludeEmpty);
  Last:=Length(lPaths)-1;
  for I:=0 to Last do
    Result:=Result+'/'+HTTPEncode(LPaths[I],aExtraUnsafeChars,True);
end;

class function TURLEncoding.URIDecode(const aValue: string; aPlusAsSpaces: Boolean): string;
begin
  Result:=UTF8Decode(DecodeURLBytes(UTF8Encode(aValue),aPlusAsSpaces));
end;


{ THTMLEncoding }

Function THTMLEncoding.DoEncode(const aInput: UnicodeString): UnicodeString;

Var
  Changed: Boolean;

begin
  Result:=HTMLSpanEncodeUnicode(PWideChar(aInput),Length(aInput),Changed);
  if not Changed then
    Result:=aInput;
end;

Function THTMLEncoding.DoEncode(const aInput: RawByteString): RawByteString;

var
  Changed: Boolean;

begin
  Result:=HTMLSpanEncodeRaw(PAnsiChar(aInput),Length(aInput),Changed);
  if not Changed then
    Result:=aInput
  else
    SetCodePage(Result,StringCodePage(aInput),False);
end;

Function THTMLEncoding.DoDecode(const aInput: RawByteString): RawByteString;

Var
  S : RawByteString;


begin
  S:=aInput;
  UniqueString(S);
  SetCodePage(S,CP_UTF8,true);
  Result:=UTF8Encode(DoDecode(UTF8Decode(S)));
end;

Function THTMLEncoding.DoDecode(const aInput: UnicodeString): UnicodeString;

var
  I, EntityEnd, OutPos, Len: SizeInt;
  U: UnicodeChar;
  CodePoint: Cardinal;
  Entity: UnicodeString;
  Resolved: Boolean;

  function ResolveNumeric(StartIndex, EndIndex: SizeInt;
    out Value: Cardinal): Boolean;
  var
    J: SizeInt;
    Base, Digit: Cardinal;
  begin
    Result:=False;
    Value:=0;
    Base:=10;
    J:=StartIndex;
    if (J<EndIndex) and (aInput[J] in ['x','X']) then
    begin
      Base:=16;
      Inc(J);
    end;
    if J>=EndIndex then
      Exit;
    while J<EndIndex do
    begin
      case aInput[J] of
        '0'..'9': Digit:=Ord(aInput[J])-Ord('0');
        'a'..'f': Digit:=Ord(aInput[J])-Ord('a')+10;
        'A'..'F': Digit:=Ord(aInput[J])-Ord('A')+10;
      else
        Exit;
      end;
      if Digit>=Base then
        Exit;
      if Value>($10ffff-Digit) div Base then
        Exit;
      Value:=Value*Base+Digit;
      Inc(J);
    end;
    Result:=True;
  end;

begin
  Len:=Length(aInput);
  if Len=0 then
    Exit('');
  I:=1;
  while (I<=Len) and (aInput[I]<>'&') do
    Inc(I);
  if I>Len then
    Exit(aInput);
  SetLength(Result,Len);
  I:=1;
  OutPos:=1;
  while I<=Len do
  begin
    if aInput[I]='&' then
    begin
      EntityEnd:=I+1;
      while (EntityEnd<=Len) and (aInput[EntityEnd]<>';') do
        Inc(EntityEnd);
      if EntityEnd<=Len then
      begin
        if (I+1<EntityEnd) and (aInput[I+1]='#') then
          Resolved:=ResolveNumeric(I+2,EntityEnd,CodePoint)
        else
        begin
          Entity:=Copy(aInput,I+1,EntityEnd-I-1);
          { HTMLDefs follows HTML 4.01 and therefore omits apos, while the
            Delphi facade accepts the XML/XHTML entity as well. }
          if Entity='apos' then
          begin
            U:='''';
            Resolved:=True;
          end
          else
            Resolved:=ResolveHTMLEntityReference(Entity,U);
          if Resolved then
            CodePoint:=Ord(U);
        end;
        if Resolved then
        begin
          if CodePoint<$10000 then
          begin
            Result[OutPos]:=UnicodeChar(CodePoint);
            Inc(OutPos);
          end
          else
          begin
            Dec(CodePoint,$10000);
            Result[OutPos]:=UnicodeChar($d800+(CodePoint shr 10));
            Result[OutPos+1]:=UnicodeChar($dc00+(CodePoint and $3ff));
            Inc(OutPos,2);
          end;
          I:=EntityEnd+1;
          Continue;
        end;
      end;
    end;
    Result[OutPos]:=aInput[I];
    Inc(OutPos);
    Inc(I);
    end;
  SetLength(Result,OutPos-1);
end;

end.

