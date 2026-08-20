program dvl_stress_001_deep_nesting;
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
                                          if R >= 20 then
                                          begin
                                            if R >= 21 then
                                            begin
                                              if R >= 22 then
                                              begin
                                                if R >= 23 then
                                                begin
                                                  if R >= 24 then
                                                  begin
                                                    if R >= 25 then
                                                    begin
                                                      if R >= 26 then
                                                      begin
                                                        if R >= 27 then
                                                        begin
                                                          if R >= 28 then
                                                          begin
                                                            if R >= 29 then
                                                            begin
                                                              if R >= 30 then
                                                              begin
                                                                if R >= 31 then
                                                                begin
                                                                  if R >= 32 then
                                                                  begin
                                                                    if R >= 33 then
                                                                    begin
                                                                      if R >= 34 then
                                                                      begin
                                                                        if R >= 35 then
                                                                        begin
                                                                          if R >= 36 then
                                                                          begin
                                                                            if R >= 37 then
                                                                            begin
                                                                              if R >= 38 then
                                                                              begin
                                                                                if R >= 39 then
                                                                                begin
                                                                                  if R >= 40 then
                                                                                  begin
                                                                                    if R >= 41 then
                                                                                    begin
                                                                                      if R >= 42 then
                                                                                      begin
                                                                                        if R >= 43 then
                                                                                        begin
                                                                                          if R >= 44 then
                                                                                          begin
                                                                                            if R >= 45 then
                                                                                            begin
                                                                                              if R >= 46 then
                                                                                              begin
                                                                                                if R >= 47 then
                                                                                                begin
                                                                                                  if R >= 48 then
                                                                                                  begin
                                                                                                    if R >= 49 then
                                                                                                    begin
                                                                                                      if R >= 50 then
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
