{ Two specializations of one generic interface bind distinct methods on the same receiver. }

type
  IBreadthProjector<T> = interface
    function Project(const Input: T): T;
  end;
  IBreadthNumberProjector = IBreadthProjector<Int64>;
  IBreadthTextProjector = IBreadthProjector<UnicodeString>;

  TBreadthDualProjector = class(TInterfacedObject, IBreadthNumberProjector, IBreadthTextProjector)
  private
    function ProjectNumber(const Input: Int64): Int64;
    function ProjectText(const Input: UnicodeString): UnicodeString;
    function IBreadthNumberProjector.Project = ProjectNumber;
    function IBreadthTextProjector.Project = ProjectText;
  public
    Trace: Integer;
    class var Releases: Integer;
    destructor Destroy; override;
  end;

function TBreadthDualProjector.ProjectNumber(const Input: Int64): Int64;
begin
  Trace := Trace * 10 + 1;
  Result := Input - 41000000013;
end;

function TBreadthDualProjector.ProjectText(const Input: UnicodeString): UnicodeString;
begin
  Trace := Trace * 10 + 2;
  Result := Input + #0'after';
end;

destructor TBreadthDualProjector.Destroy;
begin
  Inc(Releases);
  inherited;
end;

procedure ExerciseBreadthDualProjector;
var
  Obj: TBreadthDualProjector;
  Numbers: IBreadthNumberProjector;
  Texts: IBreadthTextProjector;
  Projected: UnicodeString;
begin
  Obj := TBreadthDualProjector.Create;
  Numbers := Obj;
  Texts := Obj;
  Check(Numbers.Project(OpaqueI(78000000017)) = 37000000004, 'breadth-generic-interface-dispatches-wide-number');
  Numbers := nil;
  Projected := Texts.Project('before');
  Check((Projected = 'before'#0'after') and (Obj.Trace = 12) and (TBreadthDualProjector.Releases = 0),
    'breadth-generic-interface-distinguishes-vtables-on-shared-live-receiver');
end;

procedure RunBreadthDualProjector;
begin
  TBreadthDualProjector.Releases := 0;
  ExerciseBreadthDualProjector;
  Check(TBreadthDualProjector.Releases = 1, 'breadth-generic-interface-specializations-release-shared-receiver-once');
end;
