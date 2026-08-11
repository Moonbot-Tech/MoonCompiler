{ %OPT=-O2 }
program tmoonvariantchar1;

{$mode delphi}

uses
  SysUtils,
  Variants;

type
  TProbe = class(TInvokeableVariantType)
  public
    SeenType: TVarType;
    SeenText: WideString;
    procedure Clear(var V: TVarData); override;
    procedure Copy(var Dest: TVarData; const Source: TVarData;
      const Indirect: Boolean); override;
    function DoFunction(var Dest: TVarData; const V: TVarData;
      const Name: AnsiString; const Arguments: TVarDataArray): Boolean; override;
  end;

procedure TProbe.Clear(var V: TVarData);
begin
  V.VType := varEmpty;
end;

procedure TProbe.Copy(var Dest: TVarData; const Source: TVarData;
  const Indirect: Boolean);
begin
  if Indirect and VarDataIsByRef(Source) then
    VarDataCopyNoInd(Dest, Source)
  else
    Dest.VType := Source.VType;
end;

function TProbe.DoFunction(var Dest: TVarData; const V: TVarData;
  const Name: AnsiString; const Arguments: TVarDataArray): Boolean;
begin
  Result := (Name = 'Take') and (Length(Arguments) = 1);
  if Result then
    begin
      SeenType := Arguments[0].VType;
      SeenText := VarToWideStr(Variant(Arguments[0]));
      Variant(Dest) := True;
    end;
end;

var
  Probe: TProbe;
  Value: Variant;
begin
  Probe := TProbe.Create;
  try
    TVarData(Value).VType := Probe.VarType;
    if not Boolean(Value.Take(AnsiChar('A'))) then
      Halt(1);
    if (Probe.SeenType <> varOleStr) and (Probe.SeenType <> varUString) then
      Halt(2);
    if Probe.SeenText <> 'A' then
      Halt(3);
  finally
    VarClear(Value);
    Probe.Free;
  end;
end.
