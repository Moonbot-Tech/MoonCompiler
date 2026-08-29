unit f_except;

{ Exceptions (negative pair 5): a trapping instruction observes all previous
  stores, and the first-def-inside-try form must keep the guarded write
  visible - the read after the handler merge depends on it. }

interface

uses
  f_local;

function TryFirstDef(p: PInteger; Bias: Integer): Integer;
procedure RaiseForm;
procedure OnForm;

implementation

type
  EMy = class(TObject)
  end;

// first def inside the guarded region, fault after it, read after except:
// the model must report the local write AND the wide trap-carrying write
// EXPECT: proc=TryFirstDef r=L w=LEHGTP ie=t reason=pointer_alias
function TryFirstDef(p: PInteger; Bias: Integer): Integer;
var
  Acc: Integer;
begin
  try
    Acc := Bias;
    p^ := 1;
  except
  end;
  Result := Acc;
end;

// the raise statement is lowered to a compilerproc call before the observe
// point: the trap and barrier arrive through the opaque-call classification
// EXPECT: proc=RaiseForm ie=st reason=opaque_call
procedure RaiseForm;
begin
  raise EMy.Create;
end;

// entering the handler writes the exception variable; the guarded call is a
// barrier
// EXPECT: proc=OnForm ie=st reason=opaque_call
procedure OnForm;
begin
  try
    Poke;
  except
    on E: TObject do
      GHit := 1;
  end;
end;

end.
