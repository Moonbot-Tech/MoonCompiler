program Fpc41558RegvarObjectchecksInline;

{$mode objfpc}
{$optimization off}
{$optimization regvar}
{$objectchecks on}
{$modeswitch advancedrecords}

type
  TBound = record
    Physical, Logical, Offset: Integer;
    procedure Init; inline;
  end;

  TAttribute = class
    FStartX: TBound;
    procedure SetStartX(AValue: TBound); virtual;
    procedure SetFrameBoundsLog; inline;
  end;

  TMarkup = class
    function HasMatches: Boolean; virtual;
    function GetAttribute: TAttribute;
  end;

procedure TBound.Init;
begin
end;

procedure TAttribute.SetStartX(AValue: TBound);
begin
end;

procedure TAttribute.SetFrameBoundsLog;
var
  B: TBound;
begin
  B.Init;
  SetStartX(B);
end;

function TMarkup.HasMatches: Boolean;
begin
  Result := False;
end;

function TMarkup.GetAttribute: TAttribute;
begin
  Result := nil;
  if not HasMatches then
    Exit;
  Result.SetFrameBoundsLog;
end;

var
  Markup: TMarkup;
  Value: TObject;
begin
  Markup := TMarkup.Create;
  try
    Value := Markup.GetAttribute;
    if Value <> nil then
      Halt(1);
  finally
    Markup.Free;
  end;
end.
