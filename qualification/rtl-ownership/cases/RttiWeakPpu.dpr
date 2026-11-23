program RttiWeakPpu;
{$mode delphiunicode}
uses mormot.core.fpcx64mm, WeakInterfaceTypes;
{$ifdef CHECK_WEAK_THREADVAR}
{$RTTI EXPLICIT PROPERTIES([vcPublic])}
type
  TThreadHolder = class
  public
    class threadvar Current: TRow;
    class property Link: IInterface read Current.Link;
  end;
{$endif}
var
  Strong: IInterface;
  Row: TRow;
begin
  {$ifdef CHECK_WEAK_THREADVAR}
  if TThreadHolder.ClassInfo=nil then Halt(3);
  {$endif}
  Strong := TInterfacedObject.Create;
  Replace(Row, Strong);
  if Pointer(Row.Link) <> Pointer(Strong) then Halt(1);
  Row.Link := Strong;
  {$ifdef CHECK_STRONG_VAR}AssignStrong(Row.Link);{$endif}
  {$ifdef CHECK_STRONG_OUT}ResetStrong(Row.Link);{$endif}
  Strong := nil;
  if PPointer(@Row.Link)^ <> nil then Halt(2);
  WriteLn('WEAK_PPU_PASS');
end.
