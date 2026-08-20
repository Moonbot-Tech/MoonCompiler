program exception_unwind_order_semantic;

{ Managed locals of recursive frames unwind from the innermost frame out.

  The red form (audit 50b82f51 interaction, Devil dvl-0003): at O2/O3 the
  tail-recursion optimizer turned the recursive call into a jump although
  an interface local is released after that call returns - the call was
  never in tail position.  With one shared frame the next iteration's
  assignment released the previous level's reference, so the observable
  destruction order inverted: bax instead of the Delphi/O1 abx, an
  inner-destructor-sees-dead-owner hazard.  do_opttail now refuses the
  optimization when a used managed local (or a managed temporary,
  announced by pass_1) forces per-frame cleanup; pure recursion keeps the
  loop conversion. }

{$mode delphiunicode}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,cwstring,{$endif UNIX}
  SysUtils;

var
  Trail: AnsiString = '';

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

procedure DeepThree(Level: Integer);
var
  L: IInterface;
begin
  L := TTag.Create(AnsiChar(Ord('a') + Level));
  if Level > 0 then
    DeepThree(Level - 1)
  else
    raise Exception.Create('boom');
end;

var
  Fails: Integer = 0;
begin
  Trail := '';
  try
    Deep(1);
  except
    on Exception do
      Trail := Trail + 'x';
  end;
  if Trail <> 'abx' then
  begin
    WriteLn('FAIL two-frames trail=', Trail, ' want=abx');
    Inc(Fails);
  end;
  Trail := '';
  try
    DeepThree(2);
  except
    on Exception do
      Trail := Trail + 'x';
  end;
  if Trail <> 'abcx' then
  begin
    WriteLn('FAIL three-frames trail=', Trail, ' want=abcx');
    Inc(Fails);
  end;
  if Fails <> 0 then
    Halt(1);
  WriteLn('UNWIND_ORDER_SEMANTIC_OK');
end.
