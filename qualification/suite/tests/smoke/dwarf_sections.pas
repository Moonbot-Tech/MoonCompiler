program dwarf_sections;
{$mode objfpc}{$H+}
uses
  {$ifdef unix}cthreads,{$endif}
  SysUtils, Classes, lnfodwrf{$ifdef REPORTS}, Moon.Diagnostics{$endif};

procedure OriginalFault; noinline;
begin
  raise Exception.Create('DWARF original fault');
end;

procedure LookupMarker; noinline;
begin
  if ParamCount<0 then Writeln('unreachable');
end;

function ResolveMarker: Boolean;
var F,S: ShortString; L: LongInt;
begin
  Result:=GetLineInfo(PtrUInt(@LookupMarker)+1,F,S,L);
  if Result then begin
    Writeln('LOOKUP=',F,'|',S,'|',L);
    if (Pos('LookupMarker',F)=0) or (Pos('dwarf_sections.pas',S)=0) or ((L<13) or (L>14)) then Halt(11);
  end;
end;

type
  TLookupThread=class(TThread)
    Good: Boolean;
    procedure Execute; override;
  end;

procedure TLookupThread.Execute;
var I: Integer;
begin
  Good:=True;
  for I:=1 to 20 do
    Good:=ResolveMarker and Good;
end;

var I: Integer; Expected,Actual: Boolean; Workers: array[0..3] of TLookupThread;
  {$ifdef REPORTS}Name: string;{$endif}
begin
  Expected:=ParamStr(1)='symbols';
  Actual:=ResolveMarker;
  Writeln('SYMBOLS=',Actual);
  if Actual<>Expected then Halt(12);
  CloseDwarf;
  for I:=0 to High(Workers) do Workers[I]:=TLookupThread.Create(False);
  for I:=0 to High(Workers) do begin
    Workers[I].WaitFor;
    if Workers[I].Good<>Expected then Halt(13);
    Workers[I].Free;
  end;
  {$ifdef REPORTS}
  InitializeReports(ParamStr(2));
  try
    OriginalFault;
  except
    Name:=WriteExceptionReport('compressed DWARF original fault');
    Writeln('REPORT=',Name);
  end;
  Name:=WriteManualReport('manual following exception');
  Writeln('REPORT=',Name);
  {$endif}
  CloseDwarf;
  Writeln('DWARF_SECTIONS_PASS');
end.
