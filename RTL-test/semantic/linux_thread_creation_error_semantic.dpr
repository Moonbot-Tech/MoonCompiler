program linux_thread_creation_error_semantic;
{ %TARGET=linux }
{$mode delphiunicode}
uses cthreads, Classes, SysUtils;
type
  TWorker=class(TThread)
    Ran: Boolean;
    procedure Execute; override;
  end;
procedure TWorker.Execute;
begin Ran:=True end;
var W: TWorker; Reported: Boolean;
begin
  Reported:=False;
  try
    W:=TWorker.Create(True,1024);
    W.Free;
  except
    on E:EThread do
      Reported:=(Pos('pthread_attr_setstacksize returned 22',E.Message)>0) and
                (Pos('stack=1024 bytes',E.Message)>0);
  end;
  if not Reported then Halt(1);
  W:=TWorker.Create(False);
  try
    W.WaitFor;
    if not W.Ran then Halt(2);
  finally W.Free end;
  WriteLn('LINUX_THREAD_CREATION_ERROR_PASS');
end.
