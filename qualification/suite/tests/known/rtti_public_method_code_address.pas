program rtti_public_method_code_address;

{ Delphi 12.2 Win64: METHOD=1, CODE=1, CALLED=1.
  Current MoonBot FPC x86-64 Linux: METHOD=0, CODE=0, CALLED=0.
  Published methods are covered separately in Omni and remain callable; this
  repro isolates extended RTTI requested explicitly for a public method. }

{$ifdef FPC}
  {$mode delphiunicode}{$H+}
{$endif}
{$APPTYPE CONSOLE}

uses
  SysUtils,
  Rtti;

type
  {$RTTI EXPLICIT METHODS([vcPublic])}
  TSubject = class
  public
    Called: Boolean;
    procedure Fire(Sender: TObject);
  end;

  TNotifyCode = procedure(Instance, Sender: TObject);

procedure TSubject.Fire(Sender: TObject);
begin
  Called := Sender = Self;
end;

var
  Context: TRttiContext;
  Method: TRttiMethod;
  Subject: TSubject;
begin
  Subject := TSubject.Create;
  Context := TRttiContext.Create;
  try
    Method := Context.GetType(TypeInfo(TSubject)).GetMethod('Fire');
    Writeln('METHOD=', Ord(Method <> nil));
    Writeln('CODE=', Ord((Method <> nil) and (Method.CodeAddress <> nil)));
    if (Method <> nil) and (Method.CodeAddress <> nil) then
      TNotifyCode(Method.CodeAddress)(Subject, Subject);
    Writeln('CALLED=', Ord(Subject.Called));
  finally
    Context.Free;
    Subject.Free;
  end;
end.
