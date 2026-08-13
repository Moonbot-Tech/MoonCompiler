program tracker_so_18;

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch nestedprocvars}
  {$modeswitch inlinevars}
{$endif}
{$APPTYPE CONSOLE}
{$Q-}{$R-}

uses
  SysUtils, Classes, Math, Variants, TypInfo, Rtti,
  Generics.Defaults, Generics.Collections;

procedure Check(Condition: Boolean; const Name: string);
begin
  if not Condition then
    raise Exception.Create(Name);
end;

type
  IBase=interface ['{D0060E42-B860-456E-9C06-77ED237E8E3A}'] procedure Base; end;
  IDerived=interface(IBase) ['{73CA1644-ACB5-488C-A506-78E8B4FAF86C}'] procedure Derived; end;
  TImpl=class(TInterfacedObject,IDerived) procedure Base; procedure Derived; end;
  TStore<T:IBase>=class Value:T; end;
var InterfaceCalls:Integer;
procedure TImpl.Base; begin Inc(InterfaceCalls); end; procedure TImpl.Derived; begin Inc(InterfaceCalls); end;

procedure Run;
begin
InterfaceCalls:=0; var Store:=TStore<IDerived>.Create; try Store.Value:=TImpl.Create; Store.Value.Base; Store.Value.Derived; Check(InterfaceCalls=2,'calls'); finally Store.Free; end;
end;

begin
  try
    Run;
    WriteLn('PASS SO-18');
  except
    on E: Exception do
    begin
      WriteLn('FAIL SO-18: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
