program test;

{$mode objfpc}

type
  TMyCC = class of TMyClass;
  TMyClass = class
    class function func: TMyCC; inline;
  end;

class function TMyClass.func: TMyCC;
begin
  func().func;
end;

begin
end.
