program conditional_reraise_semantic;
{$mode delphi}
uses SysUtils;
type
  EOriginal = class(Exception);
  EReplacement = class(Exception);
  ECertificate = class(Exception);
  TLife = class(TInterfacedObject)
    destructor Destroy; override;
  end;
var
  Finalized, Destroyed: Integer;
  Original: Exception;

destructor TLife.Destroy;
begin
  Inc(Destroyed);
  inherited;
end;

procedure Check(Value: Boolean);
begin
  If not Value then
    Halt(1);
end;

procedure Run(Kind: Integer);
var
  Life: IInterface;
  Caught: Boolean;

  procedure Inner;
  begin
    try
      If Kind = 0 then begin
        Original := EOriginal.Create('original');
        raise Original;
      end else
        raise Exception.Create('lower');
    except
      on E: Exception do begin
        If Kind < 2 then begin
          If E is EOriginal then
            raise;
          raise EReplacement.Create('replacement');
        end;
        If Kind = 2 then
          raise ECertificate.Create('certificate');
        try
          raise Exception.Create('retry');
        except
          on E2: Exception do begin
            If E2 is EOriginal then
              raise;
            raise EReplacement.Create('retry replacement');
          end;
        end;
      end;
    end;
  end;

begin
  Life := TLife.Create;
  Caught := False;
  try
    try
      Inner;
    finally
      Inc(Finalized);
    end;
  except
    on E: Exception do begin
      Caught := True;
      case Kind of
        0: Check((E = Original) and (E.Message = 'original'));
        1: Check((E.ClassType = EReplacement) and (E.Message = 'replacement'));
        2: Check((E.ClassType = ECertificate) and (E.Message = 'certificate'));
        3: Check((E.ClassType = EReplacement) and (E.Message = 'retry replacement'));
      end;
    end;
  end;
  Check(Caught);
end;

var I: Integer;
begin
  for I := 0 to 3 do begin
    Run(I);
    Check((Finalized = I + 1) and (Destroyed = I + 1));
  end;
  WriteLn('CONDITIONAL_RERAISE_PASS');
end.
