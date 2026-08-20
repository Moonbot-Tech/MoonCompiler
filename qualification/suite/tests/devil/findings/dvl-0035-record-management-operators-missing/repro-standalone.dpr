program mgmt;
{$ifdef FPC}{$mode delphiunicode}{$H+}{$modeswitch advancedrecords}{$endif}
{$APPTYPE CONSOLE}
uses
{$ifdef FPC}
  mormot.core.fpcx64mm,
{$endif}
  SysUtils;

var
  Trail: AnsiString;

type
  TRec = record
    Slot: Integer;
    class operator Initialize(out Dest: TRec);
    class operator Finalize(var Dest: TRec);
    class operator Assign(var Dest: TRec; const [ref] Src: TRec);
  end;

class operator TRec.Initialize(out Dest: TRec);
begin
  Dest.Slot := 0;
  Trail := Trail + 'i';
end;

class operator TRec.Finalize(var Dest: TRec);
begin
  Trail := Trail + 'f';
end;

class operator TRec.Assign(var Dest: TRec; const [ref] Src: TRec);
begin
  Dest.Slot := Src.Slot;
  Trail := Trail + 'a';
end;

procedure Scope;
var
  A, B: TRec;
begin
  A.Slot := 7;
  B := A;
  Trail := Trail + '|';
end;

begin
  Trail := '';
  Scope;
  WriteLn('trail = ', string(Trail));
end.
