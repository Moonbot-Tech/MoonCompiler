program tracker_qp_25;

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

type
  TManaged = record
    Value: string;
    class var InitCount, FinalCount: Integer;
    {$ifdef FPC}
    class operator Initialize(var Dest: TManaged);
    {$else}
    class operator Initialize(out Dest: TManaged);
    {$endif}
    class operator Finalize(var Dest: TManaged);
  end;
  PManaged = ^TManaged;
{$ifdef FPC}
class operator TManaged.Initialize(var Dest: TManaged);
{$else}
class operator TManaged.Initialize(out Dest: TManaged);
{$endif}
begin Inc(InitCount); end;
class operator TManaged.Finalize(var Dest: TManaged);
begin Inc(FinalCount); end;

procedure Run;
begin
TManaged.InitCount := 0; TManaged.FinalCount := 0;
  var Typed: PManaged;
  New(Typed);
  Typed^.Value := 'payload';
  var Raw := Pointer(Typed);
  Dispose(PManaged(Raw));
  Check(TManaged.InitCount = 1, 'initialize-count');
  Check(TManaged.FinalCount = 1, 'finalize-count');
end;

begin
  try
    Run;
    WriteLn('PASS QP-25');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-25: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
