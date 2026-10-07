{
    This file is part of the Free Component Library.

    Copyright (c) 2015 by:

      . Michael Van Canneyt michael@freepascal.org
      . Silvio Clecio github.com/silvioprog

    Text reader classes.

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{$mode objfpc}
{$h+}
{$IFNDEF FPC_DOTTEDUNITS}
unit StreamEx;
{$ENDIF FPC_DOTTEDUNITS}

Interface

{$IFDEF FPC_DOTTEDUNITS}
uses
  System.Classes, System.SysUtils, System.RtlConsts;
{$ELSE FPC_DOTTEDUNITS}
uses
  Classes, SysUtils, RtlConsts;
{$ENDIF FPC_DOTTEDUNITS}

const
  MIN_BUFFER_SIZE = 128;
  BUFFER_SIZE = 4096;
  FILE_RIGHTS = 438;

type

   { TBidirBinaryObjectReader }

   TBidirBinaryObjectReader = class(TBinaryObjectReader)
   protected
      function GetPosition: Longint;
      procedure SetPosition(const AValue: Longint);
   public
      property Position: Longint read GetPosition write SetPosition;
   end;

   { TBidirBinaryObjectWriter }

   TBidirBinaryObjectWriter = class(TBinaryObjectWriter)
   protected
      function GetPosition: Longint;
      procedure SetPosition(const AValue: Longint);
   public
      property Position: Longint read GetPosition write SetPosition;
   end;

   { TDelphiReader }

   TDelphiReader = class(TReader)
   protected
      function GetPosition: LongInt;
      procedure SetPosition(const AValue: LongInt);
      function CreateDriver(Stream: TStream; BufSize: Integer): TAbstractObjectReader; override;
   public
      function GetDriver: TBidirBinaryObjectReader;
      function ReadStr: AnsiString;
      procedure Read(var Buf; Count: LongInt); override;
      property Position: LongInt read GetPosition write SetPosition;
   end;

   { TDelphiWriter }

   TDelphiWriter = class(TWriter)
   protected
      function GetPosition: Longint;
      procedure SetPosition(const AValue: LongInt);
      function CreateDriver(Stream: TStream; BufSize: Integer): TAbstractObjectWriter; override;
   public
      function GetDriver: TBidirBinaryObjectWriter;
      procedure FlushBuffer;
      procedure Write(const Buf; Count: LongInt); override;
      procedure WriteStr(const Value: Ansistring);
      procedure WriteValue(Value: TValueType);
      property Position: LongInt read GetPosition write SetPosition;
   end;

   TTextReader = {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}Classes.TTextReader;
   TTextReaderEnumerator = {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}Classes.TTextReaderEnumerator;
   TStreamReader = {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}Classes.TStreamReader;
   TStringReader = {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}Classes.TStringReader;
   TTextWriter = {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}Classes.TTextWriter;
   TStreamWriter = {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}Classes.TStreamWriter;
   TStringWriter = {$IFDEF FPC_DOTTEDUNITS}System.{$ENDIF}Classes.TStringWriter;

   { TFileReader }

   TFileReader = class(TTextReader)
   private
     FReader: TTextReader;
   Protected
     function IsEof: Boolean; override;
   public
     constructor Create(const AFileName: TFileName; AMode: Word;
       ARights: Cardinal; ABufferSize: Integer); virtual;
     constructor Create(const AFileName: TFileName; AMode: Word;
       ABufferSize: Integer); virtual;
     constructor Create(const AFileName: TFileName; ABufferSize: Integer); virtual;
     constructor Create(const AFileName: TFileName); virtual;
     destructor Destroy; override;
     procedure Reset; override;
     procedure Close; override;
     procedure ReadLine(out AString: RTLString); override; overload;
     function Peek: Integer; override;
     function Read: Integer; overload; override;
     function Read(var Buffer: TCharArray; Index, Count: Integer): Integer; overload; override;
     procedure Rewind; override;
   end;


  { allows you to represent just a small window of a bigger stream as a substream.
    also makes sure one is actually at the correct position before clobbering stuff. }

  TWindowedStream = class(TOwnerStream)
  private
    fStart : Int64; // in the source.
    fFrontier : Int64; // in the source.
    fStartingPositionHere : Int64; // position in this Stream corresponding to Position = fStart in the source.
    fPositionHere : Int64; // position in this Stream.
  protected
     //function  GetPosition() : Int64; override; = Seek(0, soCurrent) already.
     function  GetSize() : Int64; override;
     procedure SetSize(const NewSize: Int64); override; overload;
  public
    constructor Create(aStream : TStream; const aSize : Int64; const aPositionHere : Int64 = 0);
    destructor Destroy(); override;
    function Read(var aBuffer; aCount : longint) : longint; override;
    function Write(const aBuffer; aCount : Longint): Longint; override;
    function Seek(const aOffset: Int64; aOrigin: TSeekorigin): Int64; override;
  end;


  TStreamHelper = class helper for TStream
    function  ReadWordLE :word;
    function  ReadDWordLE:dword;
    function  ReadQWordLE:qword;
    procedure WriteWordLE (w:word);
    procedure WriteDWordLE(dw:dword);
    procedure WriteQWordLE(dq:qword);
    function  ReadWordBE :word;
    function  ReadDWordBE:dword;
    function  ReadQWordBE:qword;
    procedure WriteWordBE (w:word);
    procedure WriteDWordBE(dw:dword);
    procedure WriteQWordBE(dq:qword);
    function  ReadSingle:Single;
    function  ReadDouble:Double;
    procedure WriteSingle(s:Single);
    procedure WriteDouble(d:double);
    {$ifndef FPC}
    function ReadByte  : Byte;
    function ReadWord  : Word;
    function ReadDWord : DWord;
    function ReadQWord : QWord;
    procedure WriteByte  (b : Byte);
    procedure WriteWord  (b : word);
    procedure WriteDWord (b : DWord);
    procedure WriteQWord (b : QWord);
    {$endif}
  end;

Implementation

ResourceString
  SErrCannotWriteOutsideWindow = 'Cannot write outside allocated window.';
  SErrInvalidSeekWindow = 'Cannot seek outside allocated window.';
  SErrInvalidSeekOrigin = 'Invalid seek origin.';
  SErrCannotChangeWindowSize  = 'Cannot change the size of a windowed stream';

{ TBidirBinaryObjectReader }

function TBidirBinaryObjectReader.GetPosition: Longint;
begin
   Result := FStream.Position - (FBufEnd - FBufPos);
end;

procedure TBidirBinaryObjectReader.SetPosition(const AValue: Longint);
begin
   FStream.Position := AValue;
   FBufPos := 0;
   FBufEnd := 0;
end;

{ TBidirBinaryObjectWriter }

function TBidirBinaryObjectWriter.GetPosition: Longint;
begin
   Result := FStream.Position - (FBufEnd - FBufPos);
end;

procedure TBidirBinaryObjectWriter.SetPosition(const AValue: Longint);
begin
   FStream.Position := AValue;
   FBufPos := 0;
   FBufEnd := 0;
end;



{ TDelphiReader }

function TDelphiReader.GetDriver: TBidirBinaryObjectReader;
begin
   Result := (Driver as TBidirBinaryObjectReader);
end;

function TDelphiReader.GetPosition: LongInt;
begin
   Result := GetDriver.Position;
end;

procedure TDelphiReader.SetPosition(const AValue: LongInt);
begin
   GetDriver.Position := AValue;
end;

function TDelphiReader.CreateDriver(Stream: TStream; BufSize:
Integer): TAbstractObjectReader;
begin
   Result := TBidirBinaryObjectReader.Create(Stream, BufSize);
end;


function TDelphiReader.ReadStr: AnsiString ;
begin
   Result := GetDriver.ReadStr;
end;

procedure TDelphiReader.Read(var Buf; Count: LongInt);
begin
   GetDriver.Read(Buf, Count);
end;

{ TDelphiWriter }

function TDelphiWriter.GetDriver: TBidirBinaryObjectWriter;
begin
   Result := (Driver as TBidirBinaryObjectWriter);
end;

function TDelphiWriter.GetPosition: LongInt;
begin
   Result := GetDriver.Position;
end;

procedure TDelphiWriter.SetPosition(const AValue: LongInt);
begin
   GetDriver.Position := AValue;
end;

function TDelphiWriter.CreateDriver(Stream: TStream; BufSize: Integer): TAbstractObjectWriter;
begin
   Result := TBidirBinaryObjectWriter.Create(Stream, BufSize);
end;

procedure TDelphiWriter.FlushBuffer;
begin
   GetDriver.FlushBuffer();
end;

procedure TDelphiWriter.Write(const Buf; Count: Longint);
begin
   GetDriver.Write(Buf, Count);
end;

procedure TDelphiWriter.WriteStr(const Value: AnsiString );
begin
   GetDriver.WriteStr(Value);
end;

procedure TDelphiWriter.WriteValue(Value: TValueType);
begin
   GetDriver.WriteValue(Value);
end;

{ TFileReader }

constructor TFileReader.Create(const AFileName: TFileName; AMode: Word;
  ARights: Cardinal; ABufferSize: Integer);
begin
  inherited Create;
  FReader := TStreamReader.Create(TFileStream.Create(AFileName, AMode, ARights),
    ABufferSize, True);
end;

constructor TFileReader.Create(const AFileName: TFileName; AMode: Word;
  ABufferSize: Integer);
begin
  Create(AFileName, AMode, FILE_RIGHTS, ABufferSize);
end;

constructor TFileReader.Create(const AFileName: TFileName; ABufferSize: Integer);
begin
  Create(AFileName, fmOpenRead or fmShareDenyWrite, ABufferSize);
end;

constructor TFileReader.Create(const AFileName: TFileName);
begin
  Create(AFileName, BUFFER_SIZE);
end;

destructor TFileReader.Destroy;
begin
  FReader.Free;
  inherited Destroy;
end;

procedure TFileReader.Reset;
begin
  FReader.Reset;
end;

procedure TFileReader.Close;
begin
  FReader.Close;
end;

function TFileReader.IsEof: Boolean;
begin
  Result := FReader.EndOfStream;
end;

procedure TFileReader.ReadLine(out AString: RTLString);
begin
  FReader.ReadLine(AString);
end;

function TFileReader.Peek: Integer;
begin
  Result:=FReader.Peek;
end;

function TFileReader.Read: Integer;
begin
  Result:=FReader.Read;
end;

function TFileReader.Read(var Buffer: TCharArray; Index, Count: Integer): Integer;
begin
  Result:=FReader.Read(Buffer,Index,Count);
end;

procedure TFileReader.Rewind;
begin
  FReader.Rewind;
end;

{ TStreamHelper }

function TStreamHelper.readwordLE:word;
begin
  result:=LEtoN(readword);
end;

function TStreamHelper.readdwordLE:dword;
begin
  result:=LEtoN(readdword);
end;

function TStreamHelper.readqwordLE:qword;
begin
  result:=LEtoN(readqword);
end;

function TStreamHelper.readwordBE:word;
begin
  result:=BEtoN(readword);
end;

function TStreamHelper.readdwordBE:dword;
begin
  result:=BEtoN(readdword);
end;

function TStreamHelper.readqwordBE:qword;
begin
  result:=BEtoN(readqword);
end;

procedure TStreamHelper.WriteWordBE(w:word);
begin
  WriteWord(NtoBE(w));
end;

procedure TStreamHelper.WriteDWordBE(dw:dword);
begin
  WriteDWord(NtoBE(dw));
end;

procedure TStreamHelper.WriteQWordBE(dq:qword);
begin
  WriteQWord(NtoBE(dq));
end;

procedure TStreamHelper.WriteWordLE(w:word);
begin
  WriteWord(NtoLE(w));
end;

procedure TStreamHelper.WriteDWordLE(dw:dword);
begin
  WriteDWord(NtoLE(dw));
end;

procedure TStreamHelper.WriteQWordLE(dq:qword);
begin
  WriteQWord(NtoLE(dq));
end;

function  TStreamHelper.ReadSingle:Single;
begin
  self.Read(result,sizeof(result));
end;
function  TStreamHelper.ReadDouble:Double;
begin
  self.Read(result,sizeof(result));
end;
procedure TStreamHelper.WriteSingle(s:Single);
begin
  self.Write(s,sizeof(s));
end;
procedure TStreamHelper.WriteDouble(d:double);
begin
  self.Write(d,sizeof(d));
end;


{$ifndef FPC}
// there can only be one helper per class, and I use these in Delphi for FPC compatibility.
function TStreamHelper.ReadByte: Byte;
begin
 self.Read(result,sizeof(result));
end;

function TStreamHelper.ReadDWord: DWord;
begin
 self.Read(result,sizeof(result));
end;

function TStreamHelper.ReadWord: Word;
begin
 self.Read(result,sizeof(result));
end;

procedure TStreamHelper.WriteByte(b: Byte);
begin
 self.Write(b,sizeof(b));
end;

procedure TStreamHelper.WriteDWord(b: DWord);
begin
 self.Write(b,sizeof(b));
end;

procedure TStreamHelper.WriteWord(b: Word);
begin
 self.Write(b,sizeof(b));
end;
{$endif}

{ TWindowedStream }

constructor TWindowedStream.Create(aStream : TStream; const aSize : Int64; const aPositionHere : Int64 = 0);
begin
  inherited Create(aStream);
  fStart := aStream.Position;
  fFrontier := fStart + aSize;
  fStartingPositionHere := aPositionHere;
  fPositionHere := aPositionHere;
end;

destructor TWindowedStream.Destroy();
begin
  inherited Destroy();
end;

function TWindowedStream.Read(var aBuffer; aCount : longint) : longint;
var
  vSourcePosition : Int64;
  vNewSourcePosition : Int64;
begin
  vSourcePosition := Source.Position;
  vNewSourcePosition := fStart + fPositionHere - fStartingPositionHere;
  if vNewSourcePosition <> vSourcePosition then // someone modified the file position. Bad bad.
    Source.Seek(vNewSourcePosition, 0);

  if vNewSourcePosition + aCount > fFrontier then // trying to access outside.
    aCount := fFrontier - vNewSourcePosition;

  Result := Source.Read(aBuffer, aCount);
  Inc(fPositionHere, Result);
end;


function TWindowedStream.Write(const aBuffer; aCount : Longint): Longint;
var
  vSourcePosition : Int64;
  vNewSourcePosition : Int64;
begin
  vSourcePosition := Source.Position;
  vNewSourcePosition := fStart + fPositionHere - fStartingPositionHere;
  if vNewSourcePosition <> vSourcePosition then // someone modified the file position. Bad bad.
    Source.Seek(vNewSourcePosition, 0);

  if vNewSourcePosition + aCount > fFrontier then // trying to access outside.
    Raise EWriteError.Create(SErrCannotWriteOutsideWindow);
    //aCount := fFrontier - vNewSourcePosition;

  Result := Source.Write(aBuffer, aCount);
  Inc(fPositionHere, Result);
end;

function TWindowedStream.Seek(const aOffset: Int64; aOrigin: TSeekOrigin): Int64;
var
  vNewPositionHere : Int64;
  vSourcePosition : Int64;
begin
  {
  here                       there
  fStartingPositionHere .... fStart
  fPositionHere............. x
  }

  if (aOrigin = soCurrent) and (aOffset = 0) then begin // get position.
    Result := fPositionHere;
    Exit;
  end;

  if aOrigin = soBeginning then
    vNewPositionHere := aOffset
  else if aOrigin = soCurrent then
    vNewPositionHere := fPositionHere + aOffset
  else if aOrigin = soEnd then
    vNewPositionHere := fStartingPositionHere + fFrontier - fStart + aOffset
  else
    raise EReadError.Create(SErrInvalidSeekOrigin);

  vSourcePosition := fStart + vNewPositionHere - fStartingPositionHere;
  if (vSourcePosition < 0) or (vSourcePosition >= fFrontier) then
    raise EReadError.Create(SErrInvalidSeekWindow);

  Result := Source.Seek(vSourcePosition, 0);
  //if Result = -1 ??? can that happen?
  Result := vNewPositionHere;
end;

function TWindowedStream.GetSize() : Int64;
begin
  Result := fFrontier - fStart;
end;

procedure TWindowedStream.SetSize(const NewSize: Int64); overload;
begin
  if NewSize = Self.GetSize() then
    Exit;
  raise EWriteError.Create(SErrCannotChangeWindowSize);
end;


end.
