program component_class_alias_semantic;
{$ifdef FPC}{$mode delphiunicode}{$endif}

{$APPTYPE CONSOLE}

uses
  SysUtils, Classes;

type
  TCurrentRoute = class(TComponent)
  private
    FQuota: Int64;
  published
    property Quota: Int64 read FQuota write FQuota;
  end;

const
  OldForm: AnsiString = 'object Restored: TOldRoute'#10'  Quota = 730000000031'#10'end'#10;

function Reload(ExplicitRegistration: Boolean): Boolean;
var
  TextData, Binary: TMemoryStream;
  Original, Reopened: TComponent;
begin
  If ExplicitRegistration then
    RegisterClass(TCurrentRoute);
  RegisterClassAlias(TCurrentRoute, 'TOldRoute');
{$ifdef FPC}
  { The Moon registry permits repeating the same registration. }
  RegisterClassAlias(TCurrentRoute, 'TOldRoute');
{$endif}
  TextData := TMemoryStream.Create;
  Binary := nil;
  Original := nil;
  Reopened := nil;
  try
    Binary := TMemoryStream.Create;
    Writeln('explicit=', ExplicitRegistration, ' alias=', GetClass('TOldRoute') = TCurrentRoute,
      ' canonical=', GetClass('TCurrentRoute') = TCurrentRoute);
    TextData.WriteBuffer(OldForm[1], Length(OldForm));
    TextData.Position := 0;
    ObjectTextToBinary(TextData, Binary);
    Binary.Position := 0;
    Original := Binary.ReadComponent(nil);
    Writeln('legacy instance=', Original.ClassName, ' quota=', TCurrentRoute(Original).Quota);
    Result := (Original is TCurrentRoute) and (TCurrentRoute(Original).Quota = 730000000031);
    Binary.Clear;
    Binary.WriteComponent(Original);
    Binary.Position := 0;
    try
      Reopened := Binary.ReadComponent(nil);
      Writeln('canonical instance=', Reopened.ClassName, ' quota=', TCurrentRoute(Reopened).Quota);
      Result := Result and (Reopened is TCurrentRoute) and (TCurrentRoute(Reopened).Quota = 730000000031);
    except
      on E: EClassNotFound do begin
        Writeln('canonical reload failed: ', E.ClassName, ' ', E.Message);
        Result := False;
      end;
    end;
  finally
    FreeAndNil(Reopened);
    FreeAndNil(Original);
    FreeAndNil(Binary);
    FreeAndNil(TextData);
    UnRegisterClass(TCurrentRoute);
  end;
end;

var
  AliasOnly, BothRegistered: Boolean;

begin
  AliasOnly := Reload(False);
  if (GetClass('TCurrentRoute')<>nil) or (GetClass('TOldRoute')<>nil) then Halt(3);
  BothRegistered := Reload(True);
  If not BothRegistered then
    ExitCode := 2
  else If not AliasOnly then
    ExitCode := 1;
  if ExitCode=0 then WriteLn('COMPONENT_CLASS_ALIAS_PASS');
end.
