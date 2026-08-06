{ %OPT=-O3 }
program tdelphilocalfinalizedefer1;

{$mode delphi}
{$modeswitch inlinevars}
{$modeswitch autofree}

type
  TTrace = class(TInterfacedObject)
  private
    FTag: AnsiChar;
  public
    constructor Create(Tag: AnsiChar);
    destructor Destroy; override;
  end;

var
  Trail: AnsiString;

constructor TTrace.Create(Tag: AnsiChar);
begin
  inherited Create;
  FTag := Tag;
end;

destructor TTrace.Destroy;
begin
  Trail := Trail + FTag;
  inherited Destroy;
end;

procedure Run;
begin
  var A: IInterface := TTrace.Create('a');
  defer Trail := Trail + 'd';
  var B: IInterface := TTrace.Create('b');
end;

begin
  Trail := '';
  Run;
  If Trail <> 'bda' then
    Halt(1);
end.
