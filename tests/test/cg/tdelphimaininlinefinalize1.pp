{ %OPT=-O3 }
program tdelphimaininlinefinalize1;

{$ifdef FPC}
  {$mode delphi}
  {$modeswitch inlinevars}
{$endif}

type
  TTrace = class(TInterfacedObject)
  private
    FTag: AnsiChar;
  public
    constructor Create(Tag: AnsiChar);
    destructor Destroy; override;
  end;

const
  Expected: array[1..6] of AnsiChar = ('f', 'e', 'd', 'a', 'b', 'c');

var
  NextExpected: Integer;
  GlobalA, GlobalB, GlobalC: IInterface;

constructor TTrace.Create(Tag: AnsiChar);
begin
  inherited Create;
  FTag := Tag;
end;

destructor TTrace.Destroy;
begin
  Inc(NextExpected);
  If (NextExpected > Length(Expected)) or
     (FTag <> Expected[NextExpected]) then
    ExitCode := 1;
  inherited Destroy;
end;

begin
  NextExpected := 0;
  GlobalA := TTrace.Create('a');
  GlobalB := TTrace.Create('b');
  GlobalC := TTrace.Create('c');
  var InlineD: IInterface := TTrace.Create('d');
  var InlineE: IInterface := TTrace.Create('e');
  var InlineF: IInterface := TTrace.Create('f');
end.
