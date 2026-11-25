{ A background job reports its final state to the form through OnTerminate. }

type
  TBreadthFinishedJob = class(TThread)
    Reject: Boolean;
    ResultText: string;
    procedure Execute; override;
  end;

  TBreadthJobObserver = class
    Calls: Integer;
    RanOnMain: Boolean;
    ObservedText, ErrorText: string;
    procedure Completed(Sender: TObject);
  end;

procedure TBreadthFinishedJob.Execute;
begin
  ResultText := 'request ' + #$03BB + #0 + ' end';
  If Reject then
    raise EAbort.Create('cancelled before commit');
end;

procedure TBreadthJobObserver.Completed(Sender: TObject);
var
  Job: TBreadthFinishedJob;
begin
  Inc(Calls);
  RanOnMain := TThread.CurrentThread.ThreadID = MainThreadID;
  Job := TBreadthFinishedJob(Sender);
  ObservedText := Job.ResultText;
  If Job.FatalException is EAbort then
    ErrorText := EAbort(Job.FatalException).Message;
end;

procedure BreadthCheckJobTermination(Reject: Boolean);
var
  Job: TBreadthFinishedJob;
  Observer: TBreadthJobObserver;
begin
  Observer := TBreadthJobObserver.Create;
  try
    Job := TBreadthFinishedJob.Create(True);
    try
      Job.Reject := Reject;
      Job.OnTerminate := Observer.Completed;
      Job.Start;
      Job.WaitFor;
    finally
      Job.Free;
    end;
    Check((Observer.Calls = 1) and Observer.RanOnMain, 'breadth-job-terminates-on-main-thread-exactly-once');
    Check(Observer.ObservedText = 'request ' + #$03BB + #0 + ' end', 'breadth-job-termination-keeps-result-after-thread-free');
    If Reject then
      Check(Observer.ErrorText = 'cancelled before commit', 'breadth-job-termination-delivers-original-error')
    else
      Check(Observer.ErrorText = '', 'breadth-successful-job-termination-has-no-error');
    Mix(UInt64(Length(Observer.ObservedText) * 100 + Length(Observer.ErrorText)));
  finally
    Observer.Free;
  end;
end;

procedure RunBreadthJobTermination;
begin
  BreadthCheckJobTermination(False);
  BreadthCheckJobTermination(True);
end;
