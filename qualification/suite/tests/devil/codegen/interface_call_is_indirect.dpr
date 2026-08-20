program interface_call_is_indirect;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
  {$ifdef UNIX}cthreads,{$endif}
{$endif}
  SysUtils;
type
  IThing = interface
    ['{5F1B0000-0000-0000-0000-000000000001}']
    function Value: Integer;
  end;

  TThing = class(TInterfacedObject, IThing)
    function Value: Integer;
  end;

function TThing.Value: Integer;
begin
  Result := 7;
end;

var
  T: IThing;
begin
  T := TThing.Create;
  WriteLn(T.Value);
end.
