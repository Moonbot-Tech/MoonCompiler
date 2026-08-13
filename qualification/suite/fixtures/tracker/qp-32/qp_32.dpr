program tracker_qp_32;

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
  TUnary<TArg,TResult> = reference to function(const Value: TArg): TResult;
  TBinary<TLeft,TRight,TResult> = reference to function(const Left: TLeft; const Right: TRight): TResult;
  TCurry<TLeft,TRight,TResult> = class
    class function Build(const Func: TBinary<TLeft,TRight,TResult>): TUnary<TLeft,TUnary<TRight,TResult>>; static;
  end;
class function TCurry<TLeft,TRight,TResult>.Build(
  const Func: TBinary<TLeft,TRight,TResult>): TUnary<TLeft,TUnary<TRight,TResult>>;
begin
  Result :=
    function(const Left: TLeft): TUnary<TRight,TResult>
    begin
      Result :=
        function(const Right: TRight): TResult
        begin Result := Func(Left, Right); end;
    end;
end;

procedure Run;
begin
var Join: TBinary<string,Integer,string> :=
    function(const Left: string; const Right: Integer): string
    begin Result := Left + ':' + IntToStr(Right); end;
  var Curried1 := TCurry<string,Integer,string>.Build(Join);
  var Curried2 := TCurry<string,Integer,string>.Build(Join);
  var A := Curried1('A');
  var B := Curried2('B');
  Check(A(1) = 'A:1', 'a1'); Check(B(2) = 'B:2', 'b2');
  Check(A(3) = 'A:3', 'a3'); Check(B(4) = 'B:4', 'b4');
end;

begin
  try
    Run;
    WriteLn('PASS QP-32');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-32: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
