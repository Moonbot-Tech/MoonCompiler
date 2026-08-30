unit upeepholethreadvar1;

{$mode delphi}

interface

function TouchThreadValue(Delta: Int64): Int64; inline;

implementation

threadvar
  ThreadValue: Int64;

function TouchThreadValue(Delta: Int64): Int64;
begin
  ThreadValue := ThreadValue + Delta;
  Result := ThreadValue;
end;

end.
