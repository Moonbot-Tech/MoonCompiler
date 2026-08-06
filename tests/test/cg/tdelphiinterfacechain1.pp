program tdelphiinterfacechain1;

{$ifdef FPC}
  {$mode delphi}
{$endif}

uses
  SysUtils;

type
  IBase = interface
    ['{D2A4477D-D860-443E-90BF-0EC510A0537D}']
    function GetText: string;
    property Text: string read GetText;
  end;

  IDerived = interface(IBase)
    ['{FD663604-48E8-4294-9D4D-CB34E2A4A49E}']
    function CopyValue(AValue: Integer): IDerived;
  end;

  TProbe = class(TInterfacedObject, IBase, IDerived)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    function CopyValue(AValue: Integer): IDerived;
    function GetText: string;
  end;

constructor TProbe.Create(AValue: Integer);
begin
  inherited Create;
  FValue := AValue;
end;

function TProbe.CopyValue(AValue: Integer): IDerived;
begin
  Result := TProbe.Create(AValue);
end;

function TProbe.GetText: string;
begin
  Result := IntToStr(FValue);
end;

function NewProbe(AValue: Integer): IDerived;
begin
  Result := TProbe.Create(AValue);
end;

var
  D: IDerived;
begin
  D := NewProbe(1);
  If D.CopyValue(2).Text <> '2' then
    Halt(10);
  If D.CopyValue(3).Text <> '3' then
    Halt(11);
  If D.Text <> '1' then
    Halt(12);
  D := nil;
  WriteLn('OK');
end.
