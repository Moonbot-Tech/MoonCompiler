program tracker_so_10;

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

type TLarge = record A, B, C, D: Cardinal; end;
function MakeLarge(Tag: Cardinal): TLarge;
begin Result.A := Tag; Result.B := Tag + 1; Result.C := Tag + 2; Result.D := Tag + 3; end;
procedure Verify(const Value: TLarge; Tag: Cardinal);
begin Check((Value.A=Tag) and (Value.B=Tag+1) and (Value.C=Tag+2) and (Value.D=Tag+3), 'payload'); end;

procedure Run;
begin
var List := TList<TLarge>.Create;
  try List.Add(MakeLarge(10)); List.Add(MakeLarge(30)); List.Insert(1, MakeLarge(20)); List.Insert(0, MakeLarge(0)); List.Insert(List.Count, MakeLarge(40));
    Check(List.Count=5,'count'); for var I:=0 to 4 do Verify(List[I], Cardinal(I*10));
  finally List.Free; end;
end;

begin
  try
    Run;
    WriteLn('PASS SO-10');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-10: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
