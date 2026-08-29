{ %OPT=-O2 }

program tcselocalswitches1;

{$mode delphi}

uses
  SysUtils;

var
  Values: array[0..0] of Integer;
  Index: Integer;
  FirstValue: Integer;
  SecondValue: Integer;

begin
  Values[0] := 7;
  Index := 1;
  try
    FirstValue := {$R-} Values[Index];
    SecondValue := {$R-} Values[Index] + {$R+} Values[Index];
    Writeln('missing range error: ', FirstValue, ' ', SecondValue);
    Halt(1);
  except
    on ERangeError do
      Halt(0);
    else
      Halt(2);
  end;
end.
