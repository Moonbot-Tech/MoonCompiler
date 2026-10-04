program tforunrollppu1;

{$mode delphi}
{$inline on}

uses
  uforunrollppu1;

begin
  if PureExplicit<>6 then
    Halt(1);
  if PureAuto<>6 then
    Halt(2);
  if HandlerExplicit<>2 then
    Halt(3);
  if ContinuationExplicit<>2 then
    Halt(4);
end.
