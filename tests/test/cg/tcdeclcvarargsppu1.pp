program tcdeclcvarargsppu1;

{$mode delphiunicode}

uses
  ucdeclcvarargs1;

var
  Buffer: array[0..63] of AnsiChar;
  Values: array of Integer;
  Printf: TSprintf;
begin
  If CPrintf(@Buffer[0],'%d %d',[17,23])<>5 then
    Halt(1);
  If AnsiString(PAnsiChar(@Buffer[0]))<>'17 23' then
    Halt(2);
  Printf:=GetCPrintf;
  If Printf(@Buffer[0],'%d %d',[23,17])<>5 then
    Halt(3);
  If AnsiString(PAnsiChar(@Buffer[0]))<>'23 17' then
    Halt(4);
  SetLength(Values,2);
  Values[0]:=17;
  Values[1]:=23;
  If CFirst(Values)<>17 then
    Halt(5);
  If CFirst([23,17])<>23 then
    Halt(6);
end.
