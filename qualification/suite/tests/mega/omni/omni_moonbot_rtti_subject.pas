unit omni_moonbot_rtti_subject;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}

interface

uses
  Rtti;

type
  TMoonGroupAttribute = class(TCustomAttribute)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    property Value: Integer read FValue;
  end;

  TMoonIdAttribute = class(TCustomAttribute)
  private
    FValue: Integer;
  public
    constructor Create(AValue: Integer);
    property Value: Integer read FValue;
  end;

  {$M+}
  {$RTTI EXPLICIT METHODS([vcPublic, vcPublished])
    FIELDS([vcPrivate, vcProtected, vcPublic, vcPublished])}

  [TMoonGroupAttribute(7), TMoonIdAttribute(0)]
  TMoonRttiCommand = class
  private
    FSecret: Integer;
  protected
    FProtected: Integer;
  public
    Name: string;
    Count: Int64;
    constructor Create; virtual;
    class function Kind: Integer; virtual;
    procedure PublicFire(Sender: TObject);
  published
    procedure Fire(Sender: TObject);
  end;

  [TMoonIdAttribute(13)]
  TMoonRttiLeaf = class(TMoonRttiCommand)
  public
    Extra: Boolean;
    constructor Create; override;
    class function Kind: Integer; override;
  end;

  TMoonRttiCommandClass = class of TMoonRttiCommand;

implementation

constructor TMoonGroupAttribute.Create(AValue: Integer);
begin
  FValue := AValue;
end;

constructor TMoonIdAttribute.Create(AValue: Integer);
begin
  FValue := AValue;
end;

constructor TMoonRttiCommand.Create;
begin
  inherited Create;
  FSecret := 11;
  FProtected := 12;
  Name := 'base';
  Count := 20;
end;

class function TMoonRttiCommand.Kind: Integer;
begin
  Result := 1;
end;

procedure TMoonRttiCommand.Fire(Sender: TObject);
begin
  if Sender = Self then
  begin
    Name := Name + '-fired';
    Inc(Count, FSecret + FProtected);
  end;
end;

procedure TMoonRttiCommand.PublicFire(Sender: TObject);
begin
  if Sender = Self then
  begin
    Name := Name + '-public';
    Inc(Count, 29);
  end;
end;

constructor TMoonRttiLeaf.Create;
begin
  inherited Create;
  Extra := True;
end;

class function TMoonRttiLeaf.Kind: Integer;
begin
  Result := inherited Kind + 12;
end;

end.
