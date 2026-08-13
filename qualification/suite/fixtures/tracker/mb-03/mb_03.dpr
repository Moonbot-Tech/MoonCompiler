program tracker_mb_03;

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

var RuntimeZero: UInt64 = 0;
function OpaqueWord(Value: Word): Word;
{$ifdef FPC}noinline;{$endif}
begin
  Result := Word(UInt64(Value) xor RuntimeZero);
end;

procedure Run;
begin
var A: Word := OpaqueWord(65535);
  var B: Word := OpaqueWord(65534);
  var Product: UInt64 := UInt64(A * B);
  Check(Product = UInt64(4294770690), 'word-product');
end;

begin
  try
    Run;
    WriteLn('PASS MB-03');
  except
    on E: Exception do
    begin
      WriteLn('FAIL MB-03: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
