program inline_fresh_managed_result_codegen;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils;

type
  TIntArray = array of Integer;

function MakeFresh: TIntArray; inline;
begin
  SetLength(Result,3);
  Result[0]:=10;
  Result[1]:=20;
  Result[2]:=30;
end;

function ForwardFresh: TIntArray; inline;
begin
  Result:=MakeFresh;
end;

function FreshLength: Integer; noinline;
begin
  Result:=Length(ForwardFresh);
end;

begin
  if FreshLength<>3 then
    Halt(1);
  WriteLn('INLINE_FRESH_MANAGED_RESULT_CODEGEN_PASS');
end.
