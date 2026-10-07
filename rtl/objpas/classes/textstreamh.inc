{ Text streams moved from FCL StreamEx; original implementation copyright
  2015 Michael Van Canneyt and Silvio Clecio. See COPYING.FPC.
  Character-reader extensions and Classes integration are MoonCompiler code. }
type
   TTextReader = class;
   TTextReaderEnumerator = class
   private
     FReader: TTextReader;
     FLine: RTLString;
   public
     constructor Create(AReader: TTextReader);
     function MoveNext: Boolean;
     property Current: RTLString read FLine;
   end;

   { TTextReader }

   TTextReader = class(TObject)
   Protected
     function IsEof: Boolean; virtual;
     function GetEndOfStream: Boolean; virtual;
   public
     constructor Create; virtual;
     procedure Reset; virtual;
     procedure Close; virtual; abstract;
     procedure ReadLine(out AString: RTLString); virtual; overload;
     function ReadLine: RTLString; virtual; overload;
     function Peek: Integer; virtual;
     function Read: Integer; virtual; overload;
     function Read(var Buffer: TCharArray; Index, Count: Integer): Integer; virtual; overload;
     function ReadBlock(var Buffer: TCharArray; Index, Count: Integer): Integer; virtual;
     function ReadToEnd: RTLString; virtual;
     procedure Rewind; virtual;
     function GetEnumerator: TTextReaderEnumerator;
     property Eof: Boolean read IsEof;
     property EndOfStream : boolean read IsEof;
   end;

   { TStreamReader }

   TStreamReader = class(TTextReader)
   private
     FClosed,
     FOwnsStream: Boolean;
     FStream: TStream;
     FBufferSize: Integer;
     FBufferedText: RTLString;
     FBufferedTextPosition: Integer;
     FByteTail: TBytes;
     FEncoding: TEncoding;
     FInitialEncoding: TEncoding;
     FDetectBOM: Boolean;
     FStarted: Boolean;
     FNoDataInStream: Boolean;
     procedure CompactBufferedText;
     function CompleteByteCount(const Bytes: TBytes; Count: Integer): Integer;
     procedure FillBuffer;
   Protected
     function IsEof: Boolean; override;
   public
     constructor Create(AStream: TStream; ABufferSize: Integer; AOwnsStream: Boolean); virtual;
     constructor Create(AStream: TStream); virtual;
     constructor Create(AStream: TStream; ADetectBOM: Boolean); overload;
     constructor Create(AStream: TStream; AEncoding: TEncoding;
       ADetectBOM: Boolean = False; ABufferSize: Integer = 4096); overload;
     constructor Create(const aFilename: string);
     constructor Create(const aFilename: string; aDetectBOM: Boolean);
     constructor Create(const aFilename: string; aEncoding: TEncoding; aDetectBOM: Boolean = False; aBufferSize: Integer = 4096); overload;
     destructor Destroy; override;
     procedure Reset; override;
     procedure Close; override;
     procedure ReadLine(out AString: RTLString); override; overload;
     function Peek: Integer; override;
     function Read: Integer; overload; override;
     function Read(var Buffer: TCharArray; Index, Count: Integer): Integer; overload; override;
     procedure Rewind; override;
     procedure DiscardBufferedData;
     procedure OwnStream;
     property BaseStream: TStream read FStream;
     property CurrentEncoding: TEncoding read FEncoding;
     property OwnsStream: Boolean read FOwnsStream write FOwnsStream;
   end;

   { TStringReader }

   TStringReader = class(TTextReader)
   private
     FData: RTLString;
     FPosition: Integer;
   Protected
     function IsEof: Boolean; override;
   public
     constructor Create(const AString: RTLString; ABufferSize: Integer); virtual;
     constructor Create(const AString: RTLString); virtual;
     destructor Destroy; override;
     procedure Reset; override;
     procedure Close; override;
     procedure ReadLine(out AString: RTLString); override; overload;
     function Peek: Integer; override;
     function Read: Integer; overload; override;
     function Read(var Buffer: TCharArray; Index, Count: Integer): Integer; overload; override;
     procedure Rewind; override;
   end;

   { TTextWriter }

   TTextWriter = class
   public
     procedure Close; virtual; abstract;
     procedure Flush; virtual; abstract;
     procedure Write(aValue: Boolean); overload; virtual; abstract;
     procedure Write(aValue: Char); overload; virtual; abstract;
     procedure Write(aValue: Char; aCount: Integer); overload; virtual;
     procedure Write(const aValue: TCharArray); overload; virtual; abstract;
     procedure Write(aValue: Double); overload; virtual; abstract;
     procedure Write(aValue: Integer); overload; virtual; abstract;
     procedure Write(aValue: Int64); overload; virtual; abstract;
     procedure Write(aValue: TObject); overload; virtual; abstract;
     procedure Write(aValue: Single); overload; virtual; abstract;
     procedure Write(const aValue: string); overload; virtual; abstract;
     procedure Write(aValue: Cardinal); overload; virtual; abstract;
     procedure Write(aValue: UInt64); overload; virtual; abstract;
     procedure Write(const Fmt: string; aArgs: array of const); overload; virtual; abstract;
     procedure Write(const aValue: TCharArray; aIndex, aCount: Integer); overload; virtual; abstract;
     procedure WriteLine; overload; virtual; abstract;
     procedure WriteLine(aValue: Boolean); overload; virtual; abstract;
     procedure WriteLine(aValue: Char); overload; virtual; abstract;
     procedure WriteLine(const aValue: TCharArray); overload; virtual; abstract;
     procedure WriteLine(aValue: Double); overload; virtual; abstract;
     procedure WriteLine(aValue: Integer); overload; virtual; abstract;
     procedure WriteLine(aValue: Int64); overload; virtual; abstract;
     procedure WriteLine(aValue: TObject); overload; virtual; abstract;
     procedure WriteLine(aValue: Single); overload; virtual; abstract;
     procedure WriteLine(const aValue: string); overload; virtual; abstract;
     procedure WriteLine(aValue: Cardinal); overload; virtual; abstract;
     procedure WriteLine(aValue: UInt64); overload; virtual; abstract;
     procedure WriteLine(const Format: string; Args: array of const); overload; virtual; abstract;
     procedure WriteLine(const aValue: TCharArray; Index, Count: Integer); overload; virtual; abstract;
   end;

   { TStringWriter }

   TStringWriter = class(TTextWriter)
   private
     FBuilder: TStringBuilder;
     FFreeBuilder: Boolean;
   public
     constructor Create; overload;
     constructor Create(aBuilder: TStringBuilder); overload;
     destructor Destroy; override;
     procedure Close; override;
     procedure Flush; override;
     procedure Write(aValue: Boolean); override;
     procedure Write(aValue: Char); override;
     procedure Write(aValue: Char; aCount: Integer); override;
     procedure Write(const aValue: TCharArray); override;
     procedure Write(aValue: Double); override;
     procedure Write(aValue: Integer); override;
     procedure Write(aValue: Int64); override;
     procedure Write(aValue: TObject); override;
     procedure Write(aValue: Single); override;
     procedure Write(const aValue: string); override;
     procedure Write(aValue: Cardinal); override;
     procedure Write(aValue: QWord); override;
     procedure Write(const aFmt: string; aArgs: array of const); override;
     procedure Write(const aValue: TCharArray; aIndex, aCount: Integer); override;
     procedure WriteLine; override;
     procedure WriteLine(aValue: Boolean); override;
     procedure WriteLine(aValue: Char); override;
     procedure WriteLine(const aValue: TCharArray); override;
     procedure WriteLine(aValue: Double); override;
     procedure WriteLine(aValue: Integer); override;
     procedure WriteLine(aValue: Int64); override;
     procedure WriteLine(aValue: TObject); override;
     procedure WriteLine(aValue: Single); override;
     procedure WriteLine(const aValue: string); override;
     procedure WriteLine(aValue: Cardinal); override;
     procedure WriteLine(aValue: UInt64); override;
     procedure WriteLine(const aFmt: string; aArgs: array of const); override;
     procedure WriteLine(const aValue: TCharArray; aIndex, aCount: Integer); override;
     function ToString: string; override;
     function GetStringBuilder: TStringBuilder;
   end;

   { TStreamWriter }

   TStreamWriter = class(TTextWriter)
   private
     FStream: TStream;
     FFreeStream: Boolean;
     FEncoding: TEncoding;
     FNewLine: string;
     FAutoFlush: Boolean;
     procedure WriteUnicodeSpan(Chars: PUnicodeChar; CharCount: Integer);
   protected
     FBufferIndex: Integer;
     FBuffer: TBytes;
     procedure WriteBytes(const Bytes: TBytes);
   public
     constructor Create(aStream: TStream); overload;
     constructor Create(aStream: TStream; aEncoding: TEncoding; aBufferSize: Integer = 4096); overload;
     constructor Create(const aFilename: string; aAppend: Boolean = False); overload;
     constructor Create(const aFilename: string; aAppend: Boolean; aEncoding: TEncoding; aBufferSize: Integer = 4096); overload;
     destructor Destroy; override;
     procedure Close; override;
     procedure Flush; override;
     procedure OwnStream; inline;
     procedure Write(aValue: Boolean); override;
     procedure Write(aValue: Char); override;
     procedure Write(const aValue: TCharArray); override;
     procedure Write(aValue: Double); override;
     procedure Write(aValue: Integer); override;
     procedure Write(aValue: Int64); override;
     procedure Write(aValue: TObject); override;
     procedure Write(aValue: Single); override;
     procedure Write(const aValue: string); override;
     procedure Write(aValue: Cardinal); override;
     procedure Write(aValue: UInt64); override;
     procedure Write(const Fmt: string; aArgs: array of const); override;
     procedure Write(const aValue: TCharArray; aIndex, aCount: Integer); override;
     procedure WriteLine; override;
     procedure WriteLine(aValue: Boolean); override;
     procedure WriteLine(aValue: Char); override;
     procedure WriteLine(const aValue: TCharArray); override;
     procedure WriteLine(aValue: Double); override;
     procedure WriteLine(aValue: Integer); override;
     procedure WriteLine(aValue: Int64); override;
     procedure WriteLine(aValue: TObject); override;
     procedure WriteLine(aValue: Single); override;
     procedure WriteLine(const aValue: string); override;
     procedure WriteLine(aValue: Cardinal); override;
     procedure WriteLine(aValue: UInt64); override;
     procedure WriteLine(const Fmt: string; Args: array of const); override;
     procedure WriteLine(const aValue: TCharArray; aIndex, aCount: Integer); override;
     property AutoFlush: Boolean read FAutoFlush write FAutoFlush;
     property NewLine: string read FNewLine write FNewLine;
     property Encoding: TEncoding read FEncoding;
     property BaseStream: TStream read FStream;
   end;
