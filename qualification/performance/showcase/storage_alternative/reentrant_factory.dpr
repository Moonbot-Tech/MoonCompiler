program reentrant_factory;

{$mode delphiunicode}
uses SysUtils, Generics.Defaults, Astra.Collections;

type
  TCallbackFactory = class(TGenericsHashFactory)
    class function GetHashCode(Key: Pointer; Size: SizeInt; Initial: UInt32 = 0): UInt32; override;
  end;
  TMap = TOpenAddressingLP<UnicodeString, UInt64, TCallbackFactory>;

var Map: TMap; Armed: Boolean; Calls: Integer;

class function TCallbackFactory.GetHashCode(Key: Pointer; Size: SizeInt; Initial: UInt32): UInt32;
begin
  Inc(Calls);
  If Armed then begin
    Armed := False;
    Map.Capacity := Map.Capacity * 2;
  end;
  Result := inherited GetHashCode(Key, Size, Initial);
end;

begin
  Map := TMap.Create(8);
  Map.Add('first', 1);
  Map.Add('second', 2);
  If not Map.Flat then raise Exception.Create('Callback factory did not enter flat path');
  Calls := 0;
  Armed := True;
  var Value: UInt64 := 0;
  var Found := Map.TryGetValue('first', Value);
  Writeln('callback_calls=', Calls, ' found=', Found, ' value=', Value);
  Map.Free;
  If not Found or (Value <> 1) or (Calls <> 1) then Halt(1);
end.
