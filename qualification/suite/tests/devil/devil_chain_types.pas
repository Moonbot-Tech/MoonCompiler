unit devil_chain_types;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch INLINEVARS}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
{$endif}
{$Q-}{$R-}

interface

uses
  SysUtils;

type
  { specialized on the other side of the boundary, so the     compiler has to replay this body out of the PPU }
  TDvlCarrier<T> = record
  private
    FValue: T;
    FText: AnsiString;
  public
    procedure Put(const Value: T);
    function Get: T;
    function Width: Integer;
  end;

  IDvlRelay = interface
    ['{5E000000-0000-0000-0000-0000000000A1}']
    function Relay(X: Int64): Int64;
  end;

  TDvlRelayBase = class(TInterfacedObject, IDvlRelay)
  public
    function Relay(X: Int64): Int64; virtual;
  end;

implementation

procedure TDvlCarrier<T>.Put(const Value: T);
begin
  FValue := Value;
  FText := AnsiString('carried');
end;

function TDvlCarrier<T>.Get: T;
begin
  Result := FValue;
end;

function TDvlCarrier<T>.Width: Integer;
begin
  Result := SizeOf(T) + Length(FText);
end;

function TDvlRelayBase.Relay(X: Int64): Int64;
begin
  Result := X;
end;

end.
