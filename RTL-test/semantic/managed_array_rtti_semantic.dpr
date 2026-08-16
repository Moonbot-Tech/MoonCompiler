program managed_array_rtti_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  {$endif UNIX}
  SysUtils;

type
  ITracked = interface
    ['{E71C4F29-D9F6-43E1-BD37-F4C58C307798}']
    function Number: Integer;
  end;

  TTracked = class(TInterfacedObject, ITracked)
  private
    FNumber: Integer;
  public
    constructor Create(ANumber: Integer);
    destructor Destroy; override;
    function Number: Integer;
  end;

  TAnsiVector = array[0..4] of AnsiString;
  TUnicodeVector = array[0..4] of UnicodeString;
  TBytesVector = array[0..4] of TBytes;
  TInterfaceVector = array[0..4] of ITracked;

var
  Destroyed: Integer;

procedure Check(Condition: Boolean; const What: string);
begin
  If not Condition then
    raise Exception.Create(What);
end;

constructor TTracked.Create(ANumber: Integer);
begin
  inherited Create;
  FNumber := ANumber;
end;

destructor TTracked.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;

function TTracked.Number: Integer;
begin
  Result := FNumber;
end;

procedure CheckStrings;
var
  AnsiSource, AnsiTarget: TAnsiVector;
  UnicodeSource, UnicodeTarget: TUnicodeVector;
begin
  AnsiSource[0] := AnsiString('ansi-zero');
  AnsiSource[2] := AnsiString('ansi-two');
  AnsiTarget := AnsiSource;
  AnsiSource[0] := '';
  AnsiSource[2] := '';
  Check((AnsiTarget[0] = AnsiString('ansi-zero')) and
    (AnsiTarget[1] = '') and (AnsiTarget[2] = AnsiString('ansi-two')) and
    (AnsiTarget[3] = '') and (AnsiTarget[4] = ''),
    'AnsiString array copy and nil tail');

  UnicodeSource[0] := 'unicode-zero';
  UnicodeSource[2] := UnicodeString('a') + UnicodeChar(0) + 'b';
  UnicodeTarget := UnicodeSource;
  UnicodeSource[0] := '';
  UnicodeSource[2] := '';
  Check((UnicodeTarget[0] = 'unicode-zero') and
    (UnicodeTarget[1] = '') and
    (UnicodeTarget[2] = UnicodeString('a') + UnicodeChar(0) + 'b') and
    (UnicodeTarget[3] = '') and (UnicodeTarget[4] = ''),
    'UnicodeString array copy, embedded NUL, and nil tail');
end;

procedure CheckDynamicArrays;
var
  Source, Target: TBytesVector;
begin
  Source[0] := TBytes.Create(1, 2, 3);
  Source[2] := TBytes.Create(4, 5);
  Target := Source;
  Source[0] := nil;
  Source[2] := nil;
  Check((Length(Target[0]) = 3) and (Target[0][2] = 3) and
    (Target[1] = nil) and (Length(Target[2]) = 2) and
    (Target[2][1] = 5) and (Target[3] = nil) and (Target[4] = nil),
    'dynamic-array elements and nil tail');
end;

procedure CheckInterfaces;
var
  Source, Target: TInterfaceVector;
begin
  Source[0] := TTracked.Create(10);
  Source[2] := TTracked.Create(20);
  Target := Source;
  Source[0] := nil;
  Source[2] := nil;
  Check(Destroyed = 0, 'array copy retained both interfaces');
  Check((Target[0].Number = 10) and (Target[1] = nil) and
    (Target[2].Number = 20) and (Target[3] = nil) and (Target[4] = nil),
    'interface array contents and nil tail');
end;

begin
  CheckStrings;
  CheckDynamicArrays;
  CheckInterfaces;
  Check(Destroyed = 2, 'interface array finalizes every retained value once');
  WriteLn('MANAGED_ARRAY_RTTI_OK');
end.
