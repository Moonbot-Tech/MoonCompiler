unit default_assign_generic_probe;

interface

type
  TDefaultReset = class sealed
  public
    class procedure Reset<T>(var Dest: T); static;
  end;

implementation

class procedure TDefaultReset.Reset<T>(var Dest: T);
begin
  Dest := Default(T);
end;

end.
