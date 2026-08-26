program tdelphidictionaryisempty1;

{$mode delphiunicode}

uses
  Generics.Collections;

procedure Check(Condition: Boolean; ErrorCode: Byte);
begin
  if not Condition then
    Halt(ErrorCode);
end;

var
  Dictionary: TDictionary<UInt64,string>;
begin
  Dictionary:=TDictionary<UInt64,string>.Create;
  try
    Check(Dictionary.IsEmpty and (Dictionary.Count=0),1);
    Dictionary.Add(7,'seven');
    Check(not Dictionary.IsEmpty and (Dictionary.Count=1),2);
    Dictionary.Remove(7);
    Check(Dictionary.IsEmpty and (Dictionary.Count=0),3);
  finally
    Dictionary.Free;
  end;
end.
