{ %OPT=-O2 }
program tmoonconditionalidentifier1;

{$mode delphi}

{$if MoonUndefinedConditional}
  {$fatal a bare unresolved conditional identifier must be false}
{$ifend}

{$if not MoonUndefinedConditional}
  {$fatal unary not of an unresolved conditional identifier must also be false}
{$ifend}

begin
end.
