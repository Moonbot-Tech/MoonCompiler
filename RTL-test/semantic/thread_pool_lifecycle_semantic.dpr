program thread_pool_lifecycle_semantic;

{$mode delphi}{$H+}

uses
  mormot.core.fpcx64mm,
  {$ifdef UNIX}
  cthreads,
  cwstring,
  {$endif UNIX}
  System.SysUtils,
  System.Threading;

procedure Check(aCondition: Boolean; const aMessage: string);
begin
  if not aCondition then
    raise Exception.Create('THREAD_POOL_LIFECYCLE_FAIL: '+aMessage);
end;

var
  I: Integer;
  LoopResult: TParallel.TLoopResult;
  Visited: array of Boolean;

begin
  SetLength(Visited,64);
  LoopResult:=TParallel.&For(0,High(Visited),
    procedure(aIndex: Integer)
    begin
      Visited[aIndex]:=True;
    end);
  Check(LoopResult.Completed,'parallel loop did not complete');
  for I:=0 to High(Visited) do
    Check(Visited[I],'missing index '+IntToStr(I));
  { The runner also requires the process to terminate.  This is the decisive
    oracle for workers terminated between Start and their first time slice. }
  WriteLn('THREAD_POOL_LIFECYCLE_PASS');
end.
