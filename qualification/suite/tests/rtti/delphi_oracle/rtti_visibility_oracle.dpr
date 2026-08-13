program rtti_visibility_oracle;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Rtti,
  rtti_visibility_unit in 'rtti_visibility_unit.pas';

var
  Context: TRttiContext;
  RttiType: TRttiType;
begin
  if not TouchVisibilityTypes then
    Halt(1);
  Context:=TRttiContext.Create;
  try
    for RttiType in Context.GetTypes do
      if (RttiType.Name='TInterfaceType') or
         (RttiType.Name='TImplementationType') or
         (RttiType.Name='TNestedType') then
        Writeln(RttiType.Name);
  finally
    Context.Free;
  end;
end.
