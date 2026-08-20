program dvl_stress_019_closure_depth;
{$ifdef FPC}
  {$mode delphiunicode}{$H+}
  {$modeswitch advancedrecords}
  {$modeswitch anonymousfunctions}
  {$modeswitch functionreferences}
  {$modeswitch INLINEVARS}
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
  TDvlProc = reference to procedure;

var
  R: Integer;
  P: TDvlProc;
begin
  R := 0;
  P := procedure
  begin
    Inc(R, 0);
    P := procedure
    begin
      Inc(R, 1);
      P := procedure
      begin
        Inc(R, 2);
        P := procedure
        begin
          Inc(R, 3);
          P := procedure
          begin
            Inc(R, 4);
            P := procedure
            begin
              Inc(R, 5);
              P := procedure
              begin
                Inc(R, 6);
              end;
            end;
          end;
        end;
      end;
    end;
  end;
  P();
  WriteLn(R);
end.
