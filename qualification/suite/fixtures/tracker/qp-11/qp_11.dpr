program tracker_qp_11;

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

var
  DataInit, DataFini: Integer;

type
  IMarker = interface
    ['{8E03114C-2B27-4D07-B313-806939F3D641}']
  end;
  TMarker = class(TInterfacedObject, IMarker);
  TData = record
    Value: Integer;
    class operator Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TData);
    class operator Finalize(var Dest: TData);
  end;
  TSourceRec = record
    Intf: IMarker;
    Value: Integer;
    constructor Create(AValue: Integer);
    class operator Implicit(const Source: TSourceRec): TData;
  end;

class operator TData.Initialize({$ifdef FPC}var{$else}out{$endif} Dest: TData);
begin Dest.Value := 0; Inc(DataInit); end;
class operator TData.Finalize(var Dest: TData);
begin Inc(DataFini); end;
constructor TSourceRec.Create(AValue: Integer);
begin
  Check(Intf = nil, 'interface-not-zeroed');
  Intf := TMarker.Create;
  Value := AValue;
end;
class operator TSourceRec.Implicit(const Source: TSourceRec): TData;
begin Result.Value := Source.Value; end;

procedure Run;
begin
var Data: TData := TSourceRec.Create(91);
  Check(Data.Value = 91, 'converted-value');
  Check(DataInit >= 1, 'data-init');
end;

begin
  try
    Run;
    WriteLn('PASS QP-11');
  except
    on E: Exception do
    begin
      WriteLn('FAIL QP-11: ', E.ClassName, ': ', E.Message);
      Halt(1);
    end;
  end;
end.
