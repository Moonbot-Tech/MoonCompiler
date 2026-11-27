unit BaseUnit;

{$mode delphi}

interface

type
  TBase = class
  private
    FName: string;
  public
    constructor Create(const AName: string);
    function Describe: string; virtual;
    property Name: string read FName;
  end;

implementation

constructor TBase.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

function TBase.Describe: string;
begin
  Result := 'base:' + FName;
end;

end.
