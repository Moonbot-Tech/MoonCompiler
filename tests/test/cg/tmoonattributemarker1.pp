{ %OPT=-O2 }
program tmoonattributemarker1;

{$mode delphiunicode}
{$modeswitch prefixedattributes}

uses
  Rtti;

type
  TMarkerAttribute = class(TCustomAttribute);

  [TMarkerAttribute]
  TMarkedClass = class
  private
    FValue: Integer;
  public
    [TMarkerAttribute]
    Field: Integer;
    [TMarkerAttribute]
    procedure Touch;
    [TMarkerAttribute]
    property Value: Integer read FValue write FValue;
  end;

procedure TMarkedClass.Touch;
begin
end;

begin
end.
