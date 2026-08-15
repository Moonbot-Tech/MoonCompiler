program unwind;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses SysUtils;

var
  Trail: AnsiString;

type
  TTag = class(TInterfacedObject)
  private
    FTag: AnsiChar;
  public
    constructor Create(ATag: AnsiChar);
    destructor Destroy; override;
  end;

constructor TTag.Create(ATag: AnsiChar);
begin
  inherited Create;
  FTag := ATag;
end;

destructor TTag.Destroy;
begin
  Trail := Trail + FTag;
  inherited Destroy;
end;

procedure Deep(Level: Integer);
var
  L: IInterface;
begin
  L := TTag.Create(AnsiChar(Ord('a') + Level));
  if Level > 0 then
    Deep(Level - 1)
  else
    raise Exception.Create('boom');
end;

begin
  Trail := '';
  try
    Deep(1);
  except
    on Exception do
      Trail := Trail + 'x';
  end;
  WriteLn('trail=', string(Trail), '   expected ab then x');
end.
