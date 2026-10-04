unit umoonconstmanaged1;
{$mode delphiunicode}{$inline on}
interface
uses SysUtils;
type
  IMarker = interface
    ['{6E6820F5-459E-4F7F-98B5-A2FCA1D4C1A7}']
    function Value: Integer;
  end;
  TManaged = record
    Text: UnicodeString;
    Marker: IMarker;
    Id: Integer;
    class operator Initialize(out Dest: TManaged);
    class operator Finalize(var Dest: TManaged);
    class operator Assign(var Dest: TManaged; const [ref] Source: TManaged);
  end;
var
  Created, Destroyed, Initialized, Finalized, Copies: Integer;
function MakeValue(Id: Integer): TManaged; inline;
function ReadValue(const V: TManaged): Integer; inline;
function Nested(const V: TManaged; Fail: Boolean): Integer; inline;
implementation
type
  TMarker = class(TInterfacedObject, IMarker)
    Id: Integer;
    constructor Create(AId: Integer);
    destructor Destroy; override;
    function Value: Integer;
  end;
constructor TMarker.Create(AId: Integer);
begin
  inherited Create;
  Id:=AId;
  Inc(Created);
end;
destructor TMarker.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;
function TMarker.Value: Integer;
begin
  Result:=Id;
end;
class operator TManaged.Initialize(out Dest: TManaged);
begin
  Dest.Id:=0;
  Inc(Initialized);
end;
class operator TManaged.Finalize(var Dest: TManaged);
begin
  if Assigned(Dest.Marker) then
    if (Dest.Marker.Value<>Dest.Id) or (Dest.Text<>IntToStr(Dest.Id)) then Halt(11);
  Inc(Finalized);
end;
class operator TManaged.Assign(var Dest: TManaged; const [ref] Source: TManaged);
begin
  Inc(Copies);
  Dest.Text:=Source.Text;
  Dest.Marker:=Source.Marker;
  Dest.Id:=Source.Id;
end;
function MakeValue(Id: Integer): TManaged;
begin
  Result.Text:=IntToStr(Id);
  Result.Marker:=TMarker.Create(Id);
  Result.Id:=Id;
end;
function ReadValue(const V: TManaged): Integer;
begin
  if not Assigned(V.Marker) then Halt(12);
  if (V.Marker.Value<>V.Id) or (V.Text<>IntToStr(V.Id)) then Halt(13);
  Result:=V.Id;
end;
function Nested(const V: TManaged; Fail: Boolean): Integer;
var
  Scratch, Mirror: TManaged;
begin
  Mirror:=V;
  Result:=ReadValue(Mirror);
  Scratch:=MakeValue(1234);
  if ReadValue(Scratch)<>1234 then Halt(14);
  Inc(Result,ReadValue(V));
  if Fail then raise Exception.Create('consumer');
end;
end.
