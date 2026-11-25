unit mega_breadth_unit;

{$ifdef FPC}
  {$mode delphi}{$H+}
{$endif}

interface

type
  TBreadthUnitCode = type SmallInt;

  TBreadthUnitStamp = record
    Data: Int64;
    LabelText: AnsiString;
  end;

  TBreadthUnitMap = function(const Input: TBreadthUnitStamp; Step: Int64; Scale: Double): TBreadthUnitStamp of object;

  TBreadthRouteProfile = record
    Ticket: Int64;
    Caption: UnicodeString;
  end;

  TBreadthRouteProfileHelper = record helper for TBreadthRouteProfile
    function WithSuffix(const Suffix: UnicodeString; Delta: Int64): TBreadthRouteProfile; overload; inline;
    function WithSuffix(const Suffixes: array of UnicodeString; Delta: Int64): TBreadthRouteProfile; overload;
  end;

var
  BreadthUnitCoefficient: Integer;

threadvar
  BreadthThreadToken: Int64;

function BreadthReadThreadToken(out Address: Pointer): Int64;
procedure BreadthChangeCoefficient(Delta: Integer);
function BreadthUnitDecode(Value: Int64): TBreadthUnitCode; inline;
procedure BreadthResetSequence(Initial: Integer);
function BreadthReadSequence: Integer;
function BreadthAdvanceSequence(Delta: Integer): Integer;
function BreadthNextStamp(const Prefix: AnsiString; Delta: Integer): TBreadthUnitStamp; inline;
function BreadthMapUnitStamp(const Input: TBreadthUnitStamp; Step: Int64; Scale: Double;
  Map: TBreadthUnitMap): TBreadthUnitStamp; inline;

function BreadthReadUnitResource: UnicodeString;

type
  {$RTTI EXPLICIT METHODS([vcPublic])}
  TBreadthRttiEndpoint = class
  public
    Mark: Int64;
    function Packet(Left: Int64; Scale: Double; const Text: UnicodeString; Right: Int64): UnicodeString; cdecl;
  end;

implementation

resourcestring
  BreadthStatusResource = 'unit'#0'resource';

var
  Sequence: Integer;

function TBreadthRouteProfileHelper.WithSuffix(const Suffix: UnicodeString; Delta: Int64): TBreadthRouteProfile;
begin
  Result := Self;
  Result.Caption := Caption + Suffix;
  Inc(Result.Ticket, Delta);
end;

function TBreadthRouteProfileHelper.WithSuffix(const Suffixes: array of UnicodeString; Delta: Int64): TBreadthRouteProfile;
var
  Suffix: UnicodeString;
begin
  Result := Self;
  for Suffix in Suffixes do
    Result.Caption := Result.Caption + Suffix;
  Inc(Result.Ticket, Delta);
end;

function BreadthReadUnitResource: UnicodeString;
begin
  Result := UnicodeString(LoadResString(@BreadthStatusResource));
end;

function BreadthReadThreadToken(out Address: Pointer): Int64;
begin
  Address := @BreadthThreadToken;
  Result := BreadthThreadToken;
end;

procedure BreadthChangeCoefficient(Delta: Integer);
begin
  Inc(BreadthUnitCoefficient, Delta);
end;

function BreadthUnitDecode(Value: Int64): TBreadthUnitCode;
begin
  Result := TBreadthUnitCode(Value);
end;

procedure BreadthResetSequence(Initial: Integer);
begin
  Sequence := Initial;
end;

function BreadthReadSequence: Integer;
begin
  Result := Sequence;
end;

function BreadthAdvanceSequence(Delta: Integer): Integer;
begin
  Inc(Sequence, Delta);
  Result := Sequence;
end;

function BreadthNextStamp(const Prefix: AnsiString; Delta: Integer): TBreadthUnitStamp;
begin
  Result.Data := Int64(BreadthAdvanceSequence(Delta)) * 1000000007 + Delta;
  Result.LabelText := Prefix + '!';
end;

function BreadthMapUnitStamp(const Input: TBreadthUnitStamp; Step: Int64; Scale: Double;
  Map: TBreadthUnitMap): TBreadthUnitStamp;
var
  First: TBreadthUnitStamp;
begin
  First := Map(Input, Step, Scale);
  Result := Map(First, Step - 17, -Scale);
end;

function TBreadthRttiEndpoint.Packet(Left: Int64; Scale: Double; const Text: UnicodeString; Right: Int64): UnicodeString;
begin
  Mark := Left + Right + Trunc(Scale * 8.0);
  Result := Text + '!';
end;
end.
