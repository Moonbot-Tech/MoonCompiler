{ %OPT=-Mdelphi -O2 -dMOONCOMPILER_UNICODE_DEFAULT }
program tmoonunicodeansisysutils1;

uses
  SysUtils;

procedure Check(Condition: Boolean; Code: Byte);
begin
  If not Condition then
    Halt(Code);
end;

var
  LowerText: UnicodeString;
  UpperText: UnicodeString;
begin
  LowerText := UnicodeString(#$0430#$0431#$0432#$0433);
  UpperText := UnicodeString(#$0410#$0411#$0412#$0413);

  Check(AnsiCompareText(LowerText, UpperText) = 0, 1);
  Check(AnsiCompareStr(LowerText, UpperText) <> 0, 2);
  Check(AnsiUpperCase(LowerText) = UpperText, 3);
  Check(AnsiLowerCase(UpperText) = LowerText, 4);
  Check(AnsiSameText(LowerText, UpperText), 5);
  Check(not AnsiSameStr(LowerText, UpperText), 6);
end.
