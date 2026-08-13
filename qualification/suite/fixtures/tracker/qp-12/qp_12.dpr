program tracker_qp_12;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch nestedprocvars}
  {$modeswitch inlinevars}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  SysUtils, Classes, Math, Variants, TypInfo, Rtti,
  Generics.Defaults, Generics.Collections;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then
    raise Exception.Create(Name);
end;

var LockInit, LockFini: Integer;
type
  TLocker = record
    Marker: Integer;
    class operator Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TLocker);
    class operator Finalize(var Dest: TLocker);
  end;
  TBase = class
    Lock: TLocker;
  end;
  TChild = class(TBase)
    Text: WideString;
  end;
class operator TLocker.Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TLocker);
begin Dest.Marker := 77; Inc(LockInit); end;
class operator TLocker.Finalize(var Dest: TLocker);
begin Inc(LockFini); end;

procedure Run;
begin
var I0 := LockInit;
  var F0 := LockFini;
  var Child := TChild.Create;
  Check(Child.Lock.Marker = 77, 'base-field-init');
  Child.Text := 'wide';
  Child.Free;
  Check(LockInit - I0 = 1, 'init-count');
  Check(LockFini - F0 = 1, 'fini-count');
end;

begin
  try
    Run;
    WriteLn('PASS QP-12');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-12: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
