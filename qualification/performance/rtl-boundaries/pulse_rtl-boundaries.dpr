program pulse_rtl_boundaries;

{$ifdef FPC}{$mode delphi}{$H+}{$else}{$APPTYPE CONSOLE}{$endif}
{$Q-}{$R-}

uses
  {$if defined(FPC) and not defined(PULSE_DEFAULT_MM)}
  mormot.core.fpcx64mm,
  {$ifend}
  {$I ../common/pulse_placement_uses.inc}
  SysUtils, Classes, Variants, Rtti,
  {$if defined(FPC) and defined(UNIX)}ffi.manager,{$ifend}
  {$ifdef FPC}Types,{$else}Winapi.ActiveX,{$endif}
  pulse_harness in '..\common\pulse_harness.pas';

{$I ../common/pulse_program_prefix.inc}

const
  Cells = 64;
  ShortCopy = 64;
  LongCopy = 32781;

type
  {$RTTI EXPLICIT METHODS([vcPublic]) PROPERTIES([vcPublic])}
  TBook = class
  public
    Code: Integer;
    Text: UnicodeString;
    procedure SetCode(I, Value: Integer);
    procedure SetText(I: Integer; const Value: UnicodeString);
    function GetCode(I: Integer): Integer;
    function GetText(I: Integer): UnicodeString;
    property Codes[I: Integer]: Integer read GetCode write SetCode;
    property Names[I: Integer]: UnicodeString read GetText write SetText;
  end;
  {$RTTI INHERIT}
  IFeed = interface
    ['{E01BB84D-D10D-4090-BFC3-3D17B44CCEE0}']
    function Value: Integer;
  end;

  TFeed = class(TComponent, IFeed)
    function Value: Integer;
  end;

  TFeedRoot = class(TComponent)
  private
    FFeed: IFeed;
    FTarget: TFeed;
  published
    property Feed: IFeed read FFeed write FFeed;
    property Target: TFeed read FTarget write FTarget;
  end;

var
  Book: TBook;
  Context: TRttiContext;
  Codes, Names: TRttiIndexedProperty;
  IndexArg: array[0..0] of TValue;
  CodeArg, TextArg: TValue;
  ObjectGraph, InterfaceGraph, Source, Destination: TMemoryStream;
  Reader, Writer: IStream;
  Vector, Matrix, Cube, SmallCube, Resizable, Managed: Variant;

procedure TBook.SetCode(I, Value: Integer);
begin
  if (Self=Book) and (I=3) then Code:=Value;
end;

procedure TBook.SetText(I: Integer; const Value: UnicodeString);
begin
  if (Self=Book) and (I=3) then Text:=Value;
end;

function TBook.GetCode(I: Integer): Integer;
begin Result:=Code end;

function TBook.GetText(I: Integer): UnicodeString;
begin Result:=Text end;

function TFeed.Value: Integer;
begin
  Result := Tag;
end;

procedure BuildGraph(Stream: TStream; const Prop: string);
var
  Text: TStringStream;
begin
  Text := TStringStream.Create('object Root: TFeedRoot' + sLineBreak +
    '  ' + Prop + ' = Quotes' + sLineBreak +
    '  object Quotes: TFeed' + sLineBreak + '    Tag = 37' + sLineBreak + '  end' + sLineBreak + 'end');
  try
    ObjectTextToBinary(Text, Stream);
  finally
    Text.Free;
  end;
end;

function LoadGraph(Stream: TStream): TFeedRoot;
begin
  Stream.Position := 0;
  Result := TFeedRoot(Stream.ReadComponent(nil));
end;

function CaseObject(Iterations: Integer): UInt64;
var
  I: Integer;
  Graph: TStream;
  Root: TFeedRoot;
begin
  Result := 0;
  Graph := ObjectGraph;
  for I := 1 to Iterations do begin
    Root := LoadGraph(Graph);
    try
      Result := Result + UInt64(Root.Target.Tag);
    finally
      Root.Free;
    end;
  end;
end;

function CaseInterface(Iterations: Integer): UInt64;
var
  I: Integer;
  Graph: TStream;
  Root: TFeedRoot;
begin
  Result := 0;
  Graph := InterfaceGraph;
  for I := 1 to Iterations do begin
    Root := LoadGraph(Graph);
    try
      Result := Result + UInt64(Root.Feed.Value);
    finally
      Root.Feed := nil;
      Root.Free;
    end;
  end;
end;

procedure CheckInterface;
var
  Root: TFeedRoot;
  Expected: IFeed;
begin
  Root := LoadGraph(InterfaceGraph);
  try
    If not Supports(Root.FindComponent('Quotes'), IFeed, Expected) or (Pointer(Expected) <> Pointer(Root.Feed)) then
      raise Exception.Create('reader-interface: wrong interface view');
  finally
    Expected := nil;
    Root.Feed := nil;
    Root.Free;
  end;
end;

function CaseVector(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    for J := 0 to Cells - 1 do
      Vector[J] := J + (I and 1);
    for J := 0 to Cells - 1 do
      Result := Result + UInt64(Integer(Vector[J]));
  end;
end;

function CaseMatrix(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    for J := 0 to Cells - 1 do
      Matrix[J and 7, J shr 3] := J + (I and 1);
    for J := 0 to Cells - 1 do
      Result := Result + UInt64(Integer(Matrix[J and 7, J shr 3]));
  end;
end;

function CaseCube(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    for J := 0 to Cells - 1 do
      Cube[J and 3, (J shr 2) and 3, J shr 4] := J + (I and 1);
    for J := 0 to Cells - 1 do
      Result := Result + UInt64(Integer(Cube[J and 3, (J shr 2) and 3, J shr 4]));
  end;
end;

function CaseResize(Iterations: Integer): UInt64;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    VarArrayRedim(Resizable, 16);
    Result := Result + UInt64(Integer(Resizable[3, 16]));
    Resizable[3, 16] := 19;
    VarArrayRedim(Resizable, 8);
    Result := Result + UInt64(Integer(Resizable[3, 8]));
  end;
end;

function CopySpan(Iterations, Count: Integer): UInt64;
var
  I: Integer;
  ReadCount, WrittenCount: UInt64;
  Src, Dst: TMemoryStream;
  FromAdapter, ToAdapter: IStream;
begin
  Result := 0;
  Src := Source;
  Dst := Destination;
  FromAdapter := Reader;
  ToAdapter := Writer;
  for I := 1 to Iterations do begin
    Src.Position := I and 1;
    Dst.Position := 0;
    If FromAdapter.CopyTo(ToAdapter, Count, ReadCount, WrittenCount) <> 0 then
      raise Exception.Create('IStream.CopyTo returned failure');
    If (ReadCount <> UInt64(Count)) or (WrittenCount <> UInt64(Count)) then
      raise Exception.Create('IStream.CopyTo returned incorrect byte counts');
    Result := Result + PByte(Dst.Memory)^;
  end;
end;

function CaseShortCopy(Iterations: Integer): UInt64;
begin
  Result := CopySpan(Iterations, ShortCopy);
end;

function CaseLongCopy(Iterations: Integer): UInt64;
begin
  Result := CopySpan(Iterations, LongCopy);
end;

procedure CheckCopy(Count: Integer);
begin
  FillChar(Destination.Memory^, Count + 1, $CC);
  CopySpan(1, Count);
  If (Source.Position <> Count + 1) or (Destination.Position <> Count) or
    not CompareMem(Destination.Memory, PByte(Source.Memory) + 1, Count) or
    ((PByte(Destination.Memory) + Count)^ <> $CC) then
    raise Exception.Create('IStream.CopyTo did not copy the exact span');
end;

function CaseSmallCube(Iterations: Integer): UInt64;
var
  I, J: Integer;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    for J := 0 to 7 do
      SmallCube[J and 1, (J shr 1) and 1, J shr 2] := J + (I and 1);
    for J := 0 to 7 do
      Result := Result + UInt64(Integer(SmallCube[J and 1, (J shr 1) and 1, J shr 2]));
  end;
end;

function CaseCopyCompare(Iterations: Integer): UInt64;
var
  I: Integer;
  Snapshot: Variant;
begin
  Result := 0;
  for I := 1 to Iterations do begin
    Snapshot := Managed;
    if VarSameValue(Managed, Snapshot) then
      Inc(Result);
    VarClear(Snapshot);
  end;
end;

function CaseIndexedCode(Iterations: Integer): UInt64;
var
  I: Integer;
  Target: TBook;
  Prop: TRttiIndexedProperty;
begin
  Result := 0;
  Target := Book;
  Prop := Codes;
  for I := 1 to Iterations do begin
    Prop.SetValue(Target, IndexArg, CodeArg);
    Result := Result + UInt64(Target.Code);
  end;
end;

function CaseIndexedText(Iterations: Integer): UInt64;
var
  I: Integer;
  Target: TBook;
  Prop: TRttiIndexedProperty;
begin
  Result := 0;
  Target := Book;
  Prop := Names;
  for I := 1 to Iterations do begin
    Prop.SetValue(Target, IndexArg, TextArg);
    Result := Result + UInt64(Length(Target.Text));
  end;
end;

procedure Run;
var
  Profile: TPulseProfile;
  SelectedCase: string;
  Found: Boolean;
  I: Integer;

  procedure Add(const Name, UnitName: string; Proc: TPulseCaseProc; Operations: Integer; Expected: UInt64;
    WorkBody: Pointer = nil);
  var
    Actual: UInt64;
  begin
    If (Profile.Name <> 'list') and CaseSelected(SelectedCase, Name) then begin
      If Name = 'reader-interface' then
        CheckInterface;
      If Name = 'copy-64' then
        CheckCopy(ShortCopy);
      If Name = 'copy-32781' then
        CheckCopy(LongCopy);
      Actual := Proc(1);
      If Actual <> Expected then
        raise Exception.CreateFmt('%s: expected %d, got %d', [Name, Expected, Actual]);
      If (Name = 'vararray-redim') and (VarArrayHighBound(Resizable, 2) <> 8) then
        raise Exception.Create('vararray-redim: last dimension did not shrink');
    end;
    PulseRunCase('pulse_rtl_boundaries', Name, 'rtl', UnitName, Proc, Operations, Profile, SelectedCase, Found, WorkBody);
  end;

begin
  PulseInitialize('pulse_rtl_boundaries', Profile, SelectedCase);
  Found := False;
  If Profile.Name <> 'list' then begin
    Context:=TRttiContext.Create;
    Book:=TBook.Create;
    Codes:=Context.GetType(TBook).GetIndexedProperty('Codes');
    Names:=Context.GetType(TBook).GetIndexedProperty('Names');
    IndexArg[0]:=TValue.From<Integer>(3);
    CodeArg:=TValue.From<Integer>(17);
    TextArg:=TValue.From<UnicodeString>('abc'+#0+'z');
    RegisterClass(TFeedRoot);
    RegisterClass(TFeed);
    ObjectGraph := TMemoryStream.Create;
    InterfaceGraph := TMemoryStream.Create;
    BuildGraph(ObjectGraph, 'Target');
    BuildGraph(InterfaceGraph, 'Feed');
    Vector := VarArrayCreate([0, 63], varInteger);
    Matrix := VarArrayCreate([0, 7, 0, 7], varInteger);
    Cube := VarArrayCreate([0, 3, 0, 3, 0, 3], varInteger);
    SmallCube := VarArrayCreate([0, 1, 0, 1, 0, 1], varInteger);
    Resizable := VarArrayCreate([1, 4, 1, 8], varInteger);
    Resizable[3, 8] := 73;
    Managed := VarArrayCreate([0, 7], varVariant);
    for I := 0 to 7 do
      if Odd(I) then Managed[I] := WideString('cell-') + WideString(IntToStr(I))
      else Managed[I] := I;
    Source := TMemoryStream.Create;
    Destination := TMemoryStream.Create;
    Source.Size := LongCopy + 1;
    Destination.Size := LongCopy + 1;
    for I := 0 to LongCopy do
      (PByte(Source.Memory) + I)^ := Byte((I * 31 + (I shr 8) + 7) and 255);
    Reader := TStreamAdapter.Create(Source, soReference);
    Writer := TStreamAdapter.Create(Destination, soReference);
  end;
  try
    Add('reader-object', 'Classes.TReader', @CaseObject, 1, 37);
    Add('reader-interface', 'Classes.TReader', @CaseInterface, 1, 37);
    Add('vararray-1d', 'Variants', @CaseVector, Cells * 2, 2080);
    Add('vararray-2d', 'Variants', @CaseMatrix, Cells * 2, 2080);
    Add('vararray-3d', 'Variants', @CaseCube, Cells * 2, 2080);
    Add('vararray-3d-2x2x2', 'Variants', @CaseSmallCube, 8 * 2, 36);
    Add('vararray-redim', 'Variants.VarArrayRedim', @CaseResize, 2, 73);
    Add('copy-64', 'Classes.TStreamAdapter.CopyTo', @CaseShortCopy, 1, 38, @CopySpan);
    Add('copy-32781', 'Classes.TStreamAdapter.CopyTo', @CaseLongCopy, 1, 38, @CopySpan);
    Add('vararray-copy-compare', 'Variants.VarSameValue', @CaseCopyCompare, 1, 1);
    Add('rtti-indexed-integer', 'Rtti.TRttiIndexedProperty.SetValue', @CaseIndexedCode, 1, 17);
    Add('rtti-indexed-string', 'Rtti.TRttiIndexedProperty.SetValue', @CaseIndexedText, 1, 5);
  finally
    Book.Free;
    if Profile.Name<>'list' then Context.Free;
    Reader := nil;
    Writer := nil;
    Destination.Free;
    Source.Free;
    InterfaceGraph.Free;
    ObjectGraph.Free;
  end;
  PulseFinish('pulse_rtl_boundaries', SelectedCase, Found);
end;

begin
  try
    Run;
  except
    on E: Exception do begin
      WriteLn(ErrOutput, E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
