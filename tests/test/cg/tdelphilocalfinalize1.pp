{ %OPT=-O3 }
program tdelphilocalfinalize1;

{$ifdef FPC}
  {$mode delphi}
  {$modeswitch advancedrecords}
  {$modeswitch inlinevars}
{$endif}

uses
  SysUtils;

type
  TTrace = class(TInterfacedObject)
  private
    FTag: AnsiChar;
  public
    constructor Create(ATag: AnsiChar);
    destructor Destroy; override;
  end;

  TManagedTrace = record
    Tag: AnsiChar;
    class operator Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TManagedTrace);
    class operator Finalize(var Dest: TManagedTrace);
  end;

var
  Trail: AnsiString;
  ManagedTrail: AnsiString;

constructor TTrace.Create(ATag: AnsiChar);
begin
  inherited Create;
  FTag := ATag;
end;

destructor TTrace.Destroy;
begin
  Trail := Trail + FTag;
  inherited Destroy;
end;

class operator TManagedTrace.Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TManagedTrace);
begin
  Dest.Tag := '?';
  ManagedTrail := ManagedTrail + 'I';
end;

class operator TManagedTrace.Finalize(var Dest: TManagedTrace);
begin
  ManagedTrail := ManagedTrail + 'F' + Dest.Tag;
end;

{$ifdef FPC}
function FailingInitializer: IInterface; noinline;
{$else}
{$INLINE OFF}
function FailingInitializer: IInterface;
{$INLINE ON}
{$endif}
begin
  raise Exception.Create('expected initializer failure');
end;

procedure NormalExit;
var
  A, B, C: IInterface;
begin
  A := TTrace.Create('a');
  B := TTrace.Create('b');
  C := TTrace.Create('c');
end;

procedure ExceptionalExit;
var
  A, B, C: IInterface;
begin
  A := TTrace.Create('x');
  B := TTrace.Create('y');
  C := TTrace.Create('z');
  raise Exception.Create('expected');
end;

procedure InlineSameBlock;
begin
  var A: IInterface := TTrace.Create('a');
  var B: IInterface := TTrace.Create('b');
  var C: IInterface := TTrace.Create('c');
end;

procedure InlineNestedBlock;
begin
  var A: IInterface := TTrace.Create('a');
  begin
    var B: IInterface := TTrace.Create('b');
    var C: IInterface := TTrace.Create('c');
  end;
  Trail := Trail + 'm';
end;

procedure MixedLocals;
var
  A: IInterface;
begin
  A := TTrace.Create('a');
  begin
    var B: IInterface := TTrace.Create('b');
    var C: IInterface := TTrace.Create('c');
  end;
end;

procedure InlineExceptionalExit;
begin
  var X: IInterface := TTrace.Create('x');
  begin
    var Y: IInterface := TTrace.Create('y');
    var Z: IInterface := TTrace.Create('z');
  end;
  raise Exception.Create('expected');
end;

procedure InlineInitializerException;
begin
  var A: IInterface := FailingInitializer;
end;

procedure ExitBeforeDeclaration;
begin
  Trail := Trail + 'x';
  Exit;
  var A: IInterface := TTrace.Create('a');
end;

procedure ExitAfterDeclaration;
begin
  var A: IInterface := TTrace.Create('a');
  Exit;
end;

procedure LoopControl;
var
  I: Integer;
begin
  for I := 1 to 3 do begin
    var A: IInterface := TTrace.Create(AnsiChar(Ord('0') + I));
    If I = 1 then
      Continue;
    If I = 2 then
      Break;
  end;
end;

procedure ManagedSibling;
begin
  ManagedTrail := ManagedTrail + 'A';
  begin
    ManagedTrail := ManagedTrail + 'B';
    var R: TManagedTrace;
    R.Tag := 'r';
    ManagedTrail := ManagedTrail + 'C';
  end;
  ManagedTrail := ManagedTrail + 'D';
end;

procedure ManagedBeforeDeclaration(LeaveEarly: Boolean);
begin
  ManagedTrail := ManagedTrail + 'A';
  If LeaveEarly then
    Exit;
  ManagedTrail := ManagedTrail + 'B';
  var R: TManagedTrace;
  R.Tag := 'r';
  ManagedTrail := ManagedTrail + 'C';
end;

procedure ManagedReenter;
var
  I: Integer;
begin
  for I := 1 to 2 do begin
    ManagedTrail := ManagedTrail + 'A';
    var R: TManagedTrace;
    R.Tag := AnsiChar(Ord('0') + I);
    ManagedTrail := ManagedTrail + 'B';
  end;
end;

begin
  Trail := '';
  NormalExit;
  If Trail <> 'cba' then Halt(1);

  Trail := '';
  try
    ExceptionalExit;
  except
    on Exception do ;
  end;
  If Trail <> 'zyx' then Halt(2);

  Trail := '';
  InlineSameBlock;
  If Trail <> 'cba' then Halt(3);

  Trail := '';
  InlineNestedBlock;
  If Trail <> 'cbma' then Halt(4);

  Trail := '';
  MixedLocals;
  If Trail <> 'cba' then Halt(5);

  Trail := '';
  try
    InlineExceptionalExit;
  except
    on Exception do ;
  end;
  If Trail <> 'zyx' then Halt(6);

  Trail := '';
  try
    InlineInitializerException;
  except
    on Exception do ;
  end;
  If Trail <> '' then Halt(7);

  Trail := '';
  ExitBeforeDeclaration;
  If Trail <> 'x' then Halt(8);

  Trail := '';
  ExitAfterDeclaration;
  If Trail <> 'a' then Halt(9);

  Trail := '';
  LoopControl;
  If Trail <> '12' then Halt(10);

  ManagedTrail := '';
  ManagedSibling;
  If ManagedTrail <> 'ABICFrD' then Halt(11);

  ManagedTrail := '';
  ManagedBeforeDeclaration(True);
  If ManagedTrail <> 'A' then Halt(12);

  ManagedTrail := '';
  ManagedBeforeDeclaration(False);
  If ManagedTrail <> 'ABICFr' then Halt(13);

  ManagedTrail := '';
  ManagedReenter;
  If ManagedTrail <> 'AIBF1AIBF2' then Halt(14);
end.
