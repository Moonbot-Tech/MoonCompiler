program tracker_qp_38;

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
  TSmallRecord = record A, B: Integer; end;
  TCallback = procedure(const Value: TSmallRecord; Marker: Byte);
var CallbackCount: Integer;
procedure MarkCallback(const Value: TSmallRecord; Marker: Byte);
begin
  Check((Value.A = 111) and (Value.B = 222), 'record-abi');
  Check(Marker = 73, 'byte-abi');
  Inc(CallbackCount);
end;
procedure Exercise(Callback: TCallback);
var R: TSmallRecord; P: Pointer; Marker: Byte;
begin
  R.A := 111; R.B := 222; P := @R; Marker := 73;
  for var I := 0 to 15 do Inc(R.A, I and 0);
  if P <> @R then Halt(2);
  Callback(R, Marker);
end;

procedure Run;
begin
CallbackCount := 0; Exercise(MarkCallback); Check(CallbackCount = 1, 'callback-count');
end;

begin
  try
    Run;
    WriteLn('PASS QP-38');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-38: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
