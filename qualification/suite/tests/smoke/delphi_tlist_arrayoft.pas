program delphi_tlist_arrayoft;

{$mode delphi}
{$modeswitch implicitgenerics}

uses
  System.Generics.Collections;

var
  Items: TList<Integer>;
  Buffer: TList<Integer>.arrayofT;

begin
  Items:=TList<Integer>.Create;
  try
    Items.Add(11);
    Items.Add(22);
    Buffer:=Items.List;
    Buffer[1]:=33;
    if (Length(Buffer)<Items.Count) or
       (Buffer[0]<>11) or (Items[1]<>33) then
      Halt(1);
    Writeln('DELPHI_TLIST_ARRAYOFT_OK');
  finally
    Items.Free;
  end;
end.
