program weak_interface_threads_semantic;
{$IFDEF FPC}{$MODE DELPHIUNICODE}{$ENDIF}
{$APPTYPE CONSOLE}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils;

type
  TSlot = record
    [Weak] Value: IInterface;
  end;

  TWorker = class(TThread)
    Shared: IInterface;
    Passed: Boolean;
    procedure Execute; override;
  end;

procedure TWorker.Execute;
var
  Rows: array of TSlot;
  Local: IInterface;
  I, J: Integer;
begin
  for I := 1 to 40 do
  begin
    Local := TInterfacedObject.Create;
    SetLength(Rows, 48);
    for J := 0 to High(Rows) do
      if Odd(J) then Rows[J].Value := Local else Rows[J].Value := Shared;
    SetLength(Rows, 513);
    Local := nil;
    for J := 0 to 47 do
      if Odd(J) then
      begin
        if PPointer(@Rows[J].Value)^ <> nil then Exit;
      end
      else if PPointer(@Rows[J].Value)^ <> Pointer(Shared) then Exit;
    Rows := nil;
  end;
  Passed := True;
end;

var
  Workers: array[0..7] of TWorker;
  Shared: IInterface;
  I: Integer;
begin
  Shared := TInterfacedObject.Create;
  try
    for I := 0 to High(Workers) do
    begin
      Workers[I] := TWorker.Create(True);
      Workers[I].Shared := Shared;
      Workers[I].Start;
    end;
    for I := 0 to High(Workers) do
    begin
      Workers[I].WaitFor;
      if not Workers[I].Passed then raise Exception.Create('worker failed');
    end;
  finally
    for I := 0 to High(Workers) do Workers[I].Free;
  end;
  WriteLn('WEAK_INTERFACE_THREADS_PASS');
end.
