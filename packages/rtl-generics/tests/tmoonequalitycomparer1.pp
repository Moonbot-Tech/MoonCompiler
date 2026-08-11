{ %OPT=-O2 }
program tmoonequalitycomparer1;

{$mode delphi}
{$modeswitch anonymousfunctions}
{$modeswitch functionreferences}

uses
  SysUtils,
  Generics.Defaults;

var
  Comparer: IEqualityComparer<string>;
begin
  Comparer := TEqualityComparer<string>.Construct(
    function(const Left, Right: string): Boolean
    begin
      Result := SameText(Left, Right);
    end,
    function(const Value: string): Integer
    begin
      Result := Length(Value) + 10;
    end);
  if not Comparer.Equals('Spot', 'spot') then
    Halt(1);
  if Comparer.GetHashCode('abc') <> 13 then
    Halt(2);
end.
