program dvl_stress_018_deep_nesting;
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
var
  R: Integer;
begin
  R := 0;
  if R >= 0 then
  begin
    if R >= 1 then
    begin
      if R >= 2 then
      begin
        if R >= 3 then
        begin
          if R >= 4 then
          begin
            if R >= 5 then
            begin
              if R >= 6 then
              begin
                if R >= 7 then
                begin
                  if R >= 8 then
                  begin
                    if R >= 9 then
                    begin
                      if R >= 10 then
                      begin
                        if R >= 11 then
                        begin
                          if R >= 12 then
                          begin
                            if R >= 13 then
                            begin
                              if R >= 14 then
                              begin
                                if R >= 15 then
                                begin
                                  if R >= 16 then
                                  begin
                                    if R >= 17 then
                                    begin
                                      if R >= 18 then
                                      begin
                                        if R >= 19 then
                                        begin
                                          Inc(R);
                                        end;
                                      end;
                                    end;
                                  end;
                                end;
                              end;
                            end;
                          end;
                        end;
                      end;
                    end;
                  end;
                end;
              end;
            end;
          end;
        end;
      end;
    end;
  end;
  WriteLn(R);
end.
