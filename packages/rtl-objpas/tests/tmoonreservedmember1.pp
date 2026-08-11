{ %OPT=-O2 }
program tmoonreservedmember1;

{$mode delphi}

uses
  SysUtils,
  Variants;

type
  TProbe = class(TInvokeableVariantType)
  public
    procedure Clear(var V: TVarData); override;
    procedure Copy(var Dest: TVarData; const Source: TVarData;
      const Indirect: Boolean); override;
    function GetProperty(var Dest: TVarData; const V: TVarData;
      const Name: AnsiString): Boolean; override;
  end;

procedure TProbe.Clear(var V: TVarData);
begin
  V.VType := varEmpty;
end;

procedure TProbe.Copy(var Dest: TVarData; const Source: TVarData;
  const Indirect: Boolean);
begin
  Dest.VType := Source.VType;
end;

function TProbe.GetProperty(var Dest: TVarData; const V: TVarData;
  const Name: AnsiString): Boolean;
begin
  Result := SameText(Name, 'type');
  if Result then
    Variant(Dest) := 'spot';
end;

var
  Probe: TProbe;
  Value: Variant;
begin
  Probe := TProbe.Create;
  try
    TVarData(Value).VType := Probe.VarType;
    if string(Value.type) <> 'spot' then
      Halt(1);
  finally
    VarClear(Value);
    Probe.Free;
  end;
end.
