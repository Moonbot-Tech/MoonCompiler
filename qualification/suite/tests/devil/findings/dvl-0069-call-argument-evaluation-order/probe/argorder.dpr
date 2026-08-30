program argorder;
{$APPTYPE CONSOLE}
{$ifdef FPC}{$mode delphiunicode}{$H+}{$endif}
uses SysUtils;

var Trace: string;

function F(N: Integer): Integer;
begin
  Trace := Trace + IntToStr(N);
  Result := N;
end;

procedure P2(A, B: Integer); begin end;
procedure P3(A, B, C: Integer); begin end;
procedure P5(A, B, C, D, E: Integer); begin end;
function R2(A, B: Integer): Integer; begin Result := A - B; end;

type
  TRec = record
    procedure M(A, B: Integer);
  end;
procedure TRec.M(A, B: Integer); begin end;

var
  R: TRec;
  S: string;
  I: Integer;
begin
  Trace := ''; P2(F(1), F(2));                WriteLn('два довода:        ', Trace);
  Trace := ''; P3(F(1), F(2), F(3));          WriteLn('три довода:        ', Trace);
  Trace := ''; P5(F(1), F(2), F(3), F(4), F(5)); WriteLn('пять доводов:      ', Trace);
  Trace := ''; I := R2(F(1), F(2));           WriteLn('функция:           ', Trace);
  Trace := ''; R.M(F(1), F(2));               WriteLn('метод записи:      ', Trace);
  Trace := ''; S := Format('%d%d', [F(1), F(2)]); WriteLn('открытый массив:   ', Trace);
  Trace := ''; P2(F(1) + F(2), F(3) * F(4));  WriteLn('выражения внутри:  ', Trace);
end.
