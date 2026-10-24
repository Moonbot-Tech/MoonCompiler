unit StateB;
interface
function GetText: UnicodeString;
function GetClass: TClass;
implementation
uses Ledger, StateCore;
function GetText: UnicodeString;
begin Result := TState<Integer>.Text; end;
function GetClass: TClass;
begin Result := TState<Integer>; end;
initialization
  Mark('B');
  TState<Integer>.Text := TState<Integer>.Text + 'B';
finalization
  Mark('b');
end.
