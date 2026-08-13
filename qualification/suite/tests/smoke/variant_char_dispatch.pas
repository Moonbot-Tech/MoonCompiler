program variant_char_dispatch;

{$ifdef FPC}
  {$ifdef MOONBOT_OBJFPC_CONTROL}
    {$mode objfpc}
  {$else}
    {$mode delphi}
  {$endif}
{$endif}

uses
{$ifdef FPC}
  SysUtils,
  Variants;
{$else}
  System.SysUtils,
  System.Variants;
{$endif}

type
  TCharDispatchProbe = class(TInvokeableVariantType)
  private
    FSeenText: WideString;
    FSeenType: TVarType;
  protected
{$ifndef FPC}
    function FixupIdent(const AText: string): string; override;
{$endif}
  public
    procedure Clear(var V: TVarData); override;
    procedure Copy(var Dest: TVarData; const Source: TVarData;
      const Indirect: Boolean); override;
    function DoFunction(var Dest: TVarData; const V: TVarData;
{$ifdef FPC}
      const Name: AnsiString; const Arguments: TVarDataArray): Boolean; override;
{$else}
      const Name: string; const Arguments: TVarDataArray): Boolean; override;
{$endif}
    property SeenText: WideString read FSeenText;
    property SeenType: TVarType read FSeenType;
  end;

const
{$ifdef MSWINDOWS}
  ExpectedStringCarrier = varOleStr;
{$else}
  ExpectedStringCarrier = varUString;
{$endif}

procedure TCharDispatchProbe.Clear(var V: TVarData);
begin
  V.VType := varEmpty;
end;

{$ifndef FPC}
function TCharDispatchProbe.FixupIdent(const AText: string): string;
begin
  Result := AText;
end;
{$endif}

procedure TCharDispatchProbe.Copy(var Dest: TVarData; const Source: TVarData;
  const Indirect: Boolean);
begin
  If Indirect and VarDataIsByRef(Source) then begin
    VarDataCopyNoInd(Dest, Source);
  end else begin
    Dest.VType := Source.VType;
  end;
end;

function TCharDispatchProbe.DoFunction(var Dest: TVarData;
  const V: TVarData;
{$ifdef FPC}
  const Name: AnsiString;
{$else}
  const Name: string;
{$endif}
  const Arguments: TVarDataArray): Boolean;
begin
  Result := SameText(string(Name), 'Take') and (Length(Arguments) = 1);
  If Result then begin
    FSeenType := Arguments[0].VType;
    FSeenText := VarToWideStr(Variant(Arguments[0]));
    Variant(Dest) := True;
  end;
end;

procedure Check(ACondition: Boolean; const AName: string);
begin
  If not ACondition then begin
    WriteLn('FAIL ', AName);
    Halt(1);
  end;
end;

var
  Probe: TCharDispatchProbe;
  Value: Variant;
begin
  Probe := TCharDispatchProbe.Create;
  try
    Value := Null;
    TVarData(Value).VType := Probe.VarType;

    Check(Boolean(Value.Take(AnsiChar('A'))), 'ansichar-call');
    { Delphi 12.2 Win64 reports varOleStr. On Linux the product RTL maps its
      wide-string carrier to varUString; both must remain a string value, not
      the original vtChar/vtWideChar scalar. }
    Check((Probe.SeenType = ExpectedStringCarrier) and
      (Probe.SeenText = 'A'), 'ansichar-as-string');

    Check(Boolean(Value.Take(WideChar($03BB))), 'widechar-call');
    Check((Probe.SeenType = ExpectedStringCarrier) and
      (Probe.SeenText = WideChar($03BB)), 'widechar-as-string');
  finally
    VarClear(Value);
    Probe.Free;
  end;
  WriteLn('VARIANT_CHAR_DISPATCH_OK');
end.
