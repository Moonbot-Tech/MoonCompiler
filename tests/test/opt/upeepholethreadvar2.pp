unit upeepholethreadvar2;

{$mode delphi}

interface

function StepThreadValue(Delta: Int64): Int64; inline;

implementation

uses
  upeepholethreadvar1;

function StepThreadValue(Delta: Int64): Int64;
begin
  Result := TouchThreadValue(Delta);
end;

end.
