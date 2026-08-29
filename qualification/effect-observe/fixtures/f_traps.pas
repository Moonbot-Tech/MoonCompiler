unit f_traps;

{ Integer trap forms: division traps unconditionally (zero divisor, MinInt
  div -1); checked arithmetic traps only under the check switches - and the
  unchecked twin must stay trap-free. }

interface

function DivForm(a, b: Integer): Integer;
function OvfAdd(a, b: Integer): Integer;
function PlainAdd(a, b: Integer): Integer;

implementation

// EXPECT: proc=DivForm ie=t reason=may_trap
function DivForm(a, b: Integer): Integer;
begin
  Result := a div b;
end;

{$Q+}
// EXPECT: proc=OvfAdd ie=t reason=may_trap
function OvfAdd(a, b: Integer): Integer;
begin
  Result := a + b;
end;
{$Q-}

// EXPECT: proc=PlainAdd ie=- reasons=-
function PlainAdd(a, b: Integer): Integer;
begin
  Result := a + b;
end;

end.
