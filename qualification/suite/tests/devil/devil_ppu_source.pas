unit devil_ppu_source;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
{$endif}

interface

uses
  SysUtils;

type
  { псевдонимы: ширина и знак обязаны пережить границу }
  TDvlPpuNarrow = type SmallInt;
  TDvlPpuUnsigned = type Word;
  TDvlPpuRange = 10..250;
  TDvlPpuEnum = (dvlPpuA, dvlPpuB, dvlPpuC);
  TDvlPpuSet = set of TDvlPpuEnum;

  { layout: смещения полей и упаковка }
  TDvlPpuRec = record
    Head: Byte;
    Wide: Int64;
    Tail: Word;
  end;
  TDvlPpuPacked = packed record
    Head: Byte;
    Wide: Int64;
    Tail: Word;
  end;
  {$ifdef FPC}{$push}{$endif}
  {$A8}
  TDvlPpuAligned = record
    Head: Byte;
    Wide: Int64;
  end;
  {$ifdef FPC}{$pop}{$endif}

  { класс: смещение поля и место метода в таблице }
  TDvlPpuBase = class
  public
    Slot: Integer;
    Extra: Int64;
    function Kind: Integer; virtual;
    function Second: Integer; virtual;
  end;

  {$M+}
  TDvlPpuPublished = class
  private
    FSlot: Integer;
  published
    property Slot: Integer read FSlot write FSlot;
  end;
  {$M-}

  IDvlPpu = interface
    ['{7A1D0000-0000-0000-0000-00000000000D}']
    function Ask: Integer;
  end;

  { обобщение, специализируемое по обе стороны границы }
  TDvlPpuBox<T> = record
    Value: T;
    function Width: Integer;
  end;
  TDvlPpuHere = TDvlPpuBox<SmallInt>;

  TDvlPpuHelperHost = class
  public
    Payload: Integer;
  end;
  TDvlPpuHelper = class helper for TDvlPpuHelperHost
  public
    function Doubled: Integer;
  end;

  TDvlPpuWithConst = class
  public
    const Marker = 4242;
  end;

  DvlPpuMarkAttribute = class(TCustomAttribute)
  public
    Tag: Integer;
    constructor Create(ATag: Integer);
  end;

  [DvlPpuMark(77)]
  TDvlPpuMarked = class
  end;

const
  { типизированные константы: точность и текст }
  DvlPpuCurrency: Currency = 1.2345;
  DvlPpuDouble: Double = 0.1;
  DvlPpuText: string = 'ppu-text';
  DvlPpuUntyped = 300;

{ перегрузки: набор кандидатов обязан переехать целиком }
function DvlPpuPick(const V: Integer): Integer; overload;
function DvlPpuPick(const V: Int64): Integer; overload;
function DvlPpuPick(const V: string): Integer; overload;

{ значение по умолчанию видно только через модуль }
function DvlPpuWithDefault(A: Integer; B: Integer = 7): Integer;
{ соглашение вызова объявлено здесь, вызов будет там }
function DvlPpuStd(A, B, C, D, E: Integer): Integer; stdcall;
{ тело инлайна обязано доехать до потребителя }
function DvlPpuInline(const V: Int64): Int64; inline;
function DvlPpuMakeHere: TDvlPpuHere;

implementation

constructor DvlPpuMarkAttribute.Create(ATag: Integer);
begin
  inherited Create;
  Tag := ATag;
end;

function TDvlPpuBase.Kind: Integer;
begin
  Result := 1;
end;

function TDvlPpuBase.Second: Integer;
begin
  Result := 2;
end;

function TDvlPpuBox<T>.Width: Integer;
begin
  Result := SizeOf(T);
end;

function TDvlPpuHelper.Doubled: Integer;
begin
  Result := Payload * 2;
end;

function DvlPpuPick(const V: Integer): Integer;
begin
  Result := 1;
end;

function DvlPpuPick(const V: Int64): Integer;
begin
  Result := 2;
end;

function DvlPpuPick(const V: string): Integer;
begin
  Result := 3;
end;

function DvlPpuWithDefault(A: Integer; B: Integer): Integer;
begin
  Result := A * 100 + B;
end;

function DvlPpuStd(A, B, C, D, E: Integer): Integer; stdcall;
begin
  Result := A + B * 2 + C * 3 + D * 4 + E * 5;
end;

function DvlPpuInline(const V: Int64): Int64;
begin
  Result := V;
end;

function DvlPpuMakeHere: TDvlPpuHere;
begin
  Result.Value := SmallInt(-32767);
end;

end.
