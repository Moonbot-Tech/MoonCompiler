program sdk2410_resources;

{$mode delphi}{$H+}
{$R sdk2410_resources.res}

uses {$IF defined(UNIX) and (SIZEOF(Char)=1)}cwstring,{$ENDIF} SysUtils, Classes;

type
  TResourceBase = class(TComponent)
  private
    FValue, FOther: Integer;
  published
    property Value: Integer read FValue write FValue;
    property Other: Integer read FOther write FOther;
  end;
  TResourceDerived = class(TResourceBase);
  TNoResource = class(TComponent);
  TDeltaSink = class
    Probe: TResourceBase;
    Calls: Integer;
    procedure Read(const S: TStream);
  end;

var Checks: Integer;

procedure Check(Condition: Boolean; const Name: string);
begin
  Inc(Checks);
  If not Condition then raise Exception.Create('RESOURCE_FAIL: '+Name);
end;

procedure TDeltaSink.Read(const S: TStream);
begin
  Inc(Calls);
  Check(S.Position=0,'delta stream at start');
  Check(S.ReadComponent(Probe)=Probe,'delta stream instance');
end;

procedure Components;
var P: TResourceBase; D: TResourceDerived; N: TNoResource; R: TComponent;
begin
  D:=TResourceDerived.Create(nil);
  try
    Check(InitInheritedComponent(D,TComponent),'inherited found');
    Check((D.Value=77) and (D.Other=10),'base then derived values');
  finally
    D.Free;
  end;
  N:=TNoResource.Create(nil);
  try
    Check(not InitInheritedComponent(N,TComponent),'missing inherited false');
  finally
    N.Free;
  end;
  P:=TResourceBase.Create(nil);
  try
    Check(ReadComponentRes('NAMED_COMPONENT',P)=P,'named read same instance');
    Check(P.Value=81,'named value');
    Check(InitComponentRes('NAMED_COMPONENT',P),'named init');
    Check(ReadComponentRes('MISSING_RESOURCE',P)=nil,'missing read nil');
    Check(not InitComponentRes('MISSING_RESOURCE',P),'missing init false');
  finally
    P.Free;
  end;
  R:=ReadComponentResEx(HInstance,'NAMED_COMPONENT');
  try
    Check((R is TResourceBase) and (TResourceBase(R).Value=81),'named creates class');
  finally
    R.Free;
  end;
  Check(ReadComponentResEx(HInstance,'MISSING_RESOURCE')=nil,'missing creates nil');
end;

procedure Deltas(ReaderEntry: Boolean);
var Sink: TDeltaSink; Reader: TReader; Empty: TMemoryStream;
begin
  Sink:=TDeltaSink.Create;
  Empty:=TMemoryStream.Create;
  Reader:=TReader.Create(Empty,128);
  Sink.Probe:=TResourceBase.Create(nil);
  try
    If ReaderEntry then
      Check(Reader.ReadComponentDeltaRes(Sink.Probe,['missing','second','first'],Sink.Read)=Sink.Probe,'reader same instance')
    else
      Check(ReadComponentDeltaRes(Sink.Probe,['missing','second','first'],Sink.Read)=Sink.Probe,'global same instance');
    Check((Sink.Calls=1) and (Sink.Probe.Value=92),'delta first existing candidate');
    If ReaderEntry then begin
      Reader.ReadComponentDeltaRes(Sink.Probe,['missing'],Sink.Read);
      Reader.ReadComponentDeltaRes(Sink.Probe,[],Sink.Read);
    end else begin
      ReadComponentDeltaRes(Sink.Probe,['missing'],Sink.Read);
      ReadComponentDeltaRes(Sink.Probe,[],Sink.Read);
    end;
    Check((Sink.Calls=1) and (Sink.Probe.Value=92),'missing delta no callback');
  finally
    Sink.Probe.Free;
    Reader.Free;
    Empty.Free;
    Sink.Free;
  end;
end;

procedure Payload(Stream: TResourceStream);
const Expected: array[0..18] of Byte = (83,68,75,50,52,49,48,45,114,101,115,111,117,114,99,101,0,255,127);
var Data: array[0..18] of Byte;
begin
  try
    Check(Stream.Size=19,'payload length');
    Stream.ReadBuffer(Data,SizeOf(Data));
    Check(CompareMem(@Data,@Expected,SizeOf(Data)),'payload bytes');
  finally
    Stream.Free;
  end;
end;

procedure Streams;
var A: AnsiString; W: UnicodeString; Raised: Boolean; S: TResourceStream;
begin
  {$IF SIZEOF(Char)=1}
  Payload(TResourceStream.Create(HInstance,'NAMED_RESOURCE',PAnsiChar(10)));
  Payload(TResourceStream.CreateFromID(HInstance,321,PAnsiChar(10)));
  {$ENDIF}
  Payload(TResourceStream.Create(HInstance,'NAMED_RESOURCE',PWideChar(10)));
  Payload(TResourceStream.CreateFromID(HInstance,321,PWideChar(10)));
  A:='CUSTOMTYPE';
  W:='CUSTOMTYPE';
  {$IF SIZEOF(Char)=1}
  Payload(TResourceStream.Create(HInstance,'NAMED_RESOURCE',PAnsiChar(A)));
  Payload(TResourceStream.CreateFromID(HInstance,322,PAnsiChar(A)));
  {$ENDIF}
  Payload(TResourceStream.Create(HInstance,'NAMED_RESOURCE',PWideChar(W)));
  Payload(TResourceStream.CreateFromID(HInstance,322,PWideChar(W)));
  Check(System.FindResource(HInstance,AnsiString('NAMED_RESOURCE'),PAnsiChar(10))<>0,'System named numeric type');
  Check(System.FindResource(HInstance,PAnsiChar(321),PAnsiChar(10))<>0,'System numeric name and type');
  Check(System.FindResource(HInstance,AnsiString('NAMED_RESOURCE'),AnsiString('CUSTOMTYPE'))<>0,'System string type');
  Raised:=False;
  try
    S:=TResourceStream.CreateFromID(HInstance,65530,PWideChar(10));
    S.Free;
  except
    on EResNotFound do Raised:=True;
  end;
  Check(Raised,'missing numeric resource exception');
end;

var Group: string;
begin
  try
    RegisterClass(TResourceBase);
    RegisterClass(TResourceDerived);
    Group:=ParamStr(1);
    If (Group='') or (Group='components') then Components;
    If (Group='') or (Group='delta') then Deltas(False);
    If (Group='') or (Group='reader') then Deltas(True);
    If (Group='') or (Group='streams') then Streams;
    Check(Checks>1,'fixture ran');
    Writeln('RESOURCE_PASS checks=',Checks);
  except
    on E: Exception do begin
      Writeln(E.ClassName,': ',E.Message);
      Halt(1);
    end;
  end;
end.
