unit generic_alias_replay_unit;

{$mode delphi}
{$modeswitch implicitgenerics}

interface

uses
  System.Generics.Collections;

type
  TBuffer<T> = class(TEnumerable<T>)
  public type
    TEnumerator = class(TEnumerator<T>);
  protected
    function DoGetEnumerator: System.Generics.Collections.TEnumerator<T>;
      override;
  end;

implementation

function TBuffer<T>.DoGetEnumerator:
  System.Generics.Collections.TEnumerator<T>;
begin
  Result:=nil;
end;

end.
